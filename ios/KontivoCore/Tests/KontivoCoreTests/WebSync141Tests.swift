import XCTest
@testable import KontivoCore

/// Nachzug der Web-Änderungen v89–v141 im Kern: Zahlenformat nach Währung, «1.234» = Tausender, Zahlungsregel,
/// «Behalten · läuft bis», Preisverlauf (Plakette, gratis), CSV-Rundlauf mit Zuständen, Begriffe «Person»/«Zahlungsrhythmus».
/// Erwartungswerte aus der Web-App (index.html v141, Stichtag 2026-10-03) gemessen.
final class WebSync141Tests: XCTestCase {
    override func setUp() {
        super.setUp()
        Format.homeCurrency = .CHF
    }

    override func tearDown() {
        Format.homeCurrency = .CHF
        super.tearDown()
    }

    // MARK: Zahlenformat

    func testMoneyByCurrency() {
        XCTAssertEqual(Format.money(1234.5, .CHF), "1’234.50")
        XCTAssertEqual(Format.money(1234.5, .EUR), "1.234,50")
        XCTAssertEqual(Format.money(-1234.5, .EUR), "\u{2212}1.234,50")
        XCTAssertEqual(Format.money(20, .EUR), "20,00")
        XCTAssertEqual(Format.money(1234567.891, .EUR), "1.234.567,89")
        XCTAssertEqual(Format.money0(1234.5, .EUR), "1.235")
        XCTAssertEqual(Format.moneySigned(3, plus: true, currency: .EUR), "+3,00")
        XCTAssertEqual(Format.number(12345.67, maxFractionDigits: 1, currency: .EUR), "12.345,7")
        // USD/GBP/TRY und Summen ohne Währung nach der Hauptwährung
        XCTAssertEqual(Format.money(1234.5, .USD), "1’234.50")
        XCTAssertEqual(Format.money(1234.5), "1’234.50")
        Format.homeCurrency = .EUR
        XCTAssertEqual(Format.money(1234.5, .USD), "1.234,50")
        XCTAssertEqual(Format.money(1234.5), "1.234,50")
        XCTAssertEqual(Format.money(1234.5, .CHF), "1’234.50")
        XCTAssertEqual(Format.pctText(0.5), "+0,5 %")
    }

    func testHomeCurrencyFollowsCalc() {
        var d = AppData.initial(homeCurrency: .EUR)
        d.contracts = []
        _ = Calc(data: d, today: Day(2026, 10, 3))
        XCTAssertEqual(Format.numberStyle(nil), .de)
        _ = Calc(data: AppData.initial(homeCurrency: .CHF), today: Day(2026, 10, 3))
        XCTAssertEqual(Format.numberStyle(nil), .ch)
    }

    func testPctText() {
        XCTAssertEqual(Format.pctText(10), "+10 %")
        XCTAssertEqual(Format.pctText(-9.0909), "\u{2212}9 %")
        XCTAssertEqual(Format.pctText(0), "±0 %")
        // 4.5 / 1000 * 100 = 0.44999… → «0.4» (wie toLocaleString)
        XCTAssertEqual(Format.pctText((1004.5 - 1000) / 1000 * 100), "+0.4 %")
    }

    func testAmountInputAndParse() {
        XCTAssertEqual(Format.amountInput(59.9, .CHF), "59.90")
        XCTAssertEqual(Format.amountInput(59.9, .EUR), "59,90")
        XCTAssertEqual(Format.amountInput(1234.5, .EUR), "1234,50")
        // Geld hat nie 3 Nachkommastellen: «1.234» und «1,234» sind Tausender
        XCTAssertEqual(Format.parseAmount("1.234"), 1234)
        XCTAssertEqual(Format.parseAmount("1,234"), 1234)
        XCTAssertEqual(Format.parseAmount("-1.234"), -1234)
        XCTAssertEqual(Format.parseAmount("12.345"), 12345)
        XCTAssertEqual(Format.parseAmount("0.234"), 0.234)
        XCTAssertEqual(Format.parseAmount("1234.567"), 1234.567)
        XCTAssertEqual(Format.parseAmount("1.234,50"), 1234.5)
        XCTAssertEqual(Format.parseAmount("59,90"), 59.9)
        XCTAssertEqual(Format.parseAmount("1’234.50"), 1234.5)
        XCTAssertNil(Format.parseAmount("12abc"))
        XCTAssertNil(Format.parseAmount(""))
        XCTAssertEqual(KBText.parseAmount("1.500"), 1500)
    }

    func testDecimalSplit() {
        XCTAssertEqual(Format.decimalSplit("1’234.50").whole, "1’234")
        XCTAssertEqual(Format.decimalSplit("1.234,50").whole, "1.234")
        XCTAssertEqual(Format.decimalSplit("1.234,50").fraction, ",50")
        XCTAssertEqual(Format.decimalSplit("12").fraction, "")
    }

    // MARK: Zahlungsregel

    func testPayRule() {
        XCTAssertEqual(Calc.payRule(cycle: 1, due: Day(2026, 10, 27)), "monatlich am 27.")
        XCTAssertEqual(Calc.payRule(cycle: 12, due: Day(2027, 1, 1)), "jährlich am 1. Januar")
        XCTAssertEqual(Calc.payRule(cycle: 1, due: Day(2026, 10, 31)), "monatlich am Monatsende")
        XCTAssertEqual(Calc.payRule(cycle: 3, due: Day(2026, 11, 15)), "quartalsweise am 15.")
        XCTAssertEqual(Calc.payRule(cycle: 24, due: Day(2027, 3, 31)), "alle 2 Jahre am 31. März")
        XCTAssertEqual(Calc.payRule(cycle: 0, due: Day(2026, 10, 5)), "monatlich am 5.")
        XCTAssertEqual(Calc.payRule(cycle: 1, due: nil), "")
    }

    // MARK: Fristen

    func testKeptEndItem() {
        var d = AppData.initial()
        d.contracts = [Contract(label: "Fitness", amount: 89, cycle: 1, due: Day(2026, 10, 15), end: Day(2026, 12, 31), notice: 1,
                                keptFor: Day(2026, 12, 31))]
        let calc = Calc(data: d, today: Day(2026, 10, 7))
        let it = calc.deadlineOverview().items
        XCTAssertEqual(it.count, 1)
        XCTAssertEqual(it.first?.kind, .keptEnd)
        XCTAssertEqual(it.first?.sub, "Behalten · läuft bis 31.12.")
        XCTAssertEqual(it.first?.chipLevel, .ok)
        XCTAssertEqual(it.first?.showActions, false)
        // mit Verlängerung: nächste Frist
        d.contracts[0].renewMonths = 12
        let k = Calc(data: d, today: Day(2026, 10, 7)).deadlineOverview().items.first
        XCTAssertEqual(k?.kind, .kept)
        XCTAssertEqual(k?.sub, "Behalten · nächste Frist 30.11.27")
    }

    // MARK: Preisverlauf (Web-Werte gemessen)

    func chart(_ c: Contract, home: Currency = .CHF) -> PriceChart? {
        var d = AppData.initial(homeCurrency: home)
        d.contracts = [c]
        return Calc(data: d, today: Day(2026, 10, 3)).priceChart(c)
    }

    func testPriceChartBadges() {
        let p1 = chart(Contract(amount: 50, cycle: 1, start: Day(2024, 1, 1), prices: [PriceChange(from: Day(2025, 1, 1), amount: 55)]))
        XCTAssertEqual(p1?.sinceText, "seit 01.01.24")
        XCTAssertEqual(p1?.badgeText, "↑ 10 % teurer")
        XCTAssertEqual(p1?.badgeTone, .up)
        XCTAssertEqual(p1?.accessibilityLabel, "Preisverlauf von 50.00 auf 55.00 CHF")
        XCTAssertEqual(p1?.points.filter { $0.labeled }.map { $0.valueText }, ["50.00", "55.00"])
        XCTAssertEqual(p1?.points.map { $0.dateText }, ["01.01.24", "01.01.25"])
        XCTAssertEqual(p1?.points.compactMap { $0.pctText }, ["+10 %"])
        XCTAssertEqual(p1?.nowIndex, 1)

        let p2 = chart(Contract(amount: 0, cycle: 12, prices: [PriceChange(from: Day(2026, 1, 1), amount: 9.9)]))
        XCTAssertEqual(p2?.sinceText, "seit Anfang")
        XCTAssertEqual(p2?.badgeText, "vorher gratis")
        XCTAssertEqual(p2?.points.map { $0.valueText }, ["gratis", "9.90"])
        XCTAssertEqual(p2?.points.map { $0.dateText }, ["Anfang", "01.01.26"])
        XCTAssertEqual(p2?.points.compactMap { $0.pctText }, [])

        let p3 = chart(Contract(amount: 20, cycle: 1, prices: [PriceChange(from: Day(2027, 1, 1), amount: 22)]))
        XCTAssertEqual(p3?.badgeText, "geplant ab 01.01.27")
        XCTAssertEqual(p3?.badgeTone, .neutral)
        XCTAssertEqual(p3?.nowIndex, 0)
        XCTAssertEqual(p3?.points.map { $0.isFuture }, [false, true])

        // Preise nach echtem Datum (Eingabe unsortiert), Plakette heute gegenüber Anfang
        let p4 = chart(Contract(amount: 20, cycle: 3, prices: [PriceChange(from: Day(2026, 1, 1), amount: 20), PriceChange(from: Day(2025, 1, 1), amount: 22)]))
        XCTAssertEqual(p4?.badgeText, "unverändert")
        XCTAssertEqual(p4?.points.map { $0.amount }, [20, 22, 20])
        XCTAssertEqual(p4?.points.filter { $0.labeled }.map { $0.valueText }, ["22.00", "20.00"])
        XCTAssertEqual(p4?.points.compactMap { $0.pctText }, ["+10 %", "\u{2212}9 %"])

        let p5 = chart(Contract(amount: 1000, currency: .EUR, cycle: 1, prices: [PriceChange(from: Day(2026, 5, 1), amount: 1004.5)]))
        XCTAssertEqual(p5?.badgeText, "↑ 0.4 % teurer")
        XCTAssertEqual(p5?.accessibilityLabel, "Preisverlauf von 1.000,00 auf 1.004,50 EUR")

        // nach einer Gratis-Phase keine Prozentangabe; heute gratis → «↓ 100 % günstiger»
        let p6 = chart(Contract(amount: 30, cycle: 1, start: Day(2020, 1, 1),
                                prices: [PriceChange(from: Day(2026, 10, 3), amount: 0), PriceChange(from: Day(2026, 12, 1), amount: 33)]))
        XCTAssertEqual(p6?.badgeText, "↓ 100 % günstiger")
        XCTAssertEqual(p6?.badgeTone, .down)
        XCTAssertEqual(p6?.points.map { $0.valueText }, ["30.00", "gratis", "33.00"])
        XCTAssertEqual(p6?.points.filter { $0.labeled }.map { $0.index }, [0, 2])
        XCTAssertNil(p6?.points[2].pctText)
        XCTAssertEqual(p6?.nowIndex, 1)

        XCTAssertNil(chart(Contract(amount: 20, cycle: 1)))
    }

    // MARK: CSV

    func testCSVExportStatesAndRawEnd() {
        var d = AppData.initial()
        let h = d.persons[0].id
        let p = Partner(name: "Fitnesspark")
        d.partners = [p]
        var c = Contract(label: "Abo", partnerID: p.id, amount: 89, cycle: 1, due: Day(2026, 10, 30), end: Day(2025, 11, 30), notice: 1,
                         renewMonths: 12, holderIDs: [h], trial: Day(2026, 10, 20), trialKept: Day(2026, 10, 20))
        c.noWatch = true
        c.cancelPer = Day(2026, 11, 30)
        c.cancelledOn = Day(2026, 9, 10)
        c.keptFor = Day(2026, 12, 31)
        c.pauses = [Pause(from: Day(2026, 9, 1), until: Day(2027, 1, 31))]
        d.contracts = [c, Contract(label: "Serafe", amount: 28, cycle: 3, noCancel: true, holderIDs: [h])]
        let rows = CSV.parse(CSV.export(d, today: Day(2026, 10, 3)))
        let head = rows[0]
        XCTAssertEqual(Array(head.suffix(9)), ["NichtKuendbar", "Probeabo", "GekuendigtPer", "GekuendigtAm", "NichtErinnern", "BehaltenBis",
                                              "PausiertSeit", "PausiertBis", "ProbeaboBehalten"])
        func v(_ r: [String], _ k: String) -> String { r[head.firstIndex(of: k)!] }
        XCTAssertEqual(v(rows[1], "Ende"), "2025-11-30")
        XCTAssertEqual(v(rows[1], "Probeabo"), "2026-10-20")
        XCTAssertEqual(v(rows[1], "GekuendigtPer"), "2026-11-30")
        XCTAssertEqual(v(rows[1], "GekuendigtAm"), "2026-09-10")
        XCTAssertEqual(v(rows[1], "NichtErinnern"), "ja")
        XCTAssertEqual(v(rows[1], "BehaltenBis"), "2026-12-31")
        XCTAssertEqual(v(rows[1], "PausiertSeit"), "2026-09-01")
        XCTAssertEqual(v(rows[1], "PausiertBis"), "2027-01-31")
        XCTAssertEqual(v(rows[1], "ProbeaboBehalten"), "ja")
        XCTAssertEqual(v(rows[2], "NichtKuendbar"), "ja")
        XCTAssertEqual(v(rows[2], "Probeabo"), "")
    }

    func testCSVRoundTrip() {
        var src = AppData.initial()
        let h = src.persons[0].id
        var c = Contract(label: "Abo", amount: 89, cycle: 1, due: Day(2026, 10, 30), notice: 1,
                         holderIDs: [h], cancelChannel: .email, trial: Day(2026, 10, 20), trialKept: Day(2026, 10, 20))
        c.noWatch = true
        c.cancelPer = Day(2026, 11, 30)
        c.cancelledOn = Day(2026, 9, 10)
        c.keptFor = Day(2026, 12, 31)
        c.pauses = [Pause(from: Day(2026, 9, 1), until: Day(2027, 1, 31))]
        let tax = Contract(label: "Serafe", amount: 28, cycle: 3, noCancel: true, holderIDs: [h])
        // abgelaufen, verlängert sich aber automatisch: bleibt aktiv; ohne Verlängerung ins Archiv
        let renew = Contract(label: "Zeitung", amount: 30, cycle: 12, due: Day(2027, 1, 1), end: Day(2025, 12, 31), notice: 3, renewMonths: 12, holderIDs: [h])
        let gone = Contract(label: "Kurs", amount: 50, cycle: 1, due: Day(2026, 1, 1), end: Day(2026, 3, 31), holderIDs: [h])
        src.contracts = [c, tax, renew, gone]
        let today = Day(2026, 10, 3)
        let csv = CSV.export(src, today: today)

        let pv = CSV.preview(csv: Data(csv.utf8), data: AppData.initial(), today: today)
        XCTAssertEqual(pv.items.count, 4)
        XCTAssertEqual(pv.archived, 1)
        let a = pv.items[0].contract
        XCTAssertNil(a.end)
        XCTAssertEqual(a.status, .active)
        XCTAssertEqual(a.cancelPer, Day(2026, 11, 30))
        XCTAssertEqual(a.cancelledOn, Day(2026, 9, 10))
        XCTAssertTrue(a.noWatch)
        XCTAssertEqual(a.keptFor, Day(2026, 12, 31))
        XCTAssertEqual(a.trial, Day(2026, 10, 20))
        XCTAssertEqual(a.trialKept, Day(2026, 10, 20))
        XCTAssertEqual(a.pauses, [Pause(from: Day(2026, 9, 1), until: Day(2027, 1, 31))])
        XCTAssertEqual(a.cancelChannel, .email)
        let t = pv.items[1].contract
        XCTAssertTrue(t.noCancel)
        XCTAssertFalse(t.mandatory)
        XCTAssertEqual(t.cancelTerm, .anytime)
        // Ende roh: der Import ergibt denselben Vertrag
        XCTAssertEqual(pv.items[2].contract.status, .active)
        XCTAssertEqual(pv.items[2].contract.end, Day(2025, 12, 31))
        XCTAssertEqual(pv.items[2].contract.renewMonths, 12)
        XCTAssertEqual(pv.items[3].contract.status, .cancelled)
        XCTAssertEqual(pv.items[3].contract.cancelledAt, Day(2026, 3, 31))
    }

    func testCSVVia() {
        XCTAssertEqual(CSV.via("Per Einschreiben"), .registered)
        XCTAssertEqual(CSV.via("Brief"), .letter)
        XCTAssertEqual(CSV.via("post"), .letter)
        XCTAssertEqual(CSV.via("E-Mail"), .email)
        XCTAssertEqual(CSV.via("Kundenportal"), .online)
        XCTAssertEqual(CSV.via("Online / Kundenkonto"), .online)
        XCTAssertNil(CSV.via("Telefon"))
        XCTAssertNil(CSV.via(""))
        // unbekannter Text: kein Rückfall auf den Katalog
        let rows = [["Vertragspartner", "Betrag", "KuendigungPer"], ["Netflix", "18.90", "Telefon"], ["Netflix", "12.90", ""]]
        let pv = CSV.preview(rows: rows, data: AppData.initial(), today: Day(2026, 10, 3))
        XCTAssertNil(pv.items[0].contract.cancelChannel)
        XCTAssertEqual(pv.items[1].contract.cancelChannel, .online)
    }

    func testCSVNoticeFallback() {
        let rows = [["Vertragspartner", "Betrag", "Kuendigungsfrist", "Einheit"], ["A", "10", "1.5", "m"], ["B", "10", "40", "k"]]
        let pv = CSV.preview(rows: rows, data: AppData.initial(), today: Day(2026, 10, 3))
        XCTAssertEqual(pv.items[0].contract.notice, 2)
        XCTAssertEqual(pv.items[1].contract.notice, 40)
        XCTAssertEqual(pv.items[1].contract.noticeUnit, .dayOfMonth)
    }

    // MARK: Begriffe

    func testTerminology() {
        XCTAssertEqual(ContractSort.holder.shortLabel, "Person")
        XCTAssertEqual(ContractSort.holder.optionLabel, "Person")
        XCTAssertEqual(MutationError.duplicatePerson(UUID()).message, "Diese Person gibt es schon")
        XCTAssertEqual(MutationError.lastPerson.message, "Mindestens eine Person ist nötig")
        XCTAssertEqual(Quality.checklist[0].rows.map { $0.title }, ["Person", "Betrag", "Kategorie", "Zahlungsrhythmus", "Einnahmen: Betrag, Person"])
        XCTAssertEqual(CSV.header(home: .CHF)[17], "Inhaber")
        let d = AppData.initial()
        XCTAssertEqual(d.holderChoiceToast(title: "Handy", holderIDs: []), "Handy → ohne Person")
    }

    // MARK: Einstellungen

    func testLogoSkipImportAndCodable() throws {
        let json = """
        {"app":"vertraege","settings":{"home":"CHF","logoSkip":{" Kanton TG ":1,"swisscom":0}},"contracts":{},"incomes":{}}
        """
        let r = try WebImport.importBackup(Data(json.utf8), today: Day(2026, 10, 3))
        XCTAssertEqual(r.data.settings.logoSkip, ["kanton tg"])
        let back = try AppData.decode(r.data.encoded())
        XCTAssertEqual(back.settings.logoSkip, ["kanton tg"])
        // ältere Daten ohne Feld
        let old = try AppData.decode(Data(#"{"settings":{"homeCurrency":"CHF"}}"#.utf8))
        XCTAssertEqual(old.settings.logoSkip, [])
    }
}
