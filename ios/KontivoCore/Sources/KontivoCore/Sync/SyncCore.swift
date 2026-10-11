import Foundation

// MARK: - Zustand des Abgleichs (sync-state, neben data.json, nicht im Backup)

/// Gespeicherter Zustand des Abgleichs. `data.json` bleibt die lokale Wahrheit; hier steht nur, was der Abgleich über die
/// Datensätze weiss: lokale Fassung (Prüfsumme, Änderungszeit), noch nicht Gesendetes, Server-Systemfelder, Engine-Zustand.
public struct SyncLedger: Codable, Equatable, Sendable {
    /// Lokale Fassung eines Datensatzes
    public struct Entry: Codable, Equatable, Sendable {
        /// Prüfsumme der Nutzlast; nil = lokal gelöscht (bleibt, bis die Löschung gesendet ist)
        public var digest: String?
        /// Zeitpunkt der letzten Änderung (lokal erfasst oder vom Server übernommen) – entscheidet Konflikte
        public var modifiedAt: Date

        public init(digest: String?, modifiedAt: Date) {
            self.digest = digest
            self.modifiedAt = modifiedAt
        }
    }

    /// Noch zu sendende Änderung
    public enum Pending: String, Codable, Sendable {
        case save, delete
    }

    public var format = 1
    /// Datensatzname → lokale Fassung (bleibt beim Ausschalten und Kontowechsel erhalten)
    public var entries: [String: Entry] = [:]
    /// Datensatzname → noch zu senden
    public var pending: [String: Pending] = [:]
    /// Zuletzt erfasste/übernommene abgeglichene Einstellungen (Basis für die Reihenfolgen)
    public var settingsBase: SyncSettings?
    /// Einstellungen, wie sie zuletzt in iCloud lagen (Basis für das Zusammenführen Feld für Feld)
    public var settingsServer: SyncSettings?
    /// Datensatzname → Systemfelder des Servers (CKRecord `encodeSystemFields`, für Änderungsmarken)
    public var systemFields: [String: Data] = [:]
    /// Datei-IDs, die auf dem Server liegen (hochgeladen oder heruntergeladen)
    public var serverFiles: Set<String> = []
    /// Zustand der CKSyncEngine (`State.Serialization` als JSON), erst nach dem ersten Einrichten
    public var engineState: Data?
    /// Erstes Einrichten (erster vollständiger Abruf und Zusammenführen) abgeschlossen
    public var initialDone = false
    /// iCloud-Konto (Datensatzname des Benutzers), mit dem zuletzt abgeglichen wurde
    public var accountName: String?
    /// Letzter erfolgreicher Abgleich
    public var lastSync: Date?
    /// Zusammengeführte Doppelte: Datensatzname → behaltener Datensatzname
    public var aliases: [String: String] = [:]

    public init() {}

    /// Fehlende Felder (ältere/neuere Fassung) → Standardwert
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        format = c.value(.format, 1)
        entries = c.value(.entries, [String: Entry]())
        pending = c.value(.pending, [String: Pending]())
        settingsBase = c.optional(.settingsBase)
        settingsServer = c.optional(.settingsServer)
        systemFields = c.value(.systemFields, [String: Data]())
        serverFiles = c.value(.serverFiles, Set<String>())
        engineState = c.optional(.engineState)
        initialDone = c.value(.initialDone, false)
        accountName = c.optional(.accountName)
        lastSync = c.optional(.lastSync)
        aliases = c.value(.aliases, [String: String]())
    }
}

// MARK: - Kern des Abgleichs (ohne CloudKit)

/// Zustandsmodell des Abgleichs. Bildet ab, was die CKSyncEngine meldet (abgerufen, gesendet, Konflikt, Datensatz/Zone
/// fehlt) und entscheidet nach festen Regeln:
/// - Lokale Änderungen: Vergleich alter/neuer Stand je Entität, Prüfsumme gegen die zuletzt bekannte Fassung.
/// - Konflikt: pro Datensatz gewinnt die neuere Änderung (`modifiedAt`). Eine noch nicht gesendete lokale Änderung gewinnt
///   gegen eine entfernte Löschung (kein Datenverlust).
/// - Erstes Einrichten: iCloud leer → alles hochladen; Gerät unberührt → iCloud-Daten übernehmen; sonst vereinigen und
///   Doppelte zusammenführen.
public struct SyncCore: Sendable {
    public var ledger: SyncLedger
    /// Beim ersten Einrichten gesammelte Datensätze (bis der Abruf vollständig ist; nicht gespeichert)
    public private(set) var initialRecords: [SyncKey: SyncRecord] = [:]
    public private(set) var initialDeleted: Set<SyncKey> = []

    public init(ledger: SyncLedger = SyncLedger()) {
        self.ledger = ledger
    }

    /// Noch zu sendende Datensätze (sortiert: Einstellungen, Stammdaten, Verträge, Einnahmen, Dateien)
    public var pendingKeys: [SyncKey] {
        ledger.pending.keys.compactMap { SyncKey(recordName: $0) }.sorted()
    }

    public func pending(_ key: SyncKey) -> SyncLedger.Pending? { ledger.pending[key.recordName] }

    // MARK: Lokale Änderungen

    /// Lokale Änderungen erfassen. `previous` = Stand der letzten Erfassung: nur abweichende Entitäten werden kodiert und
    /// geprüft; nil = alle Entitäten prüfen (Start). Rückgabe: neu zu sendende Datensätze.
    @discardableResult
    public mutating func captureLocalChanges(_ data: AppData, previous: AppData?, now: Date) -> [SyncKey] {
        let enc = SyncCodec.makeEncoder()
        var candidates: [SyncKey]
        if let previous {
            let d = SyncDiff.diff(old: previous, new: data)
            candidates = d.save + d.delete
            // Einstellungen immer prüfen (Reihenfolgen gegen die bekannte Fassung)
            if !candidates.contains(.settings) { candidates.append(.settings) }
        } else {
            var all = Set(SyncCodec.keys(of: data))
            for name in ledger.entries.keys {
                if let k = SyncKey(recordName: name), k.kind != .file { all.insert(k) }
            }
            candidates = all.sorted()
        }
        var changed: [SyncKey] = []
        for key in candidates where key.kind != .file {
            let name = key.recordName
            let payload: Data?
            if key.kind == .settings {
                let s = SyncSettings(data, base: ledger.settingsBase)
                ledger.settingsBase = s
                payload = SyncCodec.encode(s, encoder: enc)
            } else {
                payload = SyncCodec.payload(key, in: data, settingsBase: nil, encoder: enc)
            }
            if let p = payload {
                let dg = SyncCodec.digest(p)
                if ledger.entries[name]?.digest != dg {
                    ledger.entries[name] = SyncLedger.Entry(digest: dg, modifiedAt: now)
                    ledger.pending[name] = .save
                    changed.append(key)
                }
            } else if let e = ledger.entries[name], e.digest != nil {
                ledger.entries[name] = SyncLedger.Entry(digest: nil, modifiedAt: now)
                ledger.pending[name] = .delete
                changed.append(key)
            }
        }
        return changed
    }

    /// Dateien: referenzierte und vorhandene hochladen; auf dem Server liegende, die lokal nicht mehr referenziert und nicht
    /// mehr vorhanden sind (Aufräumen nach 7 Tagen, «Alle Daten löschen»), auch dort löschen.
    @discardableResult
    public mutating func captureFiles(_ data: AppData, isPresent: (String) -> Bool) -> [SyncKey] {
        var changed: [SyncKey] = []
        let referenced = Set(data.referencedFileIDs.filter { SyncKey.isFileID($0) })
        // Vorhandensein einmal je Datei prüfen
        var ids = referenced.union(ledger.serverFiles)
        for name in ledger.pending.keys {
            if let k = SyncKey(recordName: name), k.kind == .file { ids.insert(k.id) }
        }
        var present: [String: Bool] = [:]
        for id in ids { present[id] = isPresent(id) }
        let has = { (id: String) -> Bool in present[id] ?? false }
        for id in referenced.sorted() {
            let key = SyncKey(kind: .file, rawID: id)
            let name = key.recordName
            if has(id) {
                if !ledger.serverFiles.contains(id) {
                    if ledger.pending[name] != .save {
                        ledger.pending[name] = .save
                        changed.append(key)
                    }
                } else if ledger.pending[name] == .delete {
                    ledger.pending[name] = nil
                }
            }
        }
        for id in ledger.serverFiles.sorted() where !referenced.contains(id) && !has(id) {
            let key = SyncKey(kind: .file, rawID: id)
            if ledger.pending[key.recordName] != .delete {
                ledger.pending[key.recordName] = .delete
                changed.append(key)
            }
        }
        // Hochladen nicht mehr möglich/nötig (Datei fehlt oder wird nicht mehr gebraucht)
        for (name, p) in ledger.pending where p == .save {
            guard let k = SyncKey(recordName: name), k.kind == .file else { continue }
            if !referenced.contains(k.id) || !has(k.id) { ledger.pending[name] = nil }
        }
        return changed
    }

    // MARK: Senden

    /// Was für einen Datensatz zu senden ist.
    public enum Outgoing: Equatable, Sendable {
        case save(SyncRecord)
        /// Datei hochladen (Inhalt und Typ liefert die App)
        case saveFile(String)
        case delete(SyncKey)
    }

    /// Zu sendender Inhalt für `key`; nil = nichts zu tun (nicht mehr ausstehend, erstes Einrichten läuft noch).
    public func outgoing(_ key: SyncKey, data: AppData, now: Date = Date()) -> Outgoing? {
        guard ledger.initialDone, let p = ledger.pending[key.recordName] else { return nil }
        switch p {
        case .delete:
            return .delete(key)
        case .save:
            if key.kind == .file { return .saveFile(key.id) }
            guard let payload = SyncCodec.payload(key, in: data, settingsBase: ledger.settingsBase) else { return nil }
            return .save(SyncRecord(key: key, payload: payload, modifiedAt: ledger.entries[key.recordName]?.modifiedAt ?? now))
        }
    }

    /// Gespeichert und bestätigt. `payload` = gesendete Nutzlast. Rückgabe true = seither wieder geändert, erneut senden.
    @discardableResult
    public mutating func didSave(_ key: SyncKey, payload: Data?, systemFields: Data?) -> Bool {
        let name = key.recordName
        if let sf = systemFields { ledger.systemFields[name] = sf }
        if key.kind == .file {
            ledger.serverFiles.insert(key.id)
            if ledger.pending[name] == .save { ledger.pending[name] = nil }
            return ledger.pending[name] != nil
        }
        if key.kind == .settings, let payload, let s = SyncCodec.decode(SyncSettings.self, from: payload) {
            ledger.settingsServer = s
        }
        guard ledger.pending[name] == .save else { return ledger.pending[name] != nil }
        if let payload, let e = ledger.entries[name], e.digest == SyncCodec.digest(payload) {
            ledger.pending[name] = nil
            return false
        }
        return true
    }

    /// Gelöscht (oder auf dem Server schon nicht mehr vorhanden). Rückgabe true = inzwischen wieder angelegt, senden.
    @discardableResult
    public mutating func didDelete(_ key: SyncKey) -> Bool {
        let name = key.recordName
        ledger.systemFields[name] = nil
        if key.kind == .file { ledger.serverFiles.remove(key.id) }
        if ledger.pending[name] == .delete {
            ledger.pending[name] = nil
            if let e = ledger.entries[name], e.digest == nil { ledger.entries[name] = nil }
            return false
        }
        return ledger.pending[name] != nil
    }

    /// Datensatz gibt es auf dem Server nicht mehr (unknownItem): Systemfelder verwerfen, die Änderung bleibt ausstehend
    /// und wird als neuer Datensatz gesendet.
    public mutating func recordMissingOnServer(_ key: SyncKey) {
        ledger.systemFields[key.recordName] = nil
        if key.kind == .file { ledger.serverFiles.remove(key.id) }
    }

    /// Konflikt beim Speichern (Server hat eine andere Fassung). Die neuere Änderung gewinnt; bei Gleichstand der Server.
    /// Rückgabe true = lokale Fassung bleibt ausstehend und wird mit den neuen Systemfeldern erneut gesendet.
    public mutating func resolveConflict(server: SyncRecord, systemFields: Data?, data: inout AppData, now: Date) -> Bool {
        let name = server.key.recordName
        if let sf = systemFields { ledger.systemFields[name] = sf }
        if server.key.kind == .file {
            // Gleiche Datei-ID = gleicher Inhalt: liegt schon auf dem Server
            ledger.serverFiles.insert(server.key.id)
            if ledger.pending[name] == .save { ledger.pending[name] = nil }
            return ledger.pending[name] != nil
        }
        _ = applyNormal(records: [server], deletions: [], data: &data, isPresent: { _ in true }, now: now)
        return ledger.pending[name] != nil
    }

    /// Zone fehlt auf dem Server (gelöscht oder zurückgesetzt): alles neu hochladen.
    @discardableResult
    public mutating func zoneMissing(_ data: AppData, isPresent: (String) -> Bool, now: Date) -> [SyncKey] {
        markAllForUpload(data, isPresent: isPresent, now: now)
        return pendingKeys
    }

    // MARK: Empfangen

    public struct ApplyResult: Equatable, Sendable {
        /// Daten haben sich geändert
        public var changed = false
        /// Datensätze, die (wieder) gesendet werden müssen
        public var resend: [SyncKey] = []
        /// Erstes Einrichten läuft: nur gesammelt
        public var buffered = false

        public init(changed: Bool = false, resend: [SyncKey] = [], buffered: Bool = false) {
            self.changed = changed
            self.resend = resend
            self.buffered = buffered
        }
    }

    /// Abgerufene Änderungen übernehmen. `systemFields` je Datensatzname, `storedFiles` = abgerufene und lokal gespeicherte
    /// Dateien. Während des ersten Einrichtens wird nur gesammelt (siehe `finishFetch`).
    public mutating func applyRemote(records: [SyncRecord], deletions: [SyncKey], systemFields: [String: Data] = [:],
                                     storedFiles: [String] = [], data: inout AppData, isPresent: (String) -> Bool,
                                     now: Date) -> ApplyResult {
        for (k, v) in systemFields { ledger.systemFields[k] = v }
        for id in storedFiles where SyncKey.isFileID(id) {
            ledger.serverFiles.insert(id)
            let name = SyncKey(kind: .file, rawID: id).recordName
            if ledger.pending[name] == .save { ledger.pending[name] = nil }
        }
        if !ledger.initialDone {
            for r in records where r.key.kind != .file {
                initialRecords[r.key] = r
                initialDeleted.remove(r.key)
            }
            for k in deletions {
                initialRecords[k] = nil
                initialDeleted.insert(k)
                ledger.systemFields[k.recordName] = nil
                if k.kind == .file { ledger.serverFiles.remove(k.id) }
            }
            return ApplyResult(buffered: true)
        }
        return applyNormal(records: records, deletions: deletions, data: &data, isPresent: isPresent, now: now)
    }

    mutating func applyNormal(records: [SyncRecord], deletions: [SyncKey], data: inout AppData,
                              isPresent: (String) -> Bool, now: Date) -> ApplyResult {
        var res = ApplyResult()
        let before = data
        let aliases = SyncAliases(ledger.aliases)
        let enc = SyncCodec.makeEncoder()
        var new = SyncMerge.NewItems()
        var remoteSettings: SyncRecord?

        for r in records.sorted(by: { $0.key < $1.key }) {
            let key = r.key
            if key.kind == .file { continue }
            if key.kind == .settings {
                remoteSettings = r
                continue
            }
            let name = key.recordName
            if ledger.pending[name] != nil, let e = ledger.entries[name], e.modifiedAt > r.modifiedAt {
                // Lokale Fassung (oder Löschung) ist neuer
                res.resend.append(key)
                continue
            }
            guard let entity = SyncCodec.decodeEntity(r) else { continue }
            let (stored, rewritten) = aliases.rewrite(entity)
            SyncMerge.upsert(stored, into: &data, new: &new)
            let dg = SyncCodec.payload(of: stored, encoder: enc).map { SyncCodec.digest($0) }
            if rewritten {
                // Verweis auf eine zusammengeführte Entität umgebogen: korrigierte Fassung senden
                ledger.entries[name] = SyncLedger.Entry(digest: dg, modifiedAt: max(now, r.modifiedAt))
                ledger.pending[name] = .save
                res.resend.append(key)
            } else {
                ledger.entries[name] = SyncLedger.Entry(digest: dg, modifiedAt: r.modifiedAt)
                ledger.pending[name] = nil
            }
        }
        SyncMerge.appendNew(new, to: &data)

        let referenced = Set(data.referencedFileIDs)
        for key in deletions.sorted() {
            let name = key.recordName
            ledger.systemFields[name] = nil
            if key.kind == .file {
                ledger.serverFiles.remove(key.id)
                if referenced.contains(key.id) && isPresent(key.id) {
                    // Noch gebraucht: wieder hochladen
                    ledger.pending[name] = .save
                    res.resend.append(key)
                } else if ledger.pending[name] == .delete {
                    ledger.pending[name] = nil
                }
                continue
            }
            if ledger.pending[name] == .save || key.kind == .settings {
                // Noch nicht gesendete lokale Änderung gewinnt gegen die Löschung; Einstellungen gibt es immer
                if ledger.entries[name]?.digest != nil {
                    ledger.pending[name] = .save
                    res.resend.append(key)
                }
                continue
            }
            SyncMerge.remove(key, from: &data)
            ledger.entries[name] = nil
            ledger.pending[name] = nil
        }

        if let r = remoteSettings, case .settings(let s0)? = SyncCodec.decodeEntity(r),
           case (.settings(let rs), let rewritten) = aliases.rewrite(.settings(s0)) {
            let name = r.key.recordName
            let localTime = ledger.entries[name]?.modifiedAt ?? .distantPast
            if ledger.pending[name] == .save, let base = ledger.settingsServer {
                // Beide Seiten geändert: Feld für Feld zusammenführen (beide Änderungen bleiben)
                let local = SyncSettings(data, base: ledger.settingsBase)
                let merged = SyncSettings.merge(base: base, local: local, remote: rs)
                merged.apply(to: &data.settings)
                ledger.settingsServer = s0
                ledger.settingsBase = merged
                let dg = SyncCodec.encode(merged, encoder: enc).map { SyncCodec.digest($0) }
                ledger.entries[name] = SyncLedger.Entry(digest: dg, modifiedAt: max(now, localTime, r.modifiedAt))
                if merged == s0 {
                    ledger.pending[name] = nil
                } else {
                    ledger.pending[name] = .save
                    res.resend.append(r.key)
                }
            } else if ledger.pending[name] != nil, localTime > r.modifiedAt {
                // Ohne bekannte Basis: neuere Fassung gewinnt (hier die lokale)
                ledger.settingsServer = s0
                res.resend.append(r.key)
            } else {
                rs.apply(to: &data.settings)
                ledger.settingsServer = s0
                ledger.settingsBase = rs
                let dg = SyncCodec.encode(rs, encoder: enc).map { SyncCodec.digest($0) }
                ledger.entries[name] = SyncLedger.Entry(digest: dg, modifiedAt: rewritten ? max(now, r.modifiedAt) : r.modifiedAt)
                ledger.pending[name] = rewritten ? .save : nil
                if rewritten { res.resend.append(r.key) }
            }
        }
        SyncMerge.applyOrders(&data, settings: ledger.settingsBase)
        res.changed = data != before
        return res
    }

    // MARK: Abruf abgeschlossen

    public struct FinishResult: Equatable, Sendable {
        public var changed = false
        /// Zu sendende Datensätze (Doppelte zusammengeführt, Ergänzungen, beim ersten Einrichten alles Lokale)
        public var resend: [SyncKey] = []
        /// Dieser Abschluss war das erste Einrichten
        public var initial = false
        /// Erstes Einrichten auf einem unberührten Gerät: iCloud-Daten übernommen
        public var adopted = false

        public init(changed: Bool = false, resend: [SyncKey] = [], initial: Bool = false, adopted: Bool = false) {
            self.changed = changed
            self.resend = resend
            self.initial = initial
            self.adopted = adopted
        }
    }

    /// Nach einem vollständigen Abruf: erstes Einrichten abschliessen, Doppelte zusammenführen, Mindestbestand sichern,
    /// dadurch entstandene lokale Änderungen erfassen. Nur nach einem fehlerfreien Abruf aufrufen.
    public mutating func finishFetch(_ data: inout AppData, isPresent: (String) -> Bool, now: Date) -> FinishResult {
        var r = FinishResult()
        let before = data
        if !ledger.initialDone {
            r.initial = true
            r.adopted = finishInitial(&data, isPresent: isPresent, now: now)
        }
        let afterInitial = data
        let merged = SyncMerge.dedupe(&data)
        for m in merged { ledger.aliases[m.from.recordName] = m.into.recordName }
        trimAliases()
        SyncMerge.repair(&data)
        var keys = captureLocalChanges(data, previous: afterInitial, now: now)
        keys += captureFiles(data, isPresent: isPresent)
        ledger.lastSync = now
        r.resend = r.initial ? pendingKeys : keys
        r.changed = data != before
        return r
    }

    /// Erstes Einrichten. Rückgabe true = unberührtes Gerät hat die iCloud-Daten übernommen.
    mutating func finishInitial(_ data: inout AppData, isPresent: (String) -> Bool, now: Date) -> Bool {
        let remote = initialRecords.values.filter { !initialDeleted.contains($0.key) }.sorted { $0.key < $1.key }
        initialRecords = [:]
        initialDeleted = []
        ledger.initialDone = true
        if remote.isEmpty {
            // iCloud leer: alles hochladen
            markAllForUpload(data, isPresent: isPresent, now: now)
            return false
        }
        if SyncMerge.isUntouched(data) {
            adopt(remote, &data, isPresent: isPresent, now: now)
            return true
        }
        union(remote, &data, isPresent: isPresent, now: now)
        return false
    }

    /// Unberührtes Gerät: iCloud-Daten übernehmen, lokale Standarddaten verwerfen (nie gesendet). Fehlen in iCloud
    /// Personen oder Kategorien, bleiben die lokalen und werden hochgeladen. Darstellung, Kurse, Einführung bleiben.
    mutating func adopt(_ remote: [SyncRecord], _ data: inout AppData, isPresent: (String) -> Bool, now: Date) {
        let local = data
        var d = local
        d.persons = []
        d.categories = []
        d.partners = []
        d.contracts = []
        d.incomes = []
        ledger.pending = [:]
        ledger.entries = [:]
        ledger.settingsBase = nil
        ledger.settingsServer = nil
        _ = applyNormal(records: remote, deletions: [], data: &d, isPresent: isPresent, now: now)
        let enc = SyncCodec.makeEncoder()
        if d.persons.isEmpty {
            d.persons = local.persons
            for p in local.persons { markForUpload(SyncKey(.person, p.id), d, encoder: enc, now: now) }
        }
        if d.categories.isEmpty {
            d.categories = local.categories
            for c in local.categories { markForUpload(SyncKey(.category, c.id), d, encoder: enc, now: now) }
        }
        let ids = Set(d.persons.map { $0.id })
        d.settings.lastHolderIDs = d.settings.lastHolderIDs.filter { ids.contains($0) }
        if !remote.contains(where: { $0.key.kind == .settings }) {
            markForUpload(.settings, d, encoder: enc, now: now)
        }
        data = d
    }

    /// Beide Seiten haben Daten: vereinigen. Gleiche ID → neuere Änderung gewinnt; nur lokal vorhandene werden hochgeladen;
    /// Einstellungen: Listen vereinigt, Reihenfolgen iCloud zuerst. Doppelte führt danach `finishFetch` zusammen.
    mutating func union(_ remote: [SyncRecord], _ data: inout AppData, isPresent: (String) -> Bool, now: Date) {
        let settingsKey = SyncKey.settings.recordName
        let localSettings = SyncSettings(data, base: ledger.settingsBase)
        let localSettingsTime = ledger.entries[settingsKey]?.modifiedAt ?? .distantPast
        _ = applyNormal(records: remote.filter { $0.key.kind != .settings }, deletions: [], data: &data, isPresent: isPresent, now: now)
        let enc = SyncCodec.makeEncoder()
        if let sr = remote.first(where: { $0.key.kind == .settings }), case .settings(let rs0)? = SyncCodec.decodeEntity(sr),
           case (.settings(let rs), _) = SyncAliases(ledger.aliases).rewrite(.settings(rs0)) {
            let merged = SyncSettings.union(local: localSettings, remote: rs, preferLocal: localSettingsTime > sr.modifiedAt)
            merged.apply(to: &data.settings)
            SyncMerge.applyOrders(&data, settings: merged)
            // Basis = Stand in iCloud: weicht das Ergebnis ab, wird es als Änderung gesendet
            ledger.settingsServer = rs0
            ledger.settingsBase = rs
            ledger.entries[settingsKey] = SyncLedger.Entry(digest: SyncCodec.encode(rs, encoder: enc).map { SyncCodec.digest($0) },
                                                           modifiedAt: sr.modifiedAt)
            ledger.pending[settingsKey] = nil
            let s = SyncSettings(data, base: rs)
            if s != rs {
                // Vereinigt: als neuere Fassung senden
                ledger.settingsBase = s
                ledger.entries[settingsKey] = SyncLedger.Entry(digest: SyncCodec.encode(s, encoder: enc).map { SyncCodec.digest($0) },
                                                               modifiedAt: max(now, sr.modifiedAt))
                ledger.pending[settingsKey] = .save
            }
        } else {
            markForUpload(.settings, data, encoder: enc, now: now)
        }
        // Nur lokal vorhanden: hochladen; lokale Löschungen von Datensätzen, die es in iCloud nicht gibt: vergessen
        let remoteNames = Set(remote.map { $0.key.recordName })
        for key in SyncCodec.keys(of: data) where key.kind != .settings && !remoteNames.contains(key.recordName) {
            markForUpload(key, data, encoder: enc, now: now)
        }
        for (name, e) in ledger.entries where e.digest == nil && !remoteNames.contains(name) {
            ledger.entries[name] = nil
            ledger.pending[name] = nil
        }
    }

    /// Datensatz zum Hochladen vormerken (Fassung und Zeit bleiben, sonst jetzt).
    mutating func markForUpload(_ key: SyncKey, _ data: AppData, encoder: JSONEncoder, now: Date) {
        let name = key.recordName
        let payload: Data?
        if key.kind == .settings {
            let s = SyncSettings(data, base: ledger.settingsBase)
            ledger.settingsBase = s
            payload = SyncCodec.encode(s, encoder: encoder)
        } else {
            payload = SyncCodec.payload(key, in: data, settingsBase: nil, encoder: encoder)
        }
        guard let p = payload else { return }
        let known = ledger.entries[name]?.modifiedAt ?? now
        ledger.entries[name] = SyncLedger.Entry(digest: SyncCodec.digest(p), modifiedAt: known == .distantPast ? now : known)
        ledger.pending[name] = .save
    }

    /// Alles hochladen (iCloud leer, Zone neu): Server-Wissen verwerfen, jede Entität und jede gebrauchte Datei vormerken.
    mutating func markAllForUpload(_ data: AppData, isPresent: (String) -> Bool, now: Date) {
        ledger.systemFields = [:]
        ledger.serverFiles = []
        ledger.settingsServer = nil
        ledger.pending = [:]
        ledger.entries = ledger.entries.filter { $0.value.digest != nil }
        let enc = SyncCodec.makeEncoder()
        for key in SyncCodec.keys(of: data) { markForUpload(key, data, encoder: enc, now: now) }
        _ = captureFiles(data, isPresent: isPresent)
    }

    /// Weiterleitungen begrenzen (älteste Einträge sind bedeutungslos, sobald alle Geräte zusammengeführt haben)
    mutating func trimAliases(limit: Int = 500) {
        guard ledger.aliases.count > limit else { return }
        for k in ledger.aliases.keys.sorted().prefix(ledger.aliases.count - limit) { ledger.aliases[k] = nil }
    }

    // MARK: Zurücksetzen

    /// Server-Wissen verwerfen (Ausschalten, Abmelden, Kontowechsel, Zone gelöscht). Die lokalen Fassungen (Änderungszeiten)
    /// und noch nicht gesendete Löschungen bleiben; beim nächsten Einschalten folgt das erste Einrichten (Vereinigen).
    public mutating func resetServerState() {
        ledger.systemFields = [:]
        ledger.serverFiles = []
        ledger.settingsServer = nil
        ledger.engineState = nil
        ledger.initialDone = false
        ledger.lastSync = nil
        for (name, p) in ledger.pending where p == .save { ledger.pending[name] = nil }
        initialRecords = [:]
        initialDeleted = []
    }

    /// Neu einrichten, weil die lokalen Daten nicht sicher sind (Vorversion geladen, Datei defekt, leer statt erwartet):
    /// lokale Fassungen gelten als alt – bei gleicher ID gewinnt iCloud, nichts wird als Löschung gesendet.
    public mutating func restartInitial(localIsStale data: AppData) {
        resetServerState()
        ledger.pending = [:]
        ledger.entries = [:]
        ledger.settingsBase = nil
        let enc = SyncCodec.makeEncoder()
        for key in SyncCodec.keys(of: data) {
            let payload: Data?
            if key.kind == .settings {
                let s = SyncSettings(data, base: nil)
                ledger.settingsBase = s
                payload = SyncCodec.encode(s, encoder: enc)
            } else {
                payload = SyncCodec.payload(key, in: data, settingsBase: nil, encoder: enc)
            }
            if let p = payload { ledger.entries[key.recordName] = SyncLedger.Entry(digest: SyncCodec.digest(p), modifiedAt: .distantPast) }
        }
    }

    /// Lokale Daten sehen verloren aus: keine Verträge und Einnahmen, aber der Abgleich kennt welche, ohne dass deren
    /// Löschung erfasst wurde. Dann nicht löschen, sondern neu einrichten (`restartInitial`).
    public func looksLikeLostData(_ data: AppData) -> Bool {
        guard data.contracts.isEmpty && data.incomes.isEmpty else { return false }
        return ledger.entries.contains { name, e in
            e.digest != nil && (name.hasPrefix(SyncKind.contract.rawValue + ".") || name.hasPrefix(SyncKind.income.rawValue + "."))
        }
    }
}
