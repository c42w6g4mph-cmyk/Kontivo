import XCTest
@testable import KontivoCore

/// Tab «Kosten» → «Überblick» und «Was sich verändert hat» gegen golden_drivers.json (Web v247–v257, erzeugt mit
/// tests/make_golden_drivers.py): Säulen mit Veränderung, Kategorien mit Betrag, Chips, Verträge mit Grund, Hinweise, Donut.
/// Haushalt aus cases_budget.json (3 Stichtage), Beispieldaten costs_demo_backup.json und Wechsel-Fälle (in golden_drivers.json). Tausendertrennung: Web ' = Swift ’.
final class GoldenDriversTests: XCTestCase {
    func web(_ s: String) -> String { s.replacingOccurrences(of: "'", with: Format.thousandsSeparator) }

    func load(_ set: String, today: Day, inputs: JSObject?) throws -> WebImportResult {
        if let i = inputs?[set], case .object(let o) = i { return WebImport.importObject(o, today: today, now: Date()) }
        if set == "demo" {
            let url = try XCTUnwrap(Bundle.module.url(forResource: "costs_demo_backup", withExtension: "json")
                ?? Bundle.module.url(forResource: "costs_demo_backup", withExtension: "json", subdirectory: "Resources"))
            return try WebImport.importBackup(try Data(contentsOf: url), today: today)
        }
        guard case .object(let so) = try JSONParser.parse(GoldenTests.resource("cases_budget")) else { throw NSError(domain: "GoldenDriversTests", code: 1) }
        return GoldenBudgetTests.importHousehold(so, today: today)
    }

    func testDriversLikeWeb() throws {
        guard case .object(let go) = try JSONParser.parse(GoldenTests.resource("golden_drivers")), let results = JS.obj(go["results"]) else {
            XCTFail("golden_drivers.json unlesbar")
            return
        }
        XCTAssertGreaterThanOrEqual(results.orderedKeys.count, 4)
        for key in results.orderedKeys {
            let parts = key.components(separatedBy: "|")
            guard parts.count == 2, let today = Day(iso: parts[1]), let years = JS.obj(results[key]) else { XCTFail(key); continue }
            let r = try load(parts[0], today: today, inputs: JS.obj(go["inputs"]))
            let calc = Calc(data: r.data, today: today)
            var webID: [UUID: String] = [:]
            for (k, v) in r.contractIDs { webID[v] = k }
            for ys in years.orderedKeys {
                guard let Y = Int(ys), let e = JS.obj(years[ys]) else { continue }
                let p = "\(key) \(Y): "
                let d = calc.costDrivers(year: Y, filter: Calc.CostFilter())
                // Säulen
                let ec = JS.arr(e["cols"]).compactMap { JS.obj($0) }
                XCTAssertEqual(d.columns.map { $0.year }, ec.map { Int(JS.num($0["y"])) }, p + "Säulen Jahre")
                for (i, c) in d.columns.enumerated() where i < ec.count {
                    let x = ec[i]
                    XCTAssertEqual(Format.money0(c.total), web(JS.str(x["v"])), p + "Säule \(c.year) Total")
                    XCTAssertEqual(c.forecast ? "Prognose" : "", JS.str(x["p"]), p + "Säule \(c.year) Prognose")
                    XCTAssertEqual(web(c.deltaText ?? ""), web(JS.str(x["d"])), p + "Säule \(c.year) Veränderung")
                    XCTAssertEqual(c.place.rawValue, ["cur": "current", "past": "past", "fut": "future"][JS.str(x["cls"])] ?? "?", p + "Säule \(c.year) Lage")
                }
                // Liste «Was sich verändert hat»
                if let h = e["head"], case .string(let head) = h {
                    XCTAssertEqual(d.listTitle.replacingOccurrences(of: " · ", with: ""), head, p + "Titel")
                }
                let ecat = JS.arr(e["cats"]).compactMap { JS.obj($0) }
                XCTAssertEqual(d.groups.map { $0.key }, ecat.map { JS.str($0["k"]) }, p + "Kategorien")
                for (i, g) in d.groups.enumerated() where i < ecat.count {
                    let x = ecat[i]
                    let q = p + g.key + " "
                    let dt = Calc.driverDeltaText(g.delta)
                    XCTAssertEqual(dt.text + Format.homeCurrency.rawValue, web(JS.str(x["v"])), q + "Betrag")
                    let chips = g.chips.map { $0.name + " " + $0.word } + (g.moreCount > 0 ? ["+ \(g.moreCount) weitere"] : [])
                    let ech = JS.arr(x["chips"]).compactMap { JS.obj($0) }
                    XCTAssertEqual(chips, ech.map { JS.str($0["t"]) }, q + "Chips")
                    XCTAssertEqual(g.chips.map { ["up": "pu", "down": "pd", "swap": "ps"][$0.tone.rawValue] ?? "" },
                                   ech.filter { JS.str($0["cls"]) != "ptm2" }.map { JS.str($0["cls"]) }, q + "Chip-Farben")
                    let es = JS.arr(x["sub"]).compactMap { JS.obj($0) }
                    XCTAssertEqual(g.changes.map { webID[$0.contractID] ?? "?" }, es.map { JS.str($0["id"]) }, q + "Verträge")
                    XCTAssertEqual(g.changes.map { $0.reason }, es.map { JS.str($0["m"]) }, q + "Gründe")
                    XCTAssertEqual(g.changes.map { Calc.driverDeltaText($0.delta).text + Format.homeCurrency.rawValue }, es.map { web(JS.str($0["v"])) }, q + "Beträge")
                }
                // Hinweise (Reihenfolge wie Web: Vergleich nicht möglich / keine Veränderung / andere gleich / ohne Beginn)
                var notes: [String] = []
                if let n = d.noCompareNote { notes.append(n) }
                if d.comparable {
                    if let n = d.emptyNote { notes.append(n) }
                    if let n = d.othersNote { notes.append(n) }
                    if let n = d.noStartNote { notes.append(n) }
                }
                XCTAssertEqual(notes, JS.arr(e["note"]).map { JS.str($0) }, p + "Hinweise")
                XCTAssertEqual(d.noStartContracts.map { webID[$0] ?? "?" }, JS.arr(e["links"]).map { JS.str($0) }, p + "ohne Beginn (Verträge)")
                // Donut
                let dn = calc.costDonut(year: Y, filter: Calc.CostFilter())
                let ed = JS.arr(e["donut"]).compactMap { JS.obj($0) }
                XCTAssertEqual(dn.slices.map { $0.key + " " + $0.percentText }, ed.map { JS.str($0["k"]) + " " + JS.str($0["p"]) }, p + "Donut")
            }
        }
    }
}
