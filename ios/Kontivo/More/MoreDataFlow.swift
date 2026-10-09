import SwiftUI
import UIKit
import UniformTypeIdentifiers
import KontivoCore

// MARK: - Anfragen von aussen («Ich habe ein Backup»)

/// Anfrage an «Mehr», die Dateiauswahl für «Backup laden» zu öffnen (Einführung, Leerseite «Verträge»).
/// Aufruf: `MoreRequests.openBackupImport(model)` – wechselt in den Tab «Mehr» und öffnet dort die Dateiauswahl.
@MainActor
@Observable
final class MoreRequests {
    static let shared = MoreRequests()

    /// Zähler, damit «Mehr» auch dann reagiert, wenn es schon sichtbar ist
    private(set) var token = 0
    private var pending = false
    private var delay: Double = 0.35

    /// Tab «Mehr» zeigen und «Backup laden» auslösen. `delay`: Wartezeit, bis vorherige Fenster geschlossen sind.
    static func openBackupImport(_ model: AppModel, delay: Double = 0.45) {
        model.goTab(.more)
        shared.delay = delay
        shared.pending = true
        shared.token += 1
    }

    /// Offene Anfrage abholen (gibt die Wartezeit zurück).
    func consume() -> Double? {
        guard pending else { return nil }
        pending = false
        return delay
    }
}

// MARK: - Rückfrage (wie `ask` der Web-App)

struct MoreAsk: Identifiable {
    let id = UUID()
    var title: String
    var message: String
    /// Beschriftung des Bestätigungsknopfs; nil = nur «OK» (Hinweis)
    var confirm: String?
    var destructive: Bool = false
    var action: () -> Void = {}
}

// MARK: - Daten: Backup, CSV, Alles löschen

/// Abläufe der Gruppe «Daten» in «Mehr». Hält den Zustand für Dateiauswahl und Rückfragen.
@MainActor
@Observable
final class MoreDataFlow {
    enum ImportKind { case backup, csv }

    var showImporter = false
    var importKind: ImportKind = .backup
    var ask: MoreAsk?
    /// Läuft gerade ein Export/Import? (verhindert Doppeltippen)
    var working = false
    /// Fortschritt eines laufenden Backups (wird unter den Kacheln angezeigt)
    var progress: String?

    static let csvTypes: [UTType] = {
        var t: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .text]
        if let c = UTType(filenameExtension: "csv") { t.append(c) }
        return t
    }()

    var importTypes: [UTType] { importKind == .backup ? [.json] : MoreDataFlow.csvTypes }

    func startImport(_ kind: ImportKind) {
        guard !working else { return }
        importKind = kind
        showImporter = true
    }

    /// Rückfrage zeigen; nach einer anderen Rückfrage oder Dateiauswahl etwas verzögert, damit iOS sie sicher anzeigt.
    func show(_ a: MoreAsk, delayed: Bool = false) {
        if !delayed {
            ask = a
            return
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            self?.ask = a
        }
    }

    /// Bestätigung einer Rückfrage ausführen – kurz verzögert, bis die Rückfrage geschlossen ist
    /// (sonst kann iOS ein folgendes Fenster wie das Teilen-Menü oder die nächste Rückfrage nicht zeigen).
    func perform(_ a: MoreAsk) {
        let action = a.action
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            action()
        }
    }

    func handleImport(_ result: Result<URL, Error>, model: AppModel) {
        guard case .success(let url) = result else { return }
        switch importKind {
        case .backup: readBackup(url, model: model)
        case .csv: readCSV(url, model: model)
        }
    }

    // MARK: Backup erstellen

    /// Backup erstellen: Dateien im Hintergrund lesen (nicht auf dem Haupt-Thread), fehlende melden, dann kodieren
    func exportBackup(model: AppModel) {
        guard !working else { return }
        working = true
        progress = "Backup wird erstellt …"
        let data = model.data
        let entries: [(id: String, url: URL, type: String)] = data.referencedFileIDs.map { ($0, model.files.url($0), model.files.type($0)) }
        Task { @MainActor [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> (files: [String: ImportedFile], missing: Int) in
                var files: [String: ImportedFile] = [:]
                var missing = 0
                for e in entries {
                    if let d = try? Data(contentsOf: e.url) {
                        files[e.id] = ImportedFile(type: e.type, data: d)
                    } else {
                        missing += 1
                    }
                }
                return (files, missing)
            }.value
            guard let self else { return }
            if read.missing > 0 {
                self.working = false
                self.progress = nil
                let text = (read.missing == 1 ? "1 Datei konnte" : "\(read.missing) Dateien konnten") + " nicht gelesen werden – trotzdem sichern?"
                self.show(MoreAsk(title: "Dateien fehlen", message: text, confirm: "Trotzdem sichern") { [weak self] in
                    self?.writeBackup(data, files: read.files, model: model)
                })
            } else {
                self.writeBackup(data, files: read.files, model: model)
            }
        }
    }

    private func writeBackup(_ data: AppData, files: [String: ImportedFile], model: AppModel) {
        working = true
        progress = "Backup wird erstellt …"
        let name = Backup.fileName(today: model.today)
        Task { @MainActor [weak self] in
            let url = await Task.detached(priority: .userInitiated) { () -> URL? in
                guard let json = try? Backup.export(data, files: files) else { return nil }
                return MoreDataFlow.writeTemp(json, name: name)
            }.value
            self?.working = false
            self?.progress = nil
            guard let url else {
                model.toast("Speichern nicht möglich")
                return
            }
            MoreShare.present(url: url) { completed in
                try? FileManager.default.removeItem(at: url)
                if completed { model.toast("Backup gespeichert") }
            }
        }
    }

    // MARK: Backup laden

    private enum BackupRead: Sendable {
        case ok(BackupImportResult)
        case invalid
        case newer
    }

    private func readBackup(_ url: URL, model: AppModel) {
        working = true
        progress = "Backup wird gelesen …"
        let today = model.today
        Task { @MainActor [weak self] in
            let read = await Task.detached(priority: .userInitiated) { () -> BackupRead in
                guard let json = MoreDataFlow.readFile(url) else { return .invalid }
                do {
                    return .ok(try Backup.read(json, today: today))
                } catch BackupError.unsupportedVersion(_) {
                    return .newer
                } catch {
                    return .invalid
                }
            }.value
            guard let self else { return }
            self.working = false
            self.progress = nil
            switch read {
            case .invalid:
                model.toast(Backup.invalidMessage)
            case .newer:
                model.toast("Dieses Backup stammt aus einer neueren Version von Kontivo")
            case .ok(let r):
                self.show(MoreAsk(title: Backup.confirmTitle, message: MoreDataFlow.backupConfirmText(r),
                                  confirm: Backup.confirmButton, destructive: true) { [weak self] in
                    self?.restore(r, model: model)
                }, delayed: true)
            }
        }
    }

    /// Text der Rückfrage «Backup einspielen?» (Einzahl «1 Logo/Dokument» wie die Web-App).
    static func backupConfirmText(_ r: BackupImportResult) -> String {
        let t = r.confirmText()
        return r.files.count == 1 ? t.replacingOccurrences(of: " sowie 1 Logos/Dokumenten", with: " sowie 1 Logo/Dokument") : t
    }

    /// Backup einspielen: Dateien mit gleicher ID in den Dateispeicher, Daten ersetzen, Darstellung (theme) bleibt.
    /// Dekodiert wurde im Hintergrund; beim Schreiben gibt der Ablauf nach jeder Datei die Oberfläche frei und zeigt den Fortschritt.
    private func restore(_ r: BackupImportResult, model: AppModel) {
        working = true
        Task { @MainActor [weak self] in
            var failed = r.failedFiles
            let all = Array(r.files)
            for (i, (id, f)) in all.enumerated() {
                self?.progress = "Dateien werden übernommen… \(i + 1)/\(all.count)"
                await Task.yield()
                guard MoreDataFlow.isFileID(id) else { failed += 1; continue }
                do { try model.files.put(f.data, type: f.type, id: id) } catch { failed += 1 }
            }
            var d = r.data
            let current = model.data.settings
            d.settings.theme = current.theme
            // Die Einführung wurde auf diesem Gerät schon gesehen
            d.settings.onboarded = max(d.settings.onboarded, current.onboarded)
            model.update { $0 = d }
            model.costFilter = Calc.CostFilter()
            model.budgetPerson = nil
            model.heroFilter = nil
            self?.working = false
            self?.progress = nil
            // Speicherfehler nicht mit der Erfolgsmeldung überschreiben (F15)
            if MoreDataFlow.saveOK(model) { model.toast(Backup.doneText(failedFiles: failed)) }
        }
    }

    /// Sofort speichern. Bei Fehler bleibt die Fehlermeldung stehen; der Aufrufer zeigt dann keine Erfolgsmeldung (F15).
    /// Läuft über `model.saveNow()` (Speichersperre nach defekten Daten, einmalige Fehlermeldung).
    static func saveOK(_ model: AppModel) -> Bool {
        model.saveNow()
    }

    /// Datei-IDs wie in der Web-App: 32 Hex-Zeichen (schützt den Dateispeicher vor fremden Pfaden).
    static func isFileID(_ id: String) -> Bool {
        id.count == 32 && id.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
    }

    // MARK: CSV exportieren

    func exportCSV(model: AppModel) {
        guard !working else { return }
        let bytes = CSV.exportData(model.data, today: model.today)
        guard let url = MoreDataFlow.writeTemp(bytes, name: CSV.fileName(today: model.today)) else {
            model.toast("Speichern nicht möglich")
            return
        }
        MoreShare.present(url: url) { completed in
            try? FileManager.default.removeItem(at: url)
            if completed { model.toast("CSV gespeichert") }
        }
    }

    // MARK: CSV importieren

    private func readCSV(_ url: URL, model: AppModel) {
        guard let bytes = MoreDataFlow.readFile(url) else {
            model.toast(CSVImportPreview.readError)
            return
        }
        let p = CSV.preview(csv: bytes, data: model.data, today: model.today)
        if !p.isUsable {
            show(MoreAsk(title: CSVImportPreview.noColumnsTitle, message: CSVImportPreview.noColumnsText), delayed: true)
            return
        }
        if p.items.isEmpty {
            show(MoreAsk(title: CSVImportPreview.nothingTitle, message: p.nothingText), delayed: true)
            return
        }
        show(MoreAsk(title: p.confirmTitle, message: p.confirmText, confirm: CSVImportPreview.confirmButton) {
            let ok = model.update { CSV.apply(p, to: &$0) }
            guard ok else { return }
            model.goTab(.contracts)
            if MoreDataFlow.saveOK(model) { model.toast(p.doneText) }
        }, delayed: true)
    }

    // MARK: Alle Daten löschen

    func askWipe(model: AppModel) {
        let nc = model.data.contracts.count
        let ni = model.data.incomes.count
        let text = "Gelöscht werden " + Format.count(nc, "Vertrag", "Verträge") + ", " + Format.count(ni, "Einnahme", "Einnahmen")
            + ", eigene Kategorien, Personen, Absender sowie hochgeladene Logos und Dokumente.\n\nDarstellung und Währung bleiben erhalten.\n\nTipp: Speichere vorher ein Backup."
        show(MoreAsk(title: "Alle Daten löschen?", message: text, confirm: "Weiter", destructive: true) { [weak self] in
            self?.show(MoreAsk(title: "Wirklich endgültig löschen?", message: "Das lässt sich nicht rückgängig machen.",
                               confirm: "Endgültig löschen", destructive: true) { [weak self] in
                self?.wipe(model: model)
            })
        })
    }

    private func wipe(model: AppModel) {
        model.toast("Lösche …")
        model.files.deleteAll()
        model.update { d in
            d.wipeAll()
            // Wie die Web-App: Nach dem nächsten Start erscheint die Einführung (mit der bisherigen Währung)
            d.settings.onboarded = 0
        }
        model.costFilter = Calc.CostFilter()
        model.budgetPerson = nil
        model.heroFilter = nil
        model.searchText = ""
        model.showArchive = false
        model.goTab(.contracts)
        if MoreDataFlow.saveOK(model) { model.toast("Alle Daten gelöscht") }
    }

    // MARK: Dateien

    /// Datei aus der Dateiauswahl lesen (mit Zugriffsrecht für Dateien ausserhalb der App).
    nonisolated static func readFile(_ url: URL) -> Data? {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        var result: Data?
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordError) { u in
            result = try? Data(contentsOf: u)
        }
        if result == nil { result = try? Data(contentsOf: url) }
        return result
    }

    /// Datei mit sprechendem Namen im temporären Ordner ablegen (für das Teilen-Menü).
    nonisolated static func writeTemp(_ data: Data, name: String) -> URL? {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("Kontivo-Export", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - Teilen-Menü

/// Teilen-Menü (UIActivityViewController) für eine Datei, z.B. «In Dateien sichern». Auf dem iPad mittig ohne Pfeil.
@MainActor
enum MoreShare {
    static func present(url: URL, completion: @escaping (Bool) -> Void) {
        guard let top = topViewController() else {
            completion(false)
            return
        }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            completion(completed)
        }
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        var top = window?.rootViewController
        while let p = top?.presentedViewController, !p.isBeingDismissed { top = p }
        return top
    }
}
