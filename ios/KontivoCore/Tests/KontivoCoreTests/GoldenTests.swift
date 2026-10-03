import XCTest
@testable import KontivoCore

/// Prüft den Rechenkern gegen golden.json (aus der Web-App erzeugt): 4 Stichtage × 25 Fälle × alle Felder.
final class GoldenTests: XCTestCase {
    static func resource(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json")
            ?? Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")
        guard let u = url else { throw NSError(domain: "GoldenTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(name).json fehlt"]) }
        return try Data(contentsOf: u)
    }

    func str(_ v: JSValue?) -> String? {
        if case .string(let s)? = v { return s }
        return nil
    }

    func num(_ v: JSValue?) -> Double? {
        if case .number(let n)? = v { return n }
        return nil
    }

    func bool(_ v: JSValue?) -> Bool? {
        if case .bool(let b)? = v { return b }
        return nil
    }

    func testGolden() throws {
        let spec = try JSONParser.parse(GoldenTests.resource("cases"))
        let golden = try JSONParser.parse(GoldenTests.resource("golden"))
        guard case .object(let so) = spec, case .object(let go) = golden, let results = JS.obj(go["results"]) else {
            XCTFail("Testdaten unlesbar")
            return
        }
        let todays = JS.arr(so["todays"]).map { JS.str($0) }
        let cases = JS.arr(so["cases"]).compactMap { JS.obj($0) }
        XCTAssertEqual(todays.count, 4)
        XCTAssertEqual(cases.count, 25)
        var checked = 0
        for t in todays {
            guard let today = Day(iso: t), let exp = JS.obj(results[t]) else {
                XCTFail("Stichtag \(t)")
                continue
            }
            // Fälle als Web-Backup, damit sie denselben Weg wie ein echter Import nehmen
            var contracts = JSObject()
            for cs in cases {
                var c = JSObject()
                c["cat"] = .string("Sonstiges")
                c["status"] = .string("active")
                if let co = JS.obj(cs["c"]) {
                    for k in co.orderedKeys { c[k] = co[k] }
                }
                contracts[JS.str(cs["id"])] = .object(c)
            }
            var backup = JSObject()
            backup["app"] = .string("vertraege")
            backup["settings"] = so["settings"]
            backup["contracts"] = .object(contracts)
            backup["incomes"] = .object(JSObject())
            let r = WebImport.importObject(backup, today: today, now: Date())
            let calc = Calc(data: r.data, today: today)
            let sinan = r.personIDs["Sinan"]
            let lara = r.personIDs["Lara"]
            XCTAssertNotNil(sinan)
            XCTAssertNotNil(lara)
            for cs in cases {
                let id = JS.str(cs["id"])
                guard let uid = r.contractIDs[id], let c = r.data.contract(uid), let e = JS.obj(exp[id]) else {
                    XCTFail("\(t) \(id): Fall fehlt")
                    continue
                }
                let m = "\(t) \(id)"
                XCTAssertEqual(calc.termEnd(c)?.iso, str(e["termEnd"]), "\(m) termEnd")
                XCTAssertEqual(calc.noticeDeadline(c)?.iso, str(e["noticeDeadline"]), "\(m) noticeDeadline")
                XCTAssertEqual(calc.nextTerm(c)?.iso, str(e["nextTerm"]), "\(m) nextTerm")
                XCTAssertEqual(calc.effEnd(c)?.iso, str(e["effEnd"]), "\(m) effEnd")
                XCTAssertEqual(calc.renewTo(c)?.iso, str(e["renewTo"]), "\(m) renewTo")
                XCTAssertEqual(calc.isEnded(c), bool(e["ended"]), "\(m) ended")
                XCTAssertEqual(calc.nextDue(c)?.iso, str(e["nextDue"]), "\(m) nextDue")
                let pays = calc.occurrences(c, from: today, to: Day(today.year + 1, 12, 31)).prefix(12).map { $0.iso }
                XCTAssertEqual(Array(pays), JS.arr(e["paymentsNext12"]).compactMap { str($0) }, "\(m) paymentsNext12")
                XCTAssertEqual(Format.round2(calc.curPrice(c)), num(e["curPrice"]) ?? -1, accuracy: 1e-9, "\(m) curPrice")
                XCTAssertEqual(Format.round2(calc.monthlyCost(c)), num(e["monthlyCostHome"]) ?? -1, accuracy: 1e-9, "\(m) monthlyCostHome")
                XCTAssertEqual(calc.isAnytime(c), bool(e["anytime"]), "\(m) anytime")
                XCTAssertEqual(calc.needsAction(c), bool(e["needsAction"]), "\(m) needsAction")
                XCTAssertEqual(calc.trialNeeds(c), bool(e["trialNeeds"]), "\(m) trialNeeds")
                XCTAssertEqual(calc.isPaused(c), bool(e["paused"]), "\(m) paused")
                XCTAssertEqual(calc.holderShare(c, person: sinan), num(e["shareSinan"]) ?? -1, accuracy: 1e-12, "\(m) shareSinan")
                XCTAssertEqual(calc.holderShare(c, person: lara), num(e["shareLara"]) ?? -1, accuracy: 1e-12, "\(m) shareLara")
                XCTAssertEqual(calc.cancVia(c).jsValue, str(e["cancVia"]), "\(m) cancVia")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 100)
    }
}
