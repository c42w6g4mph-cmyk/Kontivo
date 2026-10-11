import XCTest
@testable import KontivoCore

/// iCloud-Sync: Diff, lokale Änderungen, Übernehmen entfernter Änderungen, Konflikte, erstes Einrichten.
final class SyncCoreTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    let noFiles: (String) -> Bool = { _ in false }

    /// Kern nach dem ersten Einrichten, alles gesendet (Systemfelder «tag1»)
    func synced(_ d: AppData, at time: Date? = nil) -> SyncCore {
        var core = SyncCore()
        core.ledger.initialDone = true
        core.captureLocalChanges(d, previous: nil, now: time ?? t0)
        for k in core.pendingKeys {
            if case .save(let r)? = core.outgoing(k, data: d) {
                core.didSave(k, payload: r.payload, systemFields: Data("tag1".utf8))
            }
        }
        XCTAssertTrue(core.pendingKeys.isEmpty)
        return core
    }

    /// Datensätze aller Entitäten von `d` (wie sie ein anderes Gerät gesendet hätte)
    func records(_ d: AppData, at time: Date) -> [SyncRecord] {
        SyncCodec.keys(of: d).compactMap { SyncCodec.record($0, in: d, modifiedAt: time) }
    }

    func contract(_ d: AppData, _ label: String, category: CategoryKind = .media, holder: UUID? = nil) -> Contract {
        var c = Contract(label: label, categoryID: d.categories.first { $0.kind == category }?.id, amount: 10)
        c.holderIDs = [holder ?? d.persons[0].id]
        c.createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        return c
    }

    // MARK: Diff und lokale Änderungen

    func testDiff() {
        var old = SyncCodecTests.sample()
        old.contracts.append(contract(old, "Netflix"))
        var new = old
        new.contracts[0].amount = 59.9
        new.incomes = []
        new.persons.append(Person(name: "Tim"))
        new.settings.theme = .light          // nicht abgeglichen
        new.settings.rates = ["EUR": 0.5]    // nicht abgeglichen
        var d = SyncDiff.diff(old: old, new: new)
        XCTAssertEqual(Set(d.save), [SyncKey(.contract, old.contracts[0].id), SyncKey(.person, new.persons[2].id), .settings])
        XCTAssertEqual(d.delete, [SyncKey(.income, old.incomes[0].id)])

        // Nur Darstellung: keine Änderung
        var themeOnly = old
        themeOnly.settings.theme = .light
        d = SyncDiff.diff(old: old, new: themeOnly)
        XCTAssertTrue(d.save.isEmpty && d.delete.isEmpty)

        // Kategorien umsortiert: Einstellungen (Reihenfolge)
        var moved = old
        moved.moveCategory(from: 0, to: 3)
        d = SyncDiff.diff(old: old, new: moved)
        XCTAssertEqual(d.save, [.settings])
    }

    func testCaptureOnlyRealChanges() {
        var d = SyncCodecTests.sample()
        var core = synced(d)
        XCTAssertTrue(core.captureLocalChanges(d, previous: nil, now: t(1)).isEmpty, "unverändert")
        XCTAssertTrue(core.captureLocalChanges(d, previous: d, now: t(1)).isEmpty)

        // Nur Darstellung/Kurse: nichts zu senden
        var d2 = d
        d2.settings.theme = .light
        d2.settings.rates = ["EUR": 0.5]
        XCTAssertTrue(core.captureLocalChanges(d2, previous: d, now: t(2)).isEmpty)

        // Betrag ändern → genau dieser Vertrag
        var d3 = d2
        d3.contracts[0].amount = 1
        let k = SyncKey(.contract, d.contracts[0].id)
        XCTAssertEqual(core.captureLocalChanges(d3, previous: d2, now: t(3)), [k])
        XCTAssertEqual(core.pending(k), .save)
        XCTAssertEqual(core.ledger.entries[k.recordName]?.modifiedAt, t(3))
        guard case .save(let rec)? = core.outgoing(k, data: d3) else { return XCTFail("nichts zu senden") }
        XCTAssertEqual(rec.modifiedAt, t(3))
        // Zurück auf den gesendeten Stand vor der Bestätigung: Bestätigung der neuen Fassung erledigt es
        XCTAssertFalse(core.didSave(k, payload: rec.payload, systemFields: Data("tag2".utf8)))
        XCTAssertNil(core.pending(k))
        XCTAssertEqual(core.ledger.systemFields[k.recordName], Data("tag2".utf8))

        // Während des Sendens erneut geändert → bleibt ausstehend
        var d4 = d3
        d4.contracts[0].amount = 2
        core.captureLocalChanges(d4, previous: d3, now: t(4))
        XCTAssertTrue(core.didSave(k, payload: rec.payload, systemFields: Data("tag3".utf8)), "ältere Fassung bestätigt")
        XCTAssertEqual(core.pending(k), .save)

        // Löschen → Löschung, nach Bestätigung vergessen
        d = d4
        d.deleteContract(d4.contracts[0].id)
        XCTAssertEqual(core.captureLocalChanges(d, previous: d4, now: t(5)), [k])
        XCTAssertEqual(core.pending(k), .delete)
        XCTAssertEqual(core.outgoing(k, data: d), .delete(k))
        XCTAssertFalse(core.didDelete(k))
        XCTAssertNil(core.ledger.entries[k.recordName])
        XCTAssertNil(core.ledger.systemFields[k.recordName])
    }

    func testCaptureAfterRestartFindsChangesWithoutPrevious() {
        // Absturz nach dem Speichern von data.json, vor dem Erfassen: beim Start (previous nil) gefunden
        let d = SyncCodecTests.sample()
        var core = synced(d)
        var changed = d
        changed.incomes[0].amount = 7000
        changed.partners[0].web = "neu.ch"
        let keys = core.captureLocalChanges(changed, previous: nil, now: t(1))
        XCTAssertEqual(Set(keys), [SyncKey(.income, d.incomes[0].id), SyncKey(.partner, d.partners[0].id)])
    }

    func testCaptureFiles() {
        var d = SyncCodecTests.sample()
        let logo = d.partners[0].logoID!
        let doc = d.contracts[0].documents[0].id
        let avatar = d.persons[0].avatarID!
        var core = synced(d)
        var present: Set<String> = [logo, avatar]
        let keys = core.captureFiles(d, isPresent: { present.contains($0) })
        XCTAssertEqual(Set(keys), [SyncKey.file(logo)!, SyncKey.file(avatar)!], "fehlendes Dokument wird nicht hochgeladen")
        XCTAssertEqual(core.outgoing(SyncKey.file(logo)!, data: d), .saveFile(logo))
        core.didSave(SyncKey.file(logo)!, payload: nil, systemFields: Data("f".utf8))
        core.didSave(SyncKey.file(avatar)!, payload: nil, systemFields: Data("f".utf8))
        XCTAssertEqual(core.ledger.serverFiles, [logo, avatar])
        XCTAssertTrue(core.captureFiles(d, isPresent: { present.contains($0) }).isEmpty)

        // Logo entfernt: solange die Datei da ist (Aufräumen erst nach 7 Tagen), bleibt sie auch in iCloud
        d.setPartnerLogo(d.partners[0].id, logoID: nil, background: nil)
        XCTAssertTrue(core.captureFiles(d, isPresent: { present.contains($0) }).isEmpty)
        // Aufgeräumt → auch in iCloud löschen
        present.remove(logo)
        XCTAssertEqual(core.captureFiles(d, isPresent: { present.contains($0) }), [SyncKey.file(logo)!])
        XCTAssertEqual(core.pending(SyncKey.file(logo)!), .delete)
        core.didDelete(SyncKey.file(logo)!)
        XCTAssertEqual(core.ledger.serverFiles, [avatar])
        _ = doc
    }

    // MARK: Übernehmen

    func testApplyRemoteInsertUpdateDeleteKeepsOrder() {
        var d = SyncCodecTests.sample()
        d.contracts.append(contract(d, "Netflix"))
        var core = synced(d)
        let before = d

        // Entferntes Gerät: neue Kategorie-Bezeichnung, neuer Vertrag, Einnahme gelöscht
        var remote = d
        let catIndex = remote.categories.firstIndex { $0.kind == .media }!
        remote.categories[catIndex].name = "Medien"
        var nc = contract(remote, "Spotify")
        nc.createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        remote.contracts.append(nc)
        let recs = [SyncKey(.category, remote.categories[catIndex].id), SyncKey(.contract, nc.id)]
            .compactMap { SyncCodec.record($0, in: remote, modifiedAt: t(10)) }
        let res = core.applyRemote(records: recs, deletions: [SyncKey(.income, d.incomes[0].id)], data: &d, isPresent: noFiles, now: t(11))
        XCTAssertTrue(res.changed)
        XCTAssertFalse(res.buffered)
        XCTAssertTrue(res.resend.isEmpty)
        XCTAssertEqual(d.categories.map { $0.id }, before.categories.map { $0.id }, "Reihenfolge bleibt")
        XCTAssertEqual(d.categories[catIndex].name, "Medien")
        XCTAssertEqual(d.contracts.map { $0.id }, before.contracts.map { $0.id } + [nc.id], "Neue hinten")
        XCTAssertTrue(d.incomes.isEmpty)
        XCTAssertTrue(core.pendingKeys.isEmpty, "Übernommenes ist keine lokale Änderung")
        XCTAssertTrue(core.captureLocalChanges(d, previous: before, now: t(12)).isEmpty, "auch beim nächsten Speichern nicht")
        XCTAssertNil(core.ledger.entries[SyncKey(.income, before.incomes[0].id).recordName])
    }

    func testReferencesMayArriveInAnyOrder() {
        // Vertrag kommt vor seiner Kategorie und Person: Verweise bleiben, lösen sich auf, sobald alles da ist
        var src = AppData.initial()
        let cat = Category(name: "Haustiere", colorHex: "#2E6A4E")
        src.categories.append(cat)
        let tim = Person(name: "Tim")
        src.persons.append(tim)
        var c = contract(src, "Tierversicherung")
        c.categoryID = cat.id
        c.holderIDs = [tim.id]
        src.contracts.append(c)

        var d = src
        d.categories.removeAll { $0.id == cat.id }
        d.persons.removeAll { $0.id == tim.id }
        d.contracts = []
        var core = synced(d)
        _ = core.applyRemote(records: [SyncCodec.record(SyncKey(.contract, c.id), in: src, modifiedAt: t(1))!], deletions: [],
                             data: &d, isPresent: noFiles, now: t(2))
        XCTAssertEqual(d.contracts.first?.categoryID, cat.id)
        XCTAssertNil(d.category(cat.id))
        _ = core.applyRemote(records: [SyncCodec.record(SyncKey(.category, cat.id), in: src, modifiedAt: t(1))!,
                                       SyncCodec.record(SyncKey(.person, tim.id), in: src, modifiedAt: t(1))!,
                                       SyncCodec.record(.settings, in: src, modifiedAt: t(1))!],
                             deletions: [], data: &d, isPresent: noFiles, now: t(3))
        XCTAssertEqual(d.category(d.contracts[0].categoryID)?.name, "Haustiere")
        XCTAssertEqual(d.holderNames(of: d.contracts[0]), ["Tim"])
        XCTAssertEqual(d.categories.map { $0.id }, src.categories.map { $0.id })
        XCTAssertTrue(core.pendingKeys.isEmpty)
    }

    // MARK: Konflikte

    func testConflictNewerChangeWins() {
        var d = SyncCodecTests.sample()
        var core = synced(d)
        let k = SyncKey(.contract, d.contracts[0].id)
        let prev = d
        d.contracts[0].amount = 11
        core.captureLocalChanges(d, previous: prev, now: t(10))

        var remote = prev
        remote.contracts[0].amount = 22
        // Entfernt älter: lokal bleibt und wird gesendet
        var res = core.applyRemote(records: [SyncCodec.record(k, in: remote, modifiedAt: t(5))!], deletions: [], data: &d, isPresent: noFiles, now: t(11))
        XCTAssertEqual(d.contracts[0].amount, 11)
        XCTAssertEqual(res.resend, [k])
        XCTAssertEqual(core.pending(k), .save)
        // Entfernt neuer: entfernt gewinnt
        res = core.applyRemote(records: [SyncCodec.record(k, in: remote, modifiedAt: t(20))!], deletions: [], data: &d, isPresent: noFiles, now: t(21))
        XCTAssertEqual(d.contracts[0].amount, 22)
        XCTAssertNil(core.pending(k))
        XCTAssertEqual(core.ledger.entries[k.recordName]?.modifiedAt, t(20))
    }

    func testResolveConflictOnSave() {
        var d = SyncCodecTests.sample()
        var core = synced(d)
        let k = SyncKey(.contract, d.contracts[0].id)
        let prev = d
        d.contracts[0].label = "Lokal"
        core.captureLocalChanges(d, previous: prev, now: t(10))
        var server = prev
        server.contracts[0].label = "Server"
        // Server älter → lokal bleibt, neue Systemfelder
        XCTAssertTrue(core.resolveConflict(server: SyncCodec.record(k, in: server, modifiedAt: t(5))!, systemFields: Data("s2".utf8), data: &d, now: t(11)))
        XCTAssertEqual(d.contracts[0].label, "Lokal")
        XCTAssertEqual(core.ledger.systemFields[k.recordName], Data("s2".utf8))
        // Server neuer → Server gewinnt
        XCTAssertFalse(core.resolveConflict(server: SyncCodec.record(k, in: server, modifiedAt: t(30))!, systemFields: Data("s3".utf8), data: &d, now: t(31)))
        XCTAssertEqual(d.contracts[0].label, "Server")
        XCTAssertNil(core.pending(k))
        // Datei: liegt schon auf dem Server
        let f = SyncKey.file("0123456789abcdef0123456789abcdef")!
        core.ledger.pending[f.recordName] = .save
        XCTAssertFalse(core.resolveConflict(server: SyncRecord(key: f, payload: Data(), modifiedAt: t(1)), systemFields: nil, data: &d, now: t(32)))
        XCTAssertTrue(core.ledger.serverFiles.contains(f.id))
    }

    func testUnsentLocalChangeBeatsRemoteDeletion() {
        var d = SyncCodecTests.sample()
        var core = synced(d)
        let k = SyncKey(.contract, d.contracts[0].id)
        let prev = d
        d.contracts[0].note = "noch nicht gesendet"
        core.captureLocalChanges(d, previous: prev, now: t(10))
        // Löschung von einem anderen Gerät (auch wenn später): lokale Änderung gewinnt, kein Datenverlust
        let res = core.applyRemote(records: [], deletions: [k], data: &d, isPresent: noFiles, now: t(20))
        XCTAssertEqual(d.contracts.count, 1)
        XCTAssertEqual(res.resend, [k])
        XCTAssertEqual(core.pending(k), .save)
        XCTAssertNil(core.ledger.systemFields[k.recordName], "Datensatz ist weg: neu anlegen")
        // Ohne lokale Änderung: gelöscht
        let inc = SyncKey(.income, d.incomes[0].id)
        _ = core.applyRemote(records: [], deletions: [inc], data: &d, isPresent: noFiles, now: t(21))
        XCTAssertTrue(d.incomes.isEmpty)
    }

    func testRemoteNewerChangeBeatsLocalDeletion() {
        var d = SyncCodecTests.sample()
        var core = synced(d)
        let k = SyncKey(.contract, d.contracts[0].id)
        let prev = d
        d.deleteContract(prev.contracts[0].id)
        core.captureLocalChanges(d, previous: prev, now: t(5))
        XCTAssertEqual(core.pending(k), .delete)
        var remote = prev
        remote.contracts[0].amount = 99
        _ = core.applyRemote(records: [SyncCodec.record(k, in: remote, modifiedAt: t(10))!], deletions: [], data: &d, isPresent: noFiles, now: t(11))
        XCTAssertEqual(d.contracts.first?.amount, 99, "neuere Änderung gewinnt gegen die ältere Löschung")
        XCTAssertNil(core.pending(k))
        // Ältere entfernte Änderung gegen neuere lokale Löschung: Löschung bleibt
        let prev2 = d
        d.deleteContract(prev2.contracts[0].id)
        core.captureLocalChanges(d, previous: prev2, now: t(30))
        _ = core.applyRemote(records: [SyncCodec.record(k, in: remote, modifiedAt: t(25))!], deletions: [], data: &d, isPresent: noFiles, now: t(31))
        XCTAssertTrue(d.contracts.isEmpty)
        XCTAssertEqual(core.pending(k), .delete)
    }

    func testRemoteFileDeletionWhileStillUsedReuploads() {
        let d0 = SyncCodecTests.sample()
        var d = d0
        var core = synced(d)
        let logo = d.partners[0].logoID!
        core.ledger.serverFiles = [logo]
        let res = core.applyRemote(records: [], deletions: [SyncKey.file(logo)!], data: &d, isPresent: { $0 == logo }, now: t(1))
        XCTAssertEqual(res.resend, [SyncKey.file(logo)!])
        XCTAssertEqual(core.pending(SyncKey.file(logo)!), .save)
        XCTAssertFalse(core.ledger.serverFiles.contains(logo))
        // Abgerufene und gespeicherte Datei gilt als vorhanden
        _ = core.applyRemote(records: [], deletions: [], storedFiles: [logo], data: &d, isPresent: { $0 == logo }, now: t(2))
        XCTAssertTrue(core.ledger.serverFiles.contains(logo))
        XCTAssertNil(core.pending(SyncKey.file(logo)!))
    }

    // MARK: Einstellungen und Reihenfolgen

    func testSettingsApplyAndOrderWithoutSpuriousChanges() {
        var d = SyncCodecTests.sample()
        var core = synced(d)
        // Anderes Gerät: neue Kategorie an Position 1, Sortierung geändert, Darstellung dort hell (nicht abgeglichen)
        var remote = d
        let neu = Category(name: "Garten", colorHex: "#2E6A4E")
        remote.categories.insert(neu, at: 1)
        remote.settings.sort = .partner
        remote.settings.theme = .light
        remote.settings.qualityIgnored.append("p:x:addr")
        let before = d
        // Einstellungen kommen vor der Kategorie
        _ = core.applyRemote(records: [SyncCodec.record(.settings, in: remote, modifiedAt: t(10))!], deletions: [], data: &d, isPresent: noFiles, now: t(11))
        XCTAssertEqual(d.settings.sort, .partner)
        XCTAssertEqual(d.settings.theme, .dark, "Darstellung bleibt")
        XCTAssertEqual(d.settings.qualityIgnored, ["c:x:holder", "p:x:addr"])
        XCTAssertTrue(core.captureLocalChanges(d, previous: before, now: t(12)).isEmpty, "fehlende Kategorie ist keine lokale Änderung")
        let mid = d
        _ = core.applyRemote(records: [SyncCodec.record(SyncKey(.category, neu.id), in: remote, modifiedAt: t(10))!], deletions: [], data: &d, isPresent: noFiles, now: t(13))
        XCTAssertEqual(d.categories.map { $0.id }, remote.categories.map { $0.id }, "an ihrer Stelle eingereiht")
        XCTAssertTrue(core.captureLocalChanges(d, previous: mid, now: t(14)).isEmpty)
    }

    // MARK: Erstes Einrichten

    func testFirstSetupWithEmptyICloudUploadsEverything() {
        var d = SyncCodecTests.sample()
        var core = SyncCore()
        core.captureLocalChanges(d, previous: nil, now: t0)
        XCTAssertNil(core.outgoing(.settings, data: d), "vor dem ersten Einrichten wird nichts gesendet")
        let res = core.applyRemote(records: [], deletions: [], data: &d, isPresent: noFiles, now: t(1))
        XCTAssertTrue(res.buffered)
        let present: Set<String> = [d.partners[0].logoID!]
        let fin = core.finishFetch(&d, isPresent: { present.contains($0) }, now: t(2))
        XCTAssertTrue(fin.initial)
        XCTAssertFalse(fin.adopted)
        XCTAssertTrue(core.ledger.initialDone)
        let expected = Set(SyncCodec.keys(of: d) + [SyncKey.file(d.partners[0].logoID!)!])
        XCTAssertEqual(Set(core.pendingKeys), expected)
        XCTAssertEqual(Set(fin.resend), expected)
    }

    func testUntouchedSecondDeviceAdoptsICloudData() {
        let a = SyncCodecTests.sample()
        // Neues Gerät: Einführung mit Namen und Euro, dunkle Darstellung, Einführung noch offen
        var b = AppData.initial(homeCurrency: .EUR)
        b.persons[0].name = "Sinan"
        b.settings.lastHolderIDs = [b.persons[0].id]
        b.settings.theme = .light
        b.settings.rates = ["EUR": 0.93]
        XCTAssertTrue(SyncMerge.isUntouched(b))
        var core = SyncCore()
        core.captureLocalChanges(b, previous: nil, now: t0)
        _ = core.applyRemote(records: records(a, at: t(1)), deletions: [], data: &b, isPresent: noFiles, now: t(2))
        XCTAssertEqual(b.persons.map { $0.name }, ["Sinan"], "noch nichts übernommen")
        let fin = core.finishFetch(&b, isPresent: noFiles, now: t(3))
        XCTAssertTrue(fin.adopted)
        XCTAssertEqual(b.persons.map { $0.id }, a.persons.map { $0.id }, "keine zweite «Ich»/Person")
        XCTAssertEqual(b.categories.map { $0.id }, a.categories.map { $0.id }, "keine doppelten Standardkategorien")
        XCTAssertEqual(b.contracts.map { $0.id }, a.contracts.map { $0.id })
        XCTAssertEqual(b.incomes.map { $0.id }, a.incomes.map { $0.id })
        XCTAssertEqual(b.partners, a.partners)
        XCTAssertEqual(b.settings.homeCurrency, .CHF, "Hauptwährung aus iCloud")
        XCTAssertEqual(b.settings.sort, .cost)
        XCTAssertEqual(b.settings.lastHolderIDs, a.settings.lastHolderIDs)
        XCTAssertEqual(b.settings.theme, .light, "Darstellung bleibt")
        XCTAssertEqual(b.settings.rates, ["EUR": 0.93], "Kurse bleiben")
        XCTAssertEqual(b.settings.onboarded, 0, "Einführung bleibt lokal")
        // Nichts hochzuladen (Standarddaten des neuen Geräts nie gesendet)
        XCTAssertTrue(core.pendingKeys.filter { $0.kind != .file }.isEmpty, "\(core.pendingKeys)")
    }

    func testTouchedDevicesAreUnitedAndDuplicatesMerged() throws {
        // Gerät A (schon in iCloud): Netflix in «Abos & Medien», Inhaber «Ich»
        var a = AppData.initial()
        a.contracts.append(contract(a, "Netflix"))
        a.categories.append(Category(name: "Haustiere", colorHex: "#2E6A4E"))
        // Gerät B (eigene Daten): Spotify in seinem «Abos & Medien», eigene «Ich», eigene «Haustiere», «Garten»
        var b = AppData.initial()
        b.contracts.append(contract(b, "Spotify"))
        let hb = Category(name: "Haustiere", colorHex: "#6B4E9E")
        b.categories.append(hb)
        b.categories.append(Category(name: "Garten", colorHex: "#2E6A4E"))
        var tier = contract(b, "Tierversicherung")
        tier.categoryID = hb.id
        b.contracts.append(tier)
        b.settings.qualityIgnored = ["b"]
        a.settings.qualityIgnored = ["a"]
        XCTAssertFalse(SyncMerge.isUntouched(b))
        let mediaIDs = [a, b].map { $0.categories.first { $0.kind == .media }!.id.uuidString }
        let ichIDs = [a.persons[0].id.uuidString, b.persons[0].id.uuidString]

        var core = SyncCore()
        core.captureLocalChanges(b, previous: nil, now: t(5))
        _ = core.applyRemote(records: records(a, at: t(1)), deletions: [], data: &b, isPresent: noFiles, now: t(6))
        let fin = core.finishFetch(&b, isPresent: noFiles, now: t(7))
        XCTAssertFalse(fin.adopted)

        XCTAssertEqual(Set(b.contracts.map { $0.label }), ["Netflix", "Spotify", "Tierversicherung"])
        // Jede Standardart einmal, «Haustiere» einmal, «Garten» dabei
        for kind in CategoryKind.allCases { XCTAssertEqual(b.categories.filter { $0.kind == kind }.count, 1, kind.rawValue) }
        XCTAssertEqual(b.categories.filter { $0.name == "Haustiere" }.count, 1)
        XCTAssertEqual(b.categories.count, 14)
        XCTAssertEqual(Array(b.categories.prefix(12).map { $0.kind }), Category.standard().map { $0.kind }, "Standardreihenfolge bleibt")
        // Verweise zeigen auf die behaltenen Kategorien
        let media = try XCTUnwrap(b.categories.first { $0.kind == .media })
        XCTAssertEqual(b.contracts.filter { $0.label != "Tierversicherung" }.map { $0.categoryID }, [media.id, media.id])
        let haustiere = try XCTUnwrap(b.categories.first { $0.name == "Haustiere" })
        XCTAssertEqual(b.contracts.first { $0.label == "Tierversicherung" }?.categoryID, haustiere.id)
        // Eine «Ich» mit allen Verträgen
        XCTAssertEqual(b.persons.count, 1)
        XCTAssertTrue(b.contracts.allSatisfy { $0.holderIDs == [b.persons[0].id] })
        // Behalten wird die kleinste ID (alle Geräte entscheiden gleich)
        XCTAssertEqual(media.id.uuidString, mediaIDs.min())
        XCTAssertEqual(b.persons[0].id.uuidString, ichIDs.min())
        // Listen vereinigt
        XCTAssertEqual(Set(b.settings.qualityIgnored), ["a", "b"])
        // Weiterleitungen gemerkt
        XCTAssertFalse(core.ledger.aliases.isEmpty)
        // B lädt seine eigenen Daten hoch und löscht Zusammengeführtes
        XCTAssertTrue(core.pendingKeys.contains(SyncKey(.contract, b.contracts.first { $0.label == "Spotify" }!.id)))
        XCTAssertEqual(core.pending(.settings), .save)
    }

    func testAliasRewritesLateReferences() {
        var d = AppData.initial()
        var core = synced(d)
        let keep = d.categories.first { $0.kind == .media }!.id
        let gone = UUID()
        core.ledger.aliases = [SyncKey(.category, gone).recordName: SyncKey(.category, keep).recordName]
        var remote = d
        var c = contract(d, "Spät")
        c.categoryID = gone
        remote.contracts.append(c)
        let res = core.applyRemote(records: [SyncCodec.record(SyncKey(.contract, c.id), in: remote, modifiedAt: t(1))!], deletions: [],
                                   data: &d, isPresent: noFiles, now: t(2))
        XCTAssertEqual(d.contracts.first?.categoryID, keep)
        XCTAssertEqual(res.resend, [SyncKey(.contract, c.id)])
        XCTAssertEqual(core.pending(SyncKey(.contract, c.id)), .save, "korrigierte Fassung wird gesendet")
    }

    // MARK: Verlorene Daten, Zurücksetzen

    func testRestartInitialWhenLocalDataIsStale() {
        // Vorversion geladen (Betrag 10), iCloud hat 20: iCloud gewinnt, nichts wird gelöscht
        var cloud = SyncCodecTests.sample()
        cloud.contracts[0].amount = 20
        var d = cloud
        d.contracts[0].amount = 10
        var core = synced(cloud)
        core.restartInitial(localIsStale: d)
        XCTAssertFalse(core.ledger.initialDone)
        core.captureLocalChanges(d, previous: nil, now: t(5))
        XCTAssertTrue(core.pendingKeys.isEmpty)
        _ = core.applyRemote(records: records(cloud, at: t(1)), deletions: [], data: &d, isPresent: noFiles, now: t(6))
        _ = core.finishFetch(&d, isPresent: noFiles, now: t(7))
        XCTAssertEqual(d.contracts[0].amount, 20)
        XCTAssertTrue(core.pendingKeys.filter { $0.kind != .file }.isEmpty)
    }

    func testLooksLikeLostData() {
        let d = SyncCodecTests.sample()
        let core = synced(d)
        XCTAssertFalse(core.looksLikeLostData(d))
        XCTAssertTrue(core.looksLikeLostData(AppData.initial()), "leere Daten, aber der Abgleich kennt Verträge")
        // Bewusst gelöscht (erfasst): keine Warnung
        var wiped = d
        wiped.wipeAll()
        var core2 = core
        core2.captureLocalChanges(wiped, previous: d, now: t(1))
        XCTAssertFalse(core2.looksLikeLostData(wiped))
    }

    func testWipeDeletesEverywhereAndCreatesNewDefaults() {
        let d = SyncCodecTests.sample()
        var core = synced(d)
        var w = d
        w.wipeAll()
        let keys = Set(core.captureLocalChanges(w, previous: d, now: t(1)))
        for c in d.contracts { XCTAssertEqual(core.pending(SyncKey(.contract, c.id)), .delete) }
        for p in d.persons { XCTAssertEqual(core.pending(SyncKey(.person, p.id)), .delete) }
        XCTAssertEqual(core.pending(SyncKey(.person, w.persons[0].id)), .save)
        XCTAssertTrue(keys.contains(.settings))
    }

    func testResetServerStateKeepsLocalTimesAndDeletes() {
        var d = SyncCodecTests.sample()
        var core = synced(d)
        let prev = d
        d.deleteContract(prev.contracts[0].id)
        d.incomes[0].amount = 1
        core.captureLocalChanges(d, previous: prev, now: t(3))
        core.resetServerState()
        XCTAssertFalse(core.ledger.initialDone)
        XCTAssertTrue(core.ledger.systemFields.isEmpty)
        XCTAssertEqual(core.pending(SyncKey(.contract, prev.contracts[0].id)), .delete, "lokale Löschung bleibt")
        XCTAssertNil(core.pending(SyncKey(.income, prev.incomes[0].id)))
        XCTAssertEqual(core.ledger.entries[SyncKey(.income, prev.incomes[0].id).recordName]?.modifiedAt, t(3))
    }

    func testZoneMissingUploadsEverything() {
        let d = SyncCodecTests.sample()
        var core = synced(d)
        let keys = core.zoneMissing(d, isPresent: noFiles, now: t(1))
        XCTAssertEqual(Set(keys), Set(SyncCodec.keys(of: d)))
        XCTAssertTrue(core.ledger.systemFields.isEmpty)
    }

    // MARK: Zusammenführen und Mindestbestand

    func testDedupeIsDeterministicAndKeepsPositions() {
        var a = AppData.initial()
        let b = AppData.initial()
        // Vereinigt: A-Kategorien, dann B-Kategorien
        a.categories += b.categories
        a.persons += b.persons
        var c1 = contract(a, "X")
        c1.categoryID = b.categories[3].id
        c1.holderIDs = [b.persons[0].id]
        a.contracts = [c1]
        var x = a
        var y = a
        y.categories.reverse()
        let mx = SyncMerge.dedupe(&x)
        _ = SyncMerge.dedupe(&y)
        XCTAssertEqual(x.categories.count, 12)
        XCTAssertEqual(Set(x.categories.map { $0.id }), Set(y.categories.map { $0.id }), "gleiche Entscheidung unabhängig von der Reihenfolge")
        XCTAssertEqual(x.categories.map { $0.kind }, Category.standard().map { $0.kind })
        XCTAssertEqual(x.persons.count, 1)
        XCTAssertEqual(x.contracts[0].holderIDs, [x.persons[0].id])
        XCTAssertNotNil(x.category(x.contracts[0].categoryID))
        XCTAssertEqual(mx.count, 13)
        // Eigene «Steuern …»-Kategorie (Namensregel → Art taxes) wird nicht mit der Standardkategorie zusammengelegt
        var tax = AppData.initial()
        _ = try? tax.addCategory("Steuern privat")
        XCTAssertEqual(tax.categories.filter { $0.kind == .taxes }.count, 2)
        XCTAssertTrue(SyncMerge.dedupe(&tax).isEmpty)
    }

    func testRepair() {
        var d = AppData.initial()
        d.persons = []
        d.categories.removeAll { $0.kind == .other }
        XCTAssertTrue(SyncMerge.repair(&d))
        XCTAssertEqual(d.persons.map { $0.name }, ["Ich"])
        XCTAssertNotNil(d.otherCategory)
        XCTAssertFalse(SyncMerge.repair(&d))
    }

    func testUntouched() {
        XCTAssertTrue(SyncMerge.isUntouched(AppData.initial()))
        var d = AppData.initial()
        d.persons[0].sender.street = "Seeweg 1"
        XCTAssertFalse(SyncMerge.isUntouched(d))
        d = AppData.initial()
        _ = try? d.addCategory("Haustiere")
        XCTAssertFalse(SyncMerge.isUntouched(d))
        d = AppData.initial()
        _ = d.partnerID(forName: "Swisscom")
        XCTAssertFalse(SyncMerge.isUntouched(d))
        d = AppData.initial()
        _ = try? d.addPerson("Lara")
        XCTAssertFalse(SyncMerge.isUntouched(d))
    }
}
