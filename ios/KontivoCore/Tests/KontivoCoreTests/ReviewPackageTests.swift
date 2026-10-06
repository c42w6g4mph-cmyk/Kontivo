import XCTest
@testable import KontivoCore

/// Review-Paket 06.10.2026: individuelle Aufteilung, Bisher bezahlt, Teurer geworden, Fair geteilt, Quartals-Check, Sonderkündigungsrecht.
final class ReviewPackageTests: XCTestCase {
    private func twoPersons() -> (AppData, UUID, UUID) {
        var d = AppData.initial()
        let a = Person(name: "Sinan"), b = Person(name: "Lara")
        d.persons = [a, b]
        return (d, a.id, b.id)
    }

    func testSplitShareOverridesEqualSplit() {
        var (d, a, b) = twoPersons()
        var c = Contract(label: "Miete", amount: 1000, cycle: 1, due: Day(2026, 10, 1), holderIDs: [a, b])
        let calc0 = Calc(data: d, today: Day(2026, 10, 5))
        XCTAssertEqual(calc0.holderShare(c, person: a), 0.5)
        c.split = [SplitShare(personID: a, percent: 70), SplitShare(personID: b, percent: 30)]
        d.contracts = [c]
        let calc = Calc(data: d, today: Day(2026, 10, 5))
        XCTAssertEqual(calc.holderShare(c, person: a), 0.7)
        XCTAssertEqual(calc.holderShare(c, person: b), 0.3)
        XCTAssertEqual(calc.holderShare(c, person: nil), 1)
        XCTAssertEqual(d.holdersText(of: c), "Sinan 70\u{00A0}% & Lara 30\u{00A0}%")
        // Budget pro Person nutzt die Aufteilung
        XCTAssertEqual(calc.budgetYear(2026, person: a).months[9].fixed, 700, accuracy: 0.001)
        XCTAssertEqual(calc.budgetYear(2026, person: b).months[9].fixed, 300, accuracy: 0.001)
    }

    func testInvalidSplitFallsBackToEqual() {
        let (d, a, b) = twoPersons()
        var c = Contract(label: "Miete", amount: 1000, cycle: 1, due: Day(2026, 10, 1), holderIDs: [a, b])
        c.split = [SplitShare(personID: a, percent: 70)]
        XCTAssertNil(c.validSplit)
        c.split = [SplitShare(personID: a, percent: 70), SplitShare(personID: b, percent: 40)]
        XCTAssertNil(c.validSplit)
        c.holderIDs = [a]
        c.split = [SplitShare(personID: a, percent: 100)]
        XCTAssertNil(c.validSplit)
        XCTAssertEqual(d.holdersText(of: c), "Sinan")
    }

    func testNormalizedSplitLastHolderIsRemainder() {
        let (_, a, b) = twoPersons()
        let sp = AppData.normalizedSplit([SplitShare(personID: a, percent: 65), SplitShare(personID: b, percent: 0)], holders: [a, b])
        XCTAssertEqual(sp.map { $0.percent }, [65, 35])
        XCTAssertEqual(AppData.normalizedSplit([SplitShare(personID: a, percent: 65)], holders: [a, b]), [])
        XCTAssertEqual(AppData.equalSplit(holders: [a, b, UUID()]).map { $0.percent }, [33, 33, 34])
    }

    func testSaveContractKeepsSplitAndHolderChangesDropIt() throws {
        var (d, a, b) = twoPersons()
        var c = Contract(label: "Miete", categoryID: d.categories[0].id, amount: 1000, cycle: 1, due: Day(2026, 10, 1), holderIDs: [a, b])
        c.split = [SplitShare(personID: a, percent: 70), SplitShare(personID: b, percent: 30)]
        let id = try d.saveContract(c, today: Day(2026, 10, 5))
        XCTAssertEqual(d.contract(id)?.validSplit?[a], 70)
        // Person löschen → gleich
        try d.deletePerson(b, transferTo: nil)
        XCTAssertEqual(d.contract(id)?.split, [])
        XCTAssertEqual(d.contract(id)?.holderIDs, [a])
    }

    func testMergePersonCarriesSplit() throws {
        var (d, a, b) = twoPersons()
        let c2 = Person(name: "Lara2")
        d.persons.append(c2)
        var c = Contract(label: "Miete", categoryID: d.categories[0].id, amount: 1000, cycle: 1, due: Day(2026, 10, 1), holderIDs: [a, b])
        c.split = [SplitShare(personID: a, percent: 70), SplitShare(personID: b, percent: 30)]
        d.contracts = [c]
        d.mergePerson(b, into: c2.id)
        XCTAssertEqual(d.contracts[0].validSplit?[c2.id], 30)
        // Zusammenführen auf einen bestehenden Inhaber → gleich
        d.mergePerson(c2.id, into: a)
        XCTAssertEqual(d.contracts[0].split, [])
    }

    func testCSVSplitRoundTrip() {
        var (d, a, b) = twoPersons()
        var c = Contract(label: "Miete", categoryID: d.categories[0].id, amount: 1000, cycle: 1, due: Day(2026, 10, 1), holderIDs: [a, b])
        c.split = [SplitShare(personID: a, percent: 70), SplitShare(personID: b, percent: 30)]
        d.contracts = [c]
        let csv = CSV.export(d, today: Day(2026, 10, 5))
        XCTAssertTrue(csv.contains("Aufteilung"))
        XCTAssertTrue(csv.contains("Sinan:70 | Lara:30"))
        XCTAssertEqual(CSV.parseSplit("Sinan:70 | lara: 30 %", holders: ["Sinan", "Lara"]), ["Sinan": 70, "Lara": 30])
        XCTAssertEqual(CSV.parseSplit("Sinan:70", holders: ["Sinan", "Lara"]), [:])
        XCTAssertEqual(CSV.parseSplit("Sinan:70 | Lara:40", holders: ["Sinan", "Lara"]), [:])
    }

    func testPaidSoFarAndNextDebit() {
        var d = AppData.initial()
        d.contracts = [
            Contract(label: "Netflix", amount: 20, cycle: 1, due: Day(2026, 10, 15), start: Day(2026, 1, 15)),
            Contract(label: "Miete", amount: 1500, cycle: 1, due: Day(2026, 10, 1)),
        ]
        let calc = Calc(data: d, today: Day(2026, 10, 5))
        let p = calc.paidSoFar(d.contracts[0])
        XCTAssertEqual(p?.sum, 180)   // Jan–Sep
        XCTAssertEqual(p?.sinceYear, 2026)
        XCTAssertNil(calc.paidSoFar(d.contracts[1]))
        let n = calc.nextDebit()
        XCTAssertEqual(n?.contractID, d.contracts[0].id)
        XCTAssertEqual(n?.when, "am 15.10.26")
        XCTAssertEqual(n?.value, 20)
    }

    func testPriceIncreasesAndSpecialCancelHint() {
        var d = AppData.initial()
        var c = Contract(label: "Netflix", amount: 15, cycle: 1, due: Day(2026, 10, 15), start: Day(2025, 1, 15))
        c.prices = [PriceChange(from: Day(2026, 9, 1), amount: 18), PriceChange(from: Day(2025, 3, 1), amount: 16)]
        var old = Contract(label: "Alt", amount: 10, cycle: 12, due: Day(2027, 1, 1), start: Day(2024, 1, 1))
        old.prices = [PriceChange(from: Day(2025, 1, 1), amount: 12)]
        d.contracts = [c, old]
        let calc = Calc(data: d, today: Day(2026, 10, 5))
        let inc = calc.priceIncreases(filter: Calc.CostFilter())
        XCTAssertEqual(inc.count, 1)
        XCTAssertEqual(inc[0].step, 2)
        XCTAssertEqual(inc[0].yearly, 24)
        XCTAssertTrue(calc.specialCancelHint(c))          // 01.09. liegt < 60 Tage zurück
        XCTAssertFalse(calc.specialCancelHint(old))
        var fut = c
        fut.prices = [PriceChange(from: Day(2026, 11, 1), amount: 20)]
        XCTAssertTrue(calc.specialCancelHint(fut))        // angekündigt
    }

    func testFairShare() {
        var (d, a, b) = twoPersons()
        var shared = Contract(label: "Miete", amount: 1000, cycle: 1, due: Day(2026, 10, 1), holderIDs: [a, b])
        shared.split = [SplitShare(personID: a, percent: 70), SplitShare(personID: b, percent: 30)]
        d.contracts = [shared, Contract(label: "Handy", amount: 100, cycle: 1, due: Day(2026, 10, 1), holderIDs: [b])]
        d.incomes = [Income(name: "Lohn", amount: 6000, cycle: 1, due: Day(2026, 10, 25), holderID: a),
                     Income(name: "Lohn", amount: 4000, cycle: 1, due: Day(2026, 10, 25), holderID: b)]
        let calc = Calc(data: d, today: Day(2026, 10, 5))
        let rows = calc.fairShare()
        XCTAssertEqual(rows?.count, 2)
        XCTAssertEqual(rows?[0].fixedPercent, 64)   // 700 / 1100
        XCTAssertEqual(rows?[0].incomePercent, 60)
        XCTAssertEqual(rows?[1].subline, "Fixkosten 36\u{00A0}% · Einnahmen 40\u{00A0}%")
        // ohne gemeinsamen Vertrag nichts
        d.contracts[0].holderIDs = [a]
        XCTAssertNil(Calc(data: d, today: Day(2026, 10, 5)).fairShare())
    }

    func testReviewFlow() {
        var d = AppData.initial()
        d.contracts = [Contract(label: "Netflix", amount: 20, cycle: 1, due: Day(2026, 10, 15), start: Day(2026, 1, 15), cancelTerm: .monthEnd),
                       Contract(label: "Miete", amount: 1500, cycle: 1, due: Day(2026, 10, 1), start: Day(2026, 1, 1))]
        let today = Day(2026, 10, 5)
        XCTAssertEqual(Calc(data: d, today: today).reviewList().map { $0.label }, ["Miete", "Netflix"])
        let id = d.contracts[0].id
        d.setReview(id, .kill, today: today)
        var calc = Calc(data: d, today: today)
        XCTAssertTrue(calc.reviewKill(d.contracts[0]))
        XCTAssertEqual(calc.freshReview(d.contracts[0]), .kill)
        let ov = calc.deadlineOverview()
        XCTAssertEqual(ov.marked.map { $0.contractID }, [id])
        XCTAssertEqual(ov.markedMonthly, 20)
        XCTAssertEqual(ov.marked[0].cancelTitle, "Kündigen")
        // gleiche Antwort nochmals → zurück
        d.setReview(id, .kill, today: today)
        XCTAssertNil(d.contracts[0].review)
        // alt → unbeantwortet
        d.contracts[0].review = ContractReview(verdict: .keep, at: Day(2026, 1, 1))
        XCTAssertNil(Calc(data: d, today: today).freshReview(d.contracts[0]))
        // Kündigen löscht den Vermerk
        d.contracts[0].review = ContractReview(verdict: .kill, at: today)
        d.markCancelled(id, trial: false, today: today)
        XCTAssertNil(d.contracts[0].review)
        calc = Calc(data: d, today: today)
        XCTAssertTrue(calc.deadlineOverview().marked.isEmpty)
        d.markReviewed(today: today)
        XCTAssertEqual(d.settings.lastReview, today)
        XCTAssertNil(d.settings.reviewSnooze)
    }

    func testCostYearPreviousSplit() {
        var d = AppData.initial()
        var c = Contract(label: "Netflix", categoryID: d.categories[0].id, amount: 10, cycle: 1, due: Day(2026, 10, 15), start: Day(2025, 1, 15))
        c.prices = [PriceChange(from: Day(2026, 1, 1), amount: 20)]
        d.contracts = [c]
        let cy = Calc(data: d, today: Day(2026, 10, 5)).costYear(2026, filter: Calc.CostFilter())
        let k = Calc(data: d, today: Day(2026, 10, 5)).statKey(c, .category)
        XCTAssertEqual(cy.splitPrevYear[k], 120)
        let pt = cy.previousText(k)
        XCTAssertEqual(pt?.delta, "+120")
        XCTAssertEqual(pt?.trend, .up)
        XCTAssertEqual(pt?.suffix, "vs. 2025")
    }

    func testBudgetShareNegativeAndWithout() {
        let ch = BudgetShare.range(.ch)
        XCTAssertEqual(BudgetShare.level(-12, ch), .negative)
        XCTAssertEqual(BudgetShare.percentText(-12), "\u{2212}12\u{00A0}%")
        XCTAssertEqual(BudgetShare.headline(.negative).title, "Die Fixkosten übersteigen die Einnahmen.")
        XCTAssertTrue(BudgetShare.showsTips(.negative))
        XCTAssertEqual(BudgetShare.withoutPercent(free: -300, income: 5000, monthly: 800), 10)
        XCTAssertNil(BudgetShare.withoutPercent(free: 1, income: 0, monthly: 1))
    }

    func testCatalogCancelURL() {
        XCTAssertEqual(Catalog.entries.first { $0.name == "Netflix" }?.cancelURL, "netflix.com/cancelplan")
        XCTAssertEqual(Catalog.entries.first { $0.name == "CSS" }?.cancelURL, "")
    }

    func testContractCodableRoundTrip() throws {
        let (_, a, b) = twoPersons()
        var c = Contract(label: "Miete", amount: 1000, cycle: 1, due: Day(2026, 10, 1), holderIDs: [a, b])
        c.split = [SplitShare(personID: a, percent: 70), SplitShare(personID: b, percent: 30)]
        c.review = ContractReview(verdict: .kill, at: Day(2026, 10, 5))
        let data = try JSONEncoder().encode(c)
        let back = try JSONDecoder().decode(Contract.self, from: data)
        XCTAssertEqual(back.split, c.split)
        XCTAssertEqual(back.review, c.review)
        // alte Daten ohne die Felder
        let old = try JSONDecoder().decode(Contract.self, from: Data("{\"label\":\"X\"}".utf8))
        XCTAssertEqual(old.split, [])
        XCTAssertNil(old.review)
    }
}
