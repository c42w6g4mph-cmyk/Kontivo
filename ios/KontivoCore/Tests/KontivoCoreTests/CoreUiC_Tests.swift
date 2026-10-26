import XCTest
@testable import KontivoCore

/// Oberflächen-Logik Bereich c (Web v240–v243, v314–v321, C24/C25, Logo-Suche v292–v294, baab11e): Werte aus der Web-App gemessen.
final class CoreUiCTests: XCTestCase {
    // MARK: Erfolgskarte Katalog

    func testCatalogHintShort() {
        let h1 = CatalogCard.hintShort("Mit 2 Monaten Frist auf jedes Monatsende kündbar, frühestens nach Ablauf der Mindestvertragsdauer; nur per Hotline oder Chat, Brief und E-Mail sind ungültig.", confirmed: true)
        XCTAssertEqual(h1.first, "Mit 2 Monaten Frist auf jedes Monatsende kündbar, frühestens nach Ablauf der Mindestvertragsdauer.")
        XCTAssertEqual(h1.rest, "nur per Hotline oder Chat, Brief und E-Mail sind ungültig.")
        XCTAssertEqual(h1.warn, "")
        // Abkürzungen nur als ganzes Wort (C24): «bzw.», «z.B.», «Mo.»/«Fr.» kein Satzende, «Frist.» schon
        XCTAssertEqual(CatalogCard.hintShort("Kündigung bzw. Wechsel jederzeit möglich. Online im Kundenkonto.", confirmed: true).first,
                       "Kündigung bzw. Wechsel jederzeit möglich.")
        XCTAssertEqual(CatalogCard.hintShort("Frist z.B. 3 Monate. Danach monatlich.", confirmed: true).first, "Frist z.B. 3 Monate.")
        XCTAssertEqual(CatalogCard.hintShort("Nur schriftlich mit Frist. Kein Telefon.", confirmed: true).first, "Nur schriftlich mit Frist.")
        XCTAssertEqual(CatalogCard.hintShort("Öffnungszeiten Mo. bis Fr. telefonisch. Sonst per Mail.", confirmed: true).first,
                       "Öffnungszeiten Mo. bis Fr. telefonisch.")
        let one = CatalogCard.hintShort("Kurz.", confirmed: false)
        XCTAssertEqual(one.first, "Kurz.")
        XCTAssertEqual(one.rest, "")
        XCTAssertEqual(one.warn, "Kontaktdaten nicht offiziell bestätigt – vor dem Versand prüfen.")
        XCTAssertEqual(CatalogCard.hintShort("Ohne Satzende hier", confirmed: true).first, "Ohne Satzende hier")
        // erster Satz über 110 Zeichen: nur «Hinweis zum Kündigen anzeigen»
        let long = CatalogCard.hintShort("Nach der Mindestlaufzeit jederzeit mit 1 Monat Frist kündbar (Kündigungsbutton, E-Mail, Post oder Kündiger-Hotline); StZ Plus 24 Stunden zum Ende des Vertragsmonats.", confirmed: true)
        XCTAssertTrue(long.onlyLink)
        XCTAssertTrue(long.full.hasPrefix("Nach der Mindestlaufzeit"))
        XCTAssertTrue(CatalogCard.hintShort("", confirmed: true).isEmpty)
        XCTAssertFalse(CatalogCard.hintShort("", confirmed: false).isEmpty)
    }

    func testCatalogSummaryItems() {
        let a = CatalogSumSnap()
        var b = CatalogSumSnap(category: "Mobilfunk & Internet", noticeText: "60", noticeUnit: .days, cancelTerm: .monthEnd, cancelChannel: .online,
                               web: "https://www.swisscom.ch", cancelURL: "https://www.swisscom.ch/kuendigen", tel: "0800 800 800",
                               mail: "info@swisscom.ch", address: ["Swisscom (Schweiz) AG", "Postfach", "3050 Bern"], mandatory: false, noCancel: false)
        let it = CatalogCard.items(a, b)
        XCTAssertEqual(it.map { $0.field + " · " + $0.value }, [
            "Kategorie · Mobilfunk & Internet", "Kündigungsfrist · 60 Tage · Monatsende", "Kündigungsweg · online", "Website · swisscom.ch",
            "Kündigungslink · swisscom.ch", "Telefon · 0800 800 800", "E-Mail · info@swisscom.ch", "Adresse · 3050 Bern"])
        b = CatalogSumSnap(noticeText: "10", noticeUnit: .dayOfMonth, fixedTerm: true, renewMonths: 12, cancelTerm: .monthEnd, mandatory: true, noCancel: true)
        XCTAssertEqual(CatalogCard.items(a, b).map { $0.field + " · " + $0.value },
                       ["Kündigungsfrist · bis zum 10.", "Mindestlaufzeit · mit Verlängerung", "Pflichtvertrag · ja", "Nicht kündbar · ja"])
        XCTAssertEqual(CatalogCard.items(a, a), [])
        XCTAssertEqual(CatalogCard.subtitle(1), "1 Angabe aus dem Kontivo-Katalog")
        XCTAssertEqual(CatalogCard.subtitle(4), "4 Angaben aus dem Kontivo-Katalog")
    }

    // MARK: Preisverlauf als Zeitstrahl

    func testPriceTimeline() {
        let today = Day(2026, 10, 3)
        let ps = [PriceChange(from: Day(2027, 1, 1), amount: 66), PriceChange(from: Day(2025, 1, 1), amount: 55)]
        let t = PriceTimelineRules.make(prices: ps, base: 50, start: Day(2024, 1, 1), today: today, income: false)
        XCTAssertTrue(t.on)
        XCTAssertEqual(t.rows.map { $0.dateText }, ["ab 01.01.27", "ab 01.01.25"])
        XCTAssertEqual(t.rows.map { $0.subText }, ["geplant · +20 %", "aktuell · +10 %"])
        XCTAssertEqual(t.rows.map { $0.pctTone }, [.up, .up])
        XCTAssertEqual(t.startLabel, "ab 01.01.24")
        XCTAssertEqual(t.startSub, "Anfangspreis")
        XCTAssertFalse(t.startIsCurrent)
        // Einnahme: mehr = grün; ohne Beginn «Anfangsbetrag»; nur geplant → Startzeile aktuell
        let i = PriceTimelineRules.make(prices: [PriceChange(from: Day(2027, 1, 1), amount: 4800)], base: 5000, start: nil, today: today, income: true)
        XCTAssertEqual(i.startLabel, "Anfangsbetrag")
        XCTAssertEqual(i.startSub, "")
        XCTAssertTrue(i.startIsCurrent)
        XCTAssertEqual(i.rows.first?.pctTone, .up)
        XCTAssertEqual(i.rows.first?.subText, "geplant · \u{2212}4 %")
        // ohne Änderungen: einfache Zeile «Betrag» bzw. «Betrag netto»
        let n = PriceTimelineRules.make(prices: [], base: 10, start: Day(2024, 1, 1), today: today, income: false)
        XCTAssertFalse(n.on)
        XCTAssertEqual(n.startLabel, "Betrag")
        XCTAssertEqual(PriceTimelineRules.make(prices: [], base: 10, start: nil, today: today, income: true).startLabel, "Betrag netto")
        // ohne Anfangspreis keine Prozentangabe
        XCTAssertNil(PriceTimelineRules.make(prices: ps, base: 0, start: nil, today: today, income: false).rows.last?.pctText)
    }

    func testPriceTimelineEdits() {
        XCTAssertEqual(PriceTimelineRules.editAmount("1’234.567"), .amount(1234.57))
        XCTAssertEqual(PriceTimelineRules.editAmount("1.234,50"), .amount(1234.5))
        XCTAssertEqual(PriceTimelineRules.editAmount(""), .reject("Betrag fehlt – zum Entfernen × tippen"))
        XCTAssertEqual(PriceTimelineRules.editAmount("abc"), .reject("Betrag prüfen"))
        let ps = [PriceChange(from: Day(2025, 1, 1), amount: 55), PriceChange(from: Day(2026, 1, 1), amount: 60)]
        XCTAssertEqual(PriceTimelineRules.editDate(Day(2023, 6, 1), old: Day(2025, 1, 1), start: Day(2024, 1, 1), prices: ps),
                       .reject("Datum muss nach dem Beginn liegen"))
        XCTAssertEqual(PriceTimelineRules.editDate(Day(2026, 1, 1), old: Day(2025, 1, 1), start: nil, prices: ps),
                       .reject("Am 1. Januar 2026 gibt es schon eine Änderung"))
        XCTAssertEqual(PriceTimelineRules.editDate(Day(2025, 1, 1), old: Day(2025, 1, 1), start: nil, prices: ps), .keep)
        let e = PriceTimelineRules.editDate(Day(2025, 3, 1), old: Day(2025, 1, 1), start: nil, prices: ps)
        XCTAssertEqual(PriceTimelineRules.apply(e, to: Day(2025, 1, 1), in: ps).map { $0.from }, [Day(2025, 3, 1), Day(2026, 1, 1)])
        XCTAssertEqual(PriceTimelineRules.apply(.amount(70), to: Day(2026, 1, 1), in: ps).map { $0.amount }, [55, 70])
    }

    func testPriceChartNearLabels() {
        var d = AppData.initial()
        let c = Contract(label: "n", amount: 50, cycle: 1, start: Day(2023, 1, 1),
                         prices: [PriceChange(from: Day(2025, 6, 1), amount: 55), PriceChange(from: Day(2026, 9, 1), amount: 60),
                                  PriceChange(from: Day(2026, 11, 1), amount: 65)])
        d.contracts = [c]
        let ch = Calc(data: d, today: Day(2026, 10, 3)).priceChart(c)
        XCTAssertEqual(ch?.points.filter { $0.labeled }.map { $0.valueText }, ["50.00", "55.00", "60.00", "65.00"])
        XCTAssertEqual(ch?.points.map { $0.anchor }, [.middle, .middle, .end, .start])
    }
}

extension CoreUiCTests {
    /// C25: automatisch angehängte Länderzeile wird nicht als Adresse gespeichert
    func testLetterAddressToSave() {
        let to = ["Swisscom", "Swisscom (Schweiz) AG", "3050 Bern", "SCHWEIZ"]
        XCTAssertEqual(Letter.addressToSave(to, partnerName: "Swisscom", countryLine: "SCHWEIZ"), "Swisscom (Schweiz) AG\n3050 Bern")
        XCTAssertEqual(Letter.addressToSave(to, partnerName: "Swisscom", countryLine: ""), "Swisscom (Schweiz) AG\n3050 Bern\nSCHWEIZ")
        XCTAssertEqual(Letter.addressToSave(["SCHWEIZ"], partnerName: "X", countryLine: "SCHWEIZ"), "SCHWEIZ")
    }
}

extension CoreUiCTests {
    /// Logo-Suche ohne Netz: kürzer suchen (v294), Website raten (d6fc9de), festes Apple-Logo (baab11e), Profilbild (v292)
    func testLogoShortenAndGuess() {
        func s(_ n: String) -> [String] { let x = LogoQuery.shorten(n); return [x.words.joined(separator: "|"), x.amt ? "amt" : "", x.variants.joined(separator: "|")] }
        XCTAssertEqual(s("Raiffeisen Pensionskasse AG"), ["Raiffeisen|Pensionskasse", "", "Raiffeisen Pensionskasse|Raiffeisen"])
        XCTAssertEqual(s("Stadtverwaltung Kreuzlingen"), ["Stadtverwaltung|Kreuzlingen", "amt", ""])
        XCTAssertEqual(s("Energie Kreuzlingen"), ["Kreuzlingen", "amt", ""])
        XCTAssertEqual(s("Protekta Rechtsschutz-Versicherung AG"), ["Protekta|Rechtsschutz-Versicherung", "", "Protekta Rechtsschutz-Versicherung|Protekta"])
        XCTAssertEqual(s("Schweizerische Mobiliar Versicherungsgesellschaft AG"), ["Mobiliar", "", "Mobiliar"])
        XCTAssertEqual(s("Kita Sonnenschein GmbH"), ["Kita|Sonnenschein", "", "Kita Sonnenschein"])
        XCTAssertEqual(s("Sunrise"), ["Sunrise", "", ""])
        XCTAssertEqual(s("Gemeinde Tägerwilen"), ["Gemeinde|Tägerwilen", "amt", ""])
        XCTAssertEqual(s("Fitness Park Konstanz"), ["Fitness|Park|Konstanz", "", ""])
        XCTAssertEqual(s("Allianz Suisse"), ["Allianz", "", "Allianz"])

        func g(_ n: String, _ c: Currency = .CHF, short: Bool = true) -> [String] {
            LogoQuery.guessDomains(n, currency: c, shortening: short ? LogoQuery.shorten(n) : nil)
        }
        XCTAssertEqual(g("Protekta Rechtsschutz-Versicherung AG"), ["protekta.ch", "protekta.com", "protekta.de",
                                                                    "protektarechtsschutz.ch", "protektarechtsschutz.com", "protektarechtsschutz.de"])
        XCTAssertEqual(g("Gemeinde Tägerwilen", .EUR), ["gemeindetagerwilen.de", "gemeindetagerwilen.com", "gemeindetagerwilen.ch"])
        XCTAssertEqual(g("Schweizerische Mobiliar Versicherungsgesellschaft AG").prefix(4).map { $0 },
                       ["mobiliar.ch", "mobiliar.com", "mobiliar.de", "schweizerischemobiliar.ch"])
        XCTAssertEqual(g("Raiffeisen Pensionskasse AG", short: false).first, "raiffeisenpensionskasse.ch")
        XCTAssertTrue(LogoQuery.shouldGuess(knownDomain: "", manual: false, bestScore: 2.5))
        XCTAssertFalse(LogoQuery.shouldGuess(knownDomain: "", manual: false, bestScore: 3))
        XCTAssertTrue(LogoQuery.shouldGuess(knownDomain: "", manual: true, bestScore: 6))
        XCTAssertFalse(LogoQuery.shouldGuess(knownDomain: "x.ch", manual: true, bestScore: 0))
    }

    func testLogoPinAndSocial() {
        for n in ["Apple", "apple.com bill", "iCloud+", "Apple Music Familie"] { XCTAssertEqual(LogoQuery.pin(name: n)?.title, "Apple Inc.", n) }
        XCTAssertNil(LogoQuery.pin(name: "Applebee"))
        XCTAssertNil(LogoQuery.pin(name: "Netflix"))
        XCTAssertNotNil(LogoQuery.pin(name: "Foo", web: "https://www.apple.com/de"))
        // Website bekannt: nur der Eintrag mit dieser Website; passende Website ersetzt einen früheren Treffer
        XCTAssertFalse(LogoQuery.takeSocial(hasCurrent: false, currentDomOk: false, handles: 1, exactOrg: true, domOk: false, domKnown: true))
        XCTAssertTrue(LogoQuery.takeSocial(hasCurrent: false, currentDomOk: false, handles: 1, exactOrg: true, domOk: false, domKnown: false))
        XCTAssertFalse(LogoQuery.takeSocial(hasCurrent: true, currentDomOk: false, handles: 2, exactOrg: true, domOk: false, domKnown: false))
        XCTAssertTrue(LogoQuery.takeSocial(hasCurrent: true, currentDomOk: false, handles: 1, exactOrg: true, domOk: true, domKnown: true))
        XCTAssertFalse(LogoQuery.takeSocial(hasCurrent: false, currentDomOk: false, handles: 1, exactOrg: false, domOk: true, domKnown: true))
        XCTAssertFalse(LogoQuery.takeSocial(hasCurrent: false, currentDomOk: false, handles: 0, exactOrg: true, domOk: true, domKnown: true))
    }
}
