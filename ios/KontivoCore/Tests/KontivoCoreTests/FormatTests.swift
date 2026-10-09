import XCTest
@testable import KontivoCore

final class FormatTests: XCTestCase {
    /// Summen ohne Währung folgen der Hauptwährung (global, von `Calc.init` gesetzt) – hier fest CHF.
    override func setUp() {
        super.setUp()
        Format.homeCurrency = .CHF
    }

    func testMoney() {
        XCTAssertEqual(Format.money(1284.5), "1’284.50")
        XCTAssertEqual(Format.money(0), "0.00")
        XCTAssertEqual(Format.money(12), "12.00")
        XCTAssertEqual(Format.money(999.999), "1’000.00")
        XCTAssertEqual(Format.money(1234567.891), "1’234’567.89")
        XCTAssertEqual(Format.money(1.005), "1.01")
        XCTAssertEqual(Format.money(0.005), "0.01")
        XCTAssertEqual(Format.money(0.004), "0.00")
        XCTAssertEqual(Format.money(.nan), "0.00")
        XCTAssertEqual(Format.money(1e-7), "0.00")
        XCTAssertEqual(Format.money(123456789012.5), "123’456’789’012.50")
    }

    func testNegative() {
        XCTAssertEqual(Format.money(-5), "\u{2212}5.00")
        XCTAssertEqual(Format.money(-1284.5), "\u{2212}1’284.50")
        XCTAssertEqual(Format.money(-0.001), "0.00")
        XCTAssertEqual(Format.moneySigned(3, plus: true), "+3.00")
        XCTAssertEqual(Format.moneySigned(-3), "\u{2212}3.00")
        XCTAssertEqual(Format.moneySigned(0, plus: true), "0.00")
        XCTAssertEqual(Format.money0(-1234.4), "\u{2212}1’234")
    }

    func testMoney0AndNumber() {
        XCTAssertEqual(Format.money0(1234.5), "1’235")
        XCTAssertEqual(Format.money0(999.4), "999")
        XCTAssertEqual(Format.money0(0.4), "0")
        XCTAssertEqual(Format.number(4.25, maxFractionDigits: 1), "4.3")
        XCTAssertEqual(Format.number(5.0, maxFractionDigits: 1), "5")
        XCTAssertEqual(Format.number(5.04, maxFractionDigits: 1), "5")
        XCTAssertEqual(Format.number(12345.67, maxFractionDigits: 1), "12’345.7")
    }

    func testFixed2() {
        XCTAssertEqual(Format.fixed2(12.5), "12.50")
        XCTAssertEqual(Format.fixed2(0.125), "0.13")
        XCTAssertEqual(Format.fixed2(-0.125), "-0.13")
        XCTAssertEqual(Format.fixed2(1.005), "1.00")
        XCTAssertEqual(Format.fixed2(59.9 / 3), "19.97")
        XCTAssertEqual(Format.fixed2(0), "0.00")
        XCTAssertEqual(Format.fixed2(1234.5), "1234.50")
        // K-1: toFixed(1) rundet Gleichstände auf
        XCTAssertEqual(Format.fixed1(2.25), "2.3")
        XCTAssertEqual(Format.fixed1(0.75), "0.8")
        XCTAssertEqual(Format.fixed1(0.15), "0.1")
        XCTAssertEqual(Format.fixed1(12.34), "12.3")
        XCTAssertEqual(Format.fixed1(0), "0.0")
    }

    func testRounding() {
        XCTAssertEqual(Format.jsRound(2.5), 3)
        XCTAssertEqual(Format.jsRound(-2.5), -2)
        XCTAssertEqual(Format.jsRound(-2.6), -3)
        XCTAssertEqual(Format.round2(17.766), 17.77)
        XCTAssertEqual(Format.round2(19.9666), 19.97)
    }

    func testDates() {
        XCTAssertEqual(Format.fmtD(Day(2026, 10, 3)), "3. Oktober 2026")
        XCTAssertEqual(Format.fmtD(Day(2026, 3, 1)), "1. März 2026")
        XCTAssertEqual(Format.fmtD(nil), "—")
        XCTAssertEqual(Format.fmtD(iso: "2026-12-31"), "31. Dezember 2026")
        XCTAssertEqual(Format.fmtD(iso: ""), "—")
        XCTAssertEqual(Format.fmtShort(Day(2026, 10, 3)), "03.10.26")
        XCTAssertEqual(Format.fmtShort(nil), "—")
        XCTAssertEqual(Format.ddmm(Day(2026, 11, 30), currentYear: 2026), "30.11.")
        XCTAssertEqual(Format.ddmm(Day(2027, 1, 5), currentYear: 2026), "05.01.27")
        XCTAssertEqual(Format.monthYear(Day(2026, 10, 3)), "Oktober 2026")
        XCTAssertEqual(Format.shortNumericDate(Day(2026, 10, 3)), "3.10.2026")
    }

    func testPeriods() {
        XCTAssertEqual(Format.inDays(0), "heute")
        XCTAssertEqual(Format.inDays(1), "morgen")
        XCTAssertEqual(Format.inDays(5), "in 5 Tagen")
        XCTAssertEqual(Format.inDays(60), "in 60 Tagen")
        XCTAssertEqual(Format.inDays(61), "in 2 Monaten")
        XCTAssertEqual(Format.inDays(400), "in 13 Monaten")
        XCTAssertEqual(Format.inDays(800), "in 2 Jahren")
        XCTAssertEqual(Format.humanDays(0), "heute")
        XCTAssertEqual(Format.humanDays(1), "1 Tag")
        XCTAssertEqual(Format.humanDays(30), "30 Tage")
        XCTAssertEqual(Format.humanDays(91), "3 Monate")
        XCTAssertEqual(Format.humanDays(1000), "3 Jahre")
    }

    func testTexts() {
        XCTAssertEqual(Format.noticeText(notice: 3, unit: .months), "3 Monate")
        XCTAssertEqual(Format.noticeText(notice: 1, unit: .months), "1 Monat")
        XCTAssertEqual(Format.noticeText(notice: 1, unit: .weeks), "1 Woche")
        XCTAssertEqual(Format.noticeText(notice: 2, unit: .weeks), "2 Wochen")
        XCTAssertEqual(Format.noticeText(notice: 60, unit: .days), "60 Tage")
        XCTAssertEqual(Format.noticeText(notice: 15, unit: .dayOfMonth), "bis zum 15. des Monats")
        XCTAssertEqual(Format.noticeText(notice: 0, unit: .months), "")
        XCTAssertEqual(Format.cycleText(3), "quartalsweise")
        XCTAssertNil(Format.cycleText(5))
        XCTAssertEqual(Format.incomeCycleTexts[0], "einmalig")
        XCTAssertEqual(Format.termText(.contractYear), "Ende Vertragsjahr")
        XCTAssertEqual(Format.termText(.anytime), "jederzeit")
        XCTAssertEqual(Format.shareText(0.5), "Anteil 50 %")
        XCTAssertEqual(Format.shareText(1.0 / 3.0), "Anteil 33 %")
        XCTAssertEqual(Format.count(1, "Vertrag", "Verträge"), "1 Vertrag")
        XCTAssertEqual(Format.count(3, "Vertrag", "Verträge"), "3 Verträge")
        XCTAssertEqual(Format.normUrl("sunrise.ch"), "https://sunrise.ch")
        XCTAssertEqual(Format.normUrl(" http://a.ch "), "http://a.ch")
        XCTAssertEqual(Format.normUrl(""), "")
        XCTAssertEqual(Format.domain(of: "www.swisscom.ch/kuendigen"), "swisscom.ch")
        // F-1: klein und Punycode wie JS `URL.hostname`
        XCTAssertEqual(Format.domain(of: "https://WWW.Swisscom.CH:443/x?y#z"), "swisscom.ch")
        XCTAssertEqual(Format.domain(of: "müller.ch"), "xn--mller-kva.ch")
        XCTAssertEqual(Format.domain(of: "https://user@shop.example.com"), "shop.example.com")
        XCTAssertEqual(Format.domain(of: "foo bar.ch"), "")
        XCTAssertEqual(Format.domain(of: ""), "")
        XCTAssertEqual(Format.collapseSpaces("  Anna   Muster "), "Anna Muster")
        XCTAssertEqual(Format.firstName("Anna Muster"), "Anna")
        XCTAssertTrue(Format.lessDE("Ärzte", "Bank"))
        XCTAssertTrue(Format.lessDE("apple", "Bank"))
    }

    func testPartnerKeys() {
        XCTAssertEqual(Partners.lnorm("Zürich Versicherung & Co."), "zurich versicherung und co")
        XCTAssertEqual(Partners.lnorm("Straße"), "strasse")
        XCTAssertEqual(Partners.ltok("Swisscom (Schweiz) AG"), ["swisscom"])
        XCTAssertEqual(Partners.pkey("Swisscom (Schweiz) AG"), "swisscom")
        XCTAssertEqual(Partners.pkey("swisscom"), "swisscom")
        XCTAssertEqual(Partners.pkey("AG"), "ag")
        XCTAssertTrue(Partners.lusable("Helsana"))
        XCTAssertFalse(Partners.lusable("Versicherung AG"))
        XCTAssertTrue(Partners.nameEq(Partners.ltok("Helsana"), "Helsana Versicherungen AG"))
        XCTAssertFalse(Partners.nameEq(Partners.ltok("Helsana"), "Helsana Arena"))
        XCTAssertEqual(Partners.regDom("www.shop.example.ch"), "example.ch")
        XCTAssertEqual(Partners.regDom("bt.co.uk"), "bt.co.uk")
        XCTAssertEqual(Partners.regDom("www.turkcell.com.tr"), "turkcell.com.tr")
        XCTAssertEqual(Partners.regDom("shop.bbc.co.uk"), "bbc.co.uk")
        XCTAssertEqual(Partners.regDom("www.sunrise.ch"), "sunrise.ch")
        XCTAssertEqual(Partners.regDom("co.uk"), "co.uk")
    }
}
