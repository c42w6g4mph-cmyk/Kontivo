import Foundation

/// Datei im nativen Backup (Base64).
public struct BackupFile: Codable, Hashable, Sendable {
    public var type: String
    public var data: String

    public init(type: String, data: String) {
        self.type = type
        self.data = data
    }
}

/// Natives Backup: `{app:"kontivo-ios", version:1, exported, data: AppData, files: {id: {type, data}}}`.
public struct NativeBackup: Codable, Sendable {
    public var app: String
    public var version: Int
    public var exported: String
    public var data: AppData
    public var files: [String: BackupFile]

    public init(app: String = Backup.appID, version: Int = Backup.formatVersion, exported: String, data: AppData, files: [String: BackupFile]) {
        self.app = app
        self.version = version
        self.exported = exported
        self.data = data
        self.files = files
    }
}

public struct BackupImportResult: Sendable {
    public enum Source: String, Sendable {
        case native, web
    }

    public var source: Source
    public var data: AppData
    public var files: [String: ImportedFile]
    /// Zeitpunkt des Backups (ISO-Text)
    public var exported: String?
    /// Dateien, die nicht gelesen werden konnten
    public var failedFiles: Int

    /// Text der Rückfrage «Backup einspielen?».
    public func confirmText(calendar: Calendar = Day.calendar) -> String {
        Backup.confirmText(exported: exported, contracts: data.contracts.count, incomes: data.incomes.count, files: files.count, calendar: calendar)
    }
}

public enum BackupError: Error, Equatable {
    /// Keine gültige Backup-Datei
    case invalidFile
    /// Backup einer neueren App-Version
    case unsupportedVersion(Int)
}

public enum Backup {
    public static let appID = "kontivo-ios"
    public static let formatVersion = 1

    public static let confirmTitle = "Backup einspielen?"
    public static let confirmButton = "Einspielen"
    public static let invalidMessage = "Keine gültige Backup-Datei"
    public static let doneMessage = "Backup eingespielt"

    /// Dateiname «kontivo-sicherung-JJJJ-MM-TT.json».
    public static func fileName(today: Day) -> String {
        "kontivo-sicherung-" + today.iso + ".json"
    }

    /// Natives Backup erzeugen. Mitgenommen werden nur Dateien, die in den Daten referenziert sind.
    public static func export(_ data: AppData, files: [String: ImportedFile], now: Date = Date()) throws -> Data {
        var out: [String: BackupFile] = [:]
        for id in data.referencedFileIDs {
            if let f = files[id] { out[id] = BackupFile(type: f.type, data: f.data.base64EncodedString()) }
        }
        let doc = NativeBackup(exported: Timestamp.isoString(now), data: data, files: out)
        return try KontivoJSON.makeEncoder().encode(doc)
    }

    /// Referenzierte Dateien, die im Dateispeicher fehlen (für die Rückfrage vor dem Sichern).
    public static func missingFiles(_ data: AppData, available: Set<String>) -> [String] {
        data.referencedFileIDs.filter { !available.contains($0) }
    }

    /// Backup lesen: natives Format oder Web-Backup (`app:"vertraege"`, über WebImport).
    public static func read(_ json: Data, today: Day, now: Date = Date()) throws -> BackupImportResult {
        guard let v = try? JSONParser.parse(json), case .object(let o) = v else { throw BackupError.invalidFile }
        let app = JS.str(o["app"])
        if app == appID {
            let ver = JS.intOr(o["version"], 1)
            if ver > formatVersion { throw BackupError.unsupportedVersion(ver) }
            guard let doc = try? KontivoJSON.makeDecoder().decode(NativeBackup.self, from: json) else { throw BackupError.invalidFile }
            var files: [String: ImportedFile] = [:]
            var failed = 0
            for (k, f) in doc.files {
                if let d = Data(base64Encoded: f.data, options: .ignoreUnknownCharacters) {
                    files[k] = ImportedFile(type: f.type, data: d)
                } else {
                    failed += 1
                }
            }
            return BackupImportResult(source: .native, data: doc.data, files: files, exported: doc.exported.isEmpty ? nil : doc.exported, failedFiles: failed)
        }
        if app == "vertraege" && WebImport.isObjectLike(o["contracts"]) {
            let r = WebImport.importObject(o, today: today, now: now)
            return BackupImportResult(source: .web, data: r.data, files: r.files, exported: r.exported, failedFiles: r.failedFiles)
        }
        throw BackupError.invalidFile
    }

    /// «Backup vom 3.10.2026 mit 12 Verträgen und 2 Einnahmen sowie 5 Logos/Dokumenten.\n\nDie aktuellen Daten werden ersetzt.»
    public static func confirmText(exported: String?, contracts: Int, incomes: Int, files: Int, calendar: Calendar = Day.calendar) -> String {
        var when = "unbekannt"
        if let e = exported, let d = Timestamp.parse(e) { when = Format.shortNumericDate(Day(date: d, calendar: calendar)) }
        return "Backup vom " + when + " mit " + Format.count(contracts, "Vertrag", "Verträgen") + " und " + Format.count(incomes, "Einnahme", "Einnahmen")
            + (files > 0 ? " sowie " + Format.count(files, "Logo/Dokument", "Logos/Dokumenten") : "") + ".\n\nDie aktuellen Daten werden ersetzt."
    }

    /// Meldung nach dem Einspielen («Backup eingespielt» bzw. mit fehlenden Dateien).
    public static func doneText(failedFiles: Int) -> String {
        failedFiles > 0 ? "Backup eingespielt – " + Format.count(failedFiles, "Datei fehlt", "Dateien fehlen") : doneMessage
    }
}
