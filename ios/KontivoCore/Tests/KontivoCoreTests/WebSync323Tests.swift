import XCTest
@testable import KontivoCore

/// Nachzug Web v226–v323: Regeln, die nicht schon über die Prüffälle aus der Web-App (golden_*.json, BankFixtures) abgedeckt sind.
final class WebSync323Tests: XCTestCase {
    // MARK: Kündigungsschreiben nach Land (Web v229)

    func testLetterCountry() {
        XCTAssertEqual(Letter.countryOf(line: "Deutschland"), "DE")
        XCTAssertEqual(Letter.countryOf(line: " suisse "), "CH")
        XCTAssertEqual(Letter.countryOf(line: "Niederlande"), "")
        XCTAssertEqual(Letter.countryOf(lines: ["Muster GmbH", "Hauptstr. 1", "78462 Konstanz"]), "DE")
        XCTAssertEqual(Letter.countryOf(lines: ["Muster AG", "Bahnhofstrasse 1", "8001 Zürich"]), "CH")
        XCTAssertEqual(Letter.countryOf(lines: ["Muster BV", "Keizersgracht 1", "1015 CJ Amsterdam", "Niederlande"]), "X")
        XCTAssertEqual(Letter.countryOf(lines: ["Muster GmbH", "D-80331 München"]), "DE")
        XCTAssertEqual(Letter.countryOf(lines: ["Muster AG", "CH-8001 Zürich"]), "CH")
        XCTAssertEqual(Letter.countryOf(lines: []), "")
        XCTAssertEqual(Letter.senderCountry(SenderAddress(zip: "78462"), home: .CHF), "DE")
        XCTAssertEqual(Letter.senderCountry(SenderAddress(zip: "8280"), home: .EUR), "CH")
        XCTAssertEqual(Letter.senderCountry(SenderAddress(country: "Österreich"), home: .CHF), "X")
        XCTAssertEqual(Letter.senderCountry(SenderAddress(), home: .EUR), "DE")
        XCTAssertEqual(Letter.dateLine(country: "CH", city: "Kreuzlingen", today: Day(2026, 10, 3)), "Kreuzlingen, 3. Oktober 2026")
        XCTAssertEqual(Letter.dateLine(country: "DE", city: "Konstanz", today: Day(2026, 10, 3)), "Konstanz, 03.10.2026")
        XCTAssertEqual(Letter.dateLine(country: "X", city: "", today: Day(2026, 3, 21)), "21.03.2026")
    }
}

extension WebSync323Tests {
    // MARK: «Gekündigt am» (Web v249)

    /// Vertragsende ab dem Kündigungsdatum: Monatsvertrag mit 1 Monat Frist, gekündigt am 25.09. → Ende 31.10.; am 05.10. → 30.11.
    func testEndAsOfAndCancelledOn() throws {
        var d = AppData.initial()
        var c = Contract(label: "Handy", amount: 30, cycle: 1, due: Day(2026, 10, 1), notice: 1, noticeUnit: .months, cancelTerm: .monthEnd)
        c.start = Day(2025, 1, 1)
        d.contracts.append(c)
        XCTAssertEqual(Calc.endAsOf(c, cancelledOn: Day(2026, 9, 25), trial: false, data: d),
                       Calc(data: d, today: Day(2026, 9, 25)).termEnd(c))
        XCTAssertNotEqual(Calc.endAsOf(c, cancelledOn: Day(2026, 9, 25), trial: false, data: d),
                          Calc.endAsOf(c, cancelledOn: Day(2026, 10, 25), trial: false, data: d))
        var t = c
        t.trial = Day(2026, 11, 1)
        XCTAssertEqual(Calc.endAsOf(t, cancelledOn: Day(2026, 9, 25), trial: true, data: d), Day(2026, 10, 31))
        let r = try XCTUnwrap(d.markCancelled(c.id, trial: false, per: Day(2026, 10, 31), on: Day(2026, 9, 25), today: Day(2026, 10, 8)))
        XCTAssertEqual(r.cancelPer, Day(2026, 10, 31))
        XCTAssertEqual(d.contract(c.id)?.cancelledOn, Day(2026, 9, 25))
        XCTAssertEqual(d.contract(c.id)?.cancelPer, Day(2026, 10, 31))
    }
}
