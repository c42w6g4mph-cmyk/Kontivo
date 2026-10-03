import XCTest
@testable import KontivoCore

final class MutationTests: XCTestCase {
    let today = Day(2026, 10, 3)

    func base() -> AppData {
        var data = AppData.initial()
        data.persons = [Person(name: "Sinan", sender: SenderAddress(first: "Sinan", street: "Hauptstr. 1", zip: "8280", city: "Kreuzlingen")),
                        Person(name: "Lara")]
        return data
    }

    func testCancelAndMandatorySwitch() throws {
        var data = base()
        let ins = data.category(named: "Versicherung")!.id
        let pid = data.partnerID(forName: "CSS", web: "css.ch")!
        let c = Contract(label: "Krankenkasse", partnerID: pid, categoryID: ins, amount: 400, cycle: 1, due: Day(2026, 10, 15), notice: 1,
                         cancelTerm: .yearEnd, mandatory: true, customerNo: "1", holderIDs: [data.persons[0].id], cancelChannel: .registered,
                         tel: "058 277 11 11", mail: "kuendigung@css.ch", note: "alt")
        data.contracts = [c]
        let res = try XCTUnwrap(data.markCancelled(c.id, trial: false, today: today))
        XCTAssertEqual(res.cancelPer, Day(2026, 12, 31))
        XCTAssertEqual(res.toast, "Gekündigt — läuft bis 31. Dezember 2026")
        XCTAssertEqual(data.contracts[0].cancelPer, Day(2026, 12, 31))
        XCTAssertEqual(data.contracts[0].cancelledOn, today)
        let nc = try XCTUnwrap(res.replacement)
        XCTAssertNotEqual(nc.id, c.id)
        XCTAssertNil(nc.partnerID)
        XCTAssertEqual(nc.start, Day(2027, 1, 1))
        XCTAssertEqual(nc.due, Day(2027, 1, 1))
        XCTAssertEqual(nc.tel, "")
        XCTAssertEqual(nc.mail, "")
        XCTAssertEqual(nc.note, "")
        XCTAssertNil(nc.cancelChannel)
        XCTAssertNil(nc.cancelPer)
        XCTAssertEqual(res.replacementToast, "Neuen Anbieter erfassen — ab 1. Januar 2027")
        XCTAssertEqual(data.contracts.count, 1)
        data.undoCancel(c.id)
        XCTAssertNil(data.contracts[0].cancelPer)

        // Probeabo: läuft bis Tag vor Probeabo-Ende
        var t = Contract(label: "Probe", amount: 10, due: Day(2026, 10, 20), cancelTerm: .period, trial: Day(2026, 10, 20))
        t.categoryID = ins
        data.contracts.append(t)
        let rt = try XCTUnwrap(data.markCancelled(t.id, trial: true, today: today))
        XCTAssertEqual(rt.cancelPer, Day(2026, 10, 19))
        XCTAssertNil(rt.replacement)
    }

    func testPauseResumeKeepsHistory() throws {
        var data = base()
        let c = Contract(label: "Fitness", amount: 50, cycle: 1, due: Day(2026, 9, 10))
        data.contracts = [c]
        XCTAssertThrowsError(try data.pause(c.id, until: today, today: today))
        try data.pause(c.id, until: nil, today: Day(2026, 9, 1))
        XCTAssertTrue(Calc(data: data, today: today).isPaused(data.contracts[0]))
        data.resume(c.id, today: today)
        XCTAssertEqual(data.contracts[0].pauses, [Pause(from: Day(2026, 9, 1), until: today)])
        let calc = Calc(data: data, today: today)
        XCTAssertFalse(calc.isPaused(data.contracts[0]))
        // September-Zahlung bleibt ausgesetzt, Oktober zählt wieder
        XCTAssertEqual(calc.occurrences(data.contracts[0], from: Day(2026, 9, 1), to: Day(2026, 10, 31)), [Day(2026, 10, 10)])
        try data.pause(c.id, until: Day(2026, 11, 3), today: today)
        data.resume(c.id, today: today)
        XCTAssertEqual(data.contracts[0].pauses.count, 1)
        XCTAssertEqual(AppData.pauseToast(until: nil), "Pausiert — bis du fortsetzt")
        XCTAssertEqual(AppData.pauseOptions(today: today).count, 4)
    }

    func testSaveKeepsStatusFields() throws {
        var data = base()
        let cat = data.categories[0].id
        var c = Contract(label: "Miete", categoryID: cat, amount: 1500, cycle: 1, due: Day(2026, 11, 1), cancelPer: Day(2026, 12, 31),
                         keptFor: Day(2026, 12, 31), pauses: [Pause(from: Day(2026, 8, 1), until: Day(2026, 9, 1))])
        data.contracts = [c]
        c.amount = 1600.004
        c.cancelPer = nil
        c.pauses = []
        try data.saveContract(c, today: today)
        XCTAssertEqual(data.contracts[0].amount, 1600)
        XCTAssertEqual(data.contracts[0].cancelPer, Day(2026, 12, 31))
        XCTAssertEqual(data.contracts[0].pauses.count, 1)
        var bad = c
        bad.categoryID = nil
        XCTAssertThrowsError(try data.saveContract(bad, today: today)) { XCTAssertEqual($0 as? MutationError, .missingCategory) }
        var noName = Contract(categoryID: cat, amount: 1)
        XCTAssertThrowsError(try data.saveContract(noName, today: today)) { XCTAssertEqual($0 as? MutationError, .missingTitle) }
        noName.label = "Neu"
        noName.holderIDs = [data.persons[1].id]
        let id = try data.saveContract(noName, today: today)
        XCTAssertEqual(data.contract(id)?.due, today)
        XCTAssertEqual(data.settings.lastHolderIDs, [data.persons[1].id])
        XCTAssertEqual(data.defaultHolderIDs, [data.persons[1].id])
        let dup = try XCTUnwrap(data.duplicateDraft(data.contracts[0].id))
        XCTAssertNil(dup.cancelPer)
        XCTAssertEqual(dup.pauses, [])
        XCTAssertEqual(dup.label, "Miete")
    }

    func testPersons() throws {
        var data = base()
        let s = data.persons[0].id
        let l = data.persons[1].id
        data.persons[1].sameAddressAs = s
        data.contracts = [Contract(label: "A", holderIDs: [s, l]), Contract(label: "B", holderIDs: [s]), Contract(label: "C", holderIDs: [l])]
        XCTAssertThrowsError(try data.addPerson("sinan")) { XCTAssertEqual($0 as? MutationError, .duplicateName(s)) }
        XCTAssertThrowsError(try data.renamePerson(l, to: "SINAN")) { XCTAssertEqual($0 as? MutationError, .duplicateName(s)) }
        try data.renamePerson(l, to: "  Lara   Muster ")
        XCTAssertEqual(data.person(l)?.name, "Lara Muster")
        XCTAssertTrue(data.applyHolderChoice(contract: data.contracts[1].id, choice: .all))
        XCTAssertEqual(data.contracts[1].holderIDs, [s, l])
        XCTAssertEqual(data.holderChoiceToast(title: "B", holderIDs: [s, l]), "B → Beide")
        XCTAssertTrue(data.applyHolderChoice(contract: data.contracts[1].id, choice: .person(l)))
        XCTAssertEqual(data.contracts[1].holderIDs, [l])
        // Übertragen: gemeinsame bleiben gemeinsam
        XCTAssertEqual(data.transferAll(from: l, to: s), 2)
        XCTAssertEqual(data.contracts[0].holderIDs, [s, l])
        XCTAssertEqual(data.contracts[1].holderIDs, [s])
        // Löschen ohne Ziel: Adresse wird kopiert
        let x = try data.addPerson("Max")
        data.persons[data.personIndex(x)!].sameAddressAs = s
        try data.deletePerson(s, transferTo: nil)
        XCTAssertNil(data.person(s))
        XCTAssertEqual(data.person(x)?.sender.street, "Hauptstr. 1")
        XCTAssertNil(data.person(x)?.sameAddressAs)
        XCTAssertEqual(data.contracts[0].holderIDs, [l])
        // Zusammenführen
        data.mergePerson(x, into: l)
        XCTAssertNil(data.person(x))
        XCTAssertEqual(data.person(l)?.sender.street, "Hauptstr. 1")
        XCTAssertThrowsError(try data.deletePerson(l, transferTo: nil)) { XCTAssertEqual($0 as? MutationError, .lastPerson) }
    }

    func testCategoriesAndPartners() throws {
        var data = base()
        let other = data.otherCategory!.id
        let id = try data.addCategory("Haustier")
        XCTAssertEqual(data.categories.last?.icon, "tag")
        XCTAssertEqual(data.categories.last?.colorHex, Category.palette[(12 + 3) % 8])
        XCTAssertThrowsError(try data.addCategory("haustier"))
        XCTAssertThrowsError(try data.renameCategory(other, to: "Rest")) { XCTAssertEqual($0 as? MutationError, .fixedCategory) }
        let ins = data.category(named: "Versicherung")!.id
        try data.renameCategory(ins, to: "Versicherungen")
        XCTAssertEqual(data.category(ins)?.kind, .insurance)
        data.contracts = [Contract(label: "Hund", categoryID: id)]
        try data.deleteCategory(id)
        XCTAssertEqual(data.contracts[0].categoryID, other)
        data.moveCategory(from: 0, to: 2)
        XCTAssertEqual(data.categories[2].name, "Wohnen")
        data.moveCategories(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        XCTAssertEqual(data.categories[0].name, "Wohnen")

        let a = data.partnerID(forName: "Swisscom")!
        let b = data.partnerID(forName: "Swisscom (Schweiz) AG")!
        XCTAssertEqual(a, b)
        let c = data.partnerID(forName: "Salt")!
        data.setPartnerAddress(c, PostalAddress(company: "Salt Mobile SA", street: "Rue du Caudray 4", zip: "1020", city: "Renens"))
        data.setPartnerLogo(c, logoID: "x", background: nil)
        data.contracts = [Contract(label: "Handy", partnerID: a), Contract(label: "Abo", partnerID: c)]
        XCTAssertThrowsError(try data.renamePartner(a, to: "salt")) { XCTAssertEqual($0 as? MutationError, .duplicateName(c)) }
        XCTAssertEqual(data.mergePartners([c], into: a), 1)
        XCTAssertEqual(data.partners.count, 1)
        XCTAssertEqual(data.partners[0].logoID, "x")
        XCTAssertEqual(data.partners[0].address.city, "Renens")
        XCTAssertEqual(data.contracts[1].partnerID, a)
        data.contracts = []
        XCTAssertEqual(data.pruneUnusedPartners(), 1)
    }

    func testDeadlinesAndHero() {
        var data = base()
        let cat = data.categories[0].id
        let s = data.persons[0].id
        data.contracts = [
            Contract(label: "Fitness", categoryID: cat, amount: 600, cycle: 12, due: Day(2027, 1, 1), end: Day(2026, 12, 31), notice: 1, renewMonths: 12, holderIDs: [s]),
            Contract(label: "Netflix", categoryID: cat, amount: 18.9, currency: .EUR, cycle: 1, due: Day(2026, 10, 15), cancelTerm: .monthEnd, holderIDs: [s]),
            Contract(label: "Probe", categoryID: cat, amount: 12.95, cycle: 1, due: Day(2026, 10, 20), cancelTerm: .period, holderIDs: [s], trial: Day(2026, 10, 20)),
        ]
        let calc = Calc(data: data, today: Day(2026, 10, 3))
        let o = calc.deadlineOverview()
        // Seit 04.10.2026: Entscheidung erst 30 Tage vor der Frist, «dringend» ab 7 Tagen
        XCTAssertEqual(o.openCount, 1)
        XCTAssertEqual(o.decisions.map { $0.trial }, [true])
        XCTAssertEqual(o.decisions[0].line, "Probeabo endet 20.10. · noch 17 Tage")
        XCTAssertEqual(o.headerBold, "1 offen")
        XCTAssertEqual(o.headerRest, " · nächste Frist in 17 Tagen")
        XCTAssertEqual(o.upcoming.map { $0.text }, ["Frist 30.11.26"])
        XCTAssertEqual(o.anytime.map { $0.text }, ["nächste Frist 31.10.", "zum Periodenende"])
        XCTAssertEqual(calc.deadlineBadgeCount, 1)
        // 58 Tage vor der Frist: Entscheidung ja, sobald ≤ 30 Tage
        let later = Calc(data: data, today: Day(2026, 11, 1))
        XCTAssertTrue(later.needsAction(data.contracts[0]))
        XCTAssertEqual(later.urgency(data.contracts[0]).level, .warn)
        XCTAssertEqual(Calc(data: data, today: Day(2026, 11, 24)).urgency(data.contracts[0]).level, .alert)
        let h = calc.hero()
        XCTAssertEqual(h.activeCount, 3)
        XCTAssertEqual(h.monthlyTotal, 50 + 18.9 * 0.94 + 12.95, accuracy: 1e-9)
        XCTAssertTrue(h.subtitle.hasSuffix(" CHF pro Jahr · 3 aktive Verträge"))
        let y = calc.costYear(2026, filter: Calc.CostFilter())
        XCTAssertEqual(y.months[9].items.count, 2)
        XCTAssertEqual(y.months[11].sum, 18.9 * 0.94 + 12.95, accuracy: 1e-9)
        let b = calc.budgetYear(2026, person: s)
        XCTAssertEqual(b.months[11].fixed, 18.9 * 0.94 + 12.95, accuracy: 1e-9)
    }

    func testLetter() {
        var data = base()
        let s = data.persons[0].id
        let l = data.persons[1].id
        data.persons[1].sender = SenderAddress(first: "Lara", last: "Muster")
        data.persons[1].sameAddressAs = s
        let housing = data.category(named: "Wohnen")!.id
        let pid = data.partnerID(forName: "Wincasa AG")!
        data.setPartnerAddress(pid, PostalAddress(company: "Wincasa AG", street: "Postfach", zip: "8401", city: "Winterthur"))
        let c = Contract(label: "Mietvertrag Wohnung", partnerID: pid, categoryID: housing, amount: 1800, cycle: 1, due: Day(2026, 11, 1),
                         notice: 3, cancelTerm: .quarterEnd, customerNo: "4711", holderIDs: [s, l])
        data.contracts = [c]
        let calc = Calc(data: data, today: today)
        XCTAssertTrue(calc.isRent(c))
        XCTAssertEqual(calc.cancVia(c), .post)
        let p = Letter.parts(c, calc: calc)
        XCTAssertEqual(p.signers, [s, l])
        XCTAssertEqual(p.names, ["Sinan", "Lara Muster"])
        XCTAssertEqual(p.sender, ["Sinan und Lara Muster", "Hauptstr. 1", "8280 Kreuzlingen"])
        XCTAssertEqual(p.to, ["Wincasa AG", "Postfach", "8401 Winterthur"])
        XCTAssertEqual(p.subject, "Kündigung Mietvertrag Wohnung bei Wincasa AG")
        XCTAssertEqual(p.references, ["Kundennummer: 4711"])
        XCTAssertEqual(p.city, "Kreuzlingen")
        XCTAssertTrue(p.body.hasPrefix("Sehr geehrte Damen und Herren\n\nhiermit kündigen wir den oben genannten Vertrag ordentlich zum nächstmöglichen Termin, nach unserer Berechnung zum 31. März 2027."))
        XCTAssertTrue(p.body.hasSuffix("Bitte bestätigen Sie uns die Kündigung und das Vertragsende schriftlich.\n\nFreundliche Grüsse"))
        XCTAssertEqual(p.bodyText, "Kundennummer: 4711\n\n" + p.body)
        let h = Letter.hints(c, parts: p, calc: calc)
        XCTAssertEqual(h.first, "Muss spätestens am 31. Dezember 2026 beim Vertragspartner sein.")
        XCTAssertTrue(h.contains("Mietverträge verlangen Schriftform mit eigenhändiger Unterschrift (CH Art. 266l OR, DE § 568 BGB)."))
        XCTAssertEqual(h.last, "Vorlage ohne Gewähr. Prüf Adresse, Frist und die im Vertrag verlangte Form.")
        let single = Letter.parts(c, signers: [s], calc: calc)
        XCTAssertTrue(single.body.contains("kündige ich"))
        XCTAssertTrue(Letter.hints(c, parts: single, calc: calc).contains("Gemeinsamer Vertrag: In der Regel müssen alle Vertragsparteien kündigen."))
        XCTAssertEqual(Letter.pdfFileName(c, data: data, today: today), "Kuendigung-Wincasa_AG-2026-10-03.pdf")
        XCTAssertEqual(Letter.fileSafe("Zürich Versicherung"), "Zuerich_Versicherung")
        XCTAssertEqual(Letter.splitReferences("Kundennummer: 1\nVertragsnummer: 2\n\nText").references.count, 2)
        XCTAssertEqual(Letter.mailText(references: ["Kundennummer: 1"], body: "Text", names: ["A"], sender: ["A", "Str. 1"]), "Kundennummer: 1\n\nText\n\nA\nStr. 1")
        XCTAssertTrue(Letter.isRentHeuristic(label: "Routermiete", partner: "", kind: nil))
        XCTAssertTrue(Letter.isRentHeuristic(label: "Zimmer", partner: "", kind: .housing))
        XCTAssertFalse(Letter.isRentHeuristic(label: "Zimmer", partner: "", kind: nil))
    }

    func testCatalog() {
        XCTAssertEqual(Catalog.entries.count, 98)
        let css = Catalog.find(" css ")
        XCTAssertEqual(css?.cancelTerm, .yearEnd)
        XCTAssertEqual(css?.cancelChannel, .registered)
        XCTAssertEqual(css?.mandatory, true)
        XCTAssertEqual(css?.categoryKind, .insurance)
        XCTAssertEqual(Catalog.find("Serafe")?.cancelChannel, nil)
        XCTAssertEqual(Catalog.find("Deutschlandticket")?.noticeUnit, .dayOfMonth)
        XCTAssertEqual(Catalog.find("Netflix")?.flag, "CH · DE")
        XCTAssertEqual(Catalog.search("", country: "DE").filter { $0.country == "CH" }.count, 0)
        XCTAssertFalse(Catalog.suggestions("swi").isEmpty)
        XCTAssertEqual(Catalog.entry(forDomain: "www.apple.com")?.name, "Apple One")
        let names = Category.standardNames
        let hit = WebPartnerHit(name: "Muster Versicherung", desc: "Schweizer Versicherungsgesellschaft", descAll: "Schweizer Versicherungsgesellschaft insurance company", dom: "muster.ch", cc: "CH")
        let t = Catalog.standardRule(for: hit, categoryNames: names)
        XCTAssertEqual(t?.category, "Versicherung")
        XCTAssertEqual(t?.notice, 3)
        XCTAssertEqual(t?.cancelTerm, .contractYear)
        let gkv = WebPartnerHit(name: "BKK Test", desc: "gesetzliche Krankenkasse", descAll: "gesetzliche Krankenkasse", dom: "bkk.de", cc: "DE")
        XCTAssertEqual(Catalog.standardRule(for: gkv, categoryNames: names)?.notice, 2)
        let bank = WebPartnerHit(name: "Testbank", desc: "Bank", descAll: "Bank bank", dom: "testbank.ch", cc: "")
        XCTAssertEqual(Catalog.standardRule(for: bank, categoryNames: names)?.category, "Finanzen")
        XCTAssertNil(Catalog.standardRule(for: WebPartnerHit(name: "Bäckerei", descAll: "Bäckerei"), categoryNames: names))
        XCTAssertEqual(Catalog.template(for: WebPartnerHit(name: "Swisscom AG", dom: "swisscom.ch", cc: "CH"), categoryNames: names)?.name, "Swisscom AG")
    }
}
