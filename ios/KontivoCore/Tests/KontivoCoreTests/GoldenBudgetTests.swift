import XCTest
@testable import KontivoCore

/// Prüft Summen, Kosten, Budget, «Fair geteilt?», variable Kosten und Einnahmen pro Monat gegen golden_budget.json
/// (aus der Web-App v322 erzeugt mit main/tests/make_golden_budget.py; Eingabe cases_budget.json: ein Haushalt, 3 Stichtage).
final class GoldenBudgetTests: XCTestCase {
    let acc = 0.006

    func num(_ v: JSValue?) -> Double? {
        if case .number(let n)? = v { return n }
        return nil
    }

    /// Haushalt aus cases_budget.json als Web-Backup einlesen.
    static func importHousehold(_ spec: JSObject, today: Day) -> WebImportResult {
        var backup = JSObject()
        backup["app"] = .string("vertraege")
        backup["settings"] = spec["settings"]
        backup["contracts"] = spec["contracts"]
        backup["incomes"] = spec["incomes"]
        backup["vars"] = spec["vars"]
        return WebImport.importObject(backup, today: today, now: Date())
    }

    func testGoldenBudget() throws {
        let spec = try JSONParser.parse(GoldenTests.resource("cases_budget"))
        let golden = try JSONParser.parse(GoldenTests.resource("golden_budget"))
        guard case .object(let so) = spec, case .object(let go) = golden, let results = JS.obj(go["results"]) else {
            XCTFail("Testdaten unlesbar")
            return
        }
        let todays = JS.arr(so["todays"]).map { JS.str($0) }
        XCTAssertEqual(todays.count, 3)
        let kinds: [(String, BudgetKind)] = [("all", .all), ("fix", .fix), ("none", .none)]
        for t in todays {
            guard let today = Day(iso: t), let exp = JS.obj(results[t]) else {
                XCTFail("Stichtag \(t)")
                continue
            }
            let r = GoldenBudgetTests.importHousehold(so, today: today)
            XCTAssertEqual(r.data.variableCosts.count, 3, "\(t) variable Kosten importiert")
            let calc = Calc(data: r.data, today: today)
            let persons: [(String, UUID?)] = [("alle", nil), ("Sinan", r.personIDs["Sinan"]), ("Lara", r.personIDs["Lara"])]
            XCTAssertNotNil(r.personIDs["Sinan"])
            XCTAssertNotNil(r.personIDs["Lara"])
            let years = [today.year - 1, today.year, today.year + 1]

            // Kopfzeile «Fixkosten pro Monat»
            let fpm = JS.obj(exp["fixPerMonth"]) ?? JSObject()
            for (pk, pid) in persons {
                XCTAssertEqual(calc.hero(filter: Calc.CostFilter(person: pid)).monthlyTotal, num(fpm[pk]) ?? -1, accuracy: acc, "\(t) fixPerMonth \(pk)")
            }

            for y in years {
                let ys = String(y)
                // Kosten-Tab je Monat
                let ec = JS.obj(JS.obj(exp["cost"])?[ys]) ?? JSObject()
                for (pk, pid) in persons {
                    guard let e = JS.obj(ec[pk]) else { XCTFail("\(t) cost \(y) \(pk) fehlt"); continue }
                    let cy = calc.costYear(y, filter: Calc.CostFilter(person: pid))
                    XCTAssertEqual(Double(cy.paymentCount), num(e["n"]) ?? -1, "\(t) cost \(y) \(pk) n")
                    let em = JS.arr(e["months"]).compactMap { JS.obj($0) }
                    XCTAssertEqual(em.count, 12)
                    for (i, m) in em.enumerated() where i < 12 {
                        let s = "\(t) cost \(y)-\(i + 1) \(pk)"
                        XCTAssertEqual(cy.months[i].sum, num(m["sum"]) ?? -1, accuracy: acc, "\(s) sum")
                        XCTAssertEqual(cy.months[i].paid, num(m["paid"]) ?? -1, accuracy: acc, "\(s) paid")
                        XCTAssertEqual(cy.months[i].open, num(m["open"]) ?? -1, accuracy: acc, "\(s) open")
                        XCTAssertEqual(Double(cy.months[i].items.count), num(m["count"]) ?? -1, "\(s) count")
                    }
                }
                // Budget je Kostenart
                let eb = JS.obj(JS.obj(exp["budget"])?[ys]) ?? JSObject()
                for (pk, pid) in persons {
                    let ep = JS.obj(eb[pk]) ?? JSObject()
                    for (kk, kind) in kinds {
                        guard let e = JS.obj(ep[kk]) else { XCTFail("\(t) budget \(y) \(pk) \(kk) fehlt"); continue }
                        let b = calc.budgetYear(y, person: pid, kind: kind)
                        let s = "\(t) budget \(y) \(pk) \(kk)"
                        XCTAssertEqual(b.totalIncome, num(e["inc"]) ?? -1, accuracy: acc, "\(s) inc")
                        XCTAssertEqual(b.totalFixed, num(e["fix"]) ?? -1, accuracy: acc, "\(s) fix")
                        XCTAssertEqual(b.totalVariable, num(e["vr"]) ?? -1, accuracy: acc, "\(s) vr")
                        XCTAssertEqual(b.totalFree, num(e["free"]) ?? -1, accuracy: acc, "\(s) free")
                        let em = JS.arr(e["months"]).compactMap { JS.obj($0) }
                        for (i, m) in em.enumerated() where i < 12 {
                            XCTAssertEqual(b.months[i].income, num(m["inc"]) ?? -1, accuracy: acc, "\(s) \(i + 1) inc")
                            XCTAssertEqual(b.months[i].fixed, num(m["fix"]) ?? -1, accuracy: acc, "\(s) \(i + 1) fix")
                            XCTAssertEqual(b.months[i].variable, num(m["vr"]) ?? -1, accuracy: acc, "\(s) \(i + 1) vr")
                            XCTAssertEqual(b.months[i].free, num(m["free"]) ?? -1, accuracy: acc, "\(s) \(i + 1) free")
                        }
                    }
                }
                // Variable Kosten je Monat (ohne Person)
                let ev = JS.arr(JS.obj(exp["varMonth"])?[ys]).compactMap { num($0) }
                XCTAssertEqual(ev.count, 12)
                for (i, v) in ev.enumerated() where i < 12 {
                    XCTAssertEqual(calc.variableMonth(year: y, month: i + 1, person: nil), v, accuracy: acc, "\(t) varMonth \(y)-\(i + 1)")
                }
            }

            // Vorjahresmonat (Vergleichszeile im Budget)
            let epm = JS.obj(exp["budgetPrevMonth"]) ?? JSObject()
            for (pk, pid) in persons {
                let ep = JS.obj(epm[pk]) ?? JSObject()
                for (kk, kind) in kinds {
                    guard let e = JS.obj(ep[kk]) else { XCTFail("\(t) budgetPrevMonth \(pk) \(kk) fehlt"); continue }
                    let y = today.year - 1, mo = today.month
                    let m = calc.budgetPeriod(year: y, from: Day(y, mo, 1), to: Day(y, mo + 1, 0), person: pid, kind: kind).months[mo - 1]
                    let s = "\(t) budgetPrevMonth \(pk) \(kk)"
                    XCTAssertEqual(m.income, num(e["inc"]) ?? -1, accuracy: acc, "\(s) inc")
                    XCTAssertEqual(m.fixed, num(e["fix"]) ?? -1, accuracy: acc, "\(s) fix")
                    XCTAssertEqual(m.variable, num(e["vr"]) ?? -1, accuracy: acc, "\(s) vr")
                    XCTAssertEqual(m.free, num(e["free"]) ?? -1, accuracy: acc, "\(s) free")
                }
            }

            // «Fair geteilt?»: Prozente je Person aus den Web-Beträgen
            if let fs = JS.obj(exp["fairShare"]), let per = JS.obj(fs["per"]), let fix = num(fs["fix"]), let inc = num(fs["inc"]) {
                let rows = calc.fairShare() ?? []
                for pk in per.orderedKeys {
                    guard let e = JS.obj(per[pk]), let pid = r.personIDs[pk] else { continue }
                    let ef = Int(Format.jsRound((num(e["fix"]) ?? 0) / fix * 100)), ei = Int(Format.jsRound((num(e["inc"]) ?? 0) / inc * 100))
                    let row = rows.first { $0.personID == pid }
                    XCTAssertEqual(row?.fixedPercent, ef, "\(t) fairShare \(pk) Fixkosten")
                    XCTAssertEqual(row?.incomePercent, ei, "\(t) fairShare \(pk) Einnahmen")
                }
            } else {
                XCTAssertNil(calc.fairShare(), "\(t) fairShare: Web null")
            }

            // Einnahmen pro Monat (heute)
            XCTAssertEqual(calc.incomeMonthNow, num(exp["incMonthNow"]) ?? -1, accuracy: acc, "\(t) incMonthNow")
        }
    }

    /// Kostenart: ohne variable Kosten immer Fixkosten (Web `kArt`/`bArt`, v256).
    func testKindsWithoutVariableCosts() {
        var d = AppData.initial()
        d.settings.costKind = .all
        d.settings.budgetKind = .none
        let today = Day(2026, 10, 24)
        XCTAssertEqual(Calc(data: d, today: today).costKind, .fix)
        XCTAssertEqual(Calc(data: d, today: today).budgetKind, .fix)
        d.putVariableCost(VariableCost(label: "Lebensmittel", icon: .essen, amount: 900))
        XCTAssertEqual(Calc(data: d, today: today).costKind, .all)
        XCTAssertEqual(Calc(data: d, today: today).budgetKind, .none)
    }

    /// Variable Kosten überleben Speichern und Laden im nativen Format; ältere Daten ohne Liste lesen leer.
    func testVariableCostsCodable() throws {
        var d = AppData.initial()
        let p = d.persons[0].id
        d.putVariableCost(VariableCost(label: " Benzin ", icon: .benzin, amount: 180.004, holderIDs: [p], start: Day(2026, 3, 1)))
        let data = try KontivoJSON.makeEncoder().encode(d)
        let back = try KontivoJSON.makeDecoder().decode(AppData.self, from: data)
        XCTAssertEqual(back.variableCosts.count, 1)
        XCTAssertEqual(back.variableCosts[0].label, "Benzin")
        XCTAssertEqual(back.variableCosts[0].amount, 180)
        XCTAssertEqual(back.variableCosts[0].holderIDs, [p])
        let old = try KontivoJSON.makeDecoder().decode(AppData.self, from: Data("{\"settings\":{},\"contracts\":[],\"incomes\":[]}".utf8))
        XCTAssertTrue(old.variableCosts.isEmpty)
        XCTAssertEqual(old.settings.budgetKind, .fix)
    }

    /// Person löschen bzw. zusammenführen nimmt die variablen Kosten mit.
    func testPersonsAndVariableCosts() throws {
        var d = AppData.initial()
        let a = d.persons[0].id
        let b = try d.addPerson("Lara")
        d.putVariableCost(VariableCost(label: "Ferien", icon: .ferien, amount: 300, holderIDs: [a, b]))
        d.mergePerson(b, into: a)
        XCTAssertEqual(d.variableCosts[0].holderIDs, [a])
        let c = try d.addPerson("Mia")
        d.variableCosts[0].holderIDs = [a, c]
        try d.deletePerson(c, transferTo: nil)
        XCTAssertEqual(d.variableCosts[0].holderIDs, [a])
    }
}
