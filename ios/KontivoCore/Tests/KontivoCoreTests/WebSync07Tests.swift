import XCTest
@testable import KontivoCore

/// Nachzug der Web-Änderungen vom 06./07.10.2026 (v70–v88): Aufteilung in Prozent mit Nachkommastellen, «nicht kündbar»,
/// Katalog mit Kontaktdaten, Adresse einfügen, «Aufteilung und Entwicklung».
final class WebSync07Tests: XCTestCase {
    func testSplitWithDecimals() {
        let a = UUID(), b = UUID()
        var c = Contract(label: "Internet", amount: 49.9, cycle: 1, holderIDs: [a, b])
        c.split = AppData.normalizedSplit([SplitShare(personID: a, percent: 30 / 49.9 * 100), SplitShare(personID: b, percent: 0)], holders: [a, b])
        XCTAssertEqual(c.split.map { $0.percent }, [60.1202, 39.8798])
        XCTAssertEqual((c.validSplit?[a] ?? 0) * 49.9 / 100, 30, accuracy: 0.005)
        // Gleichverteilung wird als «kein split» gespeichert
        XCTAssertEqual(AppData.normalizedSplit(AppData.equalSplit(holders: [a, b]), holders: [a, b]), [])
    }

    func testNoCancel() throws {
        var d = AppData.initial()
        d.contracts = [Contract(label: "Serafe", amount: 28, cycle: 1, due: Day(2026, 10, 25), notice: 1, cancelTerm: .anytime, noCancel: true)]
        let calc = Calc(data: d, today: Day(2026, 10, 7))
        XCTAssertTrue(calc.isFixed(d.contracts[0]))
        XCTAssertNil(calc.noticeDeadline(d.contracts[0]))
        XCTAssertTrue(calc.deadlineOverview().flexible.isEmpty)
        XCTAssertTrue(calc.reviewList().isEmpty)
        // Web-Backup überträgt das Feld
        let json = """
        {"app":"vertraege","settings":{"home":"CHF"},"contracts":{"s":{"partner":"Serafe","label":"Gebühren","cat":"Wohnen","amount":28,"cycle":1,"noCancel":true}},"incomes":{}}
        """
        let r = try WebImport.importBackup(Data(json.utf8), today: Day(2026, 10, 7))
        XCTAssertEqual(r.data.contracts.first?.noCancel, true)
    }

    func testCatalogContactsAndMatch() {
        let sunrise = Catalog.find("Sunrise")
        XCTAssertFalse(sunrise?.address.isEmpty ?? true)
        XCTAssertNotNil(Catalog.entries.first { !$0.confirmed })
        XCTAssertTrue(Catalog.entries.first { !$0.confirmed }?.hintFull.hasSuffix("vor dem Versand prüfen.") ?? false)
        XCTAssertTrue(Catalog.find("Serafe")?.isFixed ?? false)
        // Länder-Variante über die Währung
        XCTAssertEqual(Catalog.match(names: ["AXA"], currency: .EUR)?.country, "DE")
        XCTAssertEqual(Catalog.match(names: ["AXA"], currency: .CHF)?.country, "CH")
        XCTAssertNil(Catalog.match(names: ["Sparkasse Bodensee"], currency: .EUR))
    }

    func testCatalogFillPlan() {
        var d = AppData.initial()
        let p = Partner(name: "Sunrise")
        d.partners = [p]
        d.contracts = [Contract(label: "Internet", partnerID: p.id, amount: 49.9, cycle: 1)]
        let plan = d.catalogFillPlan()
        XCTAssertEqual(plan.count, 1)
        XCTAssertNotNil(plan[0].address)
        d.applyCatalogFill(plan)
        XCTAssertFalse(d.partners[0].address.isEmpty)
        XCTAssertEqual(d.partners[0].web, "sunrise.ch")
        // nur leere Felder: zweiter Lauf ändert nichts mehr an der Adresse
        XCTAssertNil(d.catalogFillPlan().first?.address)
    }

    func testAddressPaste() {
        let a = WebImport.addrFromPaste("Sunrise GmbH, Thurgauerstrasse 101B, 8152 Glattpark (Opfikon), Schweiz")
        XCTAssertEqual(a?.company, "Sunrise GmbH")
        XCTAssertEqual(a?.street, "Thurgauerstrasse 101B")
        XCTAssertEqual(a?.zip, "8152")
        XCTAssertEqual(a?.city, "Glattpark (Opfikon)")
        XCTAssertEqual(a?.country, "Schweiz")
        let b = WebImport.addrFromPaste("Swisscom (Schweiz) AG\nKundendienst\nPostfach\n3050 Bern\nTel. 0800 800 800")
        XCTAssertEqual(b?.extra, "Kundendienst")
        XCTAssertEqual(b?.street, "Postfach")
        XCTAssertEqual(b?.city, "Bern")
        let n = WebImport.addrFromPaste("Netflix International B.V., Karperstraat 8-10, 1075 KZ Amsterdam, Niederlande")
        XCTAssertEqual(n?.zip, "1075 KZ")
        XCTAssertEqual(n?.city, "Amsterdam")
        XCTAssertNil(WebImport.addrFromPaste("  "))
        XCTAssertTrue(WebImport.addrLooksPasted("A\nB"))
        XCTAssertTrue(WebImport.addrLooksPasted("Firma, Weg 1, 8000 Zürich"))
        XCTAssertFalse(WebImport.addrLooksPasted("Sunrise GmbH"))
    }

    func testCostEvolution() {
        var d = AppData.initial()
        let cat = d.categories[0].id
        d.contracts = [Contract(label: "Miete", categoryID: cat, amount: 1000, cycle: 1, due: Day(2026, 1, 1), start: Day(2024, 1, 1),
                                prices: [PriceChange(from: Day(2026, 1, 1), amount: 1100)])]
        let calc = Calc(data: d, today: Day(2026, 10, 7))
        let ev = calc.costEvolution(year: 2026, month: nil, filter: Calc.CostFilter(), dim: .category)
        XCTAssertEqual(ev.bars.map { $0.year }, [2026, 2025, 2024])
        XCTAssertEqual(ev.title, "Entwicklung 2024–2026")
        XCTAssertEqual(ev.chip, "↑ 10 % vs. 2025")
        XCTAssertEqual(ev.rows.first?.percent, 100)
        XCTAssertEqual(ev.rows.first?.change, "↑ 10 % mehr")
        XCTAssertEqual(ev.rows.first?.series.map { $0.year }, [2024, 2025, 2026])
        let m = calc.costEvolution(year: 2026, month: 10, filter: Calc.CostFilter(), dim: .category)
        XCTAssertEqual(m.title, "Oktober 2024–2026")
    }
}
