import UIKit
import KontivoCore

/// Lokaler Speicher: Daten als JSON (data.json) und Dateien (Logos, Dokumente, Bilder) unter Files/<id>.
/// Ordner: Application Support/Kontivo. Die Datei-IDs sind 32 Hex-Zeichen wie in der Web-App.
final class FileStore {
    let base: URL
    let filesDir: URL
    private var cache: [String: UIImage] = [:]
    private var metaCache: [String: String]?

    init() {
        let fm = FileManager.default
        let support = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        base = support.appendingPathComponent("Kontivo", isDirectory: true)
        filesDir = base.appendingPathComponent("Files", isDirectory: true)
        try? fm.createDirectory(at: filesDir, withIntermediateDirectories: true)
    }

    // MARK: Daten
    private var dataURL: URL { base.appendingPathComponent("data.json") }

    func loadData() -> AppData? {
        guard let d = try? Data(contentsOf: dataURL) else { return nil }
        return try? AppData.decode(d)
    }

    @discardableResult
    func saveData(_ data: AppData) -> Bool {
        do {
            let d = try data.encoded()
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
