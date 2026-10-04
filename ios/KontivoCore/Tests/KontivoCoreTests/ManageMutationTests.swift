import XCTest
@testable import KontivoCore

/// Fachaktionen des Bereichs «Verwalten» (ExtManage.swift)
final class ManageMutationTests: XCTestCase {
    let today = Day(2026, 10, 3)

    func base() -> AppData {
        var data = AppData.initial()
        data.persons = [Person(name: "Sinan"), Person(name: "Lara")]
        return data
    }

    func testNoticeValueLikeWeb() {
        XCTAssertEqual(AppData.mdNoticeValue("", unit: .months), 0)
        XCTAssertEqual(AppData.mdNoticeValue("  ", unit: .months), 0)
        XCTAssertEqual(AppData.mdNoticeValue("3", unit: .months), 3)
        XCTAssertEqual(AppData.mdNoticeValue("0", unit: .weeks), 0)
        XCTAssertNil(AppData.mdNoticeValue("1.5", unit: .months))
        XCTAssertNil(AppData.mdNoticeValue("2,5", unit: .months))
        XCTAssertNil(AppData.mdNoticeValue("-1", unit: .days))
        XCTAssertNil(AppData.mdNoticeValue("3abc", unit: .months))
        XCTAssertNil(AppData.mdNoticeValue("0", unit: .dayOfMonth))
        XCTAssertNil(AppData.mdNoticeValue("31", unit: .dayOfMonth))
        XCTAssertEqual(AppData.mdNoticeValue("28", unit: .dayOfMonth), 28)
        XCTAssertEqual(AppData.mdNoticeValue("", unit: .dayOfMonth), 0)
    }

    func testCheckNoticeOrderAndTexts() {
        XCTAssertEqual(AppData.mdCheckNotice("x", unit: .months, choice: .unset, end: nil), .invalid("Kündigungsfrist prüfen"))
        XCTAssertEqual(AppData.mdCheckNotice("3", unit: .months, choice: .fixed, end: nil), .invalid("Bitte das Vertragsende eingeben"))
        XCTAssertEqual(AppData.mdCheckNotice("3", unit: .months, choice: .unset, end: nil), .invalid("Bitte wählen, worauf kündbar"))
        XCTAssertEqual(AppData.mdCheckNotice("3", unit: .months, choice: .fixed, end: Day(2027, 12, 31)), .ok(3))
        XCTAssertEqual(AppData.mdCheckNotice("", unit: .months, choice: .anytime, end: nil), .ok(0))
    }

    func testTermChoiceInitial() {
        XCTAssertEqual(MDTermChoice.initial(for: Contract(end: Day(2027, 1, 31))), .fixed)
        XCTAssertEqual(MDTermChoice.initial(for: Contract(renewMonths: 12)), .fixed)
        XCTAssertEqual(MDTermChoice.initial(for: Contract(cancelTerm: .yearEnd)), .term(.yearEnd))
        XCTAssertEqual(MDTermChoice.initial(for: Contract(notice: 1)), .anytime)
        XCTAssertEqual(MDTermChoice.initial(for: Contract()), .unset)
        XCTAssertEqual(MDTermChoice.options[1].title, "jederzeit (mit Frist)")
    }

    func testSetNoticeAndToasts() {
        var data = base()
        let c = Contract(label: "Handy", amount: 30, cycle: 1, due: Day(2026, 10, 15), end: Day(2027, 3, 31), renewMonths: 12)
        data.contracts = [c]
        // Termin: Laufzeit wird geleert
        data.mdSetNotice(c.id, notice: 3, unit: .months, choice: .term(.yearEnd), end: nil, renew: 0)
        XCTAssertEqual(data.contracts[0].cancelTerm, .yearEnd)
        XCTAssertNil(data.contracts[0].end)
        XCTAssertEqual(data.contracts[0].renewMonths, 0)
        XCTAssertEqual(data.mdNoticeSavedToast(c.id, today: today), "Handy: gespeichert")
        // Feste Laufzeit
        data.mdSetNotice(c.id, notice: 1, unit: .months, choice: .fixed, end: Day(2027, 12, 31), renew: 12)
        XCTAssertEqual(data.contracts[0].end, Day(2027, 12, 31))
        XCTAssertEqual(data.contracts[0].renewMonths, 12)
        XCTAssertEqual(data.contracts[0].cancelTerm, .anytime)
        // jederzeit ohne Frist
        data.mdSetNotice(c.id, notice: 0, unit: .months, choice: .anytime, end: nil, renew: 0)
        XCTAssertEqual(data.mdNoticeSavedToast(c.id, today: today), "Gespeichert. Für «jederzeit» bitte eine Frist eintragen")
        // Vertragsjahr ohne Beginn und ohne Zahlungstermin: Termin nicht berechenbar
        let d = Contract(label: "Abo", amount: 10, cycle: 1)
        data.contracts.append(d)
        data.mdSetNotice(d.id, notice: 3, unit: .months, choice: .term(.contractYear), end: nil, renew: 0)
        if Calc(data: data, today: today).noticeDeadline(data.contract(d.id)!) == nil {
            XCTAssertEqual(data.mdNoticeSavedToast(d.id, today: today), "Gespeichert. Für «Ende Vertragsjahr» fehlt noch das Startdatum im Vertrag")
        }
    }

    func testSimpleSetters() {
        var data = base()
        let s = data.persons[0].id, l = data.persons[1].id
        let ins = data.category(named: "Versicherung")!.id
        let c = Contract(label: "Miete")
        let i = Income(name: "Lohn")
        data.contracts = [c]
        data.incomes = [i]
        data.mdSetHolders(contract: c.id, [l, s])
        XCTAssertEqual(data.contracts[0].holderIDs, [s, l], "Reihenfolge der Personenliste")
        data.mdSetContractAmount(c.id, Format.parseNum("1.284,50")!)
        XCTAssertEqual(data.contracts[0].amount, 1284.5)
        data.mdSetContractAmount(c.id, 12.346)
        XCTAssertEqual(data.contracts[0].amount, 12.35, accuracy: 0.0001)
        data.mdSetContractCategory(c.id, ins)
        XCTAssertEqual(data.contracts[0].categoryID, ins)
        data.mdSetContractCategory(c.id, UUID())
        XCTAssertEqual(data.contracts[0].categoryID, ins, "unbekannte Kategorie wird ignoriert")
        data.mdSetContractCycle(c.id, 12)
        XCTAssertEqual(data.contracts[0].cycle, 12)
        data.mdSetContractDue(c.id, Day(2026, 11, 1))
        XCTAssertEqual(data.contracts[0].due, Day(2026, 11, 1))
        data.mdSetCustomerNo(c.id, "  K-1 ")
        data.mdSetCancelURL(c.id, " sunrise.ch/kuendigen ")
        data.mdSetContractMail(c.id, " a@b.ch ")
        XCTAssertEqual(data.contracts[0].customerNo, "K-1")
        XCTAssertEqual(data.contracts[0].cancelURL, "sunrise.ch/kuendigen")
        XCTAssertEqual(data.contracts[0].mail, "a@b.ch")
        data.mdSetIncomeAmount(i.id, Format.parseNum("1’000.456")!)
        XCTAssertEqual(data.incomes[0].amount, 1000.46, accuracy: 0.0001)
    }

    func testContractAddressCreatesPartner() {
        var data = base()
        let c = Contract(label: "Wohnung")
        data.contracts = [c]
        let pid = data.mdSetContractAddress(c.id, company: "  Verwaltung   AG ", address: PostalAddress(street: "Seestr. 1", zip: "8280", city: "Kreuzlingen"))
        XCTAssertNotNil(pid)
        XCTAssertEqual(data.contracts[0].partnerID, pid)
        XCTAssertEqual(data.partner(pid)?.name, "Verwaltung AG")
        XCTAssertEqual(data.partner(pid)?.address.company, "Verwaltung AG")
        XCTAssertEqual(data.partner(pid)?.address.city, "Kreuzlingen")
        // mit Vertragspartner: Adresse dort
        XCTAssertEqual(data.mdSetContractAddress(c.id, company: "", address: PostalAddress(company: "X", street: "Neu 2", city: "Konstanz")), pid)
        XCTAssertEqual(data.partner(pid)?.address.street, "Neu 2")
        XCTAssertEqual(data.partners.count, 1)
    }

    func testCategoryContractsAndPerMonth() {
        var data = base()
        let other = data.otherCategory!.id
        let ins = data.category(named: "Versicherung")!.id
        data.contracts = [Contract(label: "A", categoryID: ins, amount: 100, cycle: 1, due: Day(2026, 10, 15)),
                          Contract(label: "B", categoryID: nil, amount: 120, cycle: 12, due: Day(2026, 12, 1)),
                          Contract(label: "C", categoryID: UUID(), amount: 10, cycle: 1, due: Day(2026, 10, 20)),
                          Contract(label: "D", categoryID: ins, amount: 50, cycle: 1, due: Day(2026, 10, 15), status: .cancelled)]
        XCTAssertEqual(data.mdContracts(inCategory: ins).map(\.label), ["A", "D"])
        XCTAssertEqual(data.mdContracts(inCategory: other).map(\.label), ["B", "C"])
        XCTAssertEqual(data.mdPerMonth(data.mdContracts(inCategory: ins), today: today), 100, accuracy: 0.001)
        XCTAssertEqual(data.mdPerMonth(data.mdContracts(inCategory: other), today: today), 20, accuracy: 0.001)
    }

    func testSharedEntries() {
        var data = base()
        let s = data.persons[0].id, l = data.persons[1].id
        data.contracts = [Contract(label: "A", holderIDs: [s, l]), Contract(label: "B", holderIDs: [s]), Contract(label: "C", holderIDs: [l, s])]
        XCTAssertEqual(data.sharedEntryCount(s, l), 2)
        XCTAssertEqual(data.sharedEntryCount(l, s), 2)
    }
}
