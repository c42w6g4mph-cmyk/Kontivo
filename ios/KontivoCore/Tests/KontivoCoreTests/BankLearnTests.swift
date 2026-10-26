import XCTest
@testable import KontivoCore

/// Kontoauszug Web v331–v346 ohne eigene Web-Erwartungswerte: lernt aus Korrekturen (wie main/tests/bank/learn.py), Schlüssel je
/// Unterreihe (main/tests/bank/multi.py B-H6), Backup-Import und iCloud-Abgleich von `bankLearn`, Vereine, Namen, Plakette.
final class BankLearnTests: XCTestCase {
    typealias J = [String: Any]

    func edge(_ name: String) throws -> (BankFile, AppData) {
        let inp = try XCTUnwrap(BankParityTests.expected["edgeInput"] as? J)
        let i = try XCTUnwrap(inp[name] as? J)
        let data = try WebImport.importBackup(Data(BankParityTests.str(i["backup"]).utf8), today: BankParityTests.today).data
        return (try BankImport.read(Data(BankParityTests.str(i["txt"]).utf8)), data)
    }

    /// Wie learn.py: Sunrise bewusst abgewählt, eine Police mit Bezeichnung übernommen → beim nächsten Import abgewählt bzw. mit
    /// Bezeichnung; die anderen Policen bleiben ohne Bezeichnung.
    func testLearnFromCorrections() throws {
        var (f, data) = try edge("policen")
        var items = BankImport.find(f, data: data, today: BankParityTests.today).items
        BankImport.learnAssign(&items, settings: data.settings)
        XCTAssertTrue(items.allSatisfy { $0.learn == nil })
        let sun = try XCTUnwrap(items.first { $0.name.hasPrefix("Sunrise") })
        let pol = try XCTUnwrap(items.first { $0.name.hasPrefix("Muster Versicherung") && Swift.abs($0.amount - 404.1) < 0.001 })
        XCTAssertEqual(BankImport.label(pol), "")   // «Ohne Bezeichnung»
        BankImport.learn(sun, on: false, touched: true, label: BankImport.label(sun), reactivate: false, in: &data.settings)
        BankImport.learn(pol, on: true, touched: true, label: "Hausrat", reactivate: false, in: &data.settings)
        // unverändert übernommen, nicht angetippt: nichts lernen
        for s in items where s.id != sun.id && s.id != pol.id {
            BankImport.learn(s, on: true, touched: false, label: BankImport.label(s), reactivate: false, in: &data.settings)
        }
        XCTAssertEqual(data.settings.bankLearn.count, 2)

        // Backup-Rundgang (Web-Format) und JSON der App behalten die Korrekturen
        let enc = try KontivoJSON.makeEncoder().encode(data.settings)
        let back = try KontivoJSON.makeDecoder().decode(Settings.self, from: enc)
        XCTAssertEqual(back.bankLearn, data.settings.bankLearn)

        (f, _) = try edge("policen")
        var again = BankImport.find(f, data: data, today: BankParityTests.today).items
        BankImport.learnAssign(&again, settings: data.settings)
        func at(_ a: Double) -> BankSuggestion? { again.first { $0.name.hasPrefix("Muster Versicherung") && Swift.abs($0.amount - a) < 0.001 } }
        XCTAssertEqual(again.first { $0.name.hasPrefix("Sunrise") }?.learn?.x, true)
        XCTAssertEqual(at(404.1)?.learn?.l, "Hausrat")
        XCTAssertNil(at(383.2)?.learn)
        XCTAssertNil(at(372.7)?.learn)

        // wieder angehakt und übernommen: Korrektur «abgewählt» fällt weg
        let s2 = try XCTUnwrap(again.first { $0.name.hasPrefix("Sunrise") })
        BankImport.learn(s2, on: true, touched: true, label: BankImport.label(s2), reactivate: false, in: &data.settings)
        XCTAssertNil(data.settings.bankLearn[BankImport.learnKey(s2)])
        // ausgeblendete und «Wieder aktivieren» lernen nicht
        var ign = s2
        ign.ignored = true
        BankImport.learn(ign, on: false, touched: true, label: "", reactivate: false, in: &data.settings)
        BankImport.learn(s2, on: false, touched: true, label: "", reactivate: true, in: &data.settings)
        XCTAssertNil(data.settings.bankLearn[BankImport.learnKey(s2)])
    }

    /// Eins zu eins: jede Korrektur gilt nur für den nächstgelegenen Betrag (±35 %); höchstens 12 Einträge, gleicher Betrag ersetzt.
    func testLearnAssignAndSet() throws {
        let (f, data) = try edge("policen")
        var st = data.settings
        let items = BankImport.find(f, data: data, today: BankParityTests.today).items.filter { $0.name.hasPrefix("Muster Versicherung") }
        XCTAssertEqual(items.count, 3)
        let k = BankImport.learnKey(items[0])
        XCTAssertTrue(items.allSatisfy { BankImport.learnKey($0) == k })
        st.bankLearn[k] = [BankLearn(a: 400, l: "Hausrat")]
        var L = items
        BankImport.learnAssign(&L, settings: st)
        XCTAssertEqual(L.filter { $0.learn != nil }.map { $0.amount }, [404.1])
        // 13 Einträge → die letzten 12; gleicher Betrag wird ersetzt
        for i in 0..<13 { BankImport.learnSet(BankSuggestion.stub(amount: Double(100 + i), key: "x|CHF"), ("L\(i)", false), in: &st) }
        XCTAssertEqual(st.bankLearn["x"]?.count, 12)
        XCTAssertEqual(st.bankLearn["x"]?.first?.a, 101)
        BankImport.learnSet(BankSuggestion.stub(amount: 112, key: "x#2|CHF"), (label: "", off: true), in: &st)
        XCTAssertEqual(st.bankLearn["x"]?.last, BankLearn(a: 112, x: true))
        XCTAssertEqual(st.bankLearn["x"]?.filter { $0.a == 112 }.count, 1)
    }

    /// Unterreihen (mehrere Policen) haben verschiedene Schlüssel für «nicht mehr vorschlagen» (main/tests/bank/multi.py B-H6)
    func testIgnoreKeysPerSubSeries() throws {
        let (f, data) = try edge("jahresreihe")
        let keys = BankImport.find(f, data: data, today: BankParityTests.today).all.filter { $0.name.contains("Muster Versicherung") }.map { BankImport.ignoreKey($0) }
        XCTAssertGreaterThanOrEqual(keys.count, 2)
        XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { $0.contains("~c") })
    }

    /// Backup-Import (Web sanitizeImport): Betrag > 0 auf Rappen, Bezeichnung getrimmt, nur mit Bezeichnung oder «abgewählt», je 12
    func testWebImportBankLearn() throws {
        let entries = (0..<14).map { #"{"a":\#($0 + 1),"x":1}"# }.joined(separator: ",")
        let json = #"{"app":"vertraege","version":2,"settings":{"home":"CHF","bankLearn":{"tpl:Sunrise":[{"a":"39.004","l":"  Handy  "},{"a":0,"x":1},{"a":5},{"a":-3,"x":1},{"a":7,"x":true}],"#
            + #""viele":[\#(entries)],"leer":[{"a":5}],"kein":{"a":1}}},"contracts":{},"incomes":{}}"#
        let d = try WebImport.importBackup(Data(json.utf8), today: BankParityTests.today).data
        XCTAssertEqual(d.settings.bankLearn["tpl:Sunrise"], [BankLearn(a: 39, l: "Handy"), BankLearn(a: 7, x: true)])
        XCTAssertEqual(d.settings.bankLearn["viele"]?.count, 12)
        XCTAssertEqual(d.settings.bankLearn["viele"]?.first?.a, 3)
        XCTAssertNil(d.settings.bankLearn["leer"])
        XCTAssertNil(d.settings.bankLearn["kein"])
    }

    /// iCloud: gelernte Korrekturen werden abgeglichen; lokal geänderte Schlüssel gewinnen
    func testSyncSettingsBankLearn() throws {
        var d = AppData.initial()
        d.settings.bankLearn = ["a": [BankLearn(a: 10, x: true)]]
        let base = SyncSettings(d)
        var local = base
        local.bankLearn["b"] = [BankLearn(a: 20, l: "Hausrat")]
        var remote = base
        remote.bankLearn["a"] = nil
        remote.bankLearn["c"] = [BankLearn(a: 30, x: true)]
        let m = SyncSettings.merge(base: base, local: local, remote: remote)
        XCTAssertEqual(Set(m.bankLearn.keys), ["b", "c"])
        let u = SyncSettings.union(local: local, remote: remote, preferLocal: true)
        XCTAssertEqual(Set(u.bankLearn.keys), ["a", "b", "c"])
        var s = Settings()
        m.apply(to: &s)
        XCTAssertEqual(s.bankLearn["b"]?.first?.l, "Hausrat")
        let back = try JSONDecoder().decode(SyncSettings.self, from: try JSONEncoder().encode(m))
        XCTAssertEqual(back.bankLearn, m.bankLearn)
    }

    func testClubsNamesChip() {
        XCTAssertEqual(BankClub.label("FC Muster", "FC Muster"), "Fussball")
        XCTAssertEqual(BankClub.label("TV Musterdorf", "TV Musterdorf"), "Turnverein")
        XCTAssertEqual(BankClub.label("Musikgesellschaft Musterdorf", ""), "Musikverein")
        XCTAssertEqual(BankClub.label("Muster Verein", ""), "Mitgliedschaft")
        XCTAssertFalse(BankClub.isClub("TV Media AG", ""))
        XCTAssertFalse(BankClub.isClub("Club Med", ""))
        XCTAssertEqual(BankName.clean("Raiffeisen Pensionskasse Genosse..."), "Raiffeisen Pensionskasse")
        XCTAssertEqual(BankName.clean("Muster SaaS Dublin EUR 9.99"), "Muster SaaS Dublin")
        XCTAssertNil(BankName.subMemo("Strassenverkehrsamt\ndes Kantons Thurgau"))
        let c = BankImport.chips(dates: [Day(2026, 9, 1)], amounts: [39], count: 1, last: Day(2026, 9, 1), lowConfidence: false, change: nil,
                                 varies: false, cycle: 1, currency: "CHF", amount: 39, income: false, learnedOff: true)
        XCTAssertEqual(c.first?.text, "letztes Mal nicht übernommen")
        XCTAssertEqual(c.first?.kind, .plain)
    }
}

extension BankSuggestion {
    static func stub(amount: Double, key: String) -> BankSuggestion {
        let d = Day(2026, 9, 1)
        return BankSuggestion(id: key, key: key, name: "X", raw: "", text: "", currency: "CHF", amount: amount, cycle: 1, due: d, first: d, last: d,
                              count: 1, dates: [d], amounts: [amount], confidence: .high, varies: false, change: nil, catalog: nil, category: "",
                              kind: .unknown, cred: "", mref: "", alias: nil, ignored: false)
    }
}
