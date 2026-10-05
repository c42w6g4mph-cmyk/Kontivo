import XCTest
@testable import KontivoCore

/// Einordnung «% der Einnahmen» (Web FQ/fqState/fqTips)
final class BudgetShareTests: XCTestCase {
    func testRangesByHomeCurrency() {
        XCTAssertEqual(BudgetShare.range(BudgetShare.land(.CHF)).lo, 35)
        XCTAssertEqual(BudgetShare.range(BudgetShare.land(.CHF)).hi, 50)
        XCTAssertEqual(BudgetShare.range(BudgetShare.land(.EUR)).lo, 50)
        XCTAssertEqual(BudgetShare.range(BudgetShare.land(.USD)).hi, 65)
    }

    func testLevels() {
        let ch = BudgetShare.range(.ch)
        XCTAssertEqual(BudgetShare.level(34, ch), .low)
        XCTAssertEqual(BudgetShare.level(35, ch), .edge)
        XCTAssertEqual(BudgetShare.level(39, ch), .edge)
        XCTAssertEqual(BudgetShare.level(40, ch), .mid)
        XCTAssertEqual(BudgetShare.level(50, ch), .mid)
        XCTAssertEqual(BudgetShare.level(51, ch), .high)
    }

    func testAverageShownFromThreePoints() {
        XCTAssertFalse(BudgetShare.showAverage(month: 50, average: 52))
        XCTAssertTrue(BudgetShare.showAverage(month: 50, average: 53))
        XCTAssertFalse(BudgetShare.showAverage(month: 50, average: nil))
    }

    func testTipsTopWithoutTaxesAndAbos() {
        var d = AppData.initial()
        let tax = d.categories.first { $0.kind == .taxes }?.id
        let media = d.categories.first { $0.kind == .media }?.id
        d.contracts = [
            Contract(label: "Miete", amount: 2000, cycle: 1, due: Day(2026, 10, 1)),
            Contract(label: "Steuern", categoryID: tax, amount: 3000, cycle: 1, due: Day(2026, 10, 1)),
            Contract(label: "Netflix", categoryID: media, amount: 20, cycle: 1, due: Day(2026, 10, 1)),
            Contract(label: "Spotify", categoryID: media, amount: 12, cycle: 1, due: Day(2026, 10, 1)),
        ]
        let t = BudgetShare.tips(Calc(data: d, today: Day(2026, 10, 5)), person: nil)
        XCTAssertEqual(t.top.first?.monthly, 2000)
        XCTAssertFalse(t.top.contains { $0.monthly == 3000 })
        XCTAssertEqual(t.aboCount, 2)
        XCTAssertEqual(t.aboMonthly, 32, accuracy: 0.001)
    }
}
