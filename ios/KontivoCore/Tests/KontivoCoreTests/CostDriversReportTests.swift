import XCTest
@testable import KontivoCore

/// Web v190–v192 «Entwicklung und Preistreiber», Filterauswahl mit Betrag und v220 Fixkosten-Bericht.
/// Erwartungswerte aus der Web-App v224 (Playwright, gleiche Beispieldaten wie DemoData, Stichtag 03.10.2026).
final class CostDriversReportTests: XCTestCase {
    private func demo() throws -> Calc {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "costs_demo_backup", withExtension: "json")
            ?? Bundle.module.url(forResource: "costs_demo_backup", withExtension: "json", subdirectory: "Resources"))
        let d = try Data(contentsOf: url)
        let today = Day(2026, 10, 3)
        let data = try WebImport.importBackup(d, today: today).data
        return Calc(data: data, today: today)
    }

    private func person(_ calc: Calc, _ name: String) -> UUID? { calc.data.persons.first { $0.name == name }?.id }

    func testColumnsAndDrivers2026() throws {
        let calc = try demo()
        let d = calc.costDrivers(year: 2026, filter: Calc.CostFilter())
        XCTAssertEqual(d.columns.map(\.year), [2025, 2026, 2027])
        XCTAssertEqual(d.columns.map { Format.money0($0.total) }, ["38’463", "38’399", "38’447"])
        XCTAssertEqual(d.columns.map { $0.deltaText }, [nil, "↓ 64", "↑ 49"])
        XCTAssertEqual(d.columns.map(\.forecast), [false, false, true])
        XCTAssertEqual(d.columns.map(\.place), [.past, .current, .future])
        XCTAssertEqual(d.listTitle, "Was sich verändert hat · 2025 → 2026")
        XCTAssertEqual(d.groups.map(\.key), ["Abos & Medien"])
        XCTAssertEqual(d.groups.first?.why, "Wechsel: TV → Musik")
        XCTAssertEqual(Calc.driverDeltaText(d.groups[0].delta).text, Format.minus + "64")
        XCTAssertEqual(d.groups[0].changes.map(\.reason), ["beendet im Juni", "neu ab November"])
        XCTAssertEqual(d.othersNote, "Alle anderen Kategorien sind gleich geblieben.")
        XCTAssertNil(d.noStartNote)
    }

    func testForecastAndPastYears() throws {
        let calc = try demo()
        let f = calc.costDrivers(year: 2027, filter: Calc.CostFilter())
        XCTAssertEqual(f.listTitle, "Prognose · 2026 → 2027")
        XCTAssertEqual(f.groups.map(\.why), ["Musik mehr Zahlungen im Jahr und 1 weiterer", "Halbtax Preis ↑ 5 % seit März"])
        XCTAssertEqual(f.groups.map { Calc.driverDeltaText($0.delta).text }, ["+39", "+9"])
        XCTAssertEqual(f.groups[0].changes.map(\.reason), ["mehr Zahlungen im Jahr", "beendet im Juni 2026"])
        XCTAssertEqual(f.othersNote, "Alle anderen Kategorien bleiben gleich.")

        let p = calc.costDrivers(year: 2025, filter: Calc.CostFilter())
        XCTAssertEqual(p.listTitle, "Was sich verändert hat · 2024 → 2025")
        XCTAssertEqual(p.groups.first?.why, "Miete erstes volles Jahr")
        XCTAssertEqual(p.groups.first(where: { $0.key == "Versicherung" })?.why, "Krankenkasse erstes volles Jahr und 1 weiterer")
        XCTAssertEqual(p.groups.first(where: { $0.key == "Versicherung" })?.changes.map(\.reason), ["erstes volles Jahr", "neu ab Januar"])
        XCTAssertEqual(p.groups.map { Calc.driverDeltaText($0.delta).text },
                       ["+4’200", "+1’209", "+1’150", "+178", "+160", "+120", "+66"])

        let o = calc.costDrivers(year: 2024, filter: Calc.CostFilter())
        XCTAssertEqual(o.columns.map(\.year), [2023, 2024, 2025])
        XCTAssertEqual(o.columns.map { $0.deltaText }, [nil, nil, "↑ 7’082"])
        XCTAssertFalse(o.comparable)
        XCTAssertEqual(o.noCompareNote, "Für 2023 sind keine Zahlungen erfasst – noch kein Vergleich möglich.")
    }

    func testPersonFilter() throws {
        let calc = try demo()
        let s = calc.costDrivers(year: 2026, filter: Calc.CostFilter(person: person(calc, "Sinan")))
        XCTAssertEqual(s.columns.map { Format.money0($0.total) }, ["28’577", "28’513", "28’562"])
        let l = calc.costDrivers(year: 2027, filter: Calc.CostFilter(person: person(calc, "Lara")))
        XCTAssertEqual(l.columns.map { $0.deltaText }, [nil, "±0", "±0"])
        XCTAssertEqual(l.emptyNote, "Keine Veränderung gegenüber 2026.")
        XCTAssertTrue(l.groups.isEmpty)
    }

    func testCategoryDisplayColors() throws {
        let calc = try demo()
        XCTAssertEqual(calc.data.categoryDisplayColor(named: "Versicherung"), "#2F7F7A")
        XCTAssertEqual(calc.data.categoryDisplayColor(named: "Wohnen"), "#6A4FB3")
        XCTAssertEqual(calc.data.categoryDisplayColor(named: "Familie & Bildung"), "#3B8BC9")
        XCTAssertEqual(CategoryPalette.display("#123456", key: "Wohnen"), "#123456")
    }

    func testPickAmounts() throws {
        let calc = try demo()
        let v = calc.kbFilterValuesWithAmounts(.category, year: 2026, filter: Calc.CostFilter())
        XCTAssertEqual(v.prefix(3).map { $0.value.key + ": " + $0.text },
                       ["Wohnen: 25’200 CHF · 66 %", "Versicherung: 5’334 CHF · 14 %", "Steuern & Gebühren: 4’600 CHF · 12 %"])
        XCTAssertEqual(v.last.map { $0.value.key + ": " + $0.text }, "Mobilität: 190 CHF · 0 %")
    }

    func testReportAll() throws {
        let calc = try demo()
        let r = calc.fixReport(person: nil, showIDs: true)
        XCTAssertEqual(r.who, "Sinan & Lara")
        XCTAssertEqual(r.rows.count, 10)
        XCTAssertEqual(r.total, 3203.1827, accuracy: 0.001)
        XCTAssertEqual(r.year, 38434.242, accuracy: 0.001)
        XCTAssertEqual(r.income, 11822.3333, accuracy: 0.001)
        XCTAssertEqual(r.diff, -15, accuracy: 0.001)
        XCTAssertEqual(r.categories.map(\.name), ["Wohnen", "Versicherung", "Steuern & Gebühren", "Freizeit & Sport", "Energie & Wasser",
                                                  "Mobilfunk & Internet", "Abos & Medien", "Mobilität"])
        XCTAssertEqual(r.top.map { calc.data.contract($0.contractID)!.label }, ["Miete", "Krankenkasse", "Einkommensteuer 2026", "Fitnessabo", "Strom"])
        XCTAssertEqual(r.deadlines.map { calc.data.contract($0.contractID)!.label + " " + $0.date.iso + " " + $0.sub },
                       ["Fitnessabo 2026-10-31 Update Fitness · verlängert sich sonst", "Krankenkasse 2026-11-01 CSS · Wechsel möglich"])
        XCTAssertEqual(r.months.map { String(format: "%.2f", $0.value) },
                       ["2759.07", "3922.02", "2772.02", "3156.02", "3922.02", "2971.02", "2772.02", "3922.02", "2772.02", "2772.02", "3922.02", "2772.02"])
        XCTAssertEqual(r.months.map(\.high), [false, true, false, false, true, false, false, true, false, false, true, false])
        XCTAssertEqual(r.months[1].bigName, "Einkommensteuer 2026")
        XCTAssertEqual(r.pageCount, 2)
        let terms = r.rows.map { calc.data.contract($0.contractID)!.label + ": " + calc.reportTerm(calc.data.contract($0.contractID)!) }
        XCTAssertEqual(terms, ["Handy: 60 Tage · auf Monatsende", "Streaming: ohne Frist · auf Ende der Zahlungsperiode",
                               "Krankenkasse: nur mit neuem Anbieter · 60 Tage", "Miete: 3 Monate · auf Quartalsende", "Strom: 1 Monat · jederzeit",
                               "Hausrat: 3 Monate", "Fitnessabo: 1 Monat", "Musik: ohne Frist · auf Ende der Zahlungsperiode",
                               "Einkommensteuer 2026: nicht kündbar (Steuern & Gebühren)", "Halbtax: 1 Monat · auf Ende Vertragsjahr"])
        let halb = try XCTUnwrap(r.rows.first { calc.data.contract($0.contractID)?.label == "Halbtax" })
        XCTAssertEqual(calc.reportSheetLines(halb, showIDs: true).map { $0.label + "=" + $0.value },
                       ["Person=Sinan", "Zahlung=jährlich · 190.00 CHF", "Kündigung=1 Monat · auf Ende Vertragsjahr", "Kündbar bis=31.01.27",
                        "Kunden-Nr.=—", "Kontakt=Online / Kundenkonto"])
        XCTAssertEqual(r.sheetRows.prefix(3).map { calc.data.contract($0.contractID)!.label }, ["Miete", "Krankenkasse", "Hausrat"])
    }

    func testReportPerson() throws {
        let calc = try demo()
        let r = calc.fixReport(person: person(calc, "Lara"), showIDs: false)
        XCTAssertEqual(r.who, "Lara")
        XCTAssertEqual(r.rows.count, 5)
        XCTAssertEqual(r.total, 823.783, accuracy: 0.001)
        XCTAssertEqual(r.income, 3954, accuracy: 0.001)
        XCTAssertEqual(r.diff, 0, accuracy: 0.001)
        XCTAssertEqual(r.months.filter(\.high).map(\.bigName), ["Hausrat"])
        let miete = try XCTUnwrap(r.rows.first { calc.data.contract($0.contractID)?.label == "Miete" })
        XCTAssertEqual(calc.reportSheetLines(miete, showIDs: false).first?.value, "Sinan, Lara (Anteil 30 %)")
        XCTAssertEqual(calc.reportSheetLines(miete, showIDs: false).count, 5)
    }
}
