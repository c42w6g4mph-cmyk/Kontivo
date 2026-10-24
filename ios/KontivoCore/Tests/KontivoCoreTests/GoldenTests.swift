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
            let r = GoldenTests.importCases(cases, settings: so["settings"], today: today)
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
                // v157/v160
                XCTAssertEqual(calc.trialOn(c), bool(e["trialOn"]), "\(m) trialOn")
                XCTAssertEqual(calc.endsSelf(c), bool(e["endsSelf"]), "\(m) endsSelf")
                // v205–v209
                checkSkr(calc.specialCancelInfo(c), e["skr"], m)
                checked += 1
            }
        }
        XCTAssertEqual(checked, 100)
    }

    /// Fälle als Web-Backup, damit sie denselben Weg wie ein echter Import nehmen.
    static func importCases(_ cases: [JSObject], settings: JSValue?, today: Day) -> WebImportResult {
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
        backup["settings"] = settings
        backup["contracts"] = .object(contracts)
        backup["incomes"] = .object(JSObject())
        return WebImport.importObject(backup, today: today, now: Date())
    }

    /// Sonderkündigung gegen `skrInfo` der Web-App (null = keine).
    func checkSkr(_ x: SpecialCancelInfo?, _ v: JSValue?, _ m: String) {
        guard let e = JS.obj(v) else {
            XCTAssertNil(x, "\(m) skr: Web null")
            return
        }
        guard let x = x else {
            XCTFail("\(m) skr fehlt")
            return
        }
        XCTAssertEqual(x.from.iso, str(e["from"]), "\(m) skr.from")
        XCTAssertEqual(x.amount, num(e["amount"]) ?? -1, accuracy: 1e-9, "\(m) skr.amount")
        XCTAssertEqual(x.previous, num(e["prev"]) ?? -1, accuracy: 1e-9, "\(m) skr.prev")
        XCTAssertEqual(Double(x.percent), num(e["pct"]) ?? -1, "\(m) skr.pct")
        XCTAssertEqual(x.until?.iso, str(e["until"]), "\(m) skr.until")
        XCTAssertEqual(x.head, str(e["head"]), "\(m) skr.head")
        XCTAssertEqual(x.tail, str(e["tail"]), "\(m) skr.tail")
        XCTAssertEqual(x.rule.none, bool(e["none"]), "\(m) skr.none")
        XCTAssertEqual(x.rule.untilIsMinimum, bool(e["min"]), "\(m) skr.min")
        XCTAssertEqual(x.rule.end?.iso, str(e["end"]), "\(m) skr.end")
        XCTAssertEqual(x.rule.endIsMinimum, bool(e["endMin"]), "\(m) skr.endMin")
        XCTAssertEqual(x.rule.endText, str(e["endTxt"]), "\(m) skr.endTxt")
        XCTAssertEqual(x.rule.when, str(e["when"]), "\(m) skr.when")
        XCTAssertEqual(x.rule.source, str(e["src"]), "\(m) skr.src")
        XCTAssertEqual(x.rule.tips, JS.arr(e["tips"]).compactMap { str($0) }, "\(m) skr.tips")
    }

    /// Kopf «Verträge» je Filter und Status (Web v161/v164/v189, DOM nach `renderHero`).
    func testGoldenHero() throws {
        let spec = try JSONParser.parse(GoldenTests.resource("cases"))
        let golden = try JSONParser.parse(GoldenTests.resource("golden"))
        guard case .object(let so) = spec, case .object(let go) = golden, let heroes = JS.obj(go["hero"]) else {
            XCTFail("Testdaten unlesbar")
            return
        }
        let cases = JS.arr(so["cases"]).compactMap { JS.obj($0) }
        var checked = 0
        for t in heroes.orderedKeys {
            guard let today = Day(iso: t), let exp = JS.obj(heroes[t]) else { continue }
            let r = GoldenTests.importCases(cases, settings: so["settings"], today: today)
            let calc = Calc(data: r.data, today: today)
            // Filter wie make_golden.py (HERO_VARIANTS)
            let variants: [String: (Calc.CostFilter, Calc.HeroStatus?)] = [
                "all": (Calc.CostFilter(), nil), "act": (Calc.CostFilter(), .active), "paused": (Calc.CostFilter(), .paused),
                "fut": (Calc.CostFilter(), .future), "sinan": (Calc.CostFilter(person: r.personIDs["Sinan"]), nil),
                "lara": (Calc.CostFilter(person: r.personIDs["Lara"]), nil), "lara-paused": (Calc.CostFilter(person: r.personIDs["Lara"]), .paused),
                "tax": (Calc.CostFilter(category: "Steuern & Gebühren"), nil), "other-fut": (Calc.CostFilter(category: "Sonstiges"), .future),
            ]
            for k in exp.orderedKeys {
                guard let e = JS.obj(exp[k]), let v = variants[k] else {
                    XCTFail("\(t) Kopf \(k): Variante fehlt")
                    continue
                }
                let m = "\(t) Kopf \(k)"
                let h = calc.hero(filter: v.0, status: v.1)
                XCTAssertEqual(h.status?.rawValue, str(e["status"]), "\(m) status")
                XCTAssertEqual(Format.money(h.monthlyTotal), str(e["month"]), "\(m) Summe")
                XCTAssertEqual(h.label, str(e["label"]), "\(m) Beschriftung")
                XCTAssertEqual(h.subtitle, str(e["sub"]), "\(m) Unterzeile")
                let chips = JS.obj(e["chips"]) ?? JSObject()
                XCTAssertEqual(h.showsChips ? Double(h.activeCount) : nil, num(chips["act"]), "\(m) Chip aktiv")
                XCTAssertEqual(h.pausedCount > 0 ? Double(h.pausedCount) : nil, num(chips["paused"]), "\(m) Chip pausiert")
                XCTAssertEqual(h.futureCount > 0 ? Double(h.futureCount) : nil, num(chips["fut"]), "\(m) Chip noch nicht aktiv")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 36)
    }

    /// Sonderkündigung (Web v205–v209): Regel, Zeile im Detail und Erklärblatt (DOM von `openSkr`).
    func testGoldenSpecialCancel() throws {
        let spec = try JSONParser.parse(GoldenTests.resource("cases"))
        let golden = try JSONParser.parse(GoldenTests.resource("golden"))
        guard case .object(let so) = spec, case .object(let go) = golden, let skr = JS.obj(go["skr"]) else {
            XCTFail("Testdaten unlesbar")
            return
        }
        let cases = JS.arr(so["skrCases"]).compactMap { JS.obj($0) }
        XCTAssertEqual(cases.count, 18)
        var checked = 0
        for t in skr.orderedKeys {
            guard let today = Day(iso: t), let exp = JS.obj(skr[t]) else { continue }
            let r = GoldenTests.importCases(cases, settings: so["settings"], today: today)
            let calc = Calc(data: r.data, today: today)
            for cs in cases {
                let id = JS.str(cs["id"])
                let m = "\(t) skr \(id)"
                guard let uid = r.contractIDs[id], let c = r.data.contract(uid), let e = JS.obj(exp[id]) else {
                    XCTFail("\(m): Fall fehlt")
                    continue
                }
                checkSkr(calc.specialCancelInfo(c), e["skr"], m)
                XCTAssertEqual(calc.specialCancel(c) != nil, bool(e["detail"]), "\(m) Zeile im Detail")
                XCTAssertEqual(calc.specialCancelInfo(c)?.lineText, str(e["line"]), "\(m) Zeilentext")
                // Regel und Blatt auch ohne «ordentlich vorher kündbar» (Web v259), damit die Regeln selbst geprüft bleiben
                checkSkr(calc.specialCancelInfo(c, ignoreRegularEnd: true), e["skrRaw"], m + " (Regel)")
                checkSheet(calc.specialCancelSheet(c), e["sheet"], m)
                checkSheet(calc.specialCancelSheet(c, ignoreRegularEnd: true), e["sheetRaw"], m + " (Regel)")
                checked += 1
            }
        }
        XCTAssertEqual(checked, 72)
    }

    func checkSheet(_ sh: SpecialCancelSheet?, _ ev: JSValue?, _ m: String) {
                if let es = JS.obj(ev) {
                    XCTAssertEqual(sh?.title, str(es["title"]), "\(m) Blatt Titel")
                    XCTAssertEqual(sh?.intro, str(es["intro"]), "\(m) Blatt Einleitung")
                    let rows = JS.arr(es["rows"]).compactMap { JS.obj($0) }
                    XCTAssertEqual(sh?.rows.count, rows.count, "\(m) Blatt Zeilen")
                    for (i, row) in rows.enumerated() where i < (sh?.rows.count ?? 0) {
                        let x = sh!.rows[i]
                        XCTAssertEqual(x.key, str(row["key"]), "\(m) Zeile \(i) key")
                        XCTAssertEqual(x.value, str(row["value"]), "\(m) Zeile \(i) value")
                        XCTAssertEqual(x.sub, str(row["sub"]), "\(m) Zeile \(i) sub")
                        XCTAssertEqual(x.accent, bool(row["accent"]), "\(m) Zeile \(i) accent")
                    }
                    XCTAssertEqual(sh?.tipsTitle, str(es["tipsTitle"]), "\(m) Blatt Gut zu wissen")
                    XCTAssertEqual(sh?.tips ?? [], JS.arr(es["tips"]).compactMap { str($0) }, "\(m) Blatt Tipps")
                    XCTAssertEqual(sh?.footer, str(es["footer"]), "\(m) Blatt Grundlage")
                } else {
                    XCTAssertNil(sh, "\(m) Blatt: Web keines")
                }
    }
}
