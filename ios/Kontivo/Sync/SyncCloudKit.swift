import Foundation
import CloudKit
import KontivoCore

// MARK: - Konfiguration

/// Schalter und Konstanten des iCloud-Sync. CloudKit wird nur angesprochen, wenn der Build iCloud kann
/// (`KONTIVO_ICLOUD = YES` in project.yml → Info.plist «KontivoICloud»): ohne Berechtigung stürzt `CKContainer` ab.
enum SyncConfig {
    /// Build mit iCloud-Berechtigung
    static let buildEnabled: Bool = {
        let v = Bundle.main.object(forInfoDictionaryKey: "KontivoICloud")
        if let b = v as? Bool { return b }
        if let s = v as? String { return ["YES", "TRUE", "1"].contains(s.trimmingCharacters(in: .whitespaces).uppercased()) }
        return false
    }()

    /// iCloud-Container (Info.plist «KontivoICloudContainer» = `KONTIVO_ICLOUD_CONTAINER`)
    static let containerID: String = {
        if let s = Bundle.main.object(forInfoDictionaryKey: "KontivoICloudContainer") as? String, s.hasPrefix("iCloud.") { return s }
        return "iCloud.ch.kontivo.app"
    }()

    /// Eigene Zone in der privaten Datenbank
    static let zoneName = "Kontivo"
    static var zoneID: CKRecordZone.ID { CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName) }

    private static let enabledKey = "kontivo.icloud.enabled"

    /// Wahl des Nutzers; ohne Wahl an (wenn der Build iCloud kann und ein Konto angemeldet ist)
    static var userEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }
}

// MARK: - SyncRecord ↔ CKRecord

/// Übersetzung zwischen den Datensätzen des Kerns und CloudKit. Die Nutzlast (JSON) und die Änderungszeit liegen in
/// `encryptedValues` (Ende-zu-Ende verschlüsselt, nur der Nutzer kann sie lesen); Dateien als `CKAsset`.
enum SyncRecordMapper {
    static let payloadKey = "payload"
    static let payloadAssetKey = "payloadAsset"
    static let modifiedKey = "modifiedAt"
    static let versionKey = "v"
    static let typeKey = "type"
    static let assetKey = "asset"
    /// Grössere Nutzlast (z.B. Person mit Unterschrift) als Anhang statt im Datensatz (CloudKit: Datensatz max. 1 MB)
    static let inlineLimit = 700_000

    static func recordID(_ key: SyncKey) -> CKRecord.ID {
        CKRecord.ID(recordName: key.recordName, zoneID: SyncConfig.zoneID)
    }

    /// Schlüssel eines Datensatzes unserer Zone
    static func key(_ id: CKRecord.ID) -> SyncKey? {
        guard id.zoneID == SyncConfig.zoneID else { return nil }
        return SyncKey(recordName: id.recordName)
    }

    /// Datensatz mit den gespeicherten Systemfeldern (Änderungsmarke) oder neu
    static func base(type: String, id: CKRecord.ID, systemFields: Data?) -> CKRecord {
        if let sf = systemFields, let r = decodeSystemFields(sf), r.recordID == id, r.recordType == type { return r }
        return CKRecord(recordType: type, recordID: id)
    }

    static func record(for rec: SyncRecord, id: CKRecord.ID, systemFields: Data?) -> CKRecord {
        let r = base(type: rec.key.kind.recordType, id: id, systemFields: systemFields)
        if rec.payload.count > inlineLimit, let url = tempFile(rec.payload, name: id.recordName) {
            r.encryptedValues[payloadKey] = nil
            r[payloadAssetKey] = CKAsset(fileURL: url)
        } else {
            r.encryptedValues[payloadKey] = rec.payload
            r[payloadAssetKey] = nil
        }
        r.encryptedValues[modifiedKey] = rec.modifiedAt
        r.encryptedValues[versionKey] = rec.version
        return r
    }

    static func fileRecord(id: CKRecord.ID, url: URL, type: String, systemFields: Data?) -> CKRecord {
        let r = base(type: SyncKind.file.recordType, id: id, systemFields: systemFields)
        r.encryptedValues[typeKey] = type
        r[assetKey] = CKAsset(fileURL: url)
        return r
    }

    /// Nutzlast (im Datensatz oder als Anhang)
    static func payload(of r: CKRecord) -> Data? {
        let inline: Data? = r.encryptedValues[payloadKey]
        if let inline { return inline }
        let asset: CKAsset? = r[payloadAssetKey]
        guard let url = asset?.fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    static func syncRecord(from r: CKRecord, key: SyncKey) -> SyncRecord? {
        guard let p = payload(of: r) else { return nil }
        let modified: Date? = r.encryptedValues[modifiedKey]
        let version: Int? = r.encryptedValues[versionKey]
        return SyncRecord(key: key, payload: p, modifiedAt: modified ?? r.modificationDate ?? Date.distantPast,
                          version: version ?? SyncCodec.formatVersion)
    }

    /// Dateiinhalt und Typ eines Datei-Datensatzes
    static func file(of r: CKRecord) -> (data: Data, type: String)? {
        let asset: CKAsset? = r[assetKey]
        guard let url = asset?.fileURL, let d = try? Data(contentsOf: url) else { return nil }
        let type: String? = r.encryptedValues[typeKey]
        return (d, type ?? "")
    }

    // MARK: Systemfelder

    static func systemFields(_ r: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        r.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func decodeSystemFields(_ d: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: d) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Zwischendateien für grosse Nutzlast

    private static var tempDir: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("KontivoSync", isDirectory: true)
    }

    static func tempFile(_ data: Data, name: String) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        } catch {
            return nil
        }
    }

    static func removeTempFile(name: String) {
        try? FileManager.default.removeItem(at: tempDir.appendingPathComponent(name))
    }
}

// MARK: - Delegierter der CKSyncEngine

/// Leitet die Ereignisse der CKSyncEngine an den `SyncController` (MainActor) weiter. `generation` verwirft Ereignisse
/// einer abgelösten Engine (Ausschalten, Kontowechsel).
final class SyncEngineBridge: CKSyncEngineDelegate, @unchecked Sendable {
    weak var controller: SyncController?
    let generation: Int

    init(controller: SyncController, generation: Int) {
        self.controller = controller
        self.generation = generation
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await controller?.handle(event, engine: syncEngine, generation: generation)
    }

    func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext,
                                   syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await controller?.nextBatch(context, engine: syncEngine, generation: generation)
    }
}
