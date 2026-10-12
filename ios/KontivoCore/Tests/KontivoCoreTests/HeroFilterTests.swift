import XCTest
@testable import KontivoCore

/// Web v161 (bb0dbf1): Monatstotal auf «Verträge» folgt dem Filter (Kategorie, Vertragspartner, Person-Anteil).
final class HeroFilterTests: XCTestCase {
    func testHeroFollowsFilter() {
        let sinan = Person(name: "Sinan"), lara = Person(name: "Lara")
        var data = AppData.initial(homeCurrency: .CHF)
        data.persons = [sinan, lara]
        let wohnen = data.categories.first { $0.kind == .housing } ?? data.categories[0]
        let abos = data.categories.first { $0.id != wohnen.id }!
        data.contracts = [
            Contract(label: "Miete", categoryID: wohnen.id, amount: 2000, cycle: 1, start: Day(2024, 1, 1), holderIDs: [sinan.id, lara.id],
                     split: [SplitShare(personID: sinan.id, percent: 70), SplitShare(personID: lara.id, percent: 30)]),
            Contract(label: "Netflix", categoryID: abos.id, amount: 20, cycle: 1, start: Day(2024, 1, 1), holderIDs: [sinan.id]),
        ]
        let calc = Calc(data: data, today: Day(2026, 10, 12))

        let all = calc.hero()
        XCTAssertEqual(all.monthlyTotal, 2020, accuracy: 0.001)
        XCTAssertTrue(all.subtitle.hasSuffix("2 aktive Verträge"), all.subtitle)

        let cat = calc.hero(filter: Calc.CostFilter(category: wohnen.name))
        XCTAssertEqual(cat.monthlyTotal, 2000, accuracy: 0.001)
        XCTAssertTrue(cat.subtitle.hasSuffix(" · " + wohnen.name), cat.subtitle)

        let p = calc.hero(filter: Calc.CostFilter(person: lara.id))
        XCTAssertEqual(p.monthlyTotal, 600, accuracy: 0.001)
        XCTAssertTrue(p.subtitle.hasSuffix(" · Lara"), p.subtitle)
    }
}
