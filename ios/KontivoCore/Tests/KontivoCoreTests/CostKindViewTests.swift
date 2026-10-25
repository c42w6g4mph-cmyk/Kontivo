import XCTest
@testable import KontivoCore

/// Tab «Kosten» mit Kostenart und Bericht inkl. variabler Kosten (Web v230/v234/v239, `renderStat`, `varGroupHtml`, `repData`).
/// Erwartungswerte aus der Web-App v330 (Demo-Daten wie CostDriversReportTests plus vier variable Kosten, Stichtag 03.10.2026).
final class CostKindViewTests: XCTestCase {
    private func demo(kind: CostKind = .all) throws -> Calc {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "costs_demo_backup", withExtension: "json")
            ?? Bundle.module.url(forResource: "costs_demo_backup", withExtension: "json", subdirectory: "Resources"))
        let today = Day(2026, 10, 3)
        var d = try WebImport.importBackup(try Data(contentsOf: url), today: today).data
        let s: UUID = try XCTUnwrap(d.persons.first { $0.name == "Sinan" }?.id)
        let l: UUID = try XCTUnwrap(d.persons.first { $0.name == "Lara" }?.id)
        let t0 = Date(timeIntervalSince1970: 0)
        d.putVariableCost(VariableCost(label: "", icon: .benzin, amount: 180, holderIDs: [s], createdAt: t0))
        d.putVariableCost(VariableCost(label: "Lebensmittel", icon: .essen, amount: 650, holderIDs: [s, l], start: Day(2026, 3, 15),
                                       createdAt: t0.addingTimeInterval(1)))
        d.putVariableCost(VariableCost(label: "Auswärts essen", icon: .aus, amount: 120, currency: .EUR, holderIDs: [l], end: Day(2027, 2, 10),
                                       createdAt: t0.addingTimeInterval(2)))
        d.putVariableCost(VariableCost(label: "Ferien alt", icon: .ferien, amount: 300, holderIDs: [l], end: Day(2026, 5, 31),
                                       createdAt: t0.addingTimeInterval(3)))
        d.settings.costKind = kind
        return Calc(data: d, today: today)
    }

    private func lara(_ c: Calc) -> UUID? { c.data.persons.first { $0.name == "Lara" }?.id }

    func testKindYearAll() throws {
        let calc = try demo()
        let f = Calc.CostFilter()
        let cy = calc.costYear(2026, filter: f)
        let ky = calc.costKindYear(cy, filter: f)
        XCTAssertTrue(ky.usesVariable)
        let vm = [592.8, 592.8, 1242.8, 1242.8, 1242.8, 942.8, 942.8, 942.8, 942.8, 942.8, 942.8, 942.8]
        for i in 0..<12 {
            XCTAssertEqual(ky.months[i].variable, vm[i], accuracy: 0.001)
            XCTAssertEqual(ky.months[i].fixed, cy.months[i].sum, accuracy: 0.001)
        }
        XCTAssertEqual(ky.legend, [.fixed, .variable])
        XCTAssertNil(ky.filterNote)
        XCTAssertEqual(calc.costKindSubline(ky, month: 10), "Fixkosten 2’759.07 · variabel 942.80")
        // mit Kategoriefilter zählen nur die Verträge
        let fc = Calc.CostFilter(category: "Wohnen")
        let kc = calc.costKindYear(calc.costYear(2026, filter: fc), filter: fc)
        XCTAssertFalse(kc.usesVariable)
        XCTAssertEqual(kc.filterNote, "Mit Kategorie- oder Vertragspartnerfilter zählen nur die Verträge.")
        XCTAssertEqual(kc.legend, [])
    }

    func testKindYearVariableAndPerson() throws {
        let calc = try demo(kind: .variable)
        let f = Calc.CostFilter(person: lara(calc))
        let ky = calc.costKindYear(calc.costYear(2026, filter: f), filter: f)
        let vm = [412.8, 412.8, 737.8, 737.8, 737.8, 437.8, 437.8, 437.8, 437.8, 437.8, 437.8, 437.8]
        for i in 0..<12 {
            XCTAssertEqual(ky.months[i].total, vm[i], accuracy: 0.001)
            XCTAssertEqual(ky.months[i].fixed, 0)
        }
        XCTAssertEqual(ky.legend, [.variable])
        XCTAssertEqual(calc.costKindSubline(ky, month: 10), "geschätzt · im Budget abgezogen")
        XCTAssertEqual(calc.variableCount(year: 2026, month: 10, person: lara(calc)), 2)
        XCTAssertEqual(calc.variableCount(year: 2026, month: 4, person: nil), 4)
        XCTAssertNil(calc.costKindEmpty(ky, paymentCount: 0))
        let k27 = calc.costKindYear(calc.costYear(2031, filter: Calc.CostFilter()), filter: Calc.CostFilter())
        XCTAssertEqual(k27.months[0].total, 830, accuracy: 0.001)
    }

    func testVariableGroup() throws {
        let calc = try demo()
        let g = try XCTUnwrap(calc.variableCostGroup(year: 2026, month: 10, person: nil))
        XCTAssertEqual(g.title, "Variable Kosten Oktober")
        XCTAssertEqual(g.total, 942.8, accuracy: 0.001)
        XCTAssertEqual(g.rows.map(\.title), ["Lebensmittel", "Benzin", "Auswärts essen"])
        XCTAssertEqual(g.rows.map(\.subline), ["Sinan & Lara", "Sinan", "Lara"])
        XCTAssertEqual(g.rows[2].value, 112.8, accuracy: 0.001)
        let gl = try XCTUnwrap(calc.variableCostGroup(year: 2026, month: 10, person: lara(calc)))
        XCTAssertEqual(gl.total, 437.8, accuracy: 0.001)
        XCTAssertEqual(gl.rows.map(\.subline), ["Sinan & Lara · Anteil 50 %", "Lara"])
        XCTAssertEqual(calc.variableCostGroup(year: 2028, month: 1, person: lara(calc))?.total ?? 0, 325, accuracy: 0.001)
        // Lebensmittel gilt erst ab März
        XCTAssertEqual(calc.variableCostGroup(year: 2026, month: 2, person: lara(calc))?.rows.map(\.title), ["Ferien alt", "Auswärts essen"])
    }

    func testEmptyStates() throws {
        var calc = try demo(kind: .variable)
        var d = calc.data
        d.variableCosts = d.variableCosts.filter { $0.label == "Ferien alt" }
        calc = Calc(data: d, today: calc.today)
        let ky = calc.costKindYear(calc.costYear(2027, filter: Calc.CostFilter()), filter: Calc.CostFilter())
        XCTAssertEqual(calc.costKindEmpty(ky, paymentCount: 5)?.title, "Keine variablen Kosten in 2027")
        XCTAssertFalse(calc.costPageEmpty)
        d.contracts = []
        XCTAssertFalse(Calc(data: d, today: calc.today).costPageEmpty)
        d.settings.costKind = .fix
        XCTAssertTrue(Calc(data: d, today: calc.today).costPageEmpty)
    }

    func testReportWithVariableCosts() throws {
        let calc = try demo()
        let r = calc.fixReport(person: nil, showIDs: true, includeVariable: true)
        XCTAssertTrue(r.includeVariable)
        XCTAssertEqual(r.variableMonth, 942.8, accuracy: 0.001)
        XCTAssertEqual(r.variableYear, 10524, accuracy: 0.001)
        XCTAssertEqual(r.months.map { Format.jsRound($0.variable * 10) / 10 }, [942.8, 942.8, 942.8, 942.8, 942.8, 830, 830, 830, 830, 830, 830, 830])
        XCTAssertEqual(r.categories.last?.name, "Variable Kosten")
        XCTAssertEqual(r.categories.last?.isVariable, true)
        XCTAssertEqual(r.variables.map(\.title), ["Lebensmittel", "Benzin", "Auswärts essen"])
        XCTAssertEqual(r.variables.map(\.period), ["ab 15.03.26", "unbefristet", "bis 10.02.27"])
        XCTAssertEqual(r.variables.first?.persons, "Sinan, Lara")
        XCTAssertEqual(r.pageCount, 3)
        XCTAssertEqual(r.title, "Kostenbericht")
        XCTAssertEqual(r.fileName, "Kontivo-Kosten-2026-10-03.pdf")
        XCTAssertEqual(r.totalWithVariable, r.total + 942.8, accuracy: 0.001)

        let rl = calc.fixReport(person: lara(calc), showIDs: true, includeVariable: true)
        XCTAssertEqual(rl.variableMonth, 437.8, accuracy: 0.001)
        XCTAssertEqual(rl.variableYear, 4464, accuracy: 0.001)
        XCTAssertEqual(rl.variables.map(\.persons), ["Sinan, Lara (50 %)", "Lara"])

        let rf = calc.fixReport(person: nil, showIDs: true)
        XCTAssertFalse(rf.includeVariable)
        XCTAssertEqual(rf.pageCount, 2)
        XCTAssertEqual(rf.title, "Fixkosten-Bericht")
    }

    /// Web C27: ohne Verträge nach Pausen-/Personenfilter keine leere Seite «Vertragsblätter 0 von 0»
    func testReportWithoutSheets() throws {
        var d = try demo().data
        for i in d.contracts.indices { d.contracts[i].pauses = [Pause(from: Day(2026, 1, 1))] }
        let r = Calc(data: d, today: Day(2026, 10, 3)).fixReport(person: nil, showIDs: true)
        XCTAssertEqual(r.rows.count, 0)
        XCTAssertEqual(r.pageCount, 1)
    }
}
