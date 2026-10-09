import XCTest
@testable import KontivoCore

/// Erinnerungen vor Fristen (Plan der lokalen Mitteilungen), Kalendertexte und «Behalten · läuft bis» (Web v133 keptEnd).
final class RemindersTests: XCTestCase {
    private let today = Day(2026, 10, 8)

    private func data(_ contracts: [Contract], partners: [Partner] = []) -> AppData {
        var d = AppData.initial()
        d.partners = partners
        d.contracts = contracts
        return d
    }

    /// Handy bei Nimbo Mobile: befristet bis 31.12.2026, 1 Monat Frist, verlängert sich um 12 Monate → Frist 30.11.2026
    private func handy(_ p: Partner, mandatory: Bool = false) -> Contract {
        Contract(label: "Handy", partnerID: p.id, amount: 30, cycle: 1, end: Day(2026, 12, 31),
                 notice: 1, noticeUnit: .months, renewMonths: 12, mandatory: mandatory, customerNo: "K-77")
    }

    func testPlanTwoRemindersAtNine() {
        let p = Partner(name: "Nimbo Mobile", web: "nimbo.ch")
        let c = handy(p)
        let calc = Calc(data: data([c], partners: [p]), today: today)
        let dl = calc.reminderDeadline(for: c)
        XCTAssertEqual(dl?.kind, .notice)
        XCTAssertEqual(dl?.date, Day(2026, 11, 30))
        XCTAssertEqual(dl?.end, Day(2026, 12, 31))

        let plan = Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 8 * 60)
        XCTAssertEqual(plan.map { $0.fireDay }, [Day(2026, 11, 23), Day(2026, 11, 30)])
        XCTAssertEqual(plan.map { $0.leadDays }, [7, 0])
        XCTAssertTrue(plan.allSatisfy { $0.hour == 9 && $0.minute == 0 && $0.contractID == c.id })
        XCTAssertEqual(plan[0].title, "Kündigen bis 30. November: Handy (Nimbo Mobile)")
        XCTAssertEqual(plan[0].body, "Noch 7 Tage. Die Kündigung muss bis 30. November beim Vertragspartner sein. Behalten oder kündigen?")
        XCTAssertEqual(plan[1].body, "Heute ist der letzte Tag. Die Kündigung muss heute beim Vertragspartner sein. Behalten oder kündigen?")
        XCTAssertEqual(plan[0].id, "kontivo.frist." + c.id.uuidString + ".notice.2026-11-30.7")
        XCTAssertEqual(plan[1].id, "kontivo.frist." + c.id.uuidString + ".notice.2026-11-30.0")
        XCTAssertEqual(Set(plan.map { $0.id }).count, 2)
        XCTAssertEqual(Reminders.contractID(fromIdentifier: plan[0].id), c.id)
        XCTAssertNil(Reminders.contractID(fromIdentifier: "anderes.\(c.id.uuidString)"))

        // nur am letzten Tag (Tage vorher 0) bzw. 30 Tage vorher
        XCTAssertEqual(Reminders.plan(calc: calc, leadDays: 0, minuteOfDay: 0).map { $0.fireDay }, [Day(2026, 11, 30)])
        XCTAssertEqual(Reminders.plan(calc: calc, leadDays: 30, minuteOfDay: 0).map { $0.fireDay }, [Day(2026, 10, 31), Day(2026, 11, 30)])
        // 60 Tage vorher läge in der Vergangenheit → nur der letzte Tag
        XCTAssertEqual(Reminders.plan(calc: calc, leadDays: 60, minuteOfDay: 0).count, 1)
    }

    func testMandatoryAndOtherYear() {
        let p = Partner(name: "CSS")
        var c = handy(p, mandatory: true)
        c.label = "Krankenkasse"
        c.end = Day(2027, 12, 31)
        let calc = Calc(data: data([c], partners: [p]), today: today)
        let plan = Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 0)
        XCTAssertEqual(plan.first?.title, "Wechseln bis 30. November 2027: Krankenkasse (CSS)")
        XCTAssertTrue(plan.first?.body.hasSuffix("Wechseln oder behalten?") ?? false)
        XCTAssertEqual(Reminders.calendarTitle(plan[0].deadline, contract: c, data: calc.data), "Letzter Tag zum Wechseln: Krankenkasse (CSS)")
    }

    func testTrialUsesDayBeforeEnd() {
        let c = Contract(label: "Netflix", amount: 15, cycle: 1, trial: Day(2026, 10, 15))
        let calc = Calc(data: data([c]), today: today)
        let dl = calc.reminderDeadline(for: c)
        XCTAssertEqual(dl?.kind, .trial)
        XCTAssertEqual(dl?.date, Day(2026, 10, 15))
        XCTAssertEqual(dl?.lastDay, Day(2026, 10, 14))
        // 7 Tage vor dem 14.10. ist vorbei → nur am letzten Tag
        let plan = Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 0)
        XCTAssertEqual(plan.map { $0.fireDay }, [Day(2026, 10, 14)])
        XCTAssertEqual(plan[0].title, "Probeabo endet am 15. Oktober: Netflix")
        XCTAssertEqual(plan[0].id, "kontivo.frist." + c.id.uuidString + ".trial.2026-10-15.0")
        XCTAssertTrue(plan[0].body.contains("vor dem 15. Oktober beim Vertragspartner"))
        XCTAssertEqual(Reminders.plan(calc: calc, leadDays: 3, minuteOfDay: 0).map { $0.fireDay }, [Day(2026, 10, 11), Day(2026, 10, 14)])
        // behalten → keine Erinnerung mehr
        var kept = c
        kept.trialKept = kept.trial
        XCTAssertNil(Calc(data: data([kept]), today: today).reminderDeadline(for: kept))
    }

    func testExclusions() {
        let p = Partner(name: "Nimbo Mobile")
        var unwatched = handy(p); unwatched.noWatch = true
        var cancelled = handy(p); cancelled.cancelPer = Day(2026, 12, 31)
        var fixed = handy(p); fixed.noCancel = true
        var archived = handy(p); archived.status = .cancelled
        let anytime = Contract(label: "Streaming", amount: 10, cycle: 1, due: Day(2026, 10, 20), notice: 0, cancelTerm: .monthEnd)
        let calc = Calc(data: data([unwatched, cancelled, fixed, archived, anytime], partners: [p]), today: today)
        XCTAssertTrue(calc.reminderDeadlines().isEmpty)
        XCTAssertTrue(Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 0).isEmpty)
    }

    func testTodayOnlyBeforeNine() {
        // Frist heute (Ende 08.11., 1 Monat Frist, ohne Verlängerung)
        let c = Contract(label: "Fitness", amount: 80, cycle: 1, end: Day(2026, 11, 8), notice: 1, noticeUnit: .months)
        let calc = Calc(data: data([c]), today: today)
        XCTAssertEqual(calc.reminderDeadline(for: c)?.date, today)
        XCTAssertEqual(Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 8 * 60 + 59).map { $0.fireDay }, [today])
        XCTAssertTrue(Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 9 * 60).isEmpty)
    }

    func testLimitNearestFirst() {
        var list: [Contract] = []
        for i in 0..<40 {
            // Fristen am 30.11.2026, 31.12.2026 (Ende 31.01.), … je einen Monat später
            list.append(Contract(label: "V\(i)", amount: 10, cycle: 1, end: Day(2026, 12 + i, 31).lastDayOfMonth,
                                 notice: 1, noticeUnit: .months, renewMonths: 12))
        }
        let calc = Calc(data: data(list), today: today)
        let plan = Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 0)
        XCTAssertEqual(plan.count, Reminders.maxPending)
        XCTAssertTrue(zip(plan, plan.dropFirst()).allSatisfy { $0.fireDay <= $1.fireDay }, "nächste zuerst")
        XCTAssertEqual(plan.first?.contractID, list[0].id)
        XCTAssertEqual(Set(plan.map { $0.id }).count, plan.count)
        XCTAssertEqual(Reminders.plan(calc: calc, leadDays: 7, minuteOfDay: 0, limit: 5).count, 5)
    }

    func testKeptNextDeadlineAndKeptEnd() {
        let p = Partner(name: "Nimbo Mobile")
        var kept = handy(p)
        kept.keptFor = Day(2026, 12, 31)
        let calc = Calc(data: data([kept], partners: [p]), today: today)
        XCTAssertEqual(calc.reminderDeadline(for: kept)?.date, Day(2027, 11, 30))
        XCTAssertEqual(calc.deadlineOverview().items.first?.sub, "Behalten · nächste Frist 30.11.27")

        // Befristet ohne Verlängerung, behalten: «Behalten · läuft bis 31.12.», keine Erinnerung
        var once = Contract(label: "Zeitung", amount: 20, cycle: 1, end: Day(2026, 12, 31), notice: 1, noticeUnit: .months)
        once.keptFor = Day(2026, 12, 31)
        let c2 = Calc(data: data([once]), today: today)
        let item = c2.deadlineOverview().items.first
        XCTAssertEqual(item?.sub, "Behalten · läuft bis 31.12.")
        XCTAssertEqual(item?.date, Day(2026, 12, 31))
        XCTAssertEqual(item?.chipLevel, .ok)
        XCTAssertNil(c2.reminderDeadline(for: once))
    }

    func testCalendarNotes() throws {
        let p = Partner(name: "Nimbo Mobile", web: "nimbo.ch", address: PostalAddress(company: "Nimbo AG", street: "Weg 1", zip: "8000", city: "Zürich"))
        var c = handy(p)
        c.cancelChannel = .online
        let calc = Calc(data: data([c], partners: [p]), today: today)
        let d = try XCTUnwrap(calc.reminderDeadline(for: c))
        XCTAssertEqual(Reminders.calendarTitle(d, contract: c, data: calc.data), "Letzter Tag zum Kündigen: Handy (Nimbo Mobile)")
        let notes = Reminders.calendarNotes(d, contract: c, calc: calc)
        XCTAssertEqual(notes.components(separatedBy: "\n"), [
            "Vertragspartner: Nimbo Mobile",
            "Kündigungsweg: Online / Kundenkonto",
            "Link: https://nimbo.ch",
            "Kundennummer: K-77",
            "Kündigung muss bis 30. November 2026 beim Vertragspartner sein.",
            "Vertragsende: 31. Dezember 2026",
            "In Kontivo unter «Fristen» mit einem Tipp kündigen.",
        ])
        c.cancelChannel = .letter
        let post = Reminders.calendarNotes(d, contract: c, calc: Calc(data: data([c], partners: [p]), today: today))
        XCTAssertTrue(post.contains("Kündigungsweg: Brief"))
        XCTAssertTrue(post.contains("Adresse: Nimbo AG, Weg 1, 8000 Zürich"))
    }
}
