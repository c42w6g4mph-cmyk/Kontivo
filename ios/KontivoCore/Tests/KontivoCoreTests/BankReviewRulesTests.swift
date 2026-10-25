import XCTest
@testable import KontivoCore

/// Regeln der Vorschlagsliste im Kontoauszug-Import, die keine eigenen Web-Erwartungswerte haben (Web v327–v330:
/// `bkIncDev`, `bkIncPrices`, `agoTxt`, `fmtDot`). Plaketten und Zahlungsliste prüft BankParityTests gegen die Web-App.
final class BankReviewRulesTests: XCTestCase {
    func d(_ s: String) -> Day { Day(iso: s)! }

    func testDot() {
        XCTAssertEqual(BankImport.dot(Day(2026, 9, 5)), "05.09.2026")
    }

    func testIncomeDeviation() {
        let D = ["2026-07-25", "2026-08-25", "2026-09-25", "2026-10-23"].map(d)
        // letzte Gutschrift 8'221.90 statt 7'285.30 → nachfragen
        let v = BankImport.incomeDeviation(dates: D, amounts: [7285.30, 7285.30, 7285.30, 8221.90], amount: 7285.30, cycle: 1, edited: false)
        XCTAssertEqual(v?.date, d("2026-10-23"))
        XCTAssertEqual(v?.amount, 8221.90)
        XCTAssertEqual(v?.diff ?? 0, 936.60, accuracy: 0.001)
        // bis 2 % Abweichung, nicht monatlich, im Formular geändert: keine Rückfrage
        XCTAssertNil(BankImport.incomeDeviation(dates: D, amounts: [7285.30, 7285.30, 7285.30, 7400], amount: 7285.30, cycle: 1, edited: false))
        XCTAssertNil(BankImport.incomeDeviation(dates: D, amounts: [7285.30, 7285.30, 7285.30, 8221.90], amount: 7285.30, cycle: 12, edited: false))
        XCTAssertNil(BankImport.incomeDeviation(dates: D, amounts: [7285.30, 7285.30, 7285.30, 8221.90], amount: 7285.30, cycle: 1, edited: true))
    }

    func testIncomePricesNewLevel() {
        let D = ["2026-06-25", "2026-07-25", "2026-08-25", "2026-09-25", "2026-10-23"].map(d)
        let A = [7285.30, 7285.30, 7285.30, 7285.30, 8221.90]
        let s = BankIncomeSuggestion(key: "k", name: "Muster AG", label: "Lohn", category: "Lohn", currency: "CHF", amount: 7285.30, cycle: 1,
                                     due: d("2026-11-25"), count: 5, first: D[0], last: D[4], dates: D, amounts: A, lo: 7285.30, hi: 7285.30,
                                     varies: false, skipped: 1, raw: "Muster AG", text: "Lohn", once: false, confidence: .high)
        let v = BankImport.incomeDeviation(dates: D, amounts: A, amount: 7285.30, cycle: 1, edited: false)
        let r = BankImport.incomePrices(s, amount: 7285.30, newLevel: v)
        XCTAssertEqual(r.amount, 7285.30)
        XCTAssertEqual(r.prices, [PriceChange(from: d("2026-10-23"), amount: 8221.90)])
        // «Einmalig»: kein Verlauf
        XCTAssertEqual(BankImport.incomePrices(s, amount: 7285.30, newLevel: nil).prices, [])
    }

    func testAgoText() {
        let t = Day(2026, 10, 25)
        func ago(_ at: Day) -> String { BankImportInfo(from: Day(2025, 10, 1), to: Day(2026, 9, 30), at: at).agoText(today: t) }
        XCTAssertEqual(ago(t), "heute")
        XCTAssertEqual(ago(Day(2026, 10, 24)), "gestern")
        XCTAssertEqual(ago(Day(2026, 10, 20)), "vor 5 Tagen")
        XCTAssertEqual(ago(Day(2026, 10, 4)), "vor 3 Wochen")
        XCTAssertEqual(ago(Day(2026, 8, 20)), "vor 2 Monaten")
        XCTAssertEqual(ago(Day(2026, 7, 25)), "vor 3 Monaten")
        let i = BankImportInfo(from: Day(2025, 10, 1), to: Day(2026, 9, 30), at: Day(2026, 10, 20), files: 2)
        XCTAssertEqual(i.rangeText, "01.10.2025 – 30.09.2026")
        XCTAssertEqual(i.agoLine(today: t), "vor 5 Tagen eingelesen · 2 Dateien")
    }
}
