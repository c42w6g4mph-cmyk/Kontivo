import SwiftUI
import UIKit
import UniformTypeIdentifiers
import KontivoCore

/// Ablauf «Aus Kontoauszug» (Web: `#bankFile` change → Ladeanzeige → `openBank`).
/// 1. Quelle wählen (`pick`): Dateien, Kamera-Scan oder Fotos – Systemauswahl über UIKit
/// 2. Fenster `.bankImport(id)` öffnet sofort mit Ladeanzeige (Variante 2), Lesen/Erkennen läuft im Hintergrund
/// 3. Vorschläge prüfen (`BankReviewView`), «n Verträge anlegen»
/// Alles auf dem Gerät: Dateien und Fotos werden nur gelesen und nicht gespeichert.
@MainActor
@Observable
final class BankImportCenter {
    static let shared = BankImportCenter()

    /// Laufende/offene Abläufe je Fenster
    private(set) var sessions: [UUID: BankImportSession] = [:]

    /// Quelle wählen und danach einlesen
    func pick(_ source: BankPickSource, model: AppModel) {
        switch source {
        case .file:
            BankPickers.shared.pickFiles { [weak self] urls in
                guard !urls.isEmpty else { return }
                self?.start(.files(urls), model: model)
            }
        case .camera:
            let ok = BankPickers.shared.scan { [weak self] images in
                guard !images.isEmpty else { return }
                self?.start(.images(images, scanned: true), model: model)
            }
            if !ok { model.toast("Die Kamera ist auf diesem Gerät nicht verfügbar") }
        case .photos:
            BankPickers.shared.pickPhotos { [weak self] images in
                guard !images.isEmpty else { return }
                self?.start(.images(images, scanned: false), model: model)
            }
        }
    }

    /// Einlesen starten: Fenster sofort öffnen (Ladeanzeige), dann lesen, suchen, abgleichen
    func start(_ input: BankInput, model: AppModel) {
        let s = BankImportSession(input: input)
        sessions[s.id] = s
        model.present(.bankImport(s.id))
        s.run(model: model)
    }

    func session(_ id: UUID) -> BankImportSession? { sessions[id] }

    /// Fenster geschlossen: Ablauf abbrechen und vergessen (Web: `bkRun++`)
    func end(_ id: UUID) {
        sessions[id]?.cancel()
        // erst nach der Schliessen-Animation vergessen (sonst blitzt ein leeres Fenster auf)
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.sessions[id] = nil
        }
    }
}

/// Eingabe eines Imports
enum BankInput {
    case files([URL])
    case images([UIImage], scanned: Bool)
    /// Testdaten (UI-Tests): Inhalt und Dateiname
    case data(Data, name: String)

    /// Datenschutz-Hinweis unter den Vorschlägen
    var privacyNote: String {
        switch self {
        case .images: return "Die Fotos wurden nur auf diesem Gerät gelesen und nicht gespeichert."
        default: return "Die Datei wurde nur auf diesem Gerät gelesen und nicht gespeichert."
        }
    }
}

/// Ein Import (ein Fenster): Phase, Ergebnis, Abbruch
@MainActor
@Observable
final class BankImportSession: Identifiable {
    enum Phase: Equatable {
        /// Ladeanzeige: Schritt 0 = lesen, 1 = suchen, 2 = abgleichen; nTx = gelesene Buchungen
        case loading(step: Int, nTx: Int?)
        /// Nichts lesbar: Titel und Erklärung (statt Web-Rückfrage), Fenster bleibt mit «OK»
        case failed(title: String, text: String)
        case review
    }

    let id = UUID()
    let input: BankInput
    var phase: Phase = .loading(step: 0, nTx: nil)
    var review: BankReview?
    @ObservationIgnored private var task: Task<Void, Never>?

    init(input: BankInput) { self.input = input }

    func cancel() {
        task?.cancel()
        task = nil
    }

    /// Ergebnis einer Datei
    private struct Read {
        var name: String
        var file: BankFile?
        /// erste Zeile (Fehlermeldung «nicht erkannt»)
        var head: String = ""
        var big = false
        /// PDF/Foto: kein Text oder keine Buchungen erkannt
        var visual = false
    }

    func run(model: AppModel) {
        let input = self.input
        let home = model.data.settings.homeCurrency.rawValue
        let t0 = Date()
        task = Task { [weak self] in
            // Fenster erst zeichnen lassen, dann rechnen
            try? await Task.sleep(nanoseconds: 60_000_000)
            let reads = await Task.detached(priority: .userInitiated) { BankImportSession.readAll(input, home: home) }.value
            guard let self, !Task.isCancelled else { return }
            let ok = reads.filter { $0.file != nil }
            let bad = reads.filter { $0.file == nil }
            if ok.isEmpty {
                if !bad.isEmpty && bad.allSatisfy({ $0.big }) {
                    model.dismissTop { model.toast("Die Datei ist zu gross (über 20 MB)", seconds: 3.2) }
                    return
                }
                self.phase = .failed(title: bad.count > 1 ? "Dateien nicht erkannt" : "Datei nicht erkannt", text: Self.failText(bad))
                return
            }
            let merged = ok.count == 1 ? ok[0].file! : BankImport.merge(ok.compactMap { $0.file })
            withAnimation(.easeInOut(duration: 0.2)) { self.phase = .loading(step: 1, nTx: merged.tx.count) }
            await Self.waitUntil(t0, 0.45)
            let data = model.data, today = model.today
            let res = await Task.detached(priority: .userInitiated) { BankImport.find(merged, data: data, today: today) }.value
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { self.phase = .loading(step: 2, nTx: merged.tx.count) }
            await Self.waitUntil(t0, 0.9)
            guard !Task.isCancelled else { return }
            let label = ok.count > 1 ? "\(ok.count) Dateien" : (!merged.bank.isEmpty ? merged.bank : ok[0].name)
            self.review = BankReview(file: merged, result: res, label: label, privacy: input.privacyNote, data: model.data)
            withAnimation(.easeInOut(duration: 0.25)) { self.phase = .review }
            if !bad.isEmpty {
                model.toast(bad.count == 1 ? "«\(bad[0].name)» nicht erkannt – übersprungen" : "\(bad.count) Dateien nicht erkannt – übersprungen", seconds: 3.2)
            }
        }
    }

    private static func waitUntil(_ t0: Date, _ seconds: Double) async {
        let left = seconds - Date().timeIntervalSince(t0)
        if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
    }

    /// Erklärung «Datei nicht erkannt» (Web-Text, ergänzt um PDF/Foto, die es nativ gibt)
    private static func failText(_ bad: [Read]) -> String {
        if !bad.isEmpty && bad.allSatisfy({ $0.visual }) {
            return "Im Auszug wurden keine Buchungen mit Datum und Betrag gefunden. Fotografiere den Auszug gerade und gut beleuchtet oder nimm den CSV-Export aus dem E-Banking."
        }
        let h = bad.count == 1 ? bad[0].head : ""
        return "Kontivo liest Kontoauszüge als CSV, camt.053 (XML), MT940, PDF oder Foto. Im E-Banking findest du den Export meist unter «Kontobewegungen» oder «Umsätze» → «Exportieren»."
            + (h.isEmpty ? "" : " Erste Zeile deiner Datei: «\(h)».")
    }

    // MARK: Lesen (im Hintergrund)

    /// Grenze wie Web (20 MB)
    nonisolated static let maxBytes = 20_000_000

    nonisolated private static func readAll(_ input: BankInput, home: String) -> [Read] {
        switch input {
        case .files(let urls):
            return urls.map { readFile($0, home: home) }
        case .images(let images, let scanned):
            // alle Bilder = Seiten eines Auszugs
            let text = StatementText.images(images)
            let name = scanned ? "Scan" : (images.count == 1 ? "Foto" : "\(images.count) Fotos")
            if let f = BankImport.readStatementText(text, defaultCurrency: home), !f.tx.isEmpty {
                return [Read(name: name, file: f)]
            }
            return [Read(name: name, file: nil, visual: true)]
        case .data(let d, let name):
            return [readData(d, name: name, ext: (name as NSString).pathExtension.lowercased(), home: home)]
        }
    }

    nonisolated private static func readFile(_ url: URL, home: String) -> Read {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let name = url.lastPathComponent
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maxBytes {
            return Read(name: name, file: nil, big: true)
        }
        guard let d = try? Data(contentsOf: url) else { return Read(name: name, file: nil) }
        return readData(d, name: name, ext: url.pathExtension.lowercased(), home: home)
    }

    nonisolated private static func readData(_ d: Data, name: String, ext: String, home: String) -> Read {
        if d.count > maxBytes { return Read(name: name, file: nil, big: true) }
        let type = UTType(filenameExtension: ext)
        let isPDF = type?.conforms(to: .pdf) == true || d.starts(with: Array("%PDF".utf8))
        let isImage = !isPDF && type?.conforms(to: .image) == true
        if isPDF || isImage {
            var text: String?
            if isPDF {
                text = StatementText.pdf(d)
            } else if let img = UIImage(data: d) {
                text = StatementText.recognize(img)
            }
            if let t = text, let f = BankImport.readStatementText(t, defaultCurrency: home), !f.tx.isEmpty {
                return Read(name: name, file: f)
            }
            return Read(name: name, file: nil, visual: true)
        }
        do {
            let f = try BankImport.read(d)
            return Read(name: name, file: f)
        } catch BankReadError.notRecognized(let first) {
            return Read(name: name, file: nil, head: String(first.prefix(80)))
        } catch BankReadError.tooBig {
            return Read(name: name, file: nil, big: true)
        } catch {
            return Read(name: name, file: nil)
        }
    }
}
