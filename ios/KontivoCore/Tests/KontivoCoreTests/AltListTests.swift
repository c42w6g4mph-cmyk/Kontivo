import XCTest
@testable import KontivoCore

/// Verträge-Tab, Ansichten «Einnahmen» und «Variabel» (Web v231–v233 `renderAltList`) und variable Kosten im Budget (v226/v238).
final class AltListTests: XCTestCase {
    let today = Day(2026, 10, 3)

    func data() -> AppData {
        var d = AppData.initial(homeCurrency: .CHF)
        let a = Person(name: "Sinan"), b = Person(name: "Lara")
        d.persons = [a, b]
        let t = { (s: Double) in Date(timeIntervalSince1970: 1_700_000_000 + s) }
        d.incomes = [
            Income(name: "Pharma AG", label: "Lohn", kind: .lohn, amount: 7200, cycle: 1, due: Day(2026, 10, 25), holderID: a.id, createdAt: t(1)),
            Income(name: "Eltern", label: "Unterstützung", kind: .unterstuetzung, amount: 300, cycle: 3, due: Day(2026, 10, 15), holderID: b.id, createdAt: t(2)),
            Income(name: "Pharma AG", label: "Bonus", kind: .bonus, amount: 2000, cycle: 0, due: Day(2026, 12, 20), holderID: a.id, createdAt: t(3)),
            Income(name: "", label: "Alt", kind: .sonstiges, amount: 100, cycle: 1, due: Day(2026, 1, 5), end: Day(2026, 5, 31), holderID: a.id, createdAt: t(4)),
            Income(name: "Firma", label: "Neu", kind: .nebeneinkommen, amount: 500, cycle: 1, due: Day(2026, 11, 25), start: Day(2026, 11, 1), holderID: b.id, createdAt: t(5)),
        ]
        d.variableCosts = [
            VariableCost(label: "Benzin", icon: .benzin, amount: 180, holderIDs: [a.id], createdAt: t(1)),
            VariableCost(label: "Lebensmittel", icon: .essen, amount: 900, holderIDs: [a.id, b.id], createdAt: t(2)),
            VariableCost(label: "Ferien", icon: .ferien, amount: 250, holderIDs: [a.id], start: Day(2026, 12, 1), createdAt: t(3)),
        ]
        return d
    }

    func calc(_ d: AppData) -> Calc { Calc(data: d, today: today) }

    func testEinnahmenStandard() {
        let c = calc(data())
        XCTAssertEqual(c.altSort(.incomes), .cat)
        let l = c.altList(.incomes, filter: AltFilter(), status: nil, search: "")
        XCTAssertFalse(l.isEmpty)
        XCTAssertEqual(l.heroLabel, "Einnahmen pro Monat")
        XCTAssertEqual(l.heroSum, 7300, accuracy: 0.001)
        XCTAssertEqual(l.heroSub, Format.money0(87600) + " CHF im Jahr")
        XCTAssertEqual(l.activeCount, 3)
        XCTAssertEqual(l.futureCount, 1)
        XCTAssertEqual(l.groups.map { $0.title }, ["Lohn", "Nebeneinkommen", "Unterstützung", "Bonus"])
        XCTAssertEqual(l.groups.map { $0.sum }, ["", "noch nicht aktiv", "", ""])
        let lohn = l.groups[0].rows[0]
        XCTAssertEqual(lohn.meta, "Pharma AG · Sinan")
        XCTAssertNil(lohn.sub)
        XCTAssertNil(lohn.tag)
        XCTAssertEqual(l.groups[2].rows[0].sub, "quartalsweise")
        XCTAssertEqual(l.groups[3].rows[0].sub, "einmalig")
        XCTAssertEqual(l.groups[1].rows[0].tag, "ab 01.11.26")
        XCTAssertEqual(l.archive.count, 1)
        XCTAssertEqual(l.archive[0].tag, "beendet 31.05.26")
        XCTAssertTrue(l.archive[0].ended)
        XCTAssertEqual(l.archiveText, "1 beendete Einnahme")
        XCTAssertNil(l.noHits)
        XCTAssertNil(l.hint)
    }

    func testEinnahmenStatusFilterSuche() {
        let c = calc(data())
        let f = c.altList(.incomes, filter: AltFilter(), status: .future, search: "")
        XCTAssertEqual(f.status, .future)
        XCTAssertEqual(f.heroLabel, "Noch nicht aktiv, pro Monat")
        XCTAssertEqual(f.heroSum, 500, accuracy: 0.001)
        XCTAssertEqual(f.heroSub, "Zählt ab Beginn zu deinen Einnahmen")
        XCTAssertEqual(f.groups.flatMap { $0.rows }.map { $0.title }, ["Neu"])

        let p = c.altList(.incomes, filter: AltFilter(holder: "Lara"), status: nil, search: "")
        XCTAssertEqual(p.heroSum, 100, accuracy: 0.001)
        XCTAssertEqual(p.heroSub, Format.money0(1200) + " CHF im Jahr – Lara")
        XCTAssertEqual(p.groups.flatMap { $0.rows }.map { $0.title }, ["Neu", "Unterstützung"])
        XCTAssertEqual(AltFilter(holder: "Lara").count(.incomes), 1)
        XCTAssertEqual(AltFilter(partner: "X").count(.variable), 0)

        // «aktiv» ohne noch nicht aktive Einträge (Filter Sinan) ist ungültig und wird zurückgesetzt
        let s = c.altList(.incomes, filter: AltFilter(holder: "Sinan"), status: .active, search: "")
        XCTAssertNil(s.status)

        let q = c.altList(.incomes, filter: AltFilter(), status: nil, search: " lohn ")
        XCTAssertEqual(q.groups.flatMap { $0.rows }.map { $0.title }, ["Lohn"])
        let none = c.altList(.incomes, filter: AltFilter(), status: nil, search: "xyz")
        XCTAssertTrue(none.groups.isEmpty)
        XCTAssertEqual(none.noHits, "Für «xyz» gibt es keinen Eintrag.")
        let nf = c.altList(.incomes, filter: AltFilter(partner: "Niemand"), status: nil, search: "")
        XCTAssertEqual(nf.noHits, "Mit diesem Filter gibt es keinen Eintrag.")
    }

    func testEinnahmenSortierung() {
        var d = data()
        d.settings.incomeSort = "due"
        var l = calc(d).altList(.incomes, filter: AltFilter(), status: nil, search: "")
        XCTAssertEqual(l.groups.map { $0.title }, [Format.monthYear(Day(2026, 10, 1)), Format.monthYear(Day(2026, 11, 1)), Format.monthYear(Day(2026, 12, 1))])
        XCTAssertEqual(l.groups[0].rows.map { $0.title }, ["Unterstützung", "Lohn"])
        XCTAssertEqual(l.groups[0].sum, Format.money(7500) + " CHF")

        d.settings.incomeSort = "partner"
        l = calc(d).altList(.incomes, filter: AltFilter(), status: nil, search: "")
        XCTAssertEqual(l.groups.map { $0.title }, ["E", "F", "P"])
        XCTAssertEqual(l.groups.map { $0.sum }, ["", "", ""])

        d.settings.incomeSort = "holder"
        l = calc(d).altList(.incomes, filter: AltFilter(), status: nil, search: "")
        XCTAssertEqual(l.groups.map { $0.title }, ["Sinan", "Lara"])
        XCTAssertEqual(l.groups[0].sum, Format.money(7200) + " CHF/Mt.")

        // «Bezeichnung» gibt es bei Einnahmen nicht → erste Option (Web `altSort`)
        d.settings.incomeSort = "name"
        XCTAssertEqual(calc(d).altSort(.incomes), .due)
        XCTAssertEqual(AltSort.cost.shortLabel(.incomes), "Betrag")
        XCTAssertEqual(AltSort.due.shortLabel(.incomes), "Nächste Zahlung")
    }

    func testVariabel() {
        let c = calc(data())
        XCTAssertEqual(c.altSort(.variable), .cost)
        let l = c.altList(.variable, filter: AltFilter(), status: nil, search: "")
        XCTAssertEqual(l.heroLabel, "Variable Kosten pro Monat")
        XCTAssertEqual(l.heroSum, 1080, accuracy: 0.001)
        XCTAssertEqual(l.heroSub, Format.money0(12960) + " CHF im Jahr · geschätzt")
        XCTAssertEqual(l.groups.count, 1)
        XCTAssertNil(l.groups[0].title)
        XCTAssertEqual(l.groups[0].rows.map { $0.title }, ["Lebensmittel", "Ferien", "Benzin"])
        XCTAssertEqual(l.groups[0].rows[0].meta, "Sinan & Lara · geschätzt")
        XCTAssertEqual(l.groups[0].rows[0].sub, "pro Monat")
        XCTAssertEqual(l.groups[0].rows[1].tag, "ab 01.12.26")
        XCTAssertEqual(l.hint, "Geschätzt, keine einzelnen Ausgaben. Im Budget vom verfügbaren Betrag abgezogen.")

        let p = c.altList(.variable, filter: AltFilter(holder: "Lara"), status: nil, search: "")
        XCTAssertEqual(p.heroSum, 450, accuracy: 0.001)
        XCTAssertEqual(p.groups[0].rows.map { $0.meta }, ["Sinan & Lara · " + Format.shareText(0.5) + " · geschätzt"])
        XCTAssertEqual(p.futureCount, 0)

        let vals = c.altFilterValues(.variable, .cat)
        XCTAssertEqual(vals.map { $0.key }, ["Benzin", "Ferien", "Lebensmittel"])
        XCTAssertEqual(vals[0].detail, "1 aktiver Eintrag")
        let inc = c.altFilterValues(.incomes, .holder)
        XCTAssertEqual(inc.map { $0.key }, ["Lara", "Sinan"])
        XCTAssertEqual(inc[1].detail, "2 aktive Einnahmen")
        XCTAssertEqual(c.altFilterValues(.incomes, .partner).map { $0.key }, ["Eltern", "Firma", "Ohne Quelle", "Pharma AG"])
        XCTAssertEqual(c.altFilterValues(.incomes, .partner)[2].detail, "nur beendete")

        var e = AppData.initial()
        e.variableCosts = []
        let empty = Calc(data: e, today: today).altList(.variable, filter: AltFilter(), status: nil, search: "")
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.emptyTitle, "Noch keine variablen Kosten")
    }

    func testBudgetVariabel() {
        var d = data()
        let c0 = calc(d)
        let oct = c0.budgetVariableRows(year: 2026, month: 10, person: nil)
        XCTAssertEqual(oct.map { $0.title }, ["Lebensmittel", "Benzin"])
        XCTAssertEqual(oct.map { $0.sub }, ["Sinan & Lara", "Sinan"])
        let lara = c0.budgetVariableRows(year: 2026, month: 10, person: d.persons[1].id)
        XCTAssertEqual(lara.map { $0.value }, [450])
        XCTAssertEqual(lara[0].sub, "Sinan & Lara · " + Format.shareText(0.5))
        XCTAssertEqual(c0.budgetVariableRows(year: 2026, month: 12, person: nil).count, 3)

        // Standard «Fixkosten»: keine variablen Kosten abgezogen
        XCTAssertEqual(c0.budgetKind, .fix)
        XCTAssertEqual(c0.budgetYear(2026, person: nil).months[9].variable, 0)
        d.settings.budgetKind = .all
        let c = calc(d)
        let bm = c.budgetYear(2026, person: nil).months[9]
        XCTAssertEqual(bm.variable, 1080, accuracy: 0.001)
        XCTAssertEqual(c.budgetSubline(bm), "verfügbar nach Fix- und variablen Kosten")
        let lines = c.budgetSumLines(bm)
        XCTAssertEqual(lines.map { $0.label }, ["Einnahmen", Format.minus + " Fixkosten", "= Nach Fixkosten", Format.minus + " Variable Kosten", "= Verfügbar"])
        XCTAssertEqual(lines[4].value, bm.free, accuracy: 0.001)
        XCTAssertTrue(lines[2].isSubtotal && lines[4].isTotal)
        d.settings.budgetKind = .none
        let n = calc(d).budgetYear(2026, person: nil).months[9]
        XCTAssertEqual(calc(d).budgetSubline(n), "Einnahmen, ohne Kosten")
        XCTAssertEqual(calc(d).budgetSumLines(Calc.BudgetMonth(income: 10, fixed: 3)).map { $0.label }, ["Einnahmen", Format.minus + " Ausgaben", "= Verfügbar"])
        // ohne variable Kosten keine Kostenart-Wahl (v256)
        d.variableCosts = []
        XCTAssertEqual(calc(d).budgetKind, .fix)
    }

    func testVariabelAnsichtUndFormular() {
        var d = data()
        let c = calc(d)
        let lm = d.variableCosts[1]
        let info = c.variableDetail(lm)
        XCTAssertEqual(info.title, "Lebensmittel")
        XCTAssertNil(info.pill)
        // laufende Einnahmen heute: Lohn 7200 + Unterstützung 100 (Bonus einmalig, «Neu» noch nicht aktiv)
        XCTAssertEqual(info.incomePercent, Int(Format.jsRound(900 / 7300 * 100)))
        XCTAssertEqual(info.variablePercent, Int(Format.jsRound(900 / 1330 * 100)))
        XCTAssertEqual(info.rows.map { $0.label }, ["Betrag", "Personen", "Zählt in"])
        XCTAssertEqual(info.rows[1].value, "Sinan & Lara")
        XCTAssertEqual(c.variableDetail(d.variableCosts[2]).pill, "Ab " + Format.fmtD(Day(2026, 12, 1)))
        XCTAssertEqual(c.variableDetail(d.variableCosts[2]).rows.map { $0.label }, ["Betrag", "Ab", "Personen", "Zählt in"])

        XCTAssertEqual(c.variableSuggestions(excluding: nil).map { $0.displayName },
                       ["Auswärts essen", "Freizeit & Ausgang", "Kleidung", "Haushalt", "Geschenke", "Haustier"])
        XCTAssertEqual(c.variableSuggestions(excluding: lm.id).count, 7)

        XCTAssertEqual(VariableCostForm.missing(label: "  ", amountText: "10", start: nil, end: nil)?.message, "Bezeichnung fehlt")
        XCTAssertEqual(VariableCostForm.missing(label: "Benzin", amountText: "", start: nil, end: nil)?.message, "Betrag fehlt")
        XCTAssertEqual(VariableCostForm.missing(label: "Benzin", amountText: "0", start: nil, end: nil)?.message, "Betrag prüfen")
        XCTAssertEqual(VariableCostForm.missing(label: "Benzin", amountText: "abc", start: nil, end: nil)?.field, "amount")
        XCTAssertEqual(VariableCostForm.missing(label: "Benzin", amountText: "120", start: Day(2026, 5, 1), end: Day(2026, 4, 1))?.message, "Bis liegt vor Ab")
        XCTAssertNil(VariableCostForm.missing(label: "Benzin", amountText: "1'200.50", start: nil, end: nil))
        XCTAssertEqual(VariableCostForm.icon(forLabel: " benzin", current: .sonst), .benzin)
        XCTAssertEqual(VariableCostForm.icon(forLabel: "Benzin", current: .essen), .essen)
        XCTAssertEqual(VariableCostForm.icon(forLabel: "Tanken", current: .sonst), .sonst)

        d.incomes = []
        XCTAssertNil(calc(d).variableDetail(lm).incomePercent)
    }
}
