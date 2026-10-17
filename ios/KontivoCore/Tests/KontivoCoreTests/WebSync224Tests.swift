import XCTest
@testable import KontivoCore

/// Nachzug der Web-Änderungen v162–v224 im Kern (Bereich core). Erwartungswerte aus index.html v224 (main d8933a6).
final class WebSync224Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        Format.homeCurrency = .CHF
    }

    override func tearDown() {
        Format.homeCurrency = .CHF
        super.tearDown()
    }

    // MARK: v162 Wechselkurs

    func testRatePolicy() {
        let today = Day(2026, 10, 12)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var s = Settings(rates: ["EUR": 0.94, "USD": 0.8], rateDate: Day(2026, 10, 9), rateChecked: today)
        // Stand nicht von heute, noch nie mit Zeitpunkt geprüft → laden (vorher: rateChecked == heute → nicht mehr)
        XCTAssertTrue(RatePolicy.needsFetch(s, today: today, now: now))
        RatePolicy.markChecked(&s, today: today, now: now)
        XCTAssertEqual(s.rateCheckedAt, now)
        XCTAssertFalse(RatePolicy.needsFetch(s, today: today, now: now.addingTimeInterval(2 * 3600)))
        XCTAssertTrue(RatePolicy.needsFetch(s, today: today, now: now.addingTimeInterval(3 * 3600)))
        // Tageskurs vorhanden → nicht mehr prüfen
        s.rateDate = today
        XCTAssertFalse(RatePolicy.needsFetch(s, today: today, now: now.addingTimeInterval(10 * 3600)))
        // USD fehlt → immer laden
        s.rates = ["EUR": 0.94]
        XCTAssertTrue(RatePolicy.needsFetch(s, today: today, now: now))
    }

    func testRateCheckedAtRoundTrip() throws {
        let json = #"{"app":"vertraege","settings":{"home":"CHF","rates":{"EUR":0.94,"USD":0.8},"rateDate":"2026-10-12","rateChecked":"2026-10-12","rateCheckedAt":1800000000000},"contracts":{"a":{"label":"Test","amount":10,"cur":"CHF","cycle":1}},"incomes":{}}"#
        let r = try WebImport.importBackup(Data(json.utf8), today: Day(2026, 10, 12))
        XCTAssertEqual(r.data.settings.rateCheckedAt, Date(timeIntervalSince1970: 1_800_000_000))
        // natives Format (Codable) behält den Zeitpunkt
        let enc = try KontivoJSON.makeEncoder().encode(r.data)
        let back = try KontivoJSON.makeDecoder().decode(AppData.self, from: enc)
        XCTAssertEqual(back.settings.rateCheckedAt, r.data.settings.rateCheckedAt)
    }
}
