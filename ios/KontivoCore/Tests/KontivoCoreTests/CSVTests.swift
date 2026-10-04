import XCTest
@testable import KontivoCore

final class CSVTests: XCTestCase {
    let today = Day(2026, 10, 3)

    func sample() -> AppData {
        var data = AppData.initial()
        let me = data.persons[0].id
        let cat = data.category(named: "Mobilfunk & Internet")!.id
        let p1 = Partner(name: "Pizza \"Roma\"; GmbH", web: "pizza.ch",
                         address: PostalAddress(company: "Pizza Roma GmbH", street: "Hauptstr. 1", zip: "8000", city: "Zürich"))
        let p2 = Partner(name: "Müller ÄÖÜ")
        data.partners = [p1, p2]
        data.contracts = [
            Contract(label: "Internet \"Blue\" 24\" TV", partnerID: p1.id, categoryID: cat, amount: 49.9, currency: .CHF, cycle: 1,
                     due: Day(2026, 10, 15), notice: 2, noticeUnit: .months, cancelTerm: .monthEnd, customerNo: "K-1;2", holderIDs: [me],
                     cancelChannel: .online, cancelURL: "https://pizza.ch/kuendigen", note: "Zeile 1\nZeile 2; mit Semikolon \"zitiert\"",
                     extras: [ExtraPayment(date: Day(2026, 11, 1), amount: -20, note: "Gutschrift: Bonus")]),
            Contract(label: "Grüezi Öl", partnerID: p2.id, categoryID: cat, amount: 120, currency: .EUR, cycle: 12, due: Day(2027, 1, 1),
                     holderIDs: [me], prices: [PriceChange(from: Day(2027, 1, 1), amount: 130)]),
        ]
        return data
    }

    func testExportFormat() {
        let text = CSV.export(sample(), today: today)
        XCTAssertTrue(text.hasPrefix("\u{FEFF}Vertragspartner;Bezeichnung;Kategorie;Betrag;"))
        XCTAssertTrue(text.contains("\r\n"))
        let rows = CSV.parse(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].count, 31)
        XCTAssertEqual(rows[0][6], "ProMonat_CHF")
        XCTAssertEqual(rows[0][29], "Adresse")
        XCTAssertEqual(rows[0][30], "KuendigungsLink")
        XCTAssertEqual(rows[1].count, 31)
        XCTAssertEqual(rows[1][0], "Pizza \"Roma\"; GmbH")
        XCTAssertEqual(rows[1][1], "Internet \"Blue\" 24\" TV")
        XCTAssertEqual(rows[1][3], "49.90")
        XCTAssertEqual(rows[1][15], "K-1;2")
        XCTAssertEqual(rows[1][27], "Zeile 1\nZeile 2; mit Semikolon \"zitiert\"")
        XCTAssertEqual(rows[1][28], "2026-11-01:-20.00:Gutschrift  Bonus")
        XCTAssertEqual(rows[1][29], "Pizza Roma GmbH\nHauptstr. 1\n8000 Zürich")
        XCTAssertEqual(rows[1][30], "https://pizza.ch/kuendigen")
        XCTAssertEqual(rows[2][1], "Grüezi Öl")
        XCTAssertEqual(rows[2][14], "Anfang:120.00 | 2027-01-01:130.00")
        XCTAssertEqual(rows[2][6], "9.40")
        // CSV-1: Frist 0 und «jederzeit» ausdrücklich
        XCTAssertEqual(rows[0][10], "Kuendigungsfrist")
        XCTAssertEqual(rows[1][10], "2")
        XCTAssertEqual(rows[2][10], "0")
        XCTAssertEqual(rows[1][25], "m")
        XCTAssertEqual(rows[2][25], "jederzeit")
    }

    /// CSV-1: Rundlauf erhält Frist 0, «jederzeit» und «kein Pflichtvertrag» auch bei Katalog-Vertragspartnern.
    func testRoundTripKeepsDeliberateValues() {
        var src = AppData.initial()
        let me = src.persons[0].id
        let tel = src.category(named: "Mobilfunk & Internet")!.id
        let ins = src.category(named: "Versicherung")!.id
        let sw = Partner(name: "Swisscom")
        let css = Partner(name: "CSS")
        src.partners = [sw, css]
        src.contracts = [
            Contract(label: "Handy", partnerID: sw.id, categoryID: tel, amount: 30, cycle: 1, due: Day(2026, 10, 20), notice: 0, cancelTerm: .anytime, holderIDs: [me]),
            Contract(label: "Zusatz", partnerID: css.id, categoryID: ins, amount: 20, cycle: 1, due: Day(2026, 10, 20), notice: 0,
                     cancelTerm: .anytime, mandatory: false, holderIDs: [me]),
        ]
        let text = CSV.export(src, today: today)
        let pv = CSV.preview(csv: Data(text.utf8), data: AppData.initial(), today: today)
        XCTAssertEqual(pv.items.count, 2)
        for it in pv.items {
            XCTAssertEqual(it.contract.notice, 0)
            XCTAssertEqual(it.contract.cancelTerm, .anytime)
            XCTAssertFalse(it.contract.mandatory)
        }
        // Ohne Spalten: Katalogwerte
        let pv2 = CSV.preview(csv: Data("Vertragspartner;Betrag\nSwisscom;30\nCSS;400\n".utf8), data: AppData.initial(), today: today)
        XCTAssertEqual(pv2.items[0].contract.notice, 60)
        XCTAssertEqual(pv2.items[0].contract.cancelTerm, .monthEnd)
        XCTAssertTrue(pv2.items[1].contract.mandatory)
    }

    /// CSV-2, CSV-3, CSV-5: Turnus angepasst, einzeilige Adresse, ungültige Daten.
    func testAdjustedCyclesAddressDates() {
        let csv = "Name;Betrag;Turnus;Adresse;Beginn;Faellig\nA;120;4 Monate;\"Firma AG, Hauptstr. 1, 8000 Zürich\";31.02.2026;2026/11/03\nB;10;5;;;\n"
        let pv = CSV.preview(csv: Data(csv.utf8), data: AppData.initial(), today: today)
        XCTAssertEqual(pv.items.count, 2)
        XCTAssertEqual(pv.items[0].contract.cycle, 3)
        XCTAssertEqual(pv.items[1].contract.cycle, 6)
        XCTAssertEqual(pv.adjustedCycles, 2)
        XCTAssertEqual(pv.items[0].address, "Firma AG\nHauptstr. 1\n8000 Zürich")
        XCTAssertEqual(pv.items[0].contract.due, Day(2026, 11, 3))
        XCTAssertNil(pv.items[0].contract.start)
        XCTAssertEqual(pv.badDates, 1)
        XCTAssertTrue(pv.confirmText.contains("2 Zahlungsrhythmen angepasst.\n"))
        XCTAssertTrue(pv.confirmText.contains("1 ungültiges Datum ignoriert.\n"))
        var target = AppData.initial()
        CSV.apply(pv, to: &target)
        let p = target.partner(target.contracts[0].partnerID)
        XCTAssertEqual(p?.address.company, "Firma AG")
        XCTAssertEqual(p?.address.street, "Hauptstr. 1")
        XCTAssertEqual(p?.address.city, "Zürich")
    }

    func testRoundTrip() {
        let src = sample()
        let text = CSV.export(src, today: today)
        var target = AppData.initial()
        let pv = CSV.preview(csv: Data(text.utf8), data: target, today: today)
        XCTAssertTrue(pv.isUsable)
        XCTAssertEqual(pv.items.count, 2)
        XCTAssertEqual(pv.duplicates, 0)
        XCTAssertEqual(pv.newCategoryNames, [])
        XCTAssertEqual(pv.newHolderNames, [])
        let a = pv.items[0]
        XCTAssertEqual(a.partnerName, "Pizza \"Roma\"; GmbH")
        XCTAssertEqual(a.contract.label, "Internet \"Blue\" 24\" TV")
        XCTAssertEqual(a.contract.note, "Zeile 1\nZeile 2; mit Semikolon \"zitiert\"")
        XCTAssertEqual(a.contract.amount, 49.9, accuracy: 1e-9)
        XCTAssertEqual(a.contract.notice, 2)
        XCTAssertEqual(a.contract.cancelTerm, .monthEnd)
        XCTAssertEqual(a.contract.customerNo, "K-1;2")
        XCTAssertEqual(a.contract.cancelChannel, .online)
        XCTAssertEqual(a.contract.cancelURL, "https://pizza.ch/kuendigen")
        XCTAssertEqual(a.contract.due, Day(2026, 10, 15))
        XCTAssertEqual(a.contract.extras.count, 1)
        XCTAssertEqual(a.contract.extras.first?.amount ?? 0, -20, accuracy: 1e-9)
        XCTAssertEqual(a.address, "Pizza Roma GmbH\nHauptstr. 1\n8000 Zürich")
        XCTAssertEqual(a.web, "pizza.ch")
        XCTAssertEqual(a.categoryName, "Mobilfunk & Internet")
        XCTAssertEqual(a.holderNames, ["Ich"])
        let b = pv.items[1]
        XCTAssertEqual(b.partnerName, "Müller ÄÖÜ")
        XCTAssertEqual(b.contract.label, "Grüezi Öl")
        XCTAssertEqual(b.contract.currency, .EUR)
        XCTAssertEqual(b.contract.cycle, 12)
        XCTAssertEqual(b.contract.amount, 120, accuracy: 1e-9)
        XCTAssertEqual(b.contract.prices, [PriceChange(from: Day(2027, 1, 1), amount: 130)])

        let ids = CSV.apply(pv, to: &target)
        XCTAssertEqual(ids.count, 2)
        XCTAssertEqual(target.contracts.count, 2)
        XCTAssertEqual(target.partners.count, 2)
        let p = target.partner(target.contracts[0].partnerID)
        XCTAssertEqual(p?.name, "Pizza \"Roma\"; GmbH")
        XCTAssertEqual(p?.address.city, "Zürich")
        XCTAssertEqual(p?.address.street, "Hauptstr. 1")
        XCTAssertEqual(p?.web, "pizza.ch")
        XCTAssertEqual(target.contracts[0].holderIDs, [target.persons[0].id])
        XCTAssertEqual(target.category(target.contracts[0].categoryID)?.name, "Mobilfunk & Internet")

        // Zweiter Import: alles schon vorhanden
        let again = CSV.preview(csv: Data(text.utf8), data: target, today: today)
        XCTAssertEqual(again.items.count, 0)
        XCTAssertEqual(again.duplicates, 2)
        XCTAssertEqual(again.nothingText, "Übersprungen: 2 bereits vorhanden.")
    }

    func testCycle() {
        XCTAssertEqual(CSV.cycle("12 Monate"), .months(12))
        XCTAssertEqual(CSV.cycle("24 Monate"), .months(24))
        XCTAssertEqual(CSV.cycle("alle 2 Monate"), .months(2))
        XCTAssertEqual(CSV.cycle("3 months"), .months(3))
        XCTAssertEqual(CSV.cycle("1 Jahr"), .months(12))
        XCTAssertEqual(CSV.cycle("jährlich"), .months(12))
        XCTAssertEqual(CSV.cycle("halbjährlich"), .months(6))
        XCTAssertEqual(CSV.cycle("quartalsweise"), .months(3))
        XCTAssertEqual(CSV.cycle("monatlich"), .months(1))
        XCTAssertEqual(CSV.cycle(""), .months(1))
        XCTAssertEqual(CSV.cycle("12"), .months(12))
        // CSV-2: nächster erlaubter Turnus (bei Gleichstand der kleinere)
        XCTAssertEqual(CSV.cycle("5"), .adjusted(6))
        XCTAssertEqual(CSV.cycle("4 Monate"), .adjusted(3))
        XCTAssertEqual(CSV.cycle("18"), .adjusted(12))
        XCTAssertEqual(CSV.cycle("3 Jahre"), .adjusted(24))
        XCTAssertEqual(CSV.cycle("0"), .adjusted(1))
        XCTAssertEqual(CSV.cycle("wöchentlich"), .weeks(1))
        XCTAssertEqual(CSV.cycle("2 Wochen"), .weeks(2))
    }

    func testNumbersAndDates() {
        XCTAssertEqual(CSV.number("1'234.50"), 1234.5)
        XCTAssertEqual(CSV.number("1’234.50"), 1234.5)
        XCTAssertEqual(CSV.number("1.234,50"), 1234.5)
        XCTAssertEqual(CSV.number("1,234.50"), 1234.5)
        XCTAssertEqual(CSV.number("12,90"), 12.9)
        XCTAssertEqual(CSV.number("CHF 12.-"), 12)
        XCTAssertEqual(CSV.number("17.95 €"), 17.95)
        XCTAssertEqual(CSV.number("-12,90"), -12.9)
        XCTAssertEqual(CSV.number("1.000"), 1000)
        XCTAssertEqual(CSV.number("1.234.567"), 1234567)
        XCTAssertEqual(CSV.number("0.125"), 0.125)
        XCTAssertNil(CSV.number(""))
        XCTAssertNil(CSV.number("abc"))
        XCTAssertEqual(CSV.date("31.12.2026"), Day(2026, 12, 31))
        XCTAssertEqual(CSV.date("2026-02-28"), Day(2026, 2, 28))
        XCTAssertEqual(CSV.date("2026-03-01T10:00"), Day(2026, 3, 1))
        XCTAssertNil(CSV.date("2026-02-30"))
        XCTAssertNil(CSV.date("31.02.2025"))
        XCTAssertEqual(CSV.date("01.01.98"), Day(1998, 1, 1))
        XCTAssertEqual(CSV.date("01.01.26"), Day(2026, 1, 1))
        XCTAssertEqual(CSV.date("12/31/2025"), Day(2025, 12, 31))
        XCTAssertNil(CSV.date("morgen"))
        XCTAssertEqual(CSV.term("Monatsende"), .monthEnd)
        XCTAssertEqual(CSV.term("a"), .contractYear)
        XCTAssertEqual(CSV.term("Ende Vertragsjahr"), .contractYear)
        XCTAssertNil(CSV.term(""))
        XCTAssertEqual(CSV.categoryGuess("Krankenkasse"), "Versicherung")
        XCTAssertEqual(CSV.categoryGuess("Streaming"), "Abos & Medien")
        XCTAssertEqual(CSV.categoryGuess("Andere"), "Sonstiges")
        XCTAssertEqual(CSV.categoryGuess("Velo"), "")
        XCTAssertEqual(CSV.categoryGuess("Haustier"), "Wohnen") // wie Web: «haus» trifft die Regel Wohnen
    }

    func testParser() {
        XCTAssertEqual(CSV.parse("a;\"b\"\"c\";d\r\n1;2;3"), [["a", "b\"c", "d"], ["1", "2", "3"]])
        XCTAssertEqual(CSV.parse("\u{FEFF}x;y\n1;2\n"), [["x", "y"], ["1", "2"]])
        XCTAssertEqual(CSV.parse("Name;Betrag\nPizza 12\" gross;5\nB;6"), [["Name", "Betrag"], ["Pizza 12\" gross", "5"], ["B", "6"]])
        XCTAssertEqual(CSV.parse("sep=,\na,b\n1,2"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSV.parse("\"Name, Firma\";\"Betrag, CHF\"\nA;1"), [["Name, Firma", "Betrag, CHF"], ["A", "1"]])
        XCTAssertEqual(CSV.parse("a,b\n\n,\n1,2"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSV.parse("a\tb\n1\t2"), [["a", "b"], ["1", "2"]])
        XCTAssertEqual(CSV.parse("n;t\nx;\"Zeile 1\nZeile 2\""), [["n", "t"], ["x", "Zeile 1\nZeile 2"]])
    }

    func testHolders() {
        XCTAssertEqual(CSV.holders("Sinan, Lara Beispiel", existing: ["Ich"]), ["Sinan", "Lara Beispiel"])
        XCTAssertEqual(CSV.holders("Anna und Ben Müller", existing: []), ["Anna Müller", "Ben Müller"])
        XCTAssertEqual(CSV.holders("sinan", existing: ["Sinan"]), ["Sinan"])
        XCTAssertEqual(CSV.holders("Sinan Beispiel & Lara", existing: ["Sinan", "Lara"]), ["Sinan", "Lara"])
        // CSV-4: ganzer Text = bestehender Inhaber; eigener Export nur am Komma; mit Komma kein Vornamen-Abgleich
        XCTAssertEqual(CSV.holders("Anna & Ben", existing: ["Anna & Ben"]), ["Anna & Ben"])
        XCTAssertEqual(CSV.holders("Anna & Ben", existing: [], ownExport: true), ["Anna & Ben"])
        XCTAssertEqual(CSV.holders("Anna Müller, Anna Meier", existing: ["Anna"]), ["Anna Müller", "Anna Meier"])
    }

    func testForeignFile() {
        let data = AppData.initial()
        let csv = "Anbieter;Kosten;Zahlungsintervall;Kündigungsfrist;Kategorie;Status\nSpotify;\"12,90\";monatlich;;;\nFitness Park;600;12 Monate;3 Monate;Tiere;\nAlt AG;10;monatlich;;;gekündigt\n;5;;;;\n"
        let pv = CSV.preview(csv: Data(csv.utf8), data: data, today: today)
        XCTAssertTrue(pv.isUsable)
        XCTAssertEqual(pv.items.count, 3)
        XCTAssertEqual(pv.skipped, 1)
        XCTAssertEqual(pv.newCategoryNames, ["Tiere"])
        XCTAssertNil(data.category(named: "Tiere"))
        let spotify = pv.items[0]
        XCTAssertEqual(spotify.contract.amount, 12.9, accuracy: 1e-9)
        XCTAssertEqual(spotify.categoryName, "Abos & Medien")
        XCTAssertEqual(spotify.contract.cancelTerm, .period)
        XCTAssertEqual(spotify.web, "spotify.com")
        XCTAssertEqual(spotify.contract.due, today)
        let fit = pv.items[1]
        XCTAssertEqual(fit.contract.cycle, 12)
        XCTAssertEqual(fit.contract.notice, 3)
        XCTAssertEqual(fit.contract.noticeUnit, .months)
        XCTAssertEqual(fit.categoryName, "Tiere")
        XCTAssertEqual(pv.items[2].contract.status, .cancelled)
        XCTAssertEqual(pv.confirmTitle, "3 Verträge gefunden")
        var target = data
        CSV.apply(pv, to: &target)
        XCTAssertNotNil(target.category(named: "Tiere"))
        XCTAssertEqual(target.contracts.count, 3)
    }

    func testWindows1252() {
        let bytes: [UInt8] = Array("Vertragspartner;Betrag;W".utf8) + [0xE4] + Array("hrung\nM".utf8) + [0xFC] + Array("ller AG;12,50;EUR\n".utf8)
        let text = CSV.decodeText(Data(bytes))
        XCTAssertTrue(text.contains("Währung"))
        XCTAssertTrue(text.contains("Müller AG"))
        let pv = CSV.preview(csv: Data(bytes), data: AppData.initial(), today: today)
        XCTAssertEqual(pv.items.first?.partnerName, "Müller AG")
        XCTAssertEqual(pv.items.first?.contract.currency, .EUR)
    }
}
