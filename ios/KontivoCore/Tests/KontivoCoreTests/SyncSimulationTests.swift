import XCTest
@testable import KontivoCore

// MARK: - In-Memory-Server und simuliertes Gerät

/// Gemeinsame Uhr (jede Abfrage eine Sekunde später, ganze Sekunden)
final class SimClock {
    private var t: Double = 1_760_000_000
    func next() -> Date {
        t += 1
        return Date(timeIntervalSince1970: t)
    }
}

/// Bildet die Regeln der privaten CloudKit-Datenbank nach: Speichern nur mit aktueller Änderungsmarke (sonst Konflikt mit der
/// Server-Fassung), Systemfelder eines gelöschten Datensatzes → «unknownItem», Änderungsliste ab einem Token.
final class MemoryServer {
    struct Stored {
        var record: SyncRecord
        var tag: Int
        var file: Data?
    }

    enum SaveResult {
        case saved(Data)
        case conflict(SyncRecord, Data)
        case unknownItem
    }

    private(set) var records: [String: Stored] = [:]
    private var log: [(seq: Int, name: String)] = []
    private var seq = 0
    private var tags = 0

    static func tagData(_ t: Int) -> Data { Data("tag\(t)".utf8) }

    func save(_ r: SyncRecord, file: Data?, systemFields: Data?) -> SaveResult {
        let name = r.key.recordName
        if let cur = records[name] {
            if systemFields != MemoryServer.tagData(cur.tag) { return .conflict(cur.record, MemoryServer.tagData(cur.tag)) }
        } else if systemFields != nil {
            return .unknownItem
        }
        tags += 1
        records[name] = Stored(record: r, tag: tags, file: file)
        seq += 1
        log.append((seq, name))
        return .saved(MemoryServer.tagData(tags))
    }

    func delete(_ key: SyncKey) {
        let name = key.recordName
        guard records[name] != nil else { return }
        records[name] = nil
        seq += 1
        log.append((seq, name))
    }

    /// Endstand aller seit `token` geänderten Datensätze
    func fetch(since token: Int) -> (records: [Stored], deletions: [SyncKey], token: Int) {
        var names: [String] = []
        var seen = Set<String>()
        for e in log where e.seq > token {
            if seen.insert(e.name).inserted { names.append(e.name) }
        }
        var recs: [Stored] = []
        var dels: [SyncKey] = []
        for n in names {
            if let s = records[n] { recs.append(s) } else if let k = SyncKey(recordName: n) { dels.append(k) }
        }
        return (recs, dels, seq)
    }

    /// Schlüssel aller Entitäts-Datensätze (ohne Dateien)
    var entityKeys: Set<SyncKey> {
        Set(records.keys.compactMap { SyncKey(recordName: $0) }.filter { $0.kind != .file })
    }

    var fileIDs: Set<String> {
        Set(records.keys.compactMap { SyncKey(recordName: $0) }.filter { $0.kind == .file }.map { $0.id })
    }
}

/// Ein Gerät: Daten, Dateien, Abgleich-Kern. Senden und Abrufen wie die App mit der CKSyncEngine.
final class SimDevice {
    let name: String
    var data: AppData
    /// Stand der letzten Erfassung (wie `AppModel` beim Speichern)
    var base: AppData
    var core = SyncCore()
    var files: [String: Data] = [:]
    var token = 0
    let clock: SimClock

    init(_ name: String, data: AppData, clock: SimClock) {
        self.name = name
        self.data = data
        self.base = data
        self.clock = clock
        core.captureLocalChanges(data, previous: nil, now: clock.next())
    }

    func isPresent(_ id: String) -> Bool { files[id] != nil }

    /// Lokale Änderung (wie `AppModel.update` + Speichern)
    func edit(_ body: (inout AppData) -> Void) {
        body(&data)
        capture()
    }

    func capture() {
        core.captureLocalChanges(data, previous: base, now: clock.next())
        core.captureFiles(data, isPresent: { self.files[$0] != nil })
        base = data
    }

    /// Aufräumen wie `FileStore.collectGarbage` (ohne Wartefrist)
    func collectGarbage() {
        let used = Set(data.referencedFileIDs)
        for id in Array(files.keys) where !used.contains(id) { files[id] = nil }
        capture()
    }

    func fetch(_ server: MemoryServer) {
        capture()
        let ch = server.fetch(since: token)
        var recs: [SyncRecord] = []
        var sf: [String: Data] = [:]
        var stored: [String] = []
        for s in ch.records {
            let k = s.record.key
            sf[k.recordName] = MemoryServer.tagData(s.tag)
            if k.kind == .file {
                if let f = s.file {
                    files[k.id] = f
                    stored.append(k.id)
                }
            } else {
                recs.append(s.record)
            }
        }
        var d = data
        _ = core.applyRemote(records: recs, deletions: ch.deletions, systemFields: sf, storedFiles: stored, data: &d,
                             isPresent: { self.files[$0] != nil }, now: clock.next())
        _ = core.finishFetch(&d, isPresent: { self.files[$0] != nil }, now: clock.next())
        data = d
        token = ch.token
        base = data
    }

    func send(_ server: MemoryServer) {
        capture()
        guard core.ledger.initialDone else { return }
        for _ in 0..<5 {
            let keys = core.pendingKeys
            if keys.isEmpty { break }
            for key in keys { sendOne(key, server) }
        }
    }

    private func sendOne(_ key: SyncKey, _ server: MemoryServer) {
        let sf = core.ledger.systemFields[key.recordName]
        guard let out = core.outgoing(key, data: data, now: clock.next()) else { return }
        switch out {
        case .save(let rec):
            handle(server.save(rec, file: nil, systemFields: sf), key: key, payload: rec.payload)
        case .saveFile(let id):
            guard let bytes = files[id] else { return }
            handle(server.save(SyncRecord(key: key, payload: Data(), modifiedAt: clock.next()), file: bytes, systemFields: sf), key: key, payload: nil)
        case .delete(let k):
            server.delete(k)
            core.didDelete(k)
        }
    }

    private func handle(_ r: MemoryServer.SaveResult, key: SyncKey, payload: Data?) {
        switch r {
        case .saved(let tag):
            core.didSave(key, payload: payload, systemFields: tag)
        case .conflict(let server, let tag):
            var d = data
            _ = core.resolveConflict(server: server, systemFields: tag, data: &d, now: clock.next())
            data = d
            base = data
        case .unknownItem:
            core.recordMissingOnServer(key)
        }
    }
}

/// Reproduzierbarer Zufall (xorshift64*)
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2_685_821_657_736_338_717
    }
}

// MARK: - Simulation mit zwei Geräten

final class SyncSimulationTests: XCTestCase {

    /// Beide Geräte gleich: alle Entitäten (kanonische Nutzlast), Reihenfolgen, Dateien; nichts mehr ausstehend; Server = Geräte.
    func assertConverged(_ a: SimDevice, _ b: SimDevice, _ server: MemoryServer, file: StaticString = #filePath, line: UInt = #line) {
        let ka = Set(SyncCodec.keys(of: a.data))
        let kb = Set(SyncCodec.keys(of: b.data))
        XCTAssertEqual(ka, kb, "gleiche Datensätze", file: file, line: line)
        for k in ka {
            XCTAssertEqual(SyncCodec.payload(k, in: a.data, settingsBase: nil), SyncCodec.payload(k, in: b.data, settingsBase: nil),
                           "verschieden: \(k)", file: file, line: line)
        }
        XCTAssertEqual(a.data.categories.map { $0.id }, b.data.categories.map { $0.id }, "Kategorien-Reihenfolge", file: file, line: line)
        XCTAssertEqual(a.data.persons.map { $0.id }, b.data.persons.map { $0.id }, "Personen-Reihenfolge", file: file, line: line)
        XCTAssertEqual(server.entityKeys, ka, "Server hat dieselben Datensätze", file: file, line: line)
        for id in Set(a.data.referencedFileIDs) {
            XCTAssertEqual(a.files[id], b.files[id], "Datei \(id)", file: file, line: line)
        }
        XCTAssertEqual(a.core.pendingKeys, [], "A hat nichts mehr zu senden", file: file, line: line)
        XCTAssertEqual(b.core.pendingKeys, [], "B hat nichts mehr zu senden", file: file, line: line)
    }

    func settle(_ a: SimDevice, _ b: SimDevice, _ server: MemoryServer, rounds: Int = 4) {
        for _ in 0..<rounds {
            a.send(server)
            b.send(server)
            a.fetch(server)
            b.fetch(server)
        }
    }

    /// iPhone mit Daten richtet ein (iCloud leer), iPad neu und unberührt übernimmt
    func setUpPair() -> (SimDevice, SimDevice, MemoryServer) {
        let clock = SimClock()
        let server = MemoryServer()
        var start = SyncCodecTests.sample()
        start.persons[0].avatarID = nil
        start.contracts[0].documents = []
        let a = SimDevice("iPhone", data: start, clock: clock)
        a.files["abcdefabcdefabcdefabcdefabcdef01"] = Data("logo-swisscom".utf8)
        a.capture()
        var fresh = AppData.initial(homeCurrency: .EUR)
        fresh.settings.theme = .light
        let b = SimDevice("iPad", data: fresh, clock: clock)
        a.fetch(server)
        a.send(server)
        b.fetch(server)
        b.send(server)
        return (a, b, server)
    }

    func testSecondDeviceGetsEverythingWithoutDuplicates() {
        let (a, b, server) = setUpPair()
        settle(a, b, server, rounds: 1)
        assertConverged(a, b, server)
        XCTAssertEqual(b.data.persons.count, 2)
        XCTAssertEqual(b.data.categories.count, 13)
        XCTAssertEqual(b.files["abcdefabcdefabcdefabcdefabcdef01"], Data("logo-swisscom".utf8), "Logo heruntergeladen")
        XCTAssertEqual(b.data.settings.theme, .light, "Darstellung pro Gerät")
        XCTAssertEqual(b.data.settings.homeCurrency, .CHF)
    }

    func testEditsOnBothDevicesConverge() {
        let (a, b, server) = setUpPair()
        // A: Vertrag ändern, Kategorie anlegen und nach vorne schieben; B: Einnahme ändern, Person anlegen
        a.edit { d in
            d.contracts[0].amount = 59
            _ = try? d.addCategory("Garten")
            d.moveCategory(from: d.categories.count - 1, to: 0)
        }
        b.edit { d in
            d.incomes[0].amount = 7000
            _ = try? d.addPerson("Tim")
            d.settings.qualityIgnored.append("x")
        }
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertEqual(a.data.categories.first?.name, "Garten")
        XCTAssertEqual(b.data.contracts[0].amount, 59)
        XCTAssertEqual(a.data.incomes[0].amount, 7000)
        XCTAssertNotNil(a.data.person(named: "Tim"))
    }

    func testSameRecordChangedOnBothNewerWins() {
        let (a, b, server) = setUpPair()
        a.edit { $0.contracts[0].label = "von A" }
        b.edit { $0.contracts[0].label = "von B" }   // später
        a.send(server)
        b.send(server)   // Konflikt: B ist neuer → B gewinnt
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertEqual(a.data.contracts[0].label, "von B")
    }

    func testDeleteOnOneDeviceEditOnOtherKeepsData() {
        let (a, b, server) = setUpPair()
        let id = a.data.contracts[0].id
        a.edit { $0.deleteContract(id) }
        b.edit { d in d.contracts[0].note = "wichtig" }
        a.send(server)
        b.send(server)   // Datensatz weg → als neuer gespeichert
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertEqual(a.data.contract(id)?.note, "wichtig", "kein Datenverlust")
    }

    func testDeletePropagates() {
        let (a, b, server) = setUpPair()
        let id = a.data.incomes[0].id
        b.edit { $0.deleteIncome(id) }
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertNil(a.data.income(id))
    }

    func testFilesUploadDownloadAndCleanup() {
        let (a, b, server) = setUpPair()
        let logo = "00112233445566778899aabbccddeeff"
        // B setzt ein neues Logo
        b.files[logo] = Data("neues-logo".utf8)
        b.edit { d in d.setPartnerLogo(d.partners[0].id, logoID: logo, background: "#FFFFFF") }
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertEqual(a.files[logo], Data("neues-logo".utf8))
        XCTAssertTrue(server.fileIDs.contains(logo))
        // Altes Logo nach dem Aufräumen auch in iCloud weg
        let old = "abcdefabcdefabcdefabcdefabcdef01"
        XCTAssertTrue(server.fileIDs.contains(old))
        a.collectGarbage()
        b.collectGarbage()
        settle(a, b, server)
        XCTAssertFalse(server.fileIDs.contains(old))
        XCTAssertTrue(server.fileIDs.contains(logo))
        assertConverged(a, b, server)
    }

    func testWipeOnOneDeviceClearsBoth() {
        let (a, b, server) = setUpPair()
        a.edit { $0.wipeAll() }
        a.files = [:]
        a.capture()
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertTrue(b.data.contracts.isEmpty)
        XCTAssertTrue(b.data.incomes.isEmpty)
        XCTAssertEqual(b.data.persons.map { $0.name }, ["Ich"])
        XCTAssertEqual(b.data.categories.count, 12)
        XCTAssertTrue(server.fileIDs.isEmpty)
    }

    func testBothUntouchedAtTheSameTime() {
        // Zwei neue Geräte richten gleichzeitig ein (iCloud leer): danach eine «Ich» und 12 Kategorien
        let clock = SimClock()
        let server = MemoryServer()
        let a = SimDevice("iPhone", data: AppData.initial(), clock: clock)
        let b = SimDevice("iPad", data: AppData.initial(), clock: clock)
        a.fetch(server)
        b.fetch(server)
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertEqual(a.data.persons.count, 1)
        XCTAssertEqual(a.data.categories.count, 12)
        XCTAssertEqual(a.data.categories.map { $0.kind }, Category.standard().map { $0.kind })
    }

    func testBothWithDataAreUnited() {
        let clock = SimClock()
        let server = MemoryServer()
        var da = AppData.initial()
        var c1 = Contract(label: "Netflix", categoryID: da.categories.first { $0.kind == .media }!.id, amount: 15, holderIDs: [da.persons[0].id])
        c1.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        da.contracts.append(c1)
        var db = AppData.initial()
        var c2 = Contract(label: "Spotify", categoryID: db.categories.first { $0.kind == .media }!.id, amount: 13, holderIDs: [db.persons[0].id])
        c2.createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        db.contracts.append(c2)
        _ = db.partnerID(forName: "Spotify")
        _ = da.partnerID(forName: "spotify")
        let a = SimDevice("iPhone", data: da, clock: clock)
        let b = SimDevice("iPad", data: db, clock: clock)
        a.fetch(server)
        a.send(server)
        b.fetch(server)
        b.send(server)
        settle(a, b, server)
        assertConverged(a, b, server)
        XCTAssertEqual(Set(a.data.contracts.map { $0.label }), ["Netflix", "Spotify"])
        XCTAssertEqual(a.data.persons.count, 1, "«Ich» zusammengeführt")
        XCTAssertEqual(a.data.categories.count, 12, "Standardkategorien zusammengeführt")
        XCTAssertEqual(a.data.partners.count, 1, "Vertragspartner gleichen Namens zusammengeführt")
        let media = a.data.categories.first { $0.kind == .media }!.id
        XCTAssertTrue(a.data.contracts.allSatisfy { $0.categoryID == media && $0.holderIDs == [a.data.persons[0].id] })
    }

    func testRandomEditsConverge() {
        for seed: UInt64 in [1, 7, 42, 2026] {
            var rng = SeededRNG(seed: seed)
            let (a, b, server) = setUpPair()
            for step in 0..<80 {
                randomEdit(Bool.random(using: &rng) ? a : b, step: step, rng: &rng)
                switch Int.random(in: 0..<5, using: &rng) {
                case 0: a.send(server)
                case 1: b.send(server)
                case 2: a.fetch(server)
                case 3: b.fetch(server)
                default: break
                }
            }
            settle(a, b, server, rounds: 5)
            assertConverged(a, b, server)
            if a.data.persons.isEmpty || a.data.categories.isEmpty { XCTFail("Mindestbestand fehlt (Seed \(seed))") }
        }
    }

    private func randomEdit(_ dev: SimDevice, step: Int, rng: inout SeededRNG) {
        let catNames = ["Haustiere", "Hobby", "Garten", "Auto"]
        let partnerNames = ["Swisscom", "Netflix", "Spotify", "Sunrise", "CSS"]
        let personNames = ["Lara", "Tim", "Mia"]
        var d = dev.data
        switch Int.random(in: 0..<13, using: &rng) {
        case 0, 1:
            let pid = d.partnerID(forName: partnerNames.randomElement(using: &rng)!)
            var c = Contract(label: "V\(step)", partnerID: pid, categoryID: d.categories.randomElement(using: &rng)?.id,
                             amount: Double(Int.random(in: 1...200, using: &rng)))
            if let p = d.persons.randomElement(using: &rng) { c.holderIDs = [p.id] }
            c.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(step))
            d.contracts.append(c)
        case 2, 3:
            if !d.contracts.isEmpty {
                let i = Int.random(in: 0..<d.contracts.count, using: &rng)
                d.contracts[i].amount += 1
                d.contracts[i].note = "n\(step)"
            }
        case 4:
            if let c = d.contracts.randomElement(using: &rng) { d.deleteContract(c.id) }
        case 5:
            _ = try? d.addCategory(catNames.randomElement(using: &rng)!)
        case 6:
            if d.categories.count > 2 { d.moveCategory(from: Int.random(in: 0..<d.categories.count, using: &rng), to: 0) }
        case 7:
            _ = try? d.addPerson(personNames.randomElement(using: &rng)!)
        case 8:
            d.settings.sort = ContractSort.allCases.randomElement(using: &rng)!
            d.settings.qualityIgnored.append("k\(step)")
        case 9:
            var i = Income(name: "E\(step)", amount: 100, holderID: d.persons.first?.id)
            i.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(step))
            d.incomes.append(i)
        case 10:
            if let i = d.incomes.randomElement(using: &rng) { d.deleteIncome(i.id) }
        case 11:
            if let c = d.categories.filter({ $0.kind == nil }).randomElement(using: &rng) {
                try? d.renameCategory(c.id, to: catNames.randomElement(using: &rng)! + " \(step % 3)")
            }
        default:
            if d.persons.count > 1, let p = d.persons.last {
                try? d.deletePerson(p.id, transferTo: d.persons.first?.id)
            }
        }
        dev.data = d
        dev.capture()
    }
}
