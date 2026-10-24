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

extension WebSync323Tests {
    // MARK: Kosten «Fällig im …» (Web v244/v245/v253) und Vorjahresvergleich (v236)

    func testPaymentStatusAndMonthComparison() {
        var d = AppData.initial()
        let today = Day(2026, 10, 20)
        let calc0 = Calc(data: d, today: today)
        XCTAssertEqual(calc0.kbPaymentStatus(Day(2026, 10, 20)).text, "heute")
        XCTAssertFalse(calc0.kbPaymentStatus(Day(2026, 10, 20)).warn)
        XCTAssertEqual(calc0.kbPaymentStatus(Day(2026, 10, 23)).text, Format.fmtShort(Day(2026, 10, 23)))
        XCTAssertTrue(calc0.kbPaymentStatus(Day(2026, 10, 23)).warn)
        XCTAssertFalse(calc0.kbPaymentStatus(Day(2026, 10, 28)).warn)
        XCTAssertEqual(calc0.kbPaymentStatus(Day(2026, 10, 3)).text, Format.fmtShort(Day(2026, 10, 3)))
        XCTAssertFalse(calc0.kbPaymentStatus(Day(2026, 10, 3)).warn)
        // Vertrag ohne Beginn: Vergleich wird trotzdem gezeigt (ganz einfach Monat gegen Vorjahresmonat)
        let c = Contract(label: "Strom", amount: 100, cycle: 1, due: Day(2025, 1, 15))
        d.contracts = [c]
        let calc = Calc(data: d, today: today)
        let items = calc.costYear(2026, filter: Calc.CostFilter()).months[9].items
        XCTAssertEqual(items.count, 1)
        let cmp = calc.monthComparison(year: 2026, month: 10, filter: Calc.CostFilter(), monthSum: 120, items: items)
        XCTAssertEqual(cmp?.text, "20 CHF mehr als Oktober 2025")
        XCTAssertEqual(cmp?.trend, .up)
    }
}

extension WebSync323Tests {
    // MARK: Person «Ich» bekommt den Vornamen aus dem Absender (Web 3fc86ed)

    func testAutoNamePerson() throws {
        var d = AppData.initial()
        let me = d.persons[0].id
        XCTAssertEqual(d.persons[0].name, "Ich")
        d.setSender(me, SenderAddress(first: " Sinan  Ali ", last: "Muster", street: "Weg 1", zip: "8280", city: "Kreuzlingen"), sameAs: nil)
        XCTAssertEqual(d.person(me)?.name, "Sinan")
        // nur Platzhalter-Namen, und nur wenn der Name frei ist
        XCTAssertFalse(d.autoNamePerson(me, first: "Max"))
        let du = try d.addPerson("Du")
        _ = try d.addPerson("Lara")
        XCTAssertFalse(d.autoNamePerson(du, first: "lara"))
        XCTAssertTrue(d.autoNamePerson(du, first: "Mia"))
        XCTAssertEqual(d.person(du)?.name, "Mia")
    }
}

extension WebSync323Tests {
    // MARK: Kontoauszug: Gläubiger-ID am erfassten Vertrag nachtragen (Web v273)

    func testRememberCreditorIDs() throws {
        let csv = "Buchungstag;Auftraggeber / Begünstigter;Verwendungszweck;Gläubiger-ID;Mandatsreferenz;Betrag (EUR)\n"
            + (1...12).map { String(format: "03.%02d.2026;Telekom Deutschland GmbH;Festnetz;DE11TEL00000012345;M-1;-39,95", (($0 + 8) % 12) + 1) }.joined(separator: "\n")
        let f = try BankImport.read(Data(csv.utf8))
        var d = AppData.initial(homeCurrency: .EUR)
        let pid = d.partnerID(forName: "Telekom")
        d.contracts = [Contract(label: "Festnetz", partnerID: pid, amount: 39.95, currency: .EUR, cycle: 1, due: Day(2026, 11, 3))]
        let r = BankImport.find(f, data: d, today: Day(2026, 10, 8))
        XCTAssertEqual(r.known.count, 1)
        BankImport.rememberCreditorIDs(r, in: &d)
        XCTAssertEqual(d.contracts[0].creditorID, "DE11TEL00000012345")
        XCTAssertEqual(d.contracts[0].mandateRef, "M-1")
    }
}

extension WebSync323Tests {
    func testReactivateArchived() {
        var d = AppData.initial()
        var c = Contract(label: "Fitness", amount: 79, cycle: 1, due: Day(2026, 1, 15), end: Day(2026, 3, 31))
        c.status = .cancelled
        c.cancelPer = Day(2026, 3, 31)
        c.cancelledAt = Day(2026, 4, 1)
        d.contracts = [c]
        BankImport.reactivate(c.id, amount: 85, from: Day(2026, 9, 15), in: &d, today: Day(2026, 10, 8))
        let x = d.contracts[0]
        XCTAssertEqual(x.status, .active)
        XCTAssertNil(x.cancelPer)
        XCTAssertNil(x.cancelledAt)
        XCTAssertNil(x.end)
        XCTAssertEqual(x.prices.map { $0.amount }, [85])
    }
}
