import XCTest
@testable import KontivoCore

/// Vollständigkeit (Web vkNeeds/vkTermNeed/vkAutoPlan/vkPct, v120–v134). Erwartungswerte aus der Web-App (index.html v141)
/// mit demselben Test-Backup gemessen: «5 offen», «Noch 4 kurze Fragen», «✓ 1 Vertrag ergänzt …», «Los geht’s · ca. 1 Minute»,
/// Fragen: Logos (4 Vertragspartner), Fristen Fitnesspark und Online Shop Abo, Adresse von Lara.
final class CompletenessTests: XCTestCase {
    static let backup = """
    {"app":"vertraege","settings":{"home":"CHF","rates":{"EUR":0.94},"holders":["Sinan","Lara"],
     "senders":{"Sinan":{"first":"Sinan","last":"Muster","street":"Seestrasse 1","zip":"8280","city":"Kreuzlingen"}}},
     "contracts":{
      "c1":{"partner":"Swisscom","label":"Handy","cat":"Mobilfunk & Internet","amount":59.9,"cur":"CHF","cycle":1,"due":"2026-10-15","notice":2,"noticeU":"m","cancTerm":"m","holders":["Sinan"],"status":"active"},
      "c2":{"partner":"Fitnesspark Muster","label":"Abo","cat":"Freizeit & Sport","amount":89,"cur":"CHF","cycle":1,"due":"2026-10-15","end":"2027-03-31","renew":12,"notice":0,"noticeU":"m","holders":["Lara"],"status":"active"},
      "c3":{"partner":"Kanton TG","label":"Steuern","cat":"Steuern & Gebühren","amount":1150,"cur":"CHF","cycle":3,"due":"2026-11-30","holders":["Sinan"],"status":"active"},
      "c4":{"partner":"","label":"Miete","cat":"Wohnen","amount":2100,"cur":"CHF","cycle":1,"due":"2026-11-01","notice":3,"noticeU":"m","cancTerm":"q","holders":["Lara"],"status":"active"},
      "c5":{"partner":"Zattoo","label":"TV","cat":"Abos & Medien","amount":15,"cur":"CHF","cycle":1,"due":"2026-10-15","status":"cancelled","cancelledAt":"2026-06-30","holders":["Sinan"]},
      "c6":{"partner":"Online Shop Abo","label":"Box","cat":"Abos & Medien","amount":20,"cur":"EUR","cycle":1,"due":"2026-10-20","notice":0,"noticeU":"m","cancTerm":"","holders":["Sinan","Lara"],"cancF":"Online / Kundenkonto","status":"active"}
     },"incomes":{}}
    """
    let today = Day(2026, 10, 3)

    func load() throws -> WebImportResult {
        try WebImport.importBackup(Data(CompletenessTests.backup.utf8), today: today)
    }

    override func setUp() {
        super.setUp()
        Format.homeCurrency = .CHF
    }

    func testReportLikeWeb() throws {
        let r = try load()
        let d = r.data
        let id = { (k: String) in r.contractIDs[k]! }
        let rep = Completeness.report(d, today: today)
        XCTAssertEqual(rep.total, 5)
        XCTAssertEqual(rep.ready, 0)
        XCTAssertEqual(rep.open, 5)
        XCTAssertEqual(rep.percent, 0)
        XCTAssertEqual(rep.logoPartners.compactMap { d.partner($0)?.name }, ["Swisscom", "Fitnesspark Muster", "Kanton TG", "Online Shop Abo"])
        XCTAssertEqual(rep.termContracts, [id("c2"), id("c6")])
        XCTAssertEqual(rep.senderPersons.compactMap { d.person($0)?.name }, ["Lara"])
        XCTAssertEqual(rep.per[id("c1")], [.logo])
        XCTAssertEqual(rep.per[id("c2")], [.logo, .term, .sender])
        XCTAssertEqual(rep.per[id("c3")], [.logo])
        XCTAssertEqual(rep.per[id("c4")], [.sender])
        XCTAssertEqual(rep.per[id("c6")], [.logo, .term])
        XCTAssertNil(rep.per[id("c5")])
        XCTAssertEqual(rep.questionCount, 4)
        XCTAssertEqual(Completeness.minutes(rep), 1)
        XCTAssertEqual(Completeness.goTitle(rep), "Los geht’s · ca. 1 Minute")
        XCTAssertEqual(Completeness.startHeadline(percent: rep.percent), "Los geht’s!")
        XCTAssertEqual(Completeness.startText(questions: 4), "Noch **4 kurze Fragen**, dann behält Kontivo jede Frist im Blick und bereitet Kündigungen für dich vor.")
        XCTAssertEqual(Completeness.badge(rep), "5 offen")
        XCTAssertEqual(Completeness.accessibilityLabel(rep), "Vollständigkeit: 5 Verträge noch nicht startklar")
        XCTAssertNil(Completeness.gainText(rep, single: false))
        XCTAssertEqual(Completeness.endHeadline(rep, single: false), "0 % – gut gemacht!")
        XCTAssertEqual(Completeness.endText(rep), "Den Rest kannst du jederzeit unter Mehr → Vollständigkeit ergänzen.")

        // Katalog ergänzt still: Swisscom (Adresse, Telefon, Website)
        let plan = Completeness.autoPlan(d, today: today)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(Completeness.autoText(plan.count), "✓ 1 Vertrag ergänzt Kontivo aus dem Anbieter-Katalog")
    }

    func testAutoPlanCancelChannel() {
        var d = AppData.initial()
        let p = Partner(name: "Netflix")
        d.partners = [p]
        d.contracts = [Contract(label: "Streaming", partnerID: p.id, amount: 18.9, currency: .EUR, cycle: 1, cancelTerm: .period)]
        let plan = Completeness.autoPlan(d, today: today)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].cancelChannel, .online)
        d.applyCompletenessAuto(plan)
        XCTAssertEqual(d.contracts[0].cancelChannel, .online)
        XCTAssertTrue(Completeness.autoPlan(d, today: today).isEmpty)
    }

    func testTextsAndHints() throws {
        let r = try load()
        let d = r.data
        let calc = Calc(data: d, today: today)
        let c2 = d.contract(r.contractIDs["c2"])!, c6 = d.contract(r.contractIDs["c6"])!
        XCTAssertEqual(Completeness.termName(c2, data: d), "Fitnesspark Muster")
        XCTAssertEqual(Completeness.termQuestion("Fitnesspark Muster"), "Wie ist «Fitnesspark Muster» kündbar?")
        XCTAssertEqual(Completeness.termWho(c2, calc: calc), "Abo · 89.00 CHF monatlich")
        XCTAssertEqual(Completeness.termWho(c6, calc: calc), "Box · 20,00 EUR monatlich")
        XCTAssertEqual(Completeness.termText(catalog: nil), "Damit Kontivo dich rechtzeitig vor der Frist erinnert.")
        XCTAssertEqual(Completeness.catalogHint(Catalog.find("Swisscom")), "Üblich bei Swisscom: 60 Tage auf Monatsende")
        XCTAssertEqual(Completeness.questionLabel(2, of: 4), "Frage 2 von 4")
        XCTAssertEqual(Completeness.senderQuestion(name: "Lara", personCount: 2), "Adresse von Lara")
        XCTAssertEqual(Completeness.senderQuestion(name: "Ich", personCount: 1), "Deine Adresse")

        let h2 = Completeness.hint(contract: c2.id, data: d, today: today)
        XCTAssertEqual(h2?.title, "3 Angaben fehlen noch")
        XCTAssertEqual(h2?.detail, "Logo · Kündigungsfrist · Absender-Adresse – dann erinnert Kontivo rechtzeitig")
        let h4 = Completeness.hint(contract: r.contractIDs["c4"]!, data: d, today: today)
        XCTAssertEqual(h4?.title, "1 Angabe fehlt noch")
        XCTAssertEqual(h4?.detail, "Absender-Adresse – dann ist die Kündigung startklar")
        XCTAssertEqual(Completeness.hint(contract: r.contractIDs["c3"]!, data: d, today: today)?.detail, "Logo – dann sieht der Vertrag komplett aus")
        XCTAssertNil(Completeness.hint(contract: r.contractIDs["c5"]!, data: d, today: today))

        let single = Completeness.report(d, today: today, only: r.contractIDs["c4"])
        XCTAssertEqual(single.total, 1)
        XCTAssertEqual(Completeness.gainText(single, single: true), "fast startklar")
        XCTAssertEqual(Completeness.endTitle(single: true), "Startklar")
    }

    func testTermDraftDefaults() throws {
        let r = try load()
        let d = r.data
        let c2 = d.contract(r.contractIDs["c2"])!
        let t2 = Completeness.termDraft(c2, data: d)
        XCTAssertEqual(t2.mode, .fixed)
        XCTAssertEqual(t2.end, Day(2027, 3, 31))
        XCTAssertEqual(t2.renew, 12)
        XCTAssertEqual(t2.notice, "")
        XCTAssertNil(Completeness.termDraft(d.contract(r.contractIDs["c6"])!, data: d).mode)

        // Katalog-Vorschlag
        var e = AppData.initial()
        let p = Partner(name: "Swisscom")
        e.partners = [p]
        e.contracts = [Contract(label: "Handy", partnerID: p.id, amount: 59.9, cycle: 1, due: Day(2026, 10, 15))]
        let t = Completeness.termDraft(e.contracts[0], data: e)
        XCTAssertEqual(t.mode, .open)
        XCTAssertEqual(t.notice, "60")
        XCTAssertEqual(t.noticeUnit, .days)
        XCTAssertEqual(t.cancelTerm, .monthEnd)
        XCTAssertEqual(t.renew, 12)
    }

    func testSaveTerm() throws {
        let r = try load()
        var d = r.data
        let c2 = r.contractIDs["c2"]!, c6 = r.contractIDs["c6"]!

        // feste Laufzeit mit Verlängerung braucht eine Frist
        var t = Completeness.termDraft(d.contract(c2)!, data: d)
        XCTAssertEqual(d.saveCompletenessTerm(c2, t, today: today), .invalid(Completeness.noticeMissing))
        XCTAssertEqual(d.contract(c2)?.notice, 0)
        t.notice = "1"
        XCTAssertEqual(d.saveCompletenessTerm(c2, t, today: today), .saved)
        XCTAssertEqual(d.contract(c2)?.notice, 1)
        XCTAssertEqual(d.contract(c2)?.end, Day(2027, 3, 31))
        XCTAssertEqual(d.contract(c2)?.renewMonths, 12)
        XCTAssertFalse(Completeness.report(d, today: today).termContracts.contains(c2))

        // jederzeit kündbar ohne Frist: nichts gespeichert
        var o = CompletenessTermDraft(mode: .open)
        XCTAssertEqual(d.saveCompletenessTerm(c6, o, today: today), .invalid(Completeness.noticeMissing))
        o.notice = "1"
        o.cancelTerm = .monthEnd
        XCTAssertEqual(d.saveCompletenessTerm(c6, o, today: today), .saved)
        XCTAssertEqual(d.contract(c6)?.cancelTerm, .monthEnd)
        XCTAssertFalse(Completeness.report(d, today: today).termContracts.contains(c6))

        // nicht kündbar
        XCTAssertEqual(d.saveCompletenessTerm(c6, CompletenessTermDraft(mode: .tax), today: today), .saved)
        XCTAssertEqual(d.contract(c6)?.noCancel, true)
        XCTAssertEqual(Completeness.report(d, today: today).per[c6], [.logo])

        // feste Laufzeit ohne Verlängerung läuft aus: keine Frist nötig; ohne Datum nichts gespeichert
        var f = CompletenessTermDraft(mode: .fixed, renew: 0)
        XCTAssertEqual(d.saveCompletenessTerm(c2, f, today: today), .invalid(Completeness.endMissing))
        f.end = Day(2027, 6, 30)
        XCTAssertEqual(d.saveCompletenessTerm(c2, f, today: today), .saved)
        XCTAssertEqual(d.contract(c2)?.notice, 0)
        XCTAssertEqual(d.contract(c2)?.renewMonths, 0)
    }

    func testTermNeedRules() throws {
        let r = try load()
        var d = r.data
        let c6 = r.contractIDs["c6"]!
        d.settings.qualityIgnored = ["c:" + c6.uuidString + ":notice"]
        XCTAssertFalse(Completeness.report(d, today: today).termContracts.contains(c6))
        let calc = Calc(data: d, today: today)
        XCTAssertFalse(Completeness.termNeed(Contract(amount: 10, cycle: 1, noWatch: true), calc: calc))
        XCTAssertFalse(Completeness.termNeed(Contract(amount: 10, cycle: 1, mandatory: true), calc: calc))
        XCTAssertTrue(Completeness.termNeed(Contract(amount: 10, cycle: 12, due: Day(2027, 1, 1), cancelTerm: .yearEnd), calc: calc))
        XCTAssertFalse(Completeness.termNeed(Contract(amount: 10, cycle: 1, notice: 1), calc: calc))
    }

    func testSenderAndLogoSkip() throws {
        let r = try load()
        var d = r.data
        let lara = d.person(named: "Lara")!.id, sinan = d.person(named: "Sinan")!.id
        XCTAssertEqual(d.saveCompletenessSender(lara, first: "", last: "", street: "Weg 1", zip: "8280", city: "Kreuzlingen"), Completeness.senderMissing)
        XCTAssertEqual(d.completenessSameCandidates(for: lara).map { $0.id }, [sinan])
        d.setCompletenessSenderSame(lara, as: sinan)
        XCTAssertEqual(d.person(lara)?.sameAddressAs, sinan)
        XCTAssertEqual(d.resolvedSender(lara).street, "Seestrasse 1")
        XCTAssertNil(d.saveCompletenessSender(lara, first: "Lara", last: "Muster", street: "Weg 1", zip: "8280", city: "Kreuzlingen"))
        XCTAssertNil(d.person(lara)?.sameAddressAs)
        XCTAssertTrue(Completeness.report(d, today: today).senderPersons.isEmpty)

        let tg = d.partners.first { $0.name == "Kanton TG" }!.id
        d.skipLogo(partner: tg)
        XCTAssertEqual(d.settings.logoSkip, ["kanton tg"])
        let rep = Completeness.report(d, today: today)
        XCTAssertFalse(rep.logoPartners.contains(tg))
        XCTAssertEqual(rep.per[r.contractIDs["c3"]!], [])
        XCTAssertEqual(rep.ready, 2)
        XCTAssertEqual(rep.percent, 40)
        XCTAssertEqual(Completeness.startHeadline(percent: rep.percent), "Gute Basis!")
        XCTAssertEqual(Completeness.gainText(rep, single: false), "40 % startklar")

        // Logo-Datei vorhanden → kein Logo nötig, fehlende Datei zählt nicht
        if let i = d.partnerIndex(d.partners.first { $0.name == "Swisscom" }!.id) { d.partners[i].logoID = "abc" }
        XCTAssertFalse(Completeness.report(d, today: today, hasFile: { $0 == "abc" }).per[r.contractIDs["c1"]!]!.contains(.logo))
        XCTAssertTrue(Completeness.report(d, today: today, hasFile: { _ in false }).per[r.contractIDs["c1"]!]!.contains(.logo))
    }

    func testEmptyData() {
        let rep = Completeness.report(AppData.initial(), today: today)
        XCTAssertEqual(rep.total, 0)
        XCTAssertEqual(rep.percent, 100)
        XCTAssertEqual(Completeness.badge(rep), "")
        XCTAssertEqual(Completeness.accessibilityLabel(rep), "Vollständigkeit: keine Verträge")
        XCTAssertEqual(Completeness.endHeadline(rep, single: false), "100 % – alles komplett!")
    }
}
