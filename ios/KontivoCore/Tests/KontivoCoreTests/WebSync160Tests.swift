import XCTest
@testable import KontivoCore

/// Nachzug der Web-Änderungen v143–v160 im Kern: Probeabo (letzter Gratistag, zählt erst ab Probe-Ende), «endet von selbst»,
/// Zahlungsanker, Formular-Regeln (Zahlung am, Mindestlaufzeit, Laufzeit-Hinweis), tolerante Beträge, Zahlenformat nach
/// Hauptwährung, Vertragsnummer-Beschriftung, Brief (Anrede, KVG), Prüfungen vor dem Senden, «Schon gekündigt …»,
/// Vertragsansicht, Einnahmen (neue Arten, Ansicht, Zweitzeile), Katalog «Rundfunkgebühr», Backup-Prüfung.
/// Erwartungswerte aus der Web-App (index.html v160, main 83c905c) mit Playwright gemessen, Stichtag 2026-10-11.
final class WebSync160Tests: XCTestCase {
    let today = Day(2026, 10, 11)

    override func setUp() {
        super.setUp()
        Format.homeCurrency = .CHF
    }

    override func tearDown() {
        Format.homeCurrency = .CHF
        super.tearDown()
    }

    /// Gleicher Datenstand wie die Messung (Person «Ich», Kategorie «Sonstiges», Zahlung am 20.).
    struct Fixture {
        var data: AppData
        var ids: [String: UUID]
        func c(_ k: String) -> Contract { data.contract(ids[k])! }
    }

    func fixture() -> Fixture {
        var d = AppData.initial()
        let me = d.persons[0].id
        let other = d.category(named: "Sonstiges")!.id
        let housing = d.category(named: "Wohnen")!.id
        let taxes = d.category(named: "Steuern & Gebühren")!.id
        var ids: [String: UUID] = [:]
        func add(_ key: String, partner: String, _ c0: Contract, cat: UUID? = nil) {
            var c = c0
            c.partnerID = d.partnerID(forName: partner)
            c.categoryID = cat ?? other
            c.holderIDs = [me]
            if c.due == nil { c.due = Day(2026, 10, 20) }
            ids[key] = c.id
            d.contracts.append(c)
        }
        add("a", partner: "Netflix", Contract(label: "Netflix", amount: 20, trial: Day(2026, 10, 20)))
        add("b", partner: "Leasing AG", Contract(label: "Auto", amount: 300, end: Day(2027, 6, 30), notice: 3))
        add("c", partner: "Fitness", Contract(label: "Abo", amount: 80, start: Day(2027, 3, 15), notice: 1, cancelTerm: .monthEnd))
        add("d", partner: "Spotify", Contract(label: "Musik", amount: 10))
        add("e", partner: "Zattoo", Contract(label: "TV", amount: 15, due: Day(2026, 10, 5), trial: Day(2026, 10, 20)))
        add("g1", partner: "Alt AG", Contract(label: "Kurs", amount: 50, end: Day(2026, 3, 31), notice: 1, cancelChannel: .letter))
        add("ar", partner: "Arch", Contract(label: "Archiviert", amount: 10, end: Day(2025, 12, 31), renewMonths: 12, status: .cancelled,
                                             cancelledAt: Day(2026, 5, 3)))
        add("cp", partner: "Sunrise", Contract(label: "Internet", amount: 50, notice: 1, cancelTerm: .monthEnd, cancelChannel: .online,
                                               cancelPer: Day(2026, 12, 31), cancelledOn: Day(2026, 10, 1)))
        add("nw", partner: "Miete AG", Contract(label: "Wohnung", amount: 1500, start: Day(2020, 4, 1), notice: 3, cancelTerm: .quarterEnd,
                                                noWatch: true), cat: housing)
        add("tx", partner: "Kanton", Contract(label: "Steuern", amount: 100, noCancel: true), cat: taxes)
        return Fixture(data: d, ids: ids)
    }

    // MARK: Probeabo, «endet von selbst», Zustände

    func testTrialStates() {
        let f = fixture()
        let calc = Calc(data: f.data, today: today)
        let a = f.c("a")
        XCTAssertEqual(calc.trialLast(a), Day(2026, 10, 19))
        XCTAssertTrue(calc.trialOn(a))
        XCTAssertTrue(calc.trialNeeds(a))
        XCTAssertFalse(calc.countsMonthly(a))
        // am ersten kostenpflichtigen Tag ist es zu spät
        XCTAssertFalse(Calc(data: f.data, today: Day(2026, 10, 20)).trialOn(a))
        XCTAssertFalse(Calc(data: f.data, today: Day(2026, 10, 20)).trialNeeds(a))
        // behalten oder gekündigt: kein laufendes Probeabo
        var kept = a
        kept.trialKept = kept.trial
        XCTAssertFalse(calc.trialOn(kept))
        var cancelled = a
        cancelled.cancelPer = Day(2026, 10, 19)
        XCTAssertFalse(calc.trialOn(cancelled))
        // Zahlungen erst ab Probe-Ende (Web v153)
        let e = f.c("e")
        XCTAssertEqual(calc.occurrences(e, from: Day(2026, 10, 1), to: Day(2026, 12, 31)), [Day(2026, 11, 5), Day(2026, 12, 5)])
        XCTAssertEqual(calc.nextDue(e), Day(2026, 11, 5))
        XCTAssertEqual(calc.occurrences(a, from: Day(2026, 10, 1), to: Day(2027, 1, 31)),
                       [Day(2026, 10, 20), Day(2026, 11, 20), Day(2026, 12, 20), Day(2027, 1, 20)])
    }

    func testEndsSelfAndFutureStart() {
        let f = fixture()
        let calc = Calc(data: f.data, today: today)
        XCTAssertTrue(calc.endsSelf(f.c("b")))
        XCTAssertFalse(calc.endsSelf(f.c("c")))
        XCTAssertFalse(calc.endsSelf(f.c("tx")))
        XCTAssertFalse(calc.endsSelf(f.c("cp")))
        // Beginn in der Zukunft: Frist frühestens ab Beginn (Web v156)
        let c = f.c("c")
        XCTAssertEqual(calc.nextTerm(c), Day(2027, 4, 30))
        XCTAssertEqual(calc.termEnd(c), Day(2027, 4, 30))
        XCTAssertEqual(calc.noticeDeadline(c), Day(2027, 3, 31))
        XCTAssertEqual(f.data.partnerSuffix(of: f.c("a")), "")
        XCTAssertEqual(f.data.partnerSuffix(of: f.c("b")), "Leasing AG")
    }

    func testHeroExcludesRunningTrial() {
        let f = fixture()
        let h = Calc(data: f.data, today: today).hero()
        // ohne Netflix/TV (Probeabo), Abo (noch nicht begonnen), Archiv und Kurs (beendet)
        XCTAssertEqual(h.monthlyTotal, 300 + 10 + 50 + 1500 + 100, accuracy: 1e-9)
        var d = AppData.initial()
        d.contracts = [Contract(label: "Netflix", amount: 20, due: Day(2026, 10, 20), trial: Day(2026, 10, 20)),
                       Contract(label: "Leasing", amount: 300, due: Day(2026, 10, 20), end: Day(2027, 6, 30), notice: 3)]
        let h2 = Calc(data: d, today: today).hero()
        XCTAssertEqual(h2.monthlyTotal, 300, accuracy: 1e-9)
        XCTAssertEqual(h2.subtitle, "3’600 CHF im Jahr")   // Web v164
        // Budget-Leerseite und Pop-up ohne laufendes Probeabo
        XCTAssertEqual(Calc(data: d, today: today).kbBudgetEmptyText(),
                       "Deine Fixkosten sind schon da: 300.00 CHF im Monat. Es fehlen nur deine Einnahmen.")
        var only = AppData.initial()
        only.contracts = [d.contracts[0]]
        XCTAssertEqual(Calc(data: only, today: today).kbBudgetEmptyText(),
                       "Trag deine Einnahmen ein, z.B. Lohn, Rente oder Stipendium. Die Fixkosten kommen aus deinen Verträgen.")
        let pop = Calc(data: d, today: today).kbPopup(.category, key: "Sonstiges", personID: nil)
        XCTAssertEqual(pop.total, 300, accuracy: 1e-9)
        XCTAssertEqual(pop.rows.first { $0.text.hasPrefix("Netflix") }?.text, "Netflix · Probeabo")
        XCTAssertEqual(pop.rows.first { $0.text.hasPrefix("Netflix") }?.paused, true)
    }

    // MARK: Fristen

    func testDeadlineOverview() {
        let f = fixture()
        let calc = Calc(data: f.data, today: today)
        let o = calc.deadlineOverview()
        var web: [UUID: String] = [:]
        for (k, v) in f.ids { web[v] = k }
        XCTAssertEqual(o.items.map { web[$0.contractID] ?? "?" }, ["a", "e", "cp", "b"])
        XCTAssertEqual(o.items.map { $0.sub }, ["Probeabo · gratis bis 19.10.", "Probeabo · gratis bis 19.10.", "Gekündigt", "Endet von selbst"])
        XCTAssertEqual(o.items.map { $0.chip }, ["in 8 Tagen", "in 8 Tagen", "endet 31.12.", "endet 30.06.27"])
        XCTAssertEqual(o.items.map { $0.chipLevel }, [.warn, .warn, .end, Calc.ChipLevel.none])   // Web v163: «Endet von selbst» neutral
        XCTAssertEqual(o.items.map { $0.showActions }, [true, true, false, false])
        XCTAssertEqual(o.items.map { $0.partner }, ["", "Zattoo", "Sunrise", "Leasing AG"])
        XCTAssertEqual(o.items.map { $0.endsBySelf }, [false, false, false, true])
        XCTAssertEqual(o.status?.title, "2 Entscheidungen offen")
        XCTAssertEqual(o.status?.subtitle, "Nächste Frist in 8 Tagen")
        XCTAssertEqual(o.flexible.map { web[$0.contractID] ?? "?" }, ["c"])
        XCTAssertEqual(o.flexible.first?.sub, "Frist 1 Monat")
        XCTAssertEqual(o.flexible.first?.chip, "endet 30.04.27")
        XCTAssertEqual(o.withoutNotice.map { web[$0.contractID] ?? "?" }, ["d"])
        XCTAssertEqual(o.unwatched.map { web[$0.contractID] ?? "?" }, ["nw"])
        XCTAssertEqual(o.unwatched.first?.text, "Frist 3 Monate")
        XCTAssertEqual(o.unwatched.first?.partner, "Miete AG")
        XCTAssertEqual(Calc.DeadlineOverview.flexNote, "Vertragsende, wenn du heute kündigst")
        // Probeabo ausserhalb der 30 Tage: in der Liste, ohne Knöpfe und neutral
        var d = AppData.initial()
        d.contracts = [Contract(label: "TV", amount: 15, due: Day(2026, 10, 20), trial: Day(2026, 12, 20))]
        let o2 = Calc(data: d, today: today).deadlineOverview()
        XCTAssertEqual(o2.items.first?.sub, "Probeabo · gratis bis 19.12.")
        XCTAssertEqual(o2.items.first?.chipLevel, Calc.ChipLevel.none)
        XCTAssertEqual(o2.items.first?.showActions, false)
        XCTAssertTrue(o2.flexible.isEmpty)
    }

    func testRemindersUseTrialLast() {
        let f = fixture()
        let calc = Calc(data: f.data, today: today)
        let dl = calc.reminderDeadline(for: f.c("a"))
        XCTAssertEqual(dl?.kind, .trial)
        XCTAssertEqual(dl?.date, Day(2026, 10, 19))
        XCTAssertEqual(calc.reminderDeadline(for: f.c("e"))?.date, Day(2026, 10, 19))
        XCTAssertNil(calc.reminderDeadline(for: f.c("tx")))
        XCTAssertNil(calc.reminderDeadline(for: f.c("cp")))
    }

    // MARK: Vertragsansicht

    func testDetailInfo() {
        let f = fixture()
        let calc = Calc(data: f.data, today: today)

        // Probeabo: Kasten «Probeabo bis 19. Oktober», kein Anteil, Zeile «Probeabo»
        let a = calc.detailInfo(f.c("a"))
        XCTAssertTrue(a.pills.isEmpty)
        XCTAssertEqual(a.box?.title, "Probeabo bis 19. Oktober")
        XCTAssertEqual(a.box?.subtitle, "danach kostenpflichtig · noch 8 Tage")
        XCTAssertEqual(a.box?.trial, true)
        XCTAssertNil(a.month.sharePercent)
        XCTAssertNil(a.month.status)
        XCTAssertEqual(a.costRows.map { $0.label + " : " + $0.value }, ["Zahlung : monatlich am 20."])
        XCTAssertEqual(a.termRows.compactMap { $0.timeline == nil ? $0.label + " : " + $0.value : nil },
                       ["Kündigung : ohne Frist · jederzeit", "Nächster Termin : per 19.10.26, kündigen bis 19.10.26 (abgelaufen)",
                        "Probeabo : gratis bis 19. Oktober 2026"])
        XCTAssertEqual(a.assignmentRows.map { $0.label + " : " + $0.value }, ["Vertragspartner : Netflix", "Kategorie : Sonstiges", "Person : Ich"])
        XCTAssertEqual(a.menu.cancel?.title, "Kündigen")
        XCTAssertEqual(a.menu.cancel?.subtitle, "Weg wählen")
        XCTAssertEqual(a.menu.pause, "Pausieren")
        XCTAssertEqual(a.menu.alreadyCancelled?.title, "Schon gekündigt …")
        XCTAssertEqual(a.menu.alreadyCancelled?.subtitle, "Datum eintragen, bis wann er läuft")

        // endet von selbst: Kasten «Kündigen bis», Kündigung «nicht nötig · endet von selbst»
        let b = calc.detailInfo(f.c("b"))
        XCTAssertTrue(b.endsSelf)
        XCTAssertTrue(b.termRows.contains { $0.label == "Kündigung" && $0.value == "nicht nötig · endet von selbst" })
        XCTAssertFalse(b.termRows.contains { $0.timeline != nil })

        // Beginn in der Zukunft: «startet am 15.03.27», Zeitstrahl Frist 31.03.27, Ende 30.04.27
        let c = calc.detailInfo(f.c("c"))
        XCTAssertEqual(c.month.status, "startet am 15.03.27")
        XCTAssertEqual(c.termRows.first { $0.timeline != nil }?.timeline?.deadline, Day(2027, 3, 31))
        XCTAssertEqual(c.termRows.first { $0.timeline != nil }?.timeline?.end, Day(2027, 4, 30))
        XCTAssertEqual(c.termRows.first?.label, "Beginn")
        XCTAssertEqual(c.termRows.first?.value, "15. März 2027")

        // abgelaufen ohne Verlängerung: «Beendet am …», «nicht nötig», Menü ohne Pause, mit «Wieder aktiv setzen»
        let g = calc.detailInfo(f.c("g1"))
        XCTAssertEqual(g.pills.map { $0.text }, ["Beendet am 31. März 2026"])
        XCTAssertEqual(g.month.status, "beendet")
        XCTAssertEqual(g.termRows.map { $0.label + " : " + $0.value }, ["Vertragsende : 31. März 2026", "Kündigung : nicht nötig"])
        XCTAssertEqual(g.menu.cancel?.subtitle, "per Brief")
        XCTAssertNil(g.menu.pause)
        XCTAssertTrue(g.menu.reactivate)
        XCTAssertNil(g.menu.alreadyCancelled)

        // Archiv: «Gekündigt am …», Vertragsende = letzter Termin vor der Archivierung
        let ar = calc.detailInfo(f.c("ar"))
        XCTAssertEqual(ar.pills.map { $0.text }, ["Gekündigt am 3. Mai 2026"])
        XCTAssertEqual(ar.termRows.map { $0.label + " : " + $0.value }, ["Vertragsende : 31. Dezember 2026", "Kündigung : ohne Frist"])
        XCTAssertNil(ar.menu.cancel)
        XCTAssertTrue(ar.menu.reactivate)

        // gekündigt per: Pille «läuft bis», Kündigungsweg und «Gekündigt am»; Monatskachel wie Web v161 «gekündigt, läuft bis …»
        let cp = calc.detailInfo(f.c("cp"))
        XCTAssertEqual(cp.pills.map { $0.text }, ["Gekündigt · läuft bis 31. Dezember 2026"])
        XCTAssertEqual(cp.month.status, "gekündigt, läuft bis 31.12.26")
        XCTAssertEqual(cp.termRows.map { $0.label + " : " + $0.value },
                       ["Vertragsende : 31. Dezember 2026", "Kündigung : 1 Monat · auf Monatsende", "Kündigungsweg : Online / Kundenkonto",
                        "Gekündigt am : 1. Oktober 2026"])
        XCTAssertNil(cp.menu.cancel)
        XCTAssertTrue(cp.menu.uncancel)
        XCTAssertEqual(cp.menu.pause, "Pausieren")
        XCTAssertNil(cp.menu.alreadyCancelled)

        // nicht beobachtet, Miete: Zeitstrahl, «Frist: wird nicht beobachtet», Menü «per Brief», ohne Pause
        let nw = calc.detailInfo(f.c("nw"))
        XCTAssertEqual(nw.month.sharePercent, 77)
        XCTAssertTrue(nw.termRows.contains { $0.label == "Frist" && $0.value == "wird nicht beobachtet" })
        XCTAssertEqual(nw.termRows.first { $0.timeline != nil }?.timeline?.deadline, Day(2026, 12, 31))
        XCTAssertEqual(nw.termRows.first { $0.timeline != nil }?.timeline?.end, Day(2027, 3, 31))
        XCTAssertEqual(nw.menu.cancel?.subtitle, "per Brief")
        XCTAssertNil(nw.menu.pause)

        // nicht kündbar: Pille, «Beendet …»
        let tx = calc.detailInfo(f.c("tx"))
        XCTAssertEqual(tx.pills.map { $0.text }, ["Nicht kündbar"])
        XCTAssertEqual(tx.month.sharePercent, 5)
        XCTAssertEqual(tx.termRows.map { $0.label + " : " + $0.value }, ["Kündigung : nicht kündbar · Steuern & Gebühren"])
        XCTAssertNil(tx.menu.cancel)
        XCTAssertEqual(tx.menu.alreadyCancelled?.title, "Beendet …")
        XCTAssertEqual(tx.menu.alreadyCancelled?.subtitle, "z.B. nach Umzug")

        let d = calc.detailInfo(f.c("d"))
        XCTAssertEqual(d.month.sharePercent, 1)
        XCTAssertEqual(d.termRows.map { $0.label + " : " + $0.value }, ["Kündigung : ohne Frist · jederzeit"])
    }

    func testDetailMandatoryAndKept() {
        var d = AppData.initial()
        let me = d.persons[0].id
        let ins = d.category(named: "Versicherung")!.id
        let other = d.category(named: "Sonstiges")!.id
        let css = d.partnerID(forName: "CSS")
        let fp = d.partnerID(forName: "Fitnesspark")
        let m = Contract(label: "Krankenkasse", partnerID: css, categoryID: ins, amount: 400, due: Day(2026, 10, 20),
                         notice: 1, cancelTerm: .yearEnd, mandatory: true, customerNo: "9", contractNo: "123", holderIDs: [me],
                         payMethod: "Lastschrift", payAccount: "UBS …17")
        var k = Contract(label: "Abo", partnerID: fp, categoryID: other, amount: 80, due: Day(2026, 10, 20),
                         end: Day(2026, 12, 31), notice: 1, renewMonths: 12, holderIDs: [me])
        k.keptFor = Day(2026, 12, 31)
        d.contracts = [m, k]
        let calc = Calc(data: d, today: today)
        let mi = calc.detailInfo(m)
        XCTAssertEqual(mi.box?.title, "Wechseln bis 30. November")
        XCTAssertEqual(mi.box?.subtitle, "Vertragsende 31.12.26 · noch 50 Tage")
        XCTAssertEqual(mi.box?.cancelTitle, "Wechseln")
        XCTAssertTrue(mi.costRows.contains { $0.label == "Bezahlung" && $0.value == "Lastschrift · UBS …17" })
        XCTAssertTrue(mi.termRows.contains { $0.label == "Kündigung" && $0.value == "nur mit neuem Anbieter" })
        XCTAssertEqual(mi.assignmentRows.last?.label, "Versichertennummer")
        XCTAssertEqual(mi.assignmentRows.last?.value, "123")
        XCTAssertEqual(mi.menu.cancel?.title, "Wechseln")
        XCTAssertEqual(mi.menu.cancel?.subtitle, "per Brief")
        XCTAssertNil(mi.menu.pause)

        let ki = calc.detailInfo(k)
        XCTAssertEqual(ki.pills.map { $0.text }, ["Behalten · nächste Frist 30.11.27"])
        XCTAssertNil(ki.box)
        XCTAssertEqual(ki.termRows.first { $0.timeline != nil }?.timeline?.deadline, Day(2027, 11, 30))
        XCTAssertEqual(ki.termRows.first { $0.timeline != nil }?.timeline?.end, Day(2027, 12, 31))
        XCTAssertTrue(ki.termRows.contains { $0.label == "Sonst verlängert bis" && $0.value == "31. Dezember 2028" })
        XCTAssertTrue(ki.menu.unkeep)
    }

    func testAlreadyCancelledKillOptionsAndQuestion() throws {
        var f = fixture()
        let calc = Calc(data: f.data, today: today)
        let pb = calc.alreadyCancelledPrompt(f.c("b"))
        XCTAssertEqual(pb.title, "Schon gekündigt")
        XCTAssertEqual(pb.defaultDate, Day(2027, 6, 30))
        XCTAssertEqual(pb.chips.map { $0.title }, ["heute", "30.06.27 (Termin)"])
        let pt = calc.alreadyCancelledPrompt(f.c("tx"))
        XCTAssertEqual(pt.title, "Vertrag beendet")
        XCTAssertEqual(pt.text, "Bis wann läuft «Steuern»? Danach zählt er nicht mehr zu deinen Kosten.")
        XCTAssertEqual(pt.defaultDate, today)
        XCTAssertEqual(pt.chips.map { $0.title }, ["heute"])

        let ka = calc.killOptions(f.c("a"), trial: true)
        XCTAssertEqual(ka.title, "Kündigen: Netflix")
        XCTAssertEqual(ka.startTitle, "Kündigen: Weg wählen …")
        XCTAssertEqual(ka.doneTitle, "Als gekündigt markieren")
        XCTAssertEqual(ka.doneDetail, "läuft bis 19.10.26")
        XCTAssertEqual(ka.note, "Kündigung muss bis 19. Oktober 2026 sein. Nach dem Markieren zählt der Vertrag bis zum Ende weiter und wandert danach ins Archiv.")
        let kb = calc.killOptions(f.c("b"), trial: false)
        XCTAssertEqual(kb.title, "Kündigen: Auto")
        XCTAssertEqual(kb.doneDetail, "läuft bis 30.06.27")
        XCTAssertEqual(kb.note, "Kündigung muss bis 31. März 2027 beim Vertragspartner sein. Nach dem Markieren zählt der Vertrag bis zum Ende weiter und wandert danach ins Archiv.")
        let kd = calc.killOptions(f.c("d"), trial: false)
        XCTAssertEqual(kd.doneDetail, "")
        XCTAssertEqual(kd.note, "Nach dem Markieren zählt der Vertrag bis zum Ende weiter und wandert danach ins Archiv.")

        let q = try XCTUnwrap(calc.cancelledQuestion(f.c("b"), trial: false, letter: true))
        XCTAssertEqual(q.title, "Brief verschickt?")
        XCTAssertEqual(q.text, "«Auto» als gekündigt markieren, läuft bis 30. Juni 2027. Der Vertrag zählt bis zum Ende weiter und wandert danach ins Archiv.")
        XCTAssertEqual(q.no, "Noch nicht")
        XCTAssertEqual(calc.cancelledQuestion(f.c("a"), trial: true, letter: false)?.title, "Gekündigt?")
        XCTAssertNil(calc.cancelledQuestion(f.c("cp"), trial: false, letter: true))

        // «Schon gekündigt …» mit Datum: Zukunft, heute, Vergangenheit (Web v154)
        let bid = f.ids["b"]!
        let r1 = f.data.markCancelled(bid, trial: false, per: Day(2026, 12, 31), today: today)
        XCTAssertEqual(r1?.toast, "Gekündigt — läuft bis 31. Dezember 2026")
        XCTAssertEqual(f.data.contract(bid)?.cancelPer, Day(2026, 12, 31))
        XCTAssertEqual(f.data.contract(bid)?.cancelledOn, today)
        let r2 = f.data.markCancelled(bid, trial: false, per: today, today: today)
        XCTAssertEqual(r2?.toast, "Endet heute – danach im Archiv")
        let r3 = f.data.markCancelled(bid, trial: false, per: Day(2026, 9, 30), today: today)
        XCTAssertEqual(r3?.toast, "Beendet – steht jetzt im Archiv")
        XCTAssertFalse(Calc(data: f.data, today: today).isActive(f.data.contract(bid)!))
        // Wieder aktiv setzen
        f.data.reactivate(bid)
        XCTAssertNil(f.data.contract(bid)?.cancelPer)
        XCTAssertNil(f.data.contract(bid)?.cancelledOn)
        XCTAssertFalse(f.data.reactivateNeedsEnd(bid, today: today))
        XCTAssertTrue(f.data.reactivateNeedsEnd(f.ids["g1"]!, today: today))
        // Korrektur gekündigter Verträge (Formular)
        let cpid = f.ids["cp"]!
        let e1 = f.data.correctCancellation(cpid, per: nil, on: nil)
        XCTAssertEqual(e1, ContractFormRules.missingCancelPerText)
        let e2 = f.data.correctCancellation(cpid, per: Day(2026, 11, 30), on: Day(2026, 12, 1))
        XCTAssertEqual(e2, ContractFormRules.cancelOrderText)
        let e3 = f.data.correctCancellation(cpid, per: Day(2026, 11, 30), on: nil)
        XCTAssertNil(e3)
        XCTAssertEqual(f.data.contract(cpid)?.cancelPer, Day(2026, 11, 30))
        XCTAssertEqual(f.data.contract(cpid)?.cancelledOn, Day(2026, 10, 1))
    }

    // MARK: Formular

    func testDueFrom() {
        let t = today
        XCTAssertEqual(ContractFormRules.dueFrom(day: 31, month: 1, cycle: 1, today: t), Day(2026, 10, 31))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 5, month: 1, cycle: 1, today: t), Day(2026, 11, 5))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 11, month: 1, cycle: 1, today: t), Day(2026, 10, 11))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 10, month: 1, cycle: 1, today: t), Day(2026, 11, 10))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 31, month: 1, cycle: 3, today: t), Day(2026, 10, 31))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 15, month: 10, cycle: 3, today: t), Day(2026, 10, 15))
        // 29.02. als Anker in einem Schaltjahr (notfalls vor heute), damit spätere Jahre aufs Monatsende fallen
        XCTAssertEqual(ContractFormRules.dueFrom(day: 29, month: 2, cycle: 12, today: t), Day(2024, 2, 29))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 15, month: 3, cycle: 12, today: t), Day(2027, 3, 15))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 10, month: 10, cycle: 12, today: t), Day(2027, 10, 10))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 31, month: 8, cycle: 6, today: t), Day(2026, 8, 31))
        XCTAssertEqual(ContractFormRules.dueFrom(day: 1, month: 1, cycle: 24, today: t), Day(2028, 1, 1))

        XCTAssertEqual(ContractFormRules.dueFromStart(start: Day(2026, 3, 15), cycle: 12, today: t), Day(2027, 3, 15))
        XCTAssertEqual(ContractFormRules.dueFromStart(start: Day(2025, 1, 31), cycle: 3, today: t), Day(2026, 10, 31))
        XCTAssertNil(ContractFormRules.dueFromStart(start: Day(2025, 1, 31), cycle: 1, today: t))
        XCTAssertEqual(ContractFormRules.dueFromStart(start: Day(2027, 2, 1), cycle: 12, today: t), Day(2027, 2, 1))
        XCTAssertEqual(ContractFormRules.dueFromStart(start: Day(2024, 8, 31), cycle: 6, today: t), Day(2027, 2, 28))
        XCTAssertNil(ContractFormRules.dueFromStart(start: nil, cycle: 12, today: t))
        XCTAssertEqual(ContractFormRules.trialDue(trial: Day(2026, 11, 1)), Day(2026, 11, 1))

        XCTAssertEqual(ContractFormRules.dueText(Day(2026, 10, 27), cycle: 1), "27. im Monat")
        XCTAssertEqual(ContractFormRules.dueText(Day(2026, 1, 27), cycle: 3), "27. Jan, Apr, Jul, Okt")
        XCTAssertEqual(ContractFormRules.dueText(Day(2026, 11, 5), cycle: 3), "5. Feb, Mai, Aug, Nov")
        XCTAssertEqual(ContractFormRules.dueText(Day(2026, 2, 10), cycle: 2), "10. Feb, Apr, Jun, Aug, Okt, Dez")
        XCTAssertEqual(ContractFormRules.dueText(Day(2026, 9, 30), cycle: 6), "30. Mär, Sep")
        XCTAssertEqual(ContractFormRules.dueText(Day(2026, 6, 27), cycle: 12), "27. Juni")
        XCTAssertEqual(ContractFormRules.dueText(Day(2026, 6, 27), cycle: 24), "27. Juni (alle 2 Jahre)")
        XCTAssertEqual(ContractFormRules.dueText(nil, cycle: 1), "wählen")
        XCTAssertEqual(ContractFormRules.dueGridMonths(month: 1, cycle: 3), [1, 4, 7, 10])
        XCTAssertEqual(ContractFormRules.dueGridMonths(month: 6, cycle: 12), [6])
        XCTAssertEqual(ContractFormRules.dueGridMonths(month: 6, cycle: 1), [])
        XCTAssertFalse(ContractFormRules.dueGridShowsMonths(cycle: 1))
        XCTAssertTrue(ContractFormRules.dueGridShowsMonths(cycle: 3))
    }

    func testTermMonthsAndNotice() {
        XCTAssertEqual(ContractFormRules.termEnd(start: Day(2026, 1, 31), months: 1), Day(2026, 2, 27))
        XCTAssertEqual(ContractFormRules.termEnd(start: Day(2026, 1, 1), months: 12), Day(2026, 12, 31))
        XCTAssertEqual(ContractFormRules.termEnd(start: Day(2024, 2, 29), months: 12), Day(2025, 2, 27))
        XCTAssertEqual(ContractFormRules.termEnd(start: Day(2026, 3, 31), months: 24), Day(2028, 3, 30))
        XCTAssertNil(ContractFormRules.termEnd(start: Day(2026, 1, 1), months: 0))
        XCTAssertEqual(ContractFormRules.termMonths(start: Day(2026, 1, 31), end: Day(2026, 2, 27)), 1)
        XCTAssertEqual(ContractFormRules.termMonths(start: Day(2026, 1, 1), end: Day(2026, 12, 31)), 12)
        XCTAssertNil(ContractFormRules.termMonths(start: Day(2026, 1, 1), end: Day(2027, 1, 15)))
        XCTAssertEqual(ContractFormRules.termMonths(start: Day(2026, 3, 31), end: Day(2028, 3, 30)), 24)
        XCTAssertEqual(ContractFormRules.termMonthsText(12), "1 Jahr")
        XCTAssertEqual(ContractFormRules.termMonthsText(24), "2 Jahre")
        XCTAssertEqual(ContractFormRules.termMonthsText(18), "18 Monate")
        XCTAssertEqual(ContractFormRules.termMonthsText(1), "1 Monat")
        XCTAssertEqual(ContractFormRules.termMonthsButtonText(18), "18 Mt.")
        XCTAssertEqual(ContractFormRules.noticeChoiceText(15, .dayOfMonth), "bis 15. im Monat")
        XCTAssertEqual(ContractFormRules.noticeChoiceText(1, .months), "1 Monat")
        XCTAssertEqual(ContractFormRules.noticeChoiceText(2, .weeks), "2 Wochen")
        XCTAssertEqual(ContractFormRules.noticeApplyTitle(0, .months), "Keine Frist übernehmen")
        XCTAssertEqual(ContractFormRules.noticeApplyTitle(3, .days), "3 Tage übernehmen")
        XCTAssertEqual(ContractFormRules.clampNotice(31, .dayOfMonth), 28)
        XCTAssertEqual(ContractFormRules.clampNotice(31, .days), 31)
        XCTAssertEqual(ContractFormRules.noticeUnitLabel(.months, count: 1), "Monat")
        XCTAssertEqual(ContractFormRules.noticeUnitLabel(.months, count: 2), "Monate")
        XCTAssertEqual(ContractFormRules.defaultRenewOnFixed, 1)
        // «An Frist erinnern» nur mit Frist
        XCTAssertFalse(ContractFormRules.showsRemindToggle(mode: .tax, cancelTerm: .yearEnd, cycle: 1))
        XCTAssertFalse(ContractFormRules.showsRemindToggle(mode: .trial, cancelTerm: .yearEnd, cycle: 1))
        XCTAssertFalse(ContractFormRules.showsRemindToggle(mode: .open, cancelTerm: .monthEnd, cycle: 1))
        XCTAssertFalse(ContractFormRules.showsRemindToggle(mode: .open, cancelTerm: .period, cycle: 1))
        XCTAssertTrue(ContractFormRules.showsRemindToggle(mode: .open, cancelTerm: .period, cycle: 12))
        XCTAssertTrue(ContractFormRules.showsRemindToggle(mode: .fixed, cancelTerm: .anytime, cycle: 1))
        XCTAssertFalse(ContractFormRules.noWatchOnSave(mode: .trial, toggleNoWatch: true))
        XCTAssertTrue(ContractFormRules.noWatchOnSave(mode: .open, toggleNoWatch: true))
        // Art beim Öffnen
        XCTAssertEqual(ContractTermMode(contract: Contract(noCancel: true), today: today), .tax)
        XCTAssertEqual(ContractTermMode(contract: Contract(end: Day(2027, 1, 1)), today: today), .fixed)
        XCTAssertEqual(ContractTermMode(contract: Contract(trial: Day(2026, 10, 20)), today: today), .trial)
        XCTAssertEqual(ContractTermMode(contract: Contract(trial: Day(2026, 10, 1)), today: today), .open)
        XCTAssertEqual(ContractTermMode.fixed.title, "Mindestlaufzeit")
    }

    func testTermHint() {
        let calc = Calc(data: AppData.initial(), today: today)
        func h(_ mode: ContractTermMode, cycle: Int = 1, due: Day? = nil, start: Day? = nil, end: Day? = nil, renew: Int = 0,
               notice: Int = 0, unit: NoticeUnit = .months, term: CancelTerm = .anytime, trial: Day? = nil, cur: Currency = .CHF) -> String {
            ContractFormRules.termHint(TermHintInput(mode: mode, cycle: cycle, due: due, start: start, end: end, renewMonths: renew, notice: notice,
                                                     noticeUnit: unit, cancelTerm: term, trial: trial, currency: cur), calc: calc)
        }
        XCTAssertEqual(h(.tax), "Gebühren und Abgaben wie die Rundfunkgebühr: keine Fristen, kein Kündigen. Zählt in Kosten und Budget.")
        XCTAssertEqual(h(.trial, trial: Day(2026, 11, 1)), "Gratis bis 31. Oktober 2026, ab 1. November 2026 kostenpflichtig. Kontivo erinnert dich unter «Fristen».")
        XCTAssertEqual(h(.trial), "Wie lange läuft das Probeabo?")
        XCTAssertEqual(h(.fixed, end: Day(2027, 6, 30)), "Endet am 30. Juni 2027 von selbst – ohne Verlängerung ist keine Kündigung nötig.")
        XCTAssertEqual(h(.fixed, end: Day(2026, 6, 30)), "Dieser Vertrag ist am 30. Juni 2026 ausgelaufen. Beim Sichern kommt er ins Archiv – Vertragsende prüfen.")
        XCTAssertEqual(h(.fixed, end: Day(2027, 6, 30), renew: 12, notice: 3, cur: .EUR),
                       "Kündigen bis 31. März 2027, sonst +12 Monate. Hinweis Deutschland: Verbraucherverträge verlängern sich seit 03/2022 meist nur noch monatlich (§ 309 BGB).")
        XCTAssertEqual(h(.fixed, end: Day(2027, 6, 30), renew: 1, notice: 1), "Kündigen bis 31. Mai 2027, sonst +1 Monat.")
        XCTAssertEqual(h(.fixed, end: Day(2026, 10, 31), renew: 12, notice: 1),
                       "Frist für 31. Oktober 2026 verpasst · nächster Termin 31. Oktober 2027, kündigen bis 30. September 2027.")
        XCTAssertEqual(h(.fixed, renew: 12), "Vertragsende angeben, dann rechnet die App den Kündigungstermin aus.")
        XCTAssertEqual(h(.open), "Ohne Mindestlaufzeit und ohne Frist: jederzeit kündbar.")
        XCTAssertEqual(h(.open, notice: 1), "Ohne Mindestlaufzeit: kündbar mit der angegebenen Frist.")
        XCTAssertEqual(h(.open, cycle: 12), "Achtung: Bei jährlicher Zahlung ist ein Abo meist nur auf Ende der bezahlten Periode kündbar. Dann «Kündbar per: Ende Periode» wählen.")
        XCTAssertEqual(h(.open, notice: 1, term: .contractYear), "Für «Ende Vertragsjahr» bitte den Vertragsbeginn angeben.")
        XCTAssertEqual(h(.open, due: Day(2026, 10, 20), notice: 1, term: .monthEnd), "Nächster Termin: per 30. November 2026 · kündigen bis 31. Oktober 2026.")
        XCTAssertEqual(h(.open, cycle: 12, due: Day(2027, 3, 1), term: .period), "Das Abo-Jahr endet 28. Februar 2027 · kündigen bis 28. Februar 2027 (keine Frist erfasst).")
        XCTAssertEqual(h(.open, cycle: 3, due: Day(2026, 11, 1), notice: 1, term: .period), "Die bezahlte Periode endet 31. Januar 2027 · kündigen bis 31. Dezember 2026.")
        XCTAssertEqual(h(.open, due: Day(2027, 3, 15), start: Day(2027, 3, 15), notice: 3, term: .yearEnd),
                       "Nächster Termin: per 31. Dezember 2027 · kündigen bis 30. September 2027.")
    }

    // MARK: Beträge und Zahlenformat

    func testParseAmountTolerant() {
        XCTAssertEqual(Format.parseAmount("15.–"), 15)
        XCTAssertEqual(Format.parseAmount("2.000,-"), 2000)
        XCTAssertEqual(Format.parseAmount("CHF 1’234.50"), 1234.5)
        XCTAssertEqual(Format.parseAmount("€ 12,90"), 12.9)
        XCTAssertEqual(Format.parseAmount("12.90 EUR"), 12.9)
        XCTAssertEqual(Format.parseAmount("Fr. 25.-"), 25)
        XCTAssertEqual(Format.parseAmount("$5"), 5)
        XCTAssertEqual(Format.parseAmount("1.234"), 1234)
        XCTAssertNil(Format.parseAmount("abc"))
        XCTAssertEqual(Format.parseAmount("15.— "), 15)
        XCTAssertEqual(Format.parseAmount("\u{2212}5 CHF"), -5)
        XCTAssertEqual(Format.parseAmount("GBP 3"), 3)
        XCTAssertEqual(Format.parseAmount("chf 7.50"), 7.5)
    }

    func testNumberFormatFollowsHomeCurrency() {
        XCTAssertEqual(Format.money(1000, .EUR), "1’000.00")
        Format.homeCurrency = .EUR
        XCTAssertEqual(Format.money(1000, .CHF), "1.000,00")
        XCTAssertEqual(Format.numberStyle(.CHF), .de)
        Format.homeCurrency = .CHF
        XCTAssertEqual(Format.numberStyle(.EUR), .ch)
        XCTAssertEqual(Currency.onboardingDefault(preferredLanguages: ["de-CH", "en-US"]), .CHF)
        XCTAssertEqual(Currency.onboardingDefault(preferredLanguages: ["en-US", "de-AT"]), .EUR)
        XCTAssertEqual(Currency.onboardingDefault(preferredLanguages: ["fr-LI"]), .CHF)
        XCTAssertEqual(Currency.onboardingDefault(preferredLanguages: ["en-US"]), .EUR)
        XCTAssertEqual(Currency.onboardingDefault(preferredLanguages: []), .EUR)
    }

    // MARK: Brief und Senden

    func testContractNumberLabel() {
        func l(_ label: String, _ partner: String = "", _ cat: String) -> String {
            Letter.contractNumberLabel(label: label, partner: partner, categoryName: cat, categoryKind: Category.standardKinds[cat])
        }
        XCTAssertEqual(l("Krankenkasse", "", "Versicherung"), "Versichertennummer")
        XCTAssertEqual(l("Hausrat", "", "Versicherung"), "Policennummer")
        XCTAssertEqual(l("Police XY", "", "Sonstiges"), "Policennummer")
        XCTAssertEqual(l("Handy", "Swisscom", "Mobilfunk & Internet"), "Rufnummer")
        XCTAssertEqual(l("Abo", "Netflix", "Abos & Medien"), "Vertragsnummer")
        XCTAssertEqual(l("Grundversicherung", "", "Sonstiges"), "Versichertennummer")
        XCTAssertEqual(l("Internet", "Sunrise", "Mobilfunk & Internet"), "Vertragsnummer")
        XCTAssertEqual(Letter.splitReferences("Rufnummer: 079\nPolicennummer: P-1\n\nText").references, ["Rufnummer: 079", "Policennummer: P-1"])
    }

    func testLetterSalutationKvgAndChecks() {
        var d = AppData.initial()
        let me = d.persons[0].id
        let ins = d.category(named: "Versicherung")!.id
        d.persons[0].sender = SenderAddress(first: "Ich", street: "Weg 1", zip: "8000", city: "Zürich")
        let la = d.partnerID(forName: "Leasing AG")
        let mob = d.category(named: "Mobilität")!.id
        var c = Contract(label: "Auto", partnerID: la, categoryID: mob,
                         amount: 300, due: Day(2026, 10, 20), end: Day(2027, 6, 30), notice: 3, holderIDs: [me])
        d.contracts = [c]
        var calc = Calc(data: d, today: today)
        XCTAssertEqual(Letter.parts(c, calc: calc).body,
                       "Sehr geehrte Damen und Herren\n\nHiermit kündige ich den oben genannten Vertrag ordentlich zum nächstmöglichen Termin, nach meiner Berechnung zum 30. Juni 2027.\n\nBitte bestätigen Sie mir die Kündigung und das Vertragsende schriftlich.\n\nFreundliche Grüsse")
        c.currency = .EUR
        d.contracts = [c]
        calc = Calc(data: d, today: today)
        XCTAssertEqual(Letter.parts(c, calc: calc).body,
                       "Sehr geehrte Damen und Herren,\n\nhiermit kündige ich den oben genannten Vertrag ordentlich zum nächstmöglichen Termin, nach meiner Berechnung zum 30. Juni 2027.\n\nBitte bestätigen Sie mir die Kündigung und das Vertragsende schriftlich.\n\nFreundliche Grüsse")
        XCTAssertEqual(Letter.salutation(.CHF), "Sehr geehrte Damen und Herren")
        // KVG-Hinweis nur CHF und Krankenkasse/Grundversicherung/KVG
        let cssID = d.partnerID(forName: "CSS")
        let kk = Contract(label: "Krankenkasse", partnerID: cssID, categoryID: ins, amount: 400, holderIDs: [me])
        XCTAssertTrue(Letter.showsKvgHint(kk, data: d))
        var kkEUR = kk
        kkEUR.currency = .EUR
        XCTAssertFalse(Letter.showsKvgHint(kkEUR, data: d))
        XCTAssertFalse(Letter.showsKvgHint(c, data: d))
        // «Fehlt noch» erst, wenn beide Nummern fehlen
        XCTAssertTrue(Letter.showsMissingNumbers(kk))
        var withNo = kk
        withNo.customerNo = "9"
        XCTAssertFalse(Letter.showsMissingNumbers(withNo))
        // Prüfungen vor dem Senden: Nummer fehlt; ohne Person; Absender unvollständig
        XCTAssertEqual(Letter.mailChecks(kk, data: d), [.numberMissing])
        XCTAssertEqual(Letter.mailChecks(withNo, data: d), [])
        let lara = try! d.addPerson("Lara")
        var two = withNo
        two.holderIDs = [me, lara]
        XCTAssertEqual(Letter.mailChecks(two, data: d), [.senderIncomplete([lara])])
        XCTAssertEqual(Letter.mailCheckTexts(.senderIncomplete([lara]), data: d).text,
                       "Bei Lara fehlt die Adresse. Der Vertragspartner kann die Kündigung so schlechter zuordnen.")
        var none = withNo
        none.holderIDs = []
        XCTAssertEqual(Letter.mailChecks(none, data: d), [.noSigner])
        XCTAssertEqual(Letter.mailCheckTexts(.noSigner, data: d).title, "Wer kündigt?")
        XCTAssertEqual(Letter.mailCheckTexts(.numberMissing, data: d).no, "Ohne senden")
    }

    // MARK: Katalog «Rundfunkgebühr» (v158), Kündigungsweg Brief (v145)

    func testCatalogRundfunk() {
        XCTAssertNil(Catalog.find("Serafe"))
        XCTAssertNil(Catalog.find("Rundfunkbeitrag"))
        XCTAssertEqual(Catalog.find("Rundfunkgebühr", currency: .CHF)?.country, "CH")
        XCTAssertEqual(Catalog.find("Rundfunkgebühr", currency: .EUR)?.country, "DE")
        XCTAssertEqual(Catalog.find("Rundfunkgebühr", currency: .CHF)?.web, "serafe.ch")   // Katalog v224
        Format.homeCurrency = .EUR
        XCTAssertEqual(Catalog.find("Rundfunkgebühr")?.country, "DE")
        Format.homeCurrency = .CHF
        XCTAssertEqual(Catalog.find("Rundfunkgebühr")?.country, "CH")
        // Vorschläge: gleicher Name nur einmal
        XCTAssertEqual(Catalog.suggestions("rundfunk", currency: .CHF).map { $0.country }, ["CH"])
        XCTAssertEqual(Catalog.suggestions("rundfunk", currency: .EUR).map { $0.country }, ["DE"])
        XCTAssertFalse(Catalog.entries.contains { $0.name.contains("Serafe") || $0.label.contains("Serafe") })   // v224: Hinweis nennt Serafe als Stelle
        XCTAssertEqual(Catalog.find("Swiss Life")?.cancelChannel, .letter)
        XCTAssertEqual(Catalog.find("IWB")?.mandatory, false)
        XCTAssertTrue(ContractFormRules.taxInfo.contains("Rundfunkgebühr"))
        // Bank: Rundfunkbeitrag/Beitragsservice/Serafe → Rundfunkgebühr
        XCTAssertEqual(BankCatalog.entry(named: "Rundfunkgebühr", currency: "EUR")?.country, "DE")
        XCTAssertEqual(BankCatalog.entry(named: "Rundfunkgebühr", currency: "CHF")?.country, "CH")
    }

    func testCancelChannelMigration() throws {
        XCTAssertEqual(CancelChannel(webText: "Einschreiben"), .letter)
        XCTAssertEqual(CancelChannel(webText: "Brief"), .letter)
        XCTAssertEqual(CancelChannel.allCases, [.online, .email, .letter, .phone])   // Web v210: Telefon
        let old = try KontivoJSON.makeDecoder().decode([CancelChannel].self, from: Data(#"["registered","letter","online"]"#.utf8))
        XCTAssertEqual(old, [.letter, .letter, .online])
        // Web-Backup mit «Einschreiben»
        let json = """
        {"app":"vertraege","settings":{"home":"CHF"},"contracts":{"k":{"partner":"CSS","label":"KK","cat":"Versicherung","amount":1,"cycle":1,"cancF":"Einschreiben"}},"incomes":{}}
        """
        let r = try WebImport.importBackup(Data(json.utf8), today: today)
        XCTAssertEqual(r.data.contracts.first?.cancelChannel, .letter)
    }

    // MARK: Einnahmen (v155/v156/v159)

    func testIncomeKinds() throws {
        XCTAssertEqual(IncomeKind.allCases.map { $0.displayName },
                       ["Lohn", "Nebeneinkommen", "Bonus", "Rente", "Zulagen", "Unterstützung", "Kapitalerträge", "Vermietung", "Rückerstattung", "Sonstiges"])
        XCTAssertEqual(IncomeKind.zulagen.colorHex, "#B23A6F")
        XCTAssertEqual(IncomeKind.unterstuetzung.colorHex, "#3D6FA8")
        XCTAssertEqual(IncomeKind.rueckerstattung.colorHex, "#5F7A2E")
        XCTAssertEqual(IncomeKind(webName: "Unterstützung"), .unterstuetzung)
        let k = try KontivoJSON.makeDecoder().decode([IncomeKind].self, from: Data(#"["zulagen","gibtsnicht"]"#.utf8))
        XCTAssertEqual(k, [.zulagen, .sonstiges])
        let json = """
        {"app":"vertraege","settings":{"home":"CHF","holders":["Ich"]},"contracts":{"k":{"label":"x","amount":1,"cycle":1}},
         "incomes":{"i":{"name":"Kanton","cat":"Zulagen","amount":1200,"cycle":12,"due":"2026-12-15","holders":["Ich"]}}}
        """
        let r = try WebImport.importBackup(Data(json.utf8), today: today)
        XCTAssertEqual(r.data.incomes.first?.kind, .zulagen)
    }

    func testIncomeDetailAndSubline() {
        var d = AppData.initial()
        let me = d.persons[0].id
        let lohn = Income(name: "Firma AG", label: "Lohn", kind: .lohn, amount: 5000, cycle: 1, due: Day(2026, 10, 25), holderID: me)
        let zul = Income(name: "Kanton", kind: .zulagen, amount: 1200, cycle: 12, due: Day(2026, 12, 15), holderID: me)
        d.incomes = [lohn, zul]
        let calc = Calc(data: d, today: today)
        let a = calc.incomeDetail(lohn)
        XCTAssertEqual(a.title, "Lohn")
        XCTAssertEqual(a.subtitle, "Firma AG")
        XCTAssertNil(a.pill)
        XCTAssertEqual(a.mainLabel, "pro Monat")
        XCTAssertEqual(a.mainAmount, 5000, accuracy: 1e-9)
        XCTAssertEqual(a.sharePercent, 98)
        XCTAssertEqual(a.yearly ?? 0, 60000, accuracy: 1e-9)
        XCTAssertEqual(a.nextLabel, "nächste Zahlung")
        XCTAssertEqual(a.nextValue, "25.10.26")
        XCTAssertEqual(a.rows.map { $0.label + " : " + $0.value }, ["Zahlung : monatlich am 25.", "Art : Lohn", "Empfänger : Ich"])
        let b = calc.incomeDetail(zul)
        XCTAssertEqual(b.title, "Kanton")
        XCTAssertEqual(b.subtitle, "")
        XCTAssertEqual(b.mainAmount, 100, accuracy: 1e-9)
        XCTAssertEqual(b.sharePercent, 2)
        XCTAssertEqual(b.nextValue, "15.12.26")
        XCTAssertEqual(b.rows.map { $0.label + " : " + $0.value }, ["Zahlung : jährlich am 15. Dezember", "Art : Zulagen", "Empfänger : Ich"])
        // Zweitzeile: monatlich ohne, sonst Rhythmus (ab jährlich mit Monat), Empfänger nur bei mehreren Personen
        XCTAssertEqual(calc.kbIncomeSubline(lohn), "")
        XCTAssertEqual(calc.kbIncomeSubline(zul), "jährlich im Dezember")
        XCTAssertEqual(calc.kbIncomeSubline(Income(amount: 50, cycle: 0, due: Day(2026, 11, 1))), "einmalig")
        // Verlauf einer Einnahme: «mehr»/«weniger», Farben umgekehrt
        var up = zul
        up.prices = [PriceChange(from: Day(2026, 1, 1), amount: 1300)]
        let ch = calc.priceChart(up)
        XCTAssertEqual(ch?.badgeTone, .down)
        XCTAssertTrue(ch?.badgeText.hasSuffix(" mehr") ?? false)
        XCTAssertEqual(ContractFormRules.incomeDueFrom(day: 15, month: 12, cycle: 12, today: today), Day(2026, 12, 15))
    }

    func testPriceChartDropLabels() {
        var d = AppData.initial()
        let c = Contract(label: "p8", amount: 100, due: Day(2026, 10, 15), prices: [PriceChange(from: Day(2026, 9, 1), amount: 80)])
        d.contracts = [c]
        let ch = Calc(data: d, today: Day(2026, 10, 3)).priceChart(c)
        XCTAssertEqual(ch?.badgeText, "↓ 20 % günstiger")
        XCTAssertEqual(ch?.points.filter { $0.labeled }.map { $0.valueText }, ["100.00", "80.00"])
        XCTAssertEqual(ch?.points.map { $0.labelTrailing }, [false, true])
    }

    // MARK: Vollständigkeit / Datenqualität (v143, v160)

    func testCompletenessEndsSelfAndLogosOptional() {
        var d = AppData.initial()
        let me = d.persons[0].id
        let other = d.category(named: "Sonstiges")!.id
        let p = Partner(name: "Leasing AG")
        d.partners = [p]
        // feste Laufzeit ohne Verlängerung: weder Frist noch Absender nötig
        d.contracts = [Contract(label: "Auto", partnerID: p.id, categoryID: other, amount: 300, due: Day(2026, 10, 20), end: Day(2027, 6, 30),
                                holderIDs: [me])]
        let r = Completeness.report(d, today: today)
        XCTAssertEqual(r.per[d.contracts[0].id], [])
        XCTAssertEqual(r.ready, 1)
        XCTAssertEqual(r.logoPartners, [p.id])
        XCTAssertTrue(r.onlyLogosMissing)
        XCTAssertEqual(Completeness.readyLogosText(r.logoPartners.count), "Kontivo erinnert dich vor jeder Frist. Optional: 1 Vertragspartner hat noch kein Logo.")
        XCTAssertEqual(Completeness.logoApplyTitle(0), "Ohne Logos fertig")
        XCTAssertEqual(Completeness.endHeadline(r, single: true), "Startklar!")
        XCTAssertTrue(Completeness.showsEndList(r))
        let q = Quality.report(d, today: today)
        XCTAssertFalse(q.all.contains { $0.key == "c:" + d.contracts[0].id.uuidString + ":notice" })
    }

    // MARK: CSV (v143/v156)

    func testCSVColumnsV156() {
        let f = fixture()
        let rows = CSV.parse(CSV.export(f.data, today: today))
        let head = rows[0]
        XCTAssertEqual(head.count, 42)
        func v(_ label: String, _ k: String) -> String {
            let r = rows.first { $0.count > 1 && $0[1] == label }!
            return r[head.firstIndex(of: k)!]
        }
        // Web v160 gemessen: NaechsteZahlung | KuendigenBis | KuendbarPer | Zahlungsanker
        XCTAssertEqual([v("Netflix", "NaechsteZahlung"), v("Netflix", "KuendigenBis"), v("Netflix", "KuendbarPer"), v("Netflix", "Zahlungsanker")],
                       ["2026-10-20", "", "jederzeit", "2026-10-20"])
        XCTAssertEqual([v("Auto", "KuendigenBis"), v("Auto", "KuendbarPer")], ["2027-03-31", ""])
        XCTAssertEqual([v("Abo", "NaechsteZahlung"), v("Abo", "KuendigenBis"), v("Abo", "KuendbarPer")], ["2027-03-20", "2027-03-31", "m"])
        XCTAssertEqual([v("TV", "NaechsteZahlung"), v("TV", "Zahlungsanker")], ["2026-11-05", "2026-10-05"])
        XCTAssertEqual([v("Kurs", "NaechsteZahlung"), v("Kurs", "KuendigenBis"), v("Kurs", "KuendbarPer"), v("Kurs", "Kuendigungsweg")], ["", "", "", "Brief"])
        XCTAssertEqual([v("Archiviert", "KuendigenBis"), v("Archiviert", "Status")], ["", "cancelled"])
        XCTAssertEqual([v("Internet", "KuendigenBis"), v("Internet", "KuendbarPer"), v("Internet", "Kuendigungsweg")], ["", "m", "Online / Kundenkonto"])
        XCTAssertEqual([v("Wohnung", "KuendigenBis"), v("Wohnung", "KuendbarPer")], ["2026-12-31", "q"])
        XCTAssertEqual([v("Steuern", "KuendigenBis"), v("Steuern", "KuendbarPer")], ["", ""])

        // Rundlauf: Zahlungsanker geht vor «NaechsteZahlung» (31. bleibt 31.)
        var src = AppData.initial()
        src.contracts = [Contract(label: "Miete", categoryID: src.category(named: "Wohnen")!.id, amount: 1000, cycle: 1, due: Day(2026, 1, 31),
                                  holderIDs: [src.persons[0].id])]
        let pv = CSV.preview(csv: Data(CSV.export(src, today: Day(2026, 2, 10)).utf8), data: AppData.initial(), today: Day(2026, 2, 10))
        XCTAssertEqual(pv.items.first?.contract.due, Day(2026, 1, 31))
        // Spalten «Personen» / «Kuendigungsweg» / «Rhythmus_Monate» werden gelesen
        let rows2 = [["Vertragspartner", "Betrag", "Rhythmus_Monate", "Personen", "Kuendigungsweg", "KuendbarPer"],
                     ["Netflix", "18.90", "3", "Lara", "Einschreiben", "m"]]
        let pv2 = CSV.preview(rows: rows2, data: AppData.initial(), today: today)
        XCTAssertEqual(pv2.items.first?.contract.cycle, 3)
        XCTAssertEqual(pv2.items.first?.holderNames, ["Lara"])
        XCTAssertEqual(pv2.items.first?.contract.cancelChannel, .letter)
    }

    // MARK: Backup (v143)

    func testBackupStructureAndEmpty() {
        let wrong = #"{"app":"vertraege","contracts":[],"incomes":{}}"#
        XCTAssertFalse(WebImport.isWebBackup(Data(wrong.utf8)))
        XCTAssertThrowsError(try Backup.read(Data(wrong.utf8), today: today)) { e in
            XCTAssertEqual(e as? BackupError, .invalidFile)
            XCTAssertEqual((e as? BackupError)?.message, "Keine gültige Backup-Datei – es wurde nichts geändert")
        }
        let badInc = #"{"app":"vertraege","contracts":{},"incomes":[]}"#
        XCTAssertThrowsError(try Backup.read(Data(badInc.utf8), today: today)) { e in XCTAssertEqual(e as? BackupError, .invalidFile) }
        let empty = #"{"app":"vertraege","contracts":{},"incomes":{}}"#
        XCTAssertThrowsError(try Backup.read(Data(empty.utf8), today: today)) { e in
            XCTAssertEqual(e as? BackupError, .empty)
            XCTAssertEqual((e as? BackupError)?.message, "Das Backup enthält keine Verträge – es wurde nichts geändert")
        }
        let noInc = #"{"app":"vertraege","contracts":{"a":{"label":"x","amount":1,"cycle":1}}}"#
        XCTAssertNoThrow(try Backup.read(Data(noInc.utf8), today: today))
        XCTAssertEqual(Backup.confirmText(exported: nil, contracts: 2, incomes: 1, files: 0),
                       "Backup (Datum unbekannt) mit 2 Verträgen und 1 Einnahme.\n\nDie aktuellen Daten werden ersetzt.")
        // trialKept true (CSV-Import der Web-App) → Datum des Probeabos
        let tk = #"{"app":"vertraege","contracts":{"a":{"label":"x","amount":1,"cycle":1,"trial":"2026-10-20","trialKept":true}},"incomes":{}}"#
        XCTAssertEqual(try? WebImport.importBackup(Data(tk.utf8), today: today).data.contracts.first?.trialKept, Day(2026, 10, 20))
    }

    // MARK: Mutationen

    func testSaveRulesAndHolderSplit() throws {
        var d = AppData.initial()
        let me = d.persons[0].id
        let lara = try d.addPerson("Lara")
        let cat = d.category(named: "Sonstiges")!.id
        // Nicht kündbar: Frist 0 (Web v153)
        let id = try d.saveContract(Contract(label: "Gebühr", categoryID: cat, amount: 10, notice: 3, noCancel: true, holderIDs: [me]), today: today)
        XCTAssertEqual(d.contract(id)?.notice, 0)
        // Aufteilung bleibt beim Umschalten erhalten (Web v143)
        var c = Contract(label: "WG", categoryID: cat, amount: 100, holderIDs: [me, lara])
        c.split = [SplitShare(personID: me, percent: 70), SplitShare(personID: lara, percent: 30)]
        d.contracts.append(c)
        let ch1 = d.applyHolderChoice(contract: c.id, choice: .person(me))
        XCTAssertTrue(ch1)
        XCTAssertEqual(d.contract(c.id)?.split.count, 2)
        let ch2 = d.applyHolderChoice(contract: c.id, choice: .all)
        XCTAssertTrue(ch2)
        XCTAssertEqual(d.contract(c.id)?.validSplit?[me], 70)
        // bekannte Währung des Vertragspartners
        var e = d
        let nf = e.partnerID(forName: "Netflix")
        e.contracts = [Contract(label: "A", partnerID: nf, categoryID: cat, amount: 10, currency: .EUR)]
        XCTAssertEqual(e.knownPartnerCurrency(name: " netflix "), .EUR)
        XCTAssertNil(e.knownPartnerCurrency(name: "Spotify"))
        XCTAssertNil(e.knownPartnerCurrency(name: "Netflix", excluding: e.contracts[0].id))
        XCTAssertEqual(AppData.keepToast, "Behalten – Kontivo erinnert dich vor der nächsten Frist")
        XCTAssertEqual(CancelResult.replacementFormTitle, "Neuer Vertragspartner")
    }
}
