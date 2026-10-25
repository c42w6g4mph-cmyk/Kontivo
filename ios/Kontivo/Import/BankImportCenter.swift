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

    /// Einlesen starten: Fenster sofort öffnen (Ladeanzeige), dann lesen, suchen, abgleichen, Logos suchen
    /// `step`: nur Bildschirmfotos/UI-Tests – nach dem Laden direkt zu diesem Schritt («inc», «term»)
    /// Zusätzlich «pay» (erste Zahlungsliste aufgeklappt) und «fail» (nicht lesbare Datei statt Beispiel)
    func start(_ input: BankInput, model: AppModel, step: String? = nil) {
        var input = input
        #if DEBUG
        if step == "fail" { input = .data(Data("Kontoauszug\nkeine Buchungen".utf8), name: "auszug.csv") }
        #endif
        let s = BankImportSession(input: input)
        s.jumpTo = step
        sessions[s.id] = s
        model.present(.bankImport(s.id))
        s.run(model: model)
    }

    func session(_ id: UUID) -> BankImportSession? { sessions[id] }

    /// Fenster geschlossen: Ablauf abbrechen und vergessen (Web: `bkRun++`)
    func end(_ id: UUID, model: AppModel) {
        if let s = sessions[id], !s.finished { s.review?.cancel(model: model) }
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

    /// Quelle für «Andere Datei wählen» (Web v278)
    var source: BankPickSource {
        switch self {
        case .images(_, let scanned): return scanned ? .camera : .photos
        default: return .file
        }
    }

    /// Datenschutz-Hinweis im letzten Schritt (Web `.bkpriv`)
    var privacyNote: String {
        switch self {
        case .images: return "Die Fotos wurden nur auf diesem Gerät gelesen und nicht gespeichert."
        default: return "Die Datei wurde nur auf diesem Gerät gelesen und nicht gespeichert."
        }
    }

    /// Grüne Box in der Ladeanzeige (Web v201 `BK_SAFE`)
    var safeNote: String {
        switch self {
        case .images: return "Die Fotos werden nur hier gelesen – nie hochgeladen, nie gespeichert."
        default: return "Die Datei wird nur hier gelesen – nie hochgeladen, nie gespeichert."
        }
    }
}

/// Ein Import (ein Fenster): Phase, Ergebnis, Abbruch
@MainActor
@Observable
final class BankImportSession: Identifiable {
    enum Phase: Equatable {
        /// Ladeanzeige: Schritt 0 = lesen, 1 = suchen, 2 = abgleichen, 3 = Logos suchen; nTx = gelesene Buchungen
        case loading(step: Int, nTx: Int?)
        /// Nichts lesbar: Titel, Dateikarten und Erklärung (Web v278 Rückfrage), Fenster bleibt mit «Andere Datei wählen»
        case failed(BankFailure)
        case review
    }

    let id = UUID()
    let input: BankInput
    var phase: Phase = .loading(step: 0, nTx: nil)
    var review: BankReview?
    /// Übernommen (Logos nicht wieder löschen)
    var finished = false
    @ObservationIgnored var jumpTo: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var logoTask: Task<Void, Never>?
    @ObservationIgnored private var alive = true
    @ObservationIgnored private var logosFinished = false

    init(input: BankInput) { self.input = input }

    func cancel() {
        alive = false
        task?.cancel()
        task = nil
        logoTask?.cancel()
        logoTask = nil
    }

    /// Ergebnis einer Datei
    private struct Read {
        var name: String
        var file: BankFile?
        /// Grund «nicht erkannt» (Web `bkLastDiag`)
        var diag: BankReadDiag = .none
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
                self.phase = .failed(Self.failure(bad))
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
            let inc = await Task.detached(priority: .userInitiated) { BankImport.findIncome(merged, data: data, today: today) }.value
            guard !Task.isCancelled else { return }
            let label = ok.count > 1 ? "\(ok.count) Dateien" : merged.bank
            let r = BankReview(file: merged, result: res, income: inc, label: label, data: model.data)
            self.review = r
            // Logos schon jetzt suchen; höchstens ~8 s warten, der Rest kommt in der Liste nach
            withAnimation(.easeInOut(duration: 0.2)) { self.phase = .loading(step: 3, nTx: merged.tx.count) }
            self.logoTask = Task { @MainActor [weak self] in
                await BankLogos.run(r, model: model) { [weak self] in self?.alive == true }
                self?.logosFinished = true
            }
            await self.waitLogos(seconds: 8)
            guard !Task.isCancelled else { return }
            #if DEBUG
            if let j = self.jumpTo, let st = BankReview.Step(rawValue: j) { r.step = st }
            if self.jumpTo == "pay", let f = r.items.max(by: { $0.ed.amount / Double(Swift.max(1, $0.ed.cycle)) < $1.ed.amount / Double(Swift.max(1, $1.ed.cycle)) }) {
                r.togglePay(f.id)
            }
            #endif
            withAnimation(.easeInOut(duration: 0.25)) { self.phase = .review }
            if !bad.isEmpty {
                model.toast(bad.count == 1 ? "«\(bad[0].name)» nicht erkannt – übersprungen" : "\(bad.count) Dateien nicht erkannt – übersprungen", seconds: 3.2)
            }
        }
    }

    /// Auf die Logosuche warten, höchstens `seconds` (Web `Promise.race([lp, bkWait(8000)])`)
    private func waitLogos(seconds: Double) async {
        let end = Date().addingTimeInterval(seconds)
        while !logosFinished && Date() < end && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private static func waitUntil(_ t0: Date, _ seconds: Double) async {
        let left = seconds - Date().timeIntervalSince(t0)
        if left > 0 { try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000)) }
    }

    /// Nicht lesbar (Web v278): «Keine Buchungen» (alle ohne Buchungen im Zeitraum), «Kein Kontoauszug» bzw. «Keine Kontoauszüge»;
    /// je Datei eine Karte mit Grund, darunter der Rat zur einen Datei (nativ zusätzlich PDF/Foto über die Texterkennung)
    private static func failure(_ bad: [Read]) -> BankFailure {
        let allEmpty = !bad.isEmpty && bad.allSatisfy { $0.diag == .noBookings }
        let one = bad.count == 1
        func reason(_ x: Read) -> String {
            if x.big { return "Zu gross (über 20 MB)" }
            if x.visual { return "Keine Buchungen gefunden" }
            return x.diag.fileSubtitle
        }
        let text: String
        if allEmpty {
            text = BankReadDiag.noBookings.advice
        } else if one && bad[0].big {
            text = "Wähle einen kürzeren Zeitraum, z.B. die letzten 12 Monate."
        } else if !bad.isEmpty && bad.allSatisfy({ $0.visual }) {
            text = "Im Auszug wurden keine Buchungen mit Datum und Betrag gefunden. Fotografiere den Auszug gerade und gut beleuchtet oder nimm den CSV-Export aus dem E-Banking."
        } else if one {
            text = bad[0].diag.advice
        } else {
            text = "Diese Dateien enthalten keine Buchungen mit Datum und Betrag."
        }
        return BankFailure(title: allEmpty ? "Keine Buchungen" : one ? "Kein Kontoauszug" : "Keine Kontoauszüge", text: text,
                           files: bad.map { BankFailure.File(name: $0.name, reason: reason($0)) })
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
        } catch BankReadError.notRecognized(let diag) {
            return Read(name: name, file: nil, diag: diag)
        } catch BankReadError.tooBig {
            return Read(name: name, file: nil, big: true)
        } catch {
            return Read(name: name, file: nil)
        }
    }
}
