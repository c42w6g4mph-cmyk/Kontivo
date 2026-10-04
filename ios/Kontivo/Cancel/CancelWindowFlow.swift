import SwiftUI
import KontivoCore

/// Fensterwechsel der Bereiche Kündigung, Fristen und Viewer an EINER Stelle (Review S5 A5/A6/A7).
/// Heute noch mit fester Wartezeit nach dem Schliessen; sobald das AppModel eine Warteschlange
/// (`presentAfterDismiss`, `ask`) anbietet, wird nur diese Datei umgestellt.
/// Jede verzögerte Aktion prüft vorher, ob der Fensterzustand noch passt (kein anderes Fenster geöffnet
/// oder geschlossen, Vertrag noch vorhanden …); sonst entfällt sie.
@MainActor
enum CancelWindowFlow {
    /// Wartezeiten bis eine Schliessen-Animation sicher vorbei ist
    enum Wait {
        /// Ein Fenster bzw. eine Rückfrage geschlossen
        static let one: UInt64 = 550
        /// Mehrere Ebenen geschlossen (dismissAll)
        static let all: UInt64 = 650
        /// Rückkehr in die App (scenePhase .active) bis zur Rückfrage
        static let returnToApp: UInt64 = 400
    }

    /// Liegt `sheet` zuoberst?
    static func isTop(_ model: AppModel, _ sheet: AppSheet) -> Bool {
        model.sheets.last?.id == sheet.id
    }

    /// Oberstes Fenster schliessen, aber nur, wenn es `sheet` ist (Doppeltippen schliesst sonst das Fenster darunter).
    @discardableResult
    static func dismiss(_ model: AppModel, ifTop sheet: AppSheet) -> Bool {
        guard isTop(model, sheet) else { return false }
        model.dismissTop()
        return true
    }

    /// `action` ausführen, sobald die gerade laufende Schliessen-Animation vorbei ist. Hat sich der Fensterstapel
    /// seither verändert (`keepStack`) oder gilt `still` nicht mehr, entfällt die Aktion.
    static func afterDismiss(_ model: AppModel, wait ms: UInt64 = Wait.one, keepStack: Bool = true,
                             still: (() -> Bool)? = nil, _ action: @escaping () -> Void) {
        let stack = model.sheets.map(\.id)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            if keepStack && model.sheets.map(\.id) != stack { return }
            if let still, !still() { return }
            action()
        }
    }

    /// Alle Fenster schliessen und danach `sheet` öffnen (bzw. sofort, wenn keines offen ist).
    static func presentClosingOthers(_ model: AppModel, _ sheet: AppSheet, then done: (() -> Void)? = nil) {
        if model.sheets.isEmpty {
            model.present(sheet)
            done?()
            return
        }
        model.dismissAll()
        afterDismiss(model, wait: Wait.all) {
            model.present(sheet)
            done?()
        }
    }

    /// Fenster `sheet` über `from` öffnen, aber nur, wenn `from` noch zuoberst liegt (Doppeltippen, schon geschlossen).
    @discardableResult
    static func present(_ model: AppModel, _ sheet: AppSheet, over from: AppSheet) -> Bool {
        guard isTop(model, from) else { return false }
        model.present(sheet)
        return true
    }

    /// Rückfrage mit «Abbrechen» und einem OK-Knopf (heute UIKit-Alert, später `model.ask`).
    static func ask(title: String, message: String, ok: String, onOK: @escaping () -> Void) {
        CancelFlowUI.ask(title: title, message: message, ok: ok, onOK: onOK)
    }
}
