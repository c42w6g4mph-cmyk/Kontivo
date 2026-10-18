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

    // MARK: Katalog v210–v224 (Werte aus der Web-App gemessen, Formularwährung CHF)

    func testCatalogSameNames() {
        XCTAssertEqual(Catalog.entries.count, 572)
        XCTAssertEqual(Set(Catalog.entries.map { $0.id }).count, Catalog.entries.count, "id eindeutig")
        XCTAssertEqual(Catalog.all("CSS", currency: .CHF).map { $0.label }, ["Krankenkasse", "Zusatzversicherung"])
        XCTAssertEqual(Catalog.all("John Reed", currency: .EUR).map { $0.country + $0.label }, ["DEFitnessabo"])
        XCTAssertEqual(Catalog.all("John Reed", currency: .CHF).map { $0.country + $0.label }, ["CHFitnessabo"])
        // Bezeichnung entscheidet, übernommener Eintrag geht vor
        XCTAssertEqual(Catalog.find("CSS", currency: .CHF)?.label, "Krankenkasse")
        XCTAssertEqual(Catalog.find("css", currency: .CHF, label: "zusatzversicherung")?.label, "Zusatzversicherung")
        let zv = Catalog.all("CSS", currency: .CHF)[1]
        XCTAssertEqual(Catalog.find("CSS", currency: .CHF, label: "Krankenkasse", preferred: zv), zv)
        XCTAssertEqual(Catalog.find("CSS", currency: .CHF)?.mandatory, true)
        XCTAssertEqual(zv.mandatory, false)
    }

    func testCatalogHits() {
        func row(_ q: String) -> [String] {
            Catalog.hits(q, currency: .CHF).entries.map { $0.name + "|" + $0.country + "|" + $0.label + "|" + Catalog.hitSubtitle($0, currency: .CHF) }
        }
        XCTAssertEqual(row("css"), ["CSS|CH|Krankenkasse|Krankenkasse · Schweiz · Pflichtvertrag",
                                    "CSS|CH|Zusatzversicherung|Zusatzversicherung · Schweiz · 3 Monate Frist"])
        XCTAssertEqual(row("sun"), ["Sunrise|CH|Handy / Internet|Handy / Internet · 2 Monate Frist",
                                    "IKK gesund plus|DE|Krankenkasse|Krankenkasse · Pflichtvertrag",
                                    "BIG direkt gesund|DE|Krankenkasse|Krankenkasse · Pflichtvertrag"])
        XCTAssertEqual(row("rundfunk"), ["Rundfunkgebühr|CH|Rundfunkgebühr|Rundfunkgebühr · nicht kündbar"])
        XCTAssertEqual(row("john reed"), ["John Reed|DE|Fitnessabo|Fitnessabo · 1 Monat Frist", "John Reed|CH|Fitnessabo|Fitnessabo · 2 Wochen Frist"])
        XCTAssertEqual(row("ab"), ["SBB GA|CH|Generalabonnement|Generalabonnement · 1 Monat Frist",
                                   "Update Fitness|CH|Fitnessabo|Fitnessabo · 4 Wochen Frist",
                                   "Activ Fitness|CH|Fitnessabo|Fitnessabo · 2 Monate Frist"])
        XCTAssertTrue(Catalog.hits("ab", currency: .CHF).hasMore)
        XCTAssertFalse(Catalog.hits("css", currency: .CHF).hasMore)
        XCTAssertEqual(Catalog.hits("ab", currency: .CHF, more: true).entries.count, 8)
        XCTAssertFalse(Catalog.hits("ab", currency: .CHF, more: true).hasMore)
        XCTAssertTrue(Catalog.hits("s", currency: .CHF).entries.isEmpty)
        XCTAssertEqual(Catalog.hitDomains(Catalog.hits("css", currency: .CHF).entries), ["css.ch"])
    }

    func testPhoneChannel() throws {
        XCTAssertEqual(Array(Catalog.entries.filter { $0.cancelChannel == .phone }.map { $0.name }.prefix(6)),
                       ["Swisscom", "Sunrise", "Salt", "Wingo", "Yallo", "Coop Mobile"])
        XCTAssertEqual(CancelChannel(webText: "Telefon"), .phone)
        XCTAssertEqual(CancelChannel.phone.webText, "Telefon")
        XCTAssertEqual(CancelVia.tel.jsValue, "tel")
        // Web-Backup → Vertrag mit Kündigungsweg Telefon, cancVia «tel», kein Absender nötig (vkNeeds v210)
        let json = #"{"app":"vertraege","settings":{"home":"CHF","holders":["Ich"]},"contracts":{"k":{"partner":"Sunrise","label":"Handy","cat":"Mobilfunk & Internet","amount":40,"cur":"CHF","cycle":1,"cancF":"Telefon","tel":"+41 800 707 707","holders":["Ich"]}},"incomes":{}}"#
        let r = try WebImport.importBackup(Data(json.utf8), today: Day(2026, 10, 17))
        let c = r.data.contracts[0]
        XCTAssertEqual(c.cancelChannel, .phone)
        let calc = Calc(data: r.data, today: Day(2026, 10, 17))
        XCTAssertEqual(calc.cancVia(c), .tel)
        XCTAssertFalse(Completeness.senderNeeded(c, calc: calc))
        XCTAssertEqual(calc.detailMenu(c).cancel?.subtitle, "Weg wählen")
        // CSV-Rundlauf
        XCTAssertEqual(CSV.via("Telefon"), .phone)
        // natives Format
        let back = try KontivoJSON.makeDecoder().decode(Contract.self, from: KontivoJSON.makeEncoder().encode(c))
        XCTAssertEqual(back.cancelChannel, .phone)
    }

    func testCatalogTermShort() {
        XCTAssertEqual(Catalog.find("Rundfunkgebühr", currency: .CHF)?.termShort, "nicht kündbar")
        XCTAssertEqual(Catalog.find("Netflix")?.termShort, "jederzeit kündbar")
        XCTAssertEqual(Catalog.find("Swisscom")?.termShort, "60 Tage Frist")
        XCTAssertEqual(Catalog.find("CSS", currency: .CHF)?.termShort, "Pflichtvertrag")
    }

    // MARK: v165/v190 Farben, v179/v180 Person merken

    func testCategoryColors() {
        XCTAssertEqual(Category.standardColors["Versicherung"], "#2F7F7A")
        XCTAssertEqual(Category.palette[0], "#4A5A66")
        // gespeicherte alte Standardfarbe (auch altes Türkis) → neue Standardfarbe; eigene Farbe bleibt
        XCTAssertEqual(Category(name: "Versicherung", colorHex: "#0E5A5E", kind: .insurance).displayColorHex, "#2F7F7A")
        XCTAssertEqual(Category(name: "Wohnen", colorHex: "#6B4E9E", kind: .housing).displayColorHex, "#6A4FB3")
        XCTAssertEqual(Category(name: "Meine Wohnung", colorHex: "#6B4E9E", kind: .housing).displayColorHex, "#6A4FB3")
        XCTAssertEqual(Category(name: "Haustier", colorHex: "#2F86A6").displayColorHex, "#3F6E9A")
        XCTAssertEqual(Category(name: "Haustier", colorHex: "#123456").displayColorHex, "#123456")
        XCTAssertEqual(Category(name: "Haustier", colorHex: "rot").displayColorHex, "#6B7280")
        XCTAssertEqual(IncomeKind.nebeneinkommen.colorHex, "#4A5A66")
    }

    func testRememberSinglePerson() throws {
        var d = AppData.initial()
        let a = d.persons[0].id
        let b = Person(name: "Lara")
        d.persons.append(b)
        d.settings.lastHolderIDs = []
        let cat = d.categories[0].id
        let t = Day(2026, 10, 17)
        _ = try d.saveContract(Contract(label: "Beide", categoryID: cat, amount: 10, holderIDs: [a, b.id]), today: t)
        XCTAssertEqual(d.settings.lastHolderIDs, [], "«Beide» wird nicht gemerkt (Web v180)")
        _ = try d.saveContract(Contract(label: "Lara", categoryID: cat, amount: 10, holderIDs: [b.id]), today: t)
        XCTAssertEqual(d.settings.lastHolderIDs, [b.id])
        XCTAssertEqual(d.defaultHolderIDs, [b.id])
        d.settings.lastHolderIDs = [a, b.id]
        XCTAssertEqual(d.defaultHolderIDs, [a], "zwei gemerkte → erste Person (Web bkHolders)")
    }
}
