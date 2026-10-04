import UIKit
import KontivoCore

/// Lokaler Speicher: Daten als JSON (data.json) und Dateien (Logos, Dokumente, Bilder) unter Files/<id>.
/// Ordner: Application Support/Kontivo. Die Datei-IDs sind 32 Hex-Zeichen wie in der Web-App.
final class FileStore {
    let base: URL
    let filesDir: URL
    private var cache: [String: UIImage] = [:]
    private var metaCache: [String: String]?

    /// Ordner `Application Support/Kontivo` (echte Daten). Mit `folder` z.B. ein eigener Ordner für UI-Tests.
    init(folder: URL? = nil) {
        let fm = FileManager.default
        if let folder {
            base = folder
        } else {
            let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
                ?? fm.temporaryDirectory
            base = support.appendingPathComponent("Kontivo", isDirectory: true)
        }
        filesDir = base.appendingPathComponent("Files", isDirectory: true)
        try? fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
    }

    // MARK: Daten
    private var dataURL: URL { base.appendingPathComponent("data.json") }
    /// Vorversion (vor dem letzten Speichern), Rückfall beim Laden
    private var prevURL: URL { base.appendingPathComponent("data.prev.json") }

    /// Ergebnis des Ladens: fehlende und defekte Datei werden unterschieden.
    enum LoadResult {
        /// Keine Daten vorhanden (erster Start)
        case missing
        /// Gelesen; `fromPrevious` = data.json fehlte oder war defekt, die Vorversion wurde geladen
        case loaded(AppData, fromPrevious: Bool, brokenName: String?)
        /// data.json ist da, aber defekt und keine brauchbare Vorversion. `brokenName` = beiseitegelegte Datei
        case failed(brokenName: String?)
        /// Datei (noch) nicht lesbar, z.B. Gerät gesperrt (Dateischutz). Nichts verändern, später erneut laden.
        case unavailable
    }

    func loadData() -> LoadResult {
        let fm = FileManager.default
        if fm.fileExists(atPath: dataURL.path) {
            let raw: Data
            do {
                raw = try Data(contentsOf: dataURL)
            } catch {
                // Lesefehler (nicht Dekodierfehler): meist Dateischutz bei gesperrtem Gerät → Datei nicht anfassen
                return .unavailable
            }
            if let d = try? AppData.decode(raw) { return .loaded(d, fromPrevious: false, brokenName: nil) }
            // Defekt: beiseitelegen (nicht löschen), dann Vorversion versuchen
            let broken = moveAsideBroken()
            if let d = loadPrevious() { return .loaded(d, fromPrevious: true, brokenName: broken) }
            return .failed(brokenName: broken)
        }
        // data.json fehlt: Vorversion vorhanden? (z.B. Abbruch zwischen Sichern der Vorversion und Schreiben)
        if fm.fileExists(atPath: prevURL.path) {
            if let d = loadPrevious() { return .loaded(d, fromPrevious: true, brokenName: nil) }
        }
        return .missing
    }

    private func loadPrevious() -> AppData? {
        guard let raw = try? Data(contentsOf: prevURL) else { return nil }
        return try? AppData.decode(raw)
    }

    /// data.json → data.broken-<JJJJ-MM-TT-HHmmss>.json; gibt den Dateinamen zurück
    private func moveAsideBroken() -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        let name = "data.broken-" + f.string(from: Date()) + ".json"
        do {
            try FileManager.default.moveItem(at: dataURL, to: base.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    /// Speichert data.json; die bisherige Fassung bleibt als data.prev.json erhalten.
    @discardableResult
    func saveData(_ data: AppData) -> Bool {
        do {
            let d = try data.encoded()
            let fm = FileManager.default
            if fm.fileExists(atPath: dataURL.path) {
                try? fm.removeItem(at: prevURL)
                try? fm.copyItem(at: dataURL, to: prevURL)
                try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: prevURL.path)
            }
            try d.write(to: dataURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }

    // MARK: Dateien
    static func newID() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<16 { bytes[i] = UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    func url(_ id: String) -> URL { filesDir.appendingPathComponent(id) }

    func has(_ id: String?) -> Bool {
        guard let id, !id.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: url(id).path)
    }

    /// Speichert Daten unter neuer (oder vorgegebener) ID und gibt die ID zurück.
    @discardableResult
    func put(_ data: Data, type: String, id: String? = nil) throws -> String {
        let fid = id ?? FileStore.newID()
        try data.write(to: url(fid), options: [.atomic, .completeFileProtection])
        var m = loadMeta()
        m[fid] = type
        saveMeta(m)
        cache[fid] = nil
        return fid
    }

    func data(_ id: String?) -> Data? {
        guard let id, !id.isEmpty else { return nil }
        return try? Data(contentsOf: url(id))
    }

    func type(_ id: String) -> String { loadMeta()[id] ?? "" }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: url(id))
        var m = loadMeta(); m[id] = nil; saveMeta(m)
        cache[id] = nil
    }

    func allIDs() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: filesDir.path))?.filter { $0.count == 32 } ?? []
    }

    func deleteAll() {
        for id in allIDs() { try? FileManager.default.removeItem(at: url(id)) }
        saveMeta([:])
        cache.removeAll()
    }

    /// Verwaiste Dateien löschen: nicht in `keeping` und älter als `olderThanDays` (schützt Anhänge offener Formulare).
    /// Gibt die Anzahl gelöschter Dateien zurück.
    @discardableResult
    func collectGarbage(keeping: Set<String>, olderThanDays: Int = 7) -> Int {
        let limit = Date().addingTimeInterval(-Double(olderThanDays) * 86_400)
        var removed = 0
        var m = loadMeta()
        for id in allIDs() where !keeping.contains(id) {
            let attrs = try? FileManager.default.attributesOfItem(atPath: url(id).path)
            guard let mod = attrs?[.modificationDate] as? Date, mod < limit else { continue }
            if (try? FileManager.default.removeItem(at: url(id))) != nil {
                m[id] = nil
                cache[id] = nil
                removed += 1
            }
        }
        if removed > 0 { saveMeta(m) }
        return removed
    }

    func image(_ id: String?) -> UIImage? {
        guard let id, !id.isEmpty else { return nil }
        if let img = cache[id] { return img }
        guard let d = data(id), let img = UIImage(data: d) else { return nil }
        cache[id] = img
        return img
    }

    // MARK: Dateitypen (MIME) als kleine JSON-Tabelle
    private var metaURL: URL { base.appendingPathComponent("files.json") }

    private func loadMeta() -> [String: String] {
        if let m = metaCache { return m }
        let m = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: metaURL))) ?? [:]
        metaCache = m
        return m
    }

    private func saveMeta(_ m: [String: String]) {
        metaCache = m
        if let d = try? JSONEncoder().encode(m) { try? d.write(to: metaURL, options: .atomic) }
    }
}
