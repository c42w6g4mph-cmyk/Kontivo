import XCTest
@testable import KontivoCore

/// Kontoauszug als Text (PDF-Text oder OCR eines Fotos): `BankImport.readStatementText` (nur nativ, ohne Web-Gegenstück),
/// dazu Swift-eigene Abläufe des Imports (Fehler beim Lesen, ausblenden, gelernte Korrekturen, Preis übernehmen).
final class BankStatementTextTests: XCTestCase {
    static let ch = """
    PostFinance AG
    Kontoauszug Privatkonto
    IBAN CH12 0900 0000 1234 5678 9          Währung CHF
    Datum       Text                                         Gutschrift   Lastschrift   Valuta        Saldo
    30.09.2025  Saldovortrag                                                                         5'000.00
    01.10.2025  DAUERAUFTRAG Immo Seeblick AG                               1'850.00   01.10.2025    3'150.00
                Miete Wohnung 3.OG
    03.10.2025  LASTSCHRIFT Swisscom (Schweiz) AG                              79.00   03.10.2025    3'071.00
    12.10.2025  KAUF/DIENSTLEISTUNG VOM 11.10.2025                             18.90   12.10.2025    3'052.10
                KARTEN NR. XXXX1234
                NETFLIX.COM LOS GATOS
    20.10.2025  E-FINANCE Energie Kreuzlingen                                 180.50   20.10.2025    2'871.60
    25.10.2025  GUTSCHRIFT Muster AG Lohn Oktober          6'500.00                    25.10.2025    9'371.60
    28.10.2025  TWINT AN Lara Muster                                           25.00   28.10.2025    9'346.60
    31.10.2025  Kontostand                                                                           9'346.60
    """
    static let de = """
    Sparkasse Bodensee                                   Kontoauszug 10/2025
    Girokonto DE12 6905 0001 0012 3456 78
    Buchungstag Wert       Erläuterung                                  Betrag EUR
    01.10.2025  01.10.2025 Dauerauftrag Wohnbau Konstanz GmbH           -1.180,00
                           Miete Oktober
    02.10.2025  02.10.2025 Lastschrift Telekom Deutschland GmbH            -39,95
                           Festnetz Kd-Nr 123456789
    05.10.2025  05.10.2025 Kartenzahlung NETFLIX.COM                       -13,99
    15.10.2025  15.10.2025 Lastschrift Stadtwerke Konstanz GmbH           -102,00
                           Abschlag Strom
    25.10.2025  25.10.2025 Gutschrift Muster GmbH Gehalt Oktober         3.200,00
    28.10.2025  28.10.2025 Lastschrift McFit GmbH                          -24,90
    Neuer Kontostand                                                     4.321,16
    """
    static let ocr = """
    Kontobewegungen Oktober 2025
    Datum    Buchungstext                       Betrag CHF
    01.10.25 Dauerauftrag Immo Seeblick AG      1'850.00-
    03.10.25 Lastschrift Sunrise GmbH              39.00-
    05.10.25 Einkauf Coop Kreuzlingen              54.30-
    10.10.25 Gutschrift Lohn Muster AG          6'500.00 CR
    15.10.25 Lastschrift Helsana                  356.80-
    20.10.25 Rückerstattung Krankenkasse          120.00
    """
    static let desc = """
    Kontoauszug 1.10.2025 - 31.10.2025
    Datum      Buchung                              Betrag        Saldo
    28.10.2025 Lastschrift McFit GmbH                24.90     9'346.60
    25.10.2025 Lohn Muster AG                     6'500.00     9'371.60
    20.10.2025 E-Rechnung Energie Kreuzlingen       180.50     2'871.60
    12.10.2025 Kartenzahlung Netflix                 18.90     3'052.10
    03.10.2025 Lastschrift Swisscom                  79.00     3'071.00
    01.10.2025 Dauerauftrag Immo Seeblick AG      1'850.00     3'150.00
    """
    static let short = """
    Datum Text Betrag
    01.10.2025 Lastschrift Swisscom -79.00
    03.10.2025 Lastschrift Sunrise -39.00
    05.10.2025 Kartenzahlung Netflix -18.90
    """
    static let noyear = """
    Kontoauszug Oktober 2025 (01.10.2025 bis 31.10.2025)
    Datum  Text                                Belastung   Gutschrift
    01.10. Dauerauftrag Immo Seeblick AG        1'850.00
    03.10. Lastschrift Swisscom                    79.00
    12.10. Kartenzahlung Netflix                   18.90
    25.10. Lohn Muster AG                                    6'500.00
    28.10. Twint an Lara                           25.00
    """

    typealias T = (date: String, amount: Double, text: String)

    func check(_ f: BankFile?, _ exp: [T], currency: String, file: StaticString = #filePath, line: UInt = #line) {
        guard let f = f else { return XCTFail("nichts erkannt", file: file, line: line) }
        XCTAssertEqual(f.format, "Text", file: file, line: line)
        XCTAssertEqual(f.tx.map { $0.date.iso }, exp.map { $0.date }, file: file, line: line)
        XCTAssertEqual(f.tx.count, exp.count, file: file, line: line)
        for (t, e) in zip(f.tx, exp) {
            XCTAssertEqual(t.amount, e.amount, accuracy: 0.001, "\(e.date) \(e.text)", file: file, line: line)
            XCTAssertEqual(t.text, e.text, file: file, line: line)
            XCTAssertEqual(t.currency, currency, file: file, line: line)
            XCTAssertEqual(t.name, "", file: file, line: line)
        }
        XCTAssertEqual(f.from, f.tx.first?.date, file: file, line: line)
        XCTAssertEqual(f.to, f.tx.last?.date, file: file, line: line)
    }

    /// PostFinance-PDF: Spalten Gutschrift/Lastschrift/Valuta/Saldo, mehrzeilige Texte, Saldovortrag und Kontostand übersprungen.
    func testSwissStatementWithBalance() {
        check(BankImport.readStatementText(Self.ch, defaultCurrency: "EUR"), [
            ("2025-10-01", -1850.00, "DAUERAUFTRAG Immo Seeblick AG Miete Wohnung 3.OG"),
            ("2025-10-03", -79.00, "LASTSCHRIFT Swisscom (Schweiz) AG"),
            ("2025-10-12", -18.90, "KAUF/DIENSTLEISTUNG VOM 11.10.2025 KARTEN NR. XXXX1234 NETFLIX.COM LOS GATOS"),
            ("2025-10-20", -180.50, "E-FINANCE Energie Kreuzlingen"),
            ("2025-10-25", 6500.00, "GUTSCHRIFT Muster AG Lohn Oktober"),
            ("2025-10-28", -25.00, "TWINT AN Lara Muster"),
        ], currency: "CHF")
        let f = BankImport.readStatementText(Self.ch, defaultCurrency: "EUR")
        XCTAssertEqual(f?.tx.first?.kind, .so)
        XCTAssertEqual(f?.tx[2].kind, .card)
    }

    /// Sparkasse-PDF: Buchungstag + Wertstellung, Beträge mit Vorzeichen (1.234,56), ohne Vorzeichen = Gutschrift.
    func testGermanStatementSigned() {
        check(BankImport.readStatementText(Self.de, defaultCurrency: "CHF"), [
            ("2025-10-01", -1180.00, "Dauerauftrag Wohnbau Konstanz GmbH Miete Oktober"),
            ("2025-10-02", -39.95, "Lastschrift Telekom Deutschland GmbH Festnetz Kd-Nr 123456789"),
            ("2025-10-05", -13.99, "Kartenzahlung NETFLIX.COM"),
            ("2025-10-15", -102.00, "Lastschrift Stadtwerke Konstanz GmbH Abschlag Strom"),
            ("2025-10-25", 3200.00, "Gutschrift Muster GmbH Gehalt Oktober"),
            ("2025-10-28", -24.90, "Lastschrift McFit GmbH"),
        ], currency: "EUR")
    }

    /// Foto (OCR): Jahr zweistellig, Minus hinten, «CR» = Gutschrift.
    func testOcrTrailingMinus() {
        check(BankImport.readStatementText(Self.ocr, defaultCurrency: "EUR"), [
            ("2025-10-01", -1850.00, "Dauerauftrag Immo Seeblick AG"),
            ("2025-10-03", -39.00, "Lastschrift Sunrise GmbH"),
            ("2025-10-05", -54.30, "Einkauf Coop Kreuzlingen"),
            ("2025-10-10", 6500.00, "Gutschrift Lohn Muster AG"),
            ("2025-10-15", -356.80, "Lastschrift Helsana"),
            ("2025-10-20", 120.00, "Rückerstattung Krankenkasse"),
        ], currency: "CHF")
    }

    /// Neueste Buchung zuerst, ohne Vorzeichen: Belastung/Gutschrift aus dem Saldo-Verlauf; Währung aus der Vorgabe.
    func testDescendingWithBalance() {
        check(BankImport.readStatementText(Self.desc, defaultCurrency: "CHF"), [
            ("2025-10-01", -1850.00, "Dauerauftrag Immo Seeblick AG"),
            ("2025-10-03", -79.00, "Lastschrift Swisscom"),
            ("2025-10-12", -18.90, "Kartenzahlung Netflix"),
            ("2025-10-20", -180.50, "E-Rechnung Energie Kreuzlingen"),
            ("2025-10-25", 6500.00, "Lohn Muster AG"),
            ("2025-10-28", -24.90, "Lastschrift McFit GmbH"),
        ], currency: "CHF")
    }

    /// Datum ohne Jahr («01.10.») mit Jahr aus dem Kopf; Spalten Belastung/Gutschrift über die Position.
    func testDayMonthOnlyWithColumns() {
        check(BankImport.readStatementText(Self.noyear, defaultCurrency: "CHF"), [
            ("2025-10-01", -1850.00, "Dauerauftrag Immo Seeblick AG"),
            ("2025-10-03", -79.00, "Lastschrift Swisscom"),
            ("2025-10-12", -18.90, "Kartenzahlung Netflix"),
            ("2025-10-25", 6500.00, "Lohn Muster AG"),
            ("2025-10-28", -25.00, "Twint an Lara"),
        ], currency: "CHF")
    }

    /// Weniger als 5 Buchungen oder gar kein Auszug → nil.
    func testTooFew() {
        XCTAssertNil(BankImport.readStatementText(Self.short, defaultCurrency: "CHF"))
        XCTAssertNil(BankImport.readStatementText("", defaultCurrency: "CHF"))
        XCTAssertNil(BankImport.readStatementText("Sehr geehrte Damen und Herren\nIhre Rechnung vom 03.10.2025 über CHF 79.00", defaultCurrency: "CHF"))
    }

    /// Ein Jahr PostFinance-PDF als Text → dieselben Vorschläge wie die Web-App für diese Buchungen
    /// (Erwartung mit window.KontivoBank().find aus den gleichen Buchungen erzeugt).
    func testYearStatementFindsContracts() throws {
        let dir = try XCTUnwrap(Bundle.module.url(forResource: "BankFixtures", withExtension: nil))
        let txt = try String(contentsOf: dir.appendingPathComponent("statement_ch_year.txt"), encoding: .utf8)
        let f = try XCTUnwrap(BankImport.readStatementText(txt, defaultCurrency: "EUR"))
        XCTAssertEqual(f.tx.count, 76)
        XCTAssertEqual(f.tx.filter { $0.amount > 0 }.count, 12)
        let data = AppData.initial()
        let r = BankImport.find(f, data: data, today: Day(2026, 10, 8))
        let got = r.items.map { "\($0.name)|\($0.cycle)|\(String(format: "%.2f", $0.amount))|\($0.confidence.rawValue)|\($0.category)|\($0.count)" }
        XCTAssertEqual(got, [
            "Immo Seeblick AG|1|1850.00|hoch|Wohnen|12",
            "Swisscom|1|79.00|hoch|Mobilfunk & Internet|12",
            "Energie Kreuzlingen|3|180.50|hoch|Energie & Wasser|4",
            "Netflix|1|18.90|hoch|Abos & Medien|12",
            "Spotify|1|13.95|hoch|Abos & Medien|12",
        ])
    }

    // MARK: Lesen: Fehler und Kodierung

    func testReadErrors() {
        XCTAssertThrowsError(try BankImport.read(Data())) { XCTAssertEqual($0 as? BankReadError, .empty) }
        XCTAssertThrowsError(try BankImport.read(Data(count: 20_000_001))) { XCTAssertEqual($0 as? BankReadError, .tooBig) }
        XCTAssertThrowsError(try BankImport.read(Data("Hallo Welt\nkein Auszug".utf8))) {
            XCTAssertEqual($0 as? BankReadError, .notRecognized(firstLine: "Hallo Welt"))
        }
    }

    /// Excel-CSV in Windows-1252 (Umlaute), Kopf mit Bank-Erkennung, Komma-Dezimal.
    func testWindows1252() throws {
        let csv = "Buchungstag;Auftraggeber / Begünstigter;Verwendungszweck;Betrag (EUR)\r\n" +
            "01.10.2025;Müller Gärten GmbH;Rechnung;-1.234,50\r\n02.10.2025;Bäckerei Süß;Brot;-4,20\r\n"
        let data = try XCTUnwrap(csv.data(using: .windowsCP1252))
        let f = try BankImport.read(data)
        XCTAssertEqual(f.format, "CSV")
        XCTAssertEqual(f.tx.count, 2)
        XCTAssertEqual(f.tx[0].name, "Müller Gärten GmbH")
        XCTAssertEqual(f.tx[0].amount, -1234.5, accuracy: 0.001)
        XCTAssertEqual(f.tx[0].currency, "EUR")
        XCTAssertEqual(f.tx[1].name, "Bäckerei Süß")
    }

    // MARK: Ausblenden, Korrekturen, Preis übernehmen

    func monthlyCSV() -> Data {
        var rows = ["Datum;Buchungstext;Betrag;Währung"]
        for m in 0..<12 {
            let d = Day(2025, 10 + m, 5)
            rows.append(String(format: "%02d.%02d.%04d", d.day, d.month, d.year) + ";LASTSCHRIFT Muster Streaming AG;-12.90;CHF")
        }
        return Data(rows.joined(separator: "\n").utf8)
    }

    func testIgnoreAndAlias() throws {
        let f = try BankImport.read(monthlyCSV())
        var data = AppData.initial()
        let today = Day(2026, 10, 8)
        let s = try XCTUnwrap(BankImport.find(f, data: data, today: today).items.first)
        XCTAssertEqual(s.name, "Muster Streaming AG")
        XCTAssertEqual(BankImport.ignoreKey(s), "muster streaming")
        XCTAssertFalse(s.ignored)
        // gelernte Korrektur: Name und Kategorie
        BankImport.rememberCorrection(s, name: "Muster TV", category: "Abos & Medien", in: &data)
        var r = BankImport.find(f, data: data, today: today)
        XCTAssertEqual(r.items.first?.name, "Muster TV")
        XCTAssertEqual(r.items.first?.category, "Abos & Medien")
        XCTAssertEqual(r.items.first?.alias, BankAlias(n: "Muster TV", c: "Abos & Medien"))
        // unverändert übernommen: keine Korrektur
        var d2 = AppData.initial()
        BankImport.rememberCorrection(s, name: s.name, category: s.category, in: &d2)
        XCTAssertTrue(d2.settings.bankAlias.isEmpty)
        // nie mehr vorschlagen
        BankImport.ignore(s, in: &data)
        BankImport.ignore(s, in: &data)
        XCTAssertEqual(data.settings.bankIgn, ["muster streaming"])
        r = BankImport.find(f, data: data, today: today)
        XCTAssertEqual(r.items.first?.ignored, true)
        XCTAssertEqual(r.ignoredCount, 1)
        // Einstellungen bleiben beim Speichern erhalten
        let back = try KontivoJSON.decode(data.encoded())
        XCTAssertEqual(back.settings.bankIgn, ["muster streaming"])
        XCTAssertEqual(back.settings.bankAlias["muster streaming"], BankAlias(n: "Muster TV", c: "Abos & Medien"))
    }

    func testAddAndApplyPrice() throws {
        let f = try BankImport.read(monthlyCSV())
        var data = AppData.initial()
        let today = Day(2026, 10, 8)
        let s = try XCTUnwrap(BankImport.find(f, data: data, today: today).items.first)
        let id = BankImport.add(s, persons: ["Ich"], to: &data, today: today)
        let c = try XCTUnwrap(data.contract(id))
        XCTAssertEqual(data.partnerName(of: c), "Muster Streaming AG")
        XCTAssertEqual(c.amount, 12.90, accuracy: 0.001)
        XCTAssertEqual(c.due, Day(2026, 11, 5))   // letzte Zahlung 05.09.2026, monatlich bis nach heute
        XCTAssertEqual(data.holderNames(of: c), ["Ich"])
        // gleicher Auszug: jetzt bereits erfasst
        let r = BankImport.find(f, data: data, today: today)
        XCTAssertTrue(r.items.isEmpty)
        XCTAssertEqual(r.known.first?.contractID, id)
        // Preis übernehmen
        BankImport.applyPrice(BankPriceMatch(contractID: id, from: Day(2026, 11, 5), amount: 13.90, old: 12.90, suggestion: s), to: &data)
        XCTAssertEqual(data.contract(id)?.prices, [PriceChange(from: Day(2026, 11, 5), amount: 13.90)])
    }
}
