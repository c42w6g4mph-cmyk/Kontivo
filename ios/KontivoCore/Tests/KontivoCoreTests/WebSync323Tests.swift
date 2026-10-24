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
