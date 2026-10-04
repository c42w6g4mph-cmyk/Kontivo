import XCTest
@testable import KontivoCore

/// Bereich «Kosten» und «Budget» (ExtKostenBudget.swift)
final class KostenBudgetTests: XCTestCase {
    let today = Day(2026, 10, 3)

    private func data(incomeStart: Day?) -> AppData {
        var d = AppData.initial()
        d.contracts = [Contract(label: "Miete", amount: 1500, cycle: 1, due: Day(2026, 10, 1), start: Day(2024, 1, 1))]
        d.incomes = [Income(name: "Lohn", amount: 6000, cycle: 1, due: Day(2026, 10, 25), start: incomeStart)]
        return d
    }

    /// Web `bNoStart`: Einnahme ohne Beginn mit Termin im Monat sperrt den Vorjahresvergleich (Fund B-1).
    func testBudgetComparisonLockedByIncomeWithoutStart() {
        let calc = Calc(data: data(incomeStart: nil), today: today)
        XCTAssertNil(calc.kbBudgetComparison(year: 2026, month: 10, person: nil, free: 4500))
    }

    func testBudgetComparisonWithStart() throws {
        let calc = Calc(data: data(incomeStart: Day(2024, 1, 1)), today: today)
        let r = try XCTUnwrap(calc.kbBudgetComparison(year: 2026, month: 10, person: nil, free: 4500))
        XCTAssertEqual(r.text, "gleich wie Oktober 2025")
    }

    /// Einnahme eines anderen Empfängers (Anteil 0) sperrt nicht.
    func testBudgetComparisonIgnoresOtherRecipient() {
        var d = data(incomeStart: Day(2024, 1, 1))
        let other = Person(name: "Lara")
        d.persons.append(other)
        d.incomes.append(Income(name: "Lohn Lara", amount: 3000, cycle: 1, due: Day(2026, 10, 25), holderID: other.id))
        d.contracts[0].holderIDs = [d.persons[0].id]
        d.incomes[0].holderID = d.persons[0].id
        let calc = Calc(data: d, today: today)
        XCTAssertNotNil(calc.kbBudgetComparison(year: 2026, month: 10, person: d.persons[0].id, free: 4500))
        XCTAssertNil(calc.kbBudgetComparison(year: 2026, month: 10, person: other.id, free: 3000))
    }

    /// Einnahmen-Formular nutzt den gemeinsamen Zahlenleser (Web `parseNum`).
    func testParseAmountIsParseNum() {
        for s in ["6500", "6’500.50", "1.234,50", "1.234.5", "12abc", ""] {
            XCTAssertEqual(KBText.parseAmount(s), Format.parseNum(s), s)
        }
    }
}
