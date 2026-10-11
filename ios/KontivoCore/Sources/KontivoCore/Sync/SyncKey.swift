import Foundation

// MARK: - iCloud-Sync: Schlüssel und Datensatz
//
// Der Abgleich zerlegt `AppData` in einzelne Datensätze: je Vertrag, Einnahme, Person, Kategorie, Vertragspartner und Datei
// einen, dazu einen für die abgeglichenen Einstellungen. Der Kern kennt CloudKit nicht: Die App übersetzt `SyncRecord`
// in `CKRecord` und zurück (ios/Kontivo/Sync). So lässt sich alles hier ohne CloudKit testen.

/// Art eines abgeglichenen Datensatzes. Rohwert = Präfix des Datensatznamens («contract.<UUID>»).
public enum SyncKind: String, Codable, CaseIterable, Hashable, Sendable {
    case settings, person, category, partner, contract, income, file

    /// Datensatztyp in CloudKit
    public var recordType: String {
        switch self {
        case .settings: return "Settings"
        case .person: return "Person"
        case .category: return "Category"
        case .partner: return "Partner"
        case .contract: return "Contract"
        case .income: return "Income"
        case .file: return "File"
        }
    }

    /// Reihenfolge beim Sortieren (Stammdaten vor Verträgen, Einstellungen vorne, Dateien zuletzt)
    var rank: Int {
        switch self {
        case .settings: return 0
        case .person: return 1
        case .category: return 2
        case .partner: return 3
        case .contract: return 4
        case .income: return 5
        case .file: return 6
        }
    }
}

/// Schlüssel eines Datensatzes: Art + ID (UUID gross geschrieben wie `uuidString`, Datei-ID 32 Hex, Einstellungen «main»).
public struct SyncKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let kind: SyncKind
    public let id: String

    /// Schlüssel einer Entität mit UUID (Person, Kategorie, Vertragspartner, Vertrag, Einnahme)
    public init(_ kind: SyncKind, _ id: UUID) {
        self.kind = kind
        self.id = id.uuidString
    }

    /// Ungeprüft (intern und für Tests)
    init(kind: SyncKind, rawID: String) {
        self.kind = kind
        self.id = rawID
    }

    /// Der eine Datensatz der Einstellungen
    public static let settings = SyncKey(kind: .settings, rawID: "main")

    /// Datei (Logo, Dokument, Bild); nil bei ungültiger ID (schützt den Dateispeicher vor fremden Pfaden)
    public static func file(_ id: String) -> SyncKey? {
        isFileID(id) ? SyncKey(kind: .file, rawID: id) : nil
    }

    /// Datensatzname in CloudKit, z.B. «contract.6F9619FF-8B86-D011-B42D-00C04FC964FF», «file.0a1b…», «settings.main»
    public var recordName: String { kind.rawValue + "." + id }

    /// Aus dem Datensatznamen lesen; nil bei unbekannter Art oder ungültiger ID.
    public init?(recordName: String) {
        guard let dot = recordName.firstIndex(of: ".") else { return nil }
        guard let kind = SyncKind(rawValue: String(recordName[..<dot])) else { return nil }
        let raw = String(recordName[recordName.index(after: dot)...])
        switch kind {
        case .settings:
            guard raw == "main" else { return nil }
            self.init(kind: .settings, rawID: raw)
        case .file:
            guard SyncKey.isFileID(raw) else { return nil }
            self.init(kind: .file, rawID: raw)
        case .person, .category, .partner, .contract, .income:
            guard let u = UUID(uuidString: raw) else { return nil }
            self.init(kind, u)
        }
    }

    /// UUID der Entität (nil bei Einstellungen und Dateien)
    public var uuid: UUID? {
        switch kind {
        case .settings, .file: return nil
        default: return UUID(uuidString: id)
        }
    }

    /// Datei-ID wie in der Web-App: genau 32 Hex-Zeichen
    public static func isFileID(_ s: String) -> Bool {
        s.utf8.count == 32 && s.utf8.allSatisfy { c in
            switch c {
            case 48...57, 65...70, 97...102: return true
            default: return false
            }
        }
    }

    public static func < (a: SyncKey, b: SyncKey) -> Bool {
        a.kind.rank != b.kind.rank ? a.kind.rank < b.kind.rank : a.id < b.id
    }

    public var description: String { recordName }
}

/// Ein Datensatz, wie er übertragen wird: Nutzlast (JSON der Entität) und Zeitpunkt der letzten Änderung.
/// Dateien tragen keine Nutzlast (der Inhalt geht als Anhang, siehe App).
public struct SyncRecord: Hashable, Sendable {
    public var key: SyncKey
    public var payload: Data
    public var modifiedAt: Date
    /// Formatversion der Nutzlast (`SyncCodec.formatVersion`)
    public var version: Int

    public init(key: SyncKey, payload: Data, modifiedAt: Date, version: Int = SyncCodec.formatVersion) {
        self.key = key
        self.payload = payload
        self.modifiedAt = modifiedAt
        self.version = version
    }
}
