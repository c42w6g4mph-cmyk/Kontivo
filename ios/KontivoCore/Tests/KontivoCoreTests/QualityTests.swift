import XCTest
@testable import KontivoCore

final class QualityTests: XCTestCase {
    let today = Day(2026, 10, 3)

    func testCoreRules() {
        var data = AppData.initial()
        let me = data.persons[0].id
        let abos = data.category(named: "Abos & Medien")!.id
        let sunrise = Partner(name: "Sunrise")
        data.partners = [sunrise]
        let a = Contract(label: "Leer", amount: 0, cycle: 1)
        let b = Contract(label: "Internet", partnerID: sunrise.id, categoryID: abos, amount: 20, cycle: 1, due: Day(2026, 10, 15),
                         notice: 1, cancelTerm: .anytime, holderIDs: [me], cancelChannel: .letter)
        let c = Contract(label: "Archiv", amount: 0, cycle: 1, status: .cancelled)
        let d = Contract(label: "Gekündigt", categoryID: abos, amount: 10, cycle: 1, due: Day(2026, 10, 15), holderIDs: [me], cancelPer: Day(2026, 11, 30))
        data.contracts = [a, b, c, d]
        data.incomes = [Income(name: "Lohn", amount: 0)]

        let r = Quality.report(data, today: today)
        let keys = Set(r.all.map { $0.key })
        let ka = "c:" + a.id.uuidString + ":"
        let kb = "c:" + b.id.uuidString + ":"
        XCTAssertTrue(keys.contains(ka + "holder"))
        XCTAssertTrue(keys.contains(ka + "amount"))
        XCTAssertTrue(keys.contains(ka + "cat"))
        XCTAssertTrue(keys.contains(ka + "due"))
        XCTAssertTrue(keys.contains(ka + "via"))
        XCTAssertTrue(keys.contains(ka + "notice"))
        XCTAssertEqual(r.A.first { $0.key == ka + "cat" }?.reason, "Keine Kategorie")
        XCTAssertEqual(r.B.first { $0.key == ka + "notice" }?.reason, "Keine Kündigungsfrist")
        // «jederzeit» mit Frist ist vollständig (Fix N2)
        XCTAssertFalse(keys.contains(kb + "notice"))
        XCTAssertTrue(keys.contains(kb + "ref"))
        XCTAssertFalse(keys.contains(kb + "via"))
        XCTAssertTrue(keys.contains("p:" + sunrise.id.uuidString + ":addr"))
        XCTAssertTrue(keys.contains("p:" + sunrise.id.uuidString + ":logo"))
        XCTAssertTrue(keys.contains("h:" + me.uuidString + ":sender"))
        XCTAssertEqual(r.D.first { $0.criterion == .sender }?.reason, "Absender unvollständig")
        XCTAssertEqual(r.D.first { $0.criterion == .sender }?.senderLevel, 2)
        // Archiv wird nicht geprüft (Fix M5)
        XCTAssertFalse(keys.contains { $0.contains(c.id.uuidString) })
        // Gekündigt: kein Kündigungsweg mehr nötig
        XCTAssertFalse(keys.contains("c:" + d.id.uuidString + ":via"))
        XCTAssertTrue(keys.contains("i:" + data.incomes[0].id.uuidString + ":holder"))
        XCTAssertTrue(keys.contains("i:" + data.incomes[0].id.uuidString + ":amount"))
        XCTAssertEqual(r.contractCount, 3)
        XCTAssertEqual(r.select(.A, field: "inc").count, 2)
        XCTAssertEqual(r.select(.A, field: "holder").count, 1)
        XCTAssertEqual(r.select(.D, field: "addr").count, 1)

        // Ignorieren
        data.ignoreQuality([ka + "holder", kb + "ref"])
        let r2 = Quality.report(data, today: today)
        XCTAssertEqual(r2.ignoredCount, 2)
        XCTAssertFalse(r2.all.contains { $0.key == ka + "holder" })
        XCTAssertEqual(r2.totalCount, r.totalCount - 2)
        XCTAssertEqual(Quality.ignoredText(r2), "2 ignoriert")
        data.resetQualityIgnored()
        XCTAssertEqual(Quality.report(data, today: today).ignoredCount, 0)
    }

    func testCleanAndTaxes() {
        var data = AppData.initial()
        let me = data.persons[0].id
        data.persons[0].sender = SenderAddress(first: "Sinan", last: "B", street: "Hauptstr. 1", zip: "8280", city: "Kreuzlingen")
        let tax = data.category(named: "Steuern & Gebühren")!.id
        let ins = data.category(named: "Versicherung")!.id
        let p = Partner(name: "CSS", logoID: "logo1", address: PostalAddress(company: "CSS", street: "Tribschenstrasse 21", zip: "6005", city: "Luzern"))
        data.partners = [p]
        data.contracts = [
            Contract(label: "Steuern", categoryID: tax, amount: 1000, cycle: 3, due: Day(2026, 11, 30), holderIDs: [me]),
            Contract(label: "Krankenkasse", partnerID: p.id, categoryID: ins, amount: 400, cycle: 1, due: Day(2026, 10, 15),
                     notice: 1, cancelTerm: .yearEnd, mandatory: true, customerNo: "123", holderIDs: [me]),
        ]
        let r = Quality.report(data, today: today)
        XCTAssertEqual(r.totalCount, 0, r.all.map { $0.key + " " + $0.reason }.joined(separator: ", "))
        XCTAssertEqual(Quality.summary(r), "Sauber gepflegt ✓")
        XCTAssertEqual(Quality.headline(r)?.title, "Sauber gepflegt. Alle 2 Verträge sind vollständig.")
        XCTAssertEqual(Quality.checklistSubtitle(r), "2 Verträge")
        // Versicherung ohne Kündigungsweg → Brief; ohne Logo-Datei → Logo fehlt
        let r2 = Quality.report(data, today: today, hasFile: { _ in false })
        XCTAssertEqual(r2.C.count, 1)
        XCTAssertEqual(Quality.summary(r2), "1 Eintrag offen")
    }
}
