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

    // MARK: v202/v210/v214–v218 Formular

    func testFormTexts() {
        XCTAssertEqual(ContractFormRules.mandatoryTitle, "Pflichtvertrag")
        XCTAssertEqual(ContractFormRules.mandatorySubtitle, "Kündigen nur mit neuem Anbieter")
        XCTAssertTrue(ContractFormRules.mandatoryInfo.hasSuffix("\n\nBeispiele: Krankenkasse, Autohaftpflicht."))
        XCTAssertEqual(ContractFormRules.placeholder, "hinzufügen")
        XCTAssertEqual(ContractFormRules.missingEndText, "Vertragsende fehlt")
        XCTAssertEqual(Calc.priceIncreaseToast, "Preiserhöhung vorgemerkt – Hinweis zur Kündigung steht im Detail.")
    }

    func testMissingFields() {
        typealias R = ContractFormRules
        XCTAssertEqual(R.checkContract(partner: "", label: " ", hasCategory: true, amountText: "10", noticeValid: true, mode: .open, end: nil, trial: nil),
                       R.Missing(.label, "Bezeichnung fehlt"))
        XCTAssertEqual(R.checkContract(partner: "CSS", label: "", hasCategory: false, amountText: "", noticeValid: true, mode: .open, end: nil, trial: nil)?.message,
                       "Bitte eine Kategorie wählen")
        XCTAssertEqual(R.checkContract(partner: "CSS", label: "", hasCategory: true, amountText: "", noticeValid: true, mode: .open, end: nil, trial: nil),
                       R.Missing(.amount, "Betrag fehlt"))
        XCTAssertEqual(R.checkContract(partner: "CSS", label: "", hasCategory: true, amountText: "abc", noticeValid: true, mode: .open, end: nil, trial: nil),
                       R.Missing(.amount, "Betrag prüfen"))
        XCTAssertEqual(R.checkContract(partner: "CSS", label: "", hasCategory: true, amountText: "10", noticeValid: false, mode: .open, end: nil, trial: nil)?.field, .notice)
        XCTAssertEqual(R.checkContract(partner: "CSS", label: "", hasCategory: true, amountText: "10", noticeValid: true, mode: .fixed, end: nil, trial: nil),
                       R.Missing(.end, "Vertragsende fehlt"))
        XCTAssertEqual(R.checkContract(partner: "CSS", label: "", hasCategory: true, amountText: "10", noticeValid: true, mode: .trial, end: nil, trial: nil)?.message,
                       "Wie lange läuft das Probeabo?")
        XCTAssertNil(R.checkContract(partner: "CSS", label: "", hasCategory: true, amountText: "0", noticeValid: true, mode: .open, end: nil, trial: nil))
        XCTAssertEqual(R.checkPriceChange(from: nil, start: nil, amountText: "")?.message, "Datum für die Preisänderung fehlt")
        XCTAssertEqual(R.checkPriceChange(from: Day(2026, 1, 1), start: Day(2026, 1, 1), amountText: "")?.message, "Datum muss nach dem Vertragsbeginn liegen")
        XCTAssertEqual(R.checkPriceChange(from: Day(2026, 2, 1), start: Day(2026, 1, 1), amountText: " ")?.message, "Neuer Betrag fehlt")
        XCTAssertEqual(R.checkPriceChange(from: Day(2026, 2, 1), start: nil, amountText: "x")?.message, "Neuen Betrag prüfen")
        XCTAssertEqual(R.checkExtra(date: nil, amountText: "5")?.message, "Datum der Sonderzahlung fehlt")
        XCTAssertEqual(R.checkExtra(date: Day(2026, 2, 1), amountText: "")?.message, "Betrag fehlt")
        XCTAssertEqual(R.checkExtra(date: Day(2026, 2, 1), amountText: "0")?.message, "Betrag prüfen")
        XCTAssertEqual(R.checkIncome(name: "", label: "", amountText: "1")?.field, .incomeLabel)
        XCTAssertEqual(R.checkIncomePrice(from: nil, amountText: "1")?.message, "Datum fehlt")
    }

    func testSwissPowerAndLeasing() {
        typealias R = ContractFormRules
        XCTAssertTrue(R.isSwissPower(currency: .CHF, categoryKind: .energy, label: "Strom", partner: "EKZ"))
        XCTAssertFalse(R.isSwissPower(currency: .EUR, categoryKind: .energy, label: "Strom", partner: "E.ON"))
        XCTAssertFalse(R.isSwissPower(currency: .CHF, categoryKind: .energy, label: "", partner: "Energie Wasser Bern"))
        XCTAssertFalse(R.isSwissPower(currency: .CHF, categoryKind: .energy, label: "Fernwärme", partner: ""))
        XCTAssertFalse(R.isSwissPower(currency: .CHF, categoryKind: .housing, label: "Strom", partner: ""))
        let ewb = CatalogEntry(name: "Energie Wasser Bern", country: "CH", category: "Energie & Wasser", label: "Strom", web: "ewb.ch", notice: 0,
                               noticeUnit: .months, cancelTerm: .anytime, cancelChannel: nil, mandatory: false, hint: "")
        XCTAssertTrue(ewb.isSwissPower)
        XCTAssertTrue(R.isSwissPower(currency: .CHF, categoryKind: .energy, label: "", partner: "Energie Wasser Bern", catalogEntry: ewb))
        XCTAssertEqual(R.swissPowerStep(isNew: true, kindTouched: false, hasCategory: true, isSwissPower: true, appliedBefore: false), .setNotCancellable)
        XCTAssertEqual(R.swissPowerStep(isNew: true, kindTouched: false, hasCategory: true, isSwissPower: false, appliedBefore: true), .revert)
        XCTAssertEqual(R.swissPowerStep(isNew: false, kindTouched: false, hasCategory: true, isSwissPower: true, appliedBefore: false), .keep)
        XCTAssertEqual(R.swissPowerStep(isNew: true, kindTouched: true, hasCategory: true, isSwissPower: true, appliedBefore: false), .keep)
        var leasing = ewb
        leasing.label = "Auto-Leasing"
        XCTAssertTrue(leasing.isLeasing)
        XCTAssertFalse(ewb.isLeasing)
    }
}
