import XCTest
@testable import KontivoCore

/// iCloud-Sync mit variablen Kosten: Schlüssel, Rundlauf, Diff, Übernehmen, Löschen, Personen-Weiterleitung, verlorene Daten.
final class SyncVariableTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_760_000_000)
    func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }
    let noFiles: (String) -> Bool = { _ in false }

    func synced(_ d: AppData) -> SyncCore {
        var core = SyncCore()
        core.ledger.initialDone = true
        core.captureLocalChanges(d, previous: nil, now: t0)
        for k in core.pendingKeys {
            if case .save(let r)? = core.outgoing(k, data: d) {
                core.didSave(k, payload: r.payload, systemFields: Data("tag1".utf8))
            }
        }
        return core
    }

    func variable(_ d: AppData, _ label: String, at: Double = 1_700_000_000) -> VariableCost {
        VariableCost(label: label, icon: .essen, amount: 450.5, currency: .EUR, holderIDs: [d.persons[0].id],
                     start: Day(2026, 1, 1), end: nil, logoID: "0123456789abcdef0123456789abcdef", logoBg: "#ffffff",
                     createdAt: Date(timeIntervalSince1970: at))
    }

    func testKeyAndRoundTrip() throws {
        var d = AppData.initial()
        let v = variable(d, "Lebensmittel")
        d.variableCosts = [v]
        let key = SyncKey(.variable, v.id)
        XCTAssertEqual(key.recordName, "variable." + v.id.uuidString)
        XCTAssertEqual(SyncKey(recordName: key.recordName), key)
        XCTAssertTrue(SyncCodec.keys(of: d).contains(key))
        let p = try XCTUnwrap(SyncCodec.payload(key, in: d, settingsBase: nil))
        guard case .variable(let back)? = SyncCodec.decodeEntity(SyncRecord(key: key, payload: p, modifiedAt: t0)) else {
            return XCTFail("nicht gelesen")
        }
        XCTAssertEqual(back.label, "Lebensmittel")
        XCTAssertEqual(back.amount, 450.5)
        XCTAssertEqual(back.currency, .EUR)
        XCTAssertEqual(back.holderIDs, v.holderIDs)
        XCTAssertEqual(back.start, Day(2026, 1, 1))
        XCTAssertEqual(back.logoID, v.logoID)
        // falsche ID → verworfen
        XCTAssertNil(SyncCodec.decodeEntity(SyncRecord(key: SyncKey(.variable, UUID()), payload: p, modifiedAt: t0)))
        // Logo als Datei abgeglichen
        XCTAssertTrue(d.referencedFileIDs.contains(v.logoID!))
    }

    func testDiffApplyAndDelete() throws {
        var d = AppData.initial()
        d.variableCosts = [variable(d, "Benzin")]
        var core = synced(d)
        // lokal geändert → wird gesendet
        let before = d
        d.variableCosts[0].amount = 120
        let diff = SyncDiff.diff(old: before, new: d)
        XCTAssertEqual(diff.save, [SyncKey(.variable, d.variableCosts[0].id)])
        core.captureLocalChanges(d, previous: before, now: t(1))
        XCTAssertEqual(core.pendingKeys.filter { $0.kind == .variable }.count, 1)
        // anderes Gerät legt eine neue an (erscheint hinten, nach Erfassungszeit) und löscht die erste
        var e = AppData.initial()
        var core2 = synced(e)
        var remote = e
        let a = variable(remote, "Ausgang", at: 1_750_000_000)
        let b = variable(remote, "Essen", at: 1_740_000_000)
        remote.variableCosts = [a, b]
        let recs = [a, b].compactMap { SyncCodec.record(SyncKey(.variable, $0.id), in: remote, modifiedAt: t(5)) }
        let r = core2.applyRemote(records: recs, deletions: [], data: &e, isPresent: noFiles, now: t(6))
        XCTAssertTrue(r.changed)
        XCTAssertEqual(e.variableCosts.map { $0.label }, ["Essen", "Ausgang"])
        XCTAssertTrue(core2.pendingKeys.isEmpty)
        _ = core2.applyRemote(records: [], deletions: [SyncKey(.variable, b.id)], data: &e, isPresent: noFiles, now: t(7))
        XCTAssertEqual(e.variableCosts.map { $0.label }, ["Ausgang"])
    }

    func testPersonAliasRewritesHolders() {
        var d = AppData.initial()
        var core = synced(d)
        let keep = d.persons[0].id
        let gone = UUID()
        core.ledger.aliases = [SyncKey(.person, gone).recordName: SyncKey(.person, keep).recordName]
        var remote = d
        var v = variable(d, "Spät")
        v.holderIDs = [gone, keep]
        remote.variableCosts = [v]
        let res = core.applyRemote(records: [SyncCodec.record(SyncKey(.variable, v.id), in: remote, modifiedAt: t(1))!], deletions: [],
                                   data: &d, isPresent: noFiles, now: t(2))
        XCTAssertEqual(d.variableCosts.first?.holderIDs, [keep])
        XCTAssertEqual(res.resend, [SyncKey(.variable, v.id)])
    }

    func testUntouchedAndLostData() {
        var d = AppData.initial()
        XCTAssertTrue(SyncMerge.isUntouched(d))
        d.variableCosts = [variable(d, "Essen")]
        XCTAssertFalse(SyncMerge.isUntouched(d), "variable Kosten sind eigene Daten")
        let core = synced(d)
        XCTAssertFalse(core.looksLikeLostData(d))
        XCTAssertTrue(core.looksLikeLostData(AppData.initial()), "nur variable Kosten bekannt, lokal leer")
    }
}
