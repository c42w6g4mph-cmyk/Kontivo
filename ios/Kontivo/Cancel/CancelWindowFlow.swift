import SwiftUI
import KontivoCore

/// Fensterwechsel der Bereiche Kündigung, Fristen und Viewer an EINER Stelle (Review S5 A5/A6/A7).
/// Wartet über die Warteschlange des AppModels (`model.afterDismiss`) auf das tatsächliche Schliessen eines Fensters;
/// feste Wartezeiten nur noch dort, wo kein Fenster schliesst (Rückkehr in die App, Toast sichtbar lassen, Alert).
/// Jede verzögerte Aktion prüft vorher, ob der Fensterzustand noch passt (kein anderes Fenster geöffnet
/// oder geschlossen, Vertrag noch vorhanden …); sonst entfällt sie.
@MainActor
enum CancelWindowFlow {
    /// Zusätzliche Wartezeiten (ms) für Fälle ohne schliessendes Fenster
    enum Wait {
        /// Fenster geschlossen: keine feste Zeit, das Modell meldet das Ende
        static let one: UInt64 = 0
        static let all: UInt64 = 0
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

    /// `action` ausführen, sobald das laufende Schliessen fertig ist (Warteschlange des Modells), optional nach
    /// einer Mindestzeit `ms` (Alert, Toast). Hat sich der Fensterstapel seither verändert (`keepStack`) oder gilt
    /// `still` nicht mehr, entfällt die Aktion.
    static func afterDismiss(_ model: AppModel, wait ms: UInt64 = Wait.one, keepStack: Bool = true,
                             still: (() -> Bool)? = nil, _ action: @escaping () -> Void) {
        let stack = model.sheets.map(\.id)
        let run: () -> Void = {
            if keepStack && model.sheets.map(\.id) != stack { return }
            if let still, !still() { return }
            action()
        }
        guard ms > 0 else {
            model.afterDismiss(run)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: ms * 1_000_000)
            model.afterDismiss(run)
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
        afterDismiss(model) {
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

    /// Rückfrage mit «Abbrechen» und einem OK-Knopf (über `model.ask`, auf der obersten Ebene).
    static func ask(_ model: AppModel, title: String, message: String, ok: String, onOK: @escaping () -> Void) {
        model.ask(title: title, message: message, ok: ok, action: onOK)
    }
}
