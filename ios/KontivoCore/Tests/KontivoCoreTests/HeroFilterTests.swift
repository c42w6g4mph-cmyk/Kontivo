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
        XCTAssertEqual(all.subtitle, "24’240 CHF im Jahr")   // Web v164: ohne Aufzählung
        XCTAssertEqual(all.label, "Fixkosten pro Monat")

        let cat = calc.hero(filter: Calc.CostFilter(category: wohnen.name))
        XCTAssertEqual(cat.monthlyTotal, 2000, accuracy: 0.001)
        XCTAssertEqual(cat.subtitle, "24’000 CHF im Jahr – " + wohnen.name)

        let p = calc.hero(filter: Calc.CostFilter(person: lara.id))
        XCTAssertEqual(p.monthlyTotal, 600, accuracy: 0.001)
        XCTAssertEqual(p.subtitle, "7’200 CHF im Jahr – Lara")
    }

    /// Web v189: Summe folgt dem Status-Filter (pausiert / noch nicht aktiv) mit passender Beschriftung.
    func testHeroFollowsStatus() {
        var data = AppData.initial(homeCurrency: .CHF)
        let me = data.persons[0].id
        var paused = Contract(label: "Fitness", amount: 60, cycle: 1, start: Day(2024, 1, 1), holderIDs: [me])
        paused.pauses = [Pause(from: Day(2026, 9, 1), until: Day(2027, 1, 31))]
        data.contracts = [
            Contract(label: "Miete", amount: 2000, cycle: 1, start: Day(2024, 1, 1), holderIDs: [me]),
            paused,
            Contract(label: "Zeitung", amount: 240, cycle: 12, start: Day(2027, 1, 1), holderIDs: [me]),
        ]
        let calc = Calc(data: data, today: Day(2026, 10, 12))
        let a = calc.hero()
        XCTAssertEqual(a.monthlyTotal, 2000, accuracy: 1e-9)
        XCTAssertEqual([a.activeCount, a.pausedCount, a.futureCount], [1, 1, 1])
        XCTAssertNil(a.status)
        let p = calc.hero(status: .paused)
        XCTAssertEqual(p.monthlyTotal, 60, accuracy: 1e-9)
        XCTAssertEqual(p.label, "Pausiert, pro Monat")
        XCTAssertEqual(p.subtitle, "Zählt nicht zu deinen Fixkosten, solange pausiert")
        let f = calc.hero(status: .future)
        XCTAssertEqual(f.monthlyTotal, 20, accuracy: 1e-9)
        XCTAssertEqual(f.label, "Noch nicht aktiv, pro Monat")
        XCTAssertEqual(f.subtitle, "Zählt ab Vertragsbeginn zu deinen Fixkosten")
        let act = calc.hero(status: .active)
        XCTAssertEqual(act.status, .active)
        XCTAssertEqual(act.subtitle, "24’000 CHF im Jahr")
        // Zähler 0 → Filter wirkt nicht (Web setzt heroF zurück)
        var none = data
        none.contracts.remove(at: 1)
        let n = Calc(data: none, today: Day(2026, 10, 12)).hero(status: .paused)
        XCTAssertNil(n.status)
        XCTAssertEqual(n.label, "Fixkosten pro Monat")
        XCTAssertEqual(n.monthlyTotal, 2000, accuracy: 1e-9)
    }
}
