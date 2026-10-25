import SwiftUI
import KontivoCore

/// Tab «Kosten»: Kopf mit Jahr und Bericht, Filter in einer Zeile (Personen · Kostenart · Filter), Monatskarte (Diagramm),
/// Liste des Monats, variable Kosten des Monats, «Überblick» (Jahre · Kategorien) und «Was sich verändert hat».
struct CostsTab: View {
    @Environment(AppModel.self) private var model
    /// Liste «Fällig im»: nach Betrag statt Datum
    @State private var listByAmount = false
    /// Offenes Blatt der Filterleiste
    @State private var sheet: KBCostSheet?
    /// Aufgeklappte Kategorie in «Was sich verändert hat» (Web `state.ptOpen`)
    @State private var driverOpen: String?
    /// Überblick: Jahre oder Kategorien (Web `state.ptView`)
    @State private var overview: KBOverviewView = .years

    var body: some View {
        Group {
            if model.calc.costPageEmpty {
                emptyPage
            } else {
                content
            }
        }
        .kPageBackground()
        .sheet(item: $sheet) { s in
            Group {
                switch s {
                case .pick(let d): KBFilterPickSheet(dim: d)
                case .filter: KBCostFilterSheet()
                case .kind: KBCostKindSheet(changed: { autoSelectMonth() })
                }
            }
            .environment(model)
            .tint(KColor.teal)
        }
        .onChange(of: model.costFilter) { _, _ in autoSelectMonth() }
        .onAppear {
            #if DEBUG
            KBUITestSeed.applyIfNeeded(model)
            if model.uiTestMode, let o = KBUITestSeed.openArg {
                switch o {
                case "kind": sheet = .kind
                case "filter": sheet = .filter
                case "categories": overview = .categories
                case "cat": driverOpen = KBYearCache.drivers(model.calc, year: model.selectedYear, filter: model.costFilter).groups.first?.key
                default: break
                }
            }
            #endif
            dropStalePerson()
        }
        .onChange(of: model.data.persons) { _, _ in dropStalePerson() }
        .onChange(of: personsWithContracts) { _, _ in dropStalePerson() }
    }

    /// Anzahl Personen mit mindestens einem Vertrag (auch beendete; Web `holderStats().filter(c>0)`)
    private var personsWithContracts: Int {
        let used = Set(model.data.contracts.flatMap(\.holderIDs))
        return model.data.persons.filter { used.contains($0.id) }.count
    }

    /// Personenfilter zurücksetzen, wenn die Person gelöscht wurde oder nur noch eine Person Verträge hat
    /// (Chips wären ausgeblendet, Filter unsichtbar – Web `renderStat`).
    private func dropStalePerson() {
        guard let p = model.costFilter.person else { return }
        if model.data.person(p) == nil || personsWithContracts <= 1 {
            model.costFilter.person = nil
        }
    }

    /// Teilen-Symbol: Bericht nur mit aktiven Verträgen (Web `openRepOpts`)
    private func openReport() {
        if !model.calc.reportAvailable {
            model.toast(Calc.reportUnavailableText)
            return
        }
        model.present(.fixReport(person: model.costFilter.person, fromCosts: true))
    }

    // MARK: Inhalt

    private var content: some View {
        let calc = model.calc
        let year = model.selectedYear
        let month = KBMonthNav.month(model)
        let cy = KBYearCache.costYear(calc, year: year, filter: model.costFilter, split: .category)
        let ky = calc.costKindYear(cy, filter: model.costFilter)
        let fixOn = ky.kind != .variable
        return KBPage(title: "Kosten", miniTitle: "Kosten · " + String(year)) {
            KTabHeader(title: "Kosten") { KBYearNav(report: { openReport() }) }
            KBCostFilterRow(sheet: $sheet)
            if let e = calc.costKindEmpty(ky, paymentCount: cy.paymentCount) {
                noPayments(e, hint: ky.kind == .variable ? nil : cy.noStartHint)
            } else {
                KBCostMonthCard(cy: cy, ky: ky, month: month)
                    .padding(.top, 14)
                if let h = cy.noStartHint {
                    hintText(h)
                }
                if fixOn {
                    KBCostMonthList(items: cy.months[month - 1].items, month: month, byAmount: $listByAmount)
                        .id("kbList")
                }
                if ky.usesVariable, let g = calc.variableCostGroup(year: year, month: month, person: model.costFilter.person) {
                    KBVariableList(group: g)
                        .id("kbVars")
                }
                if fixOn {
                    let d = KBYearCache.drivers(calc, year: year, filter: model.costFilter)
                    KBOverviewCard(year: year, drivers: d, view: $overview, open: $driverOpen)
                    if d.comparable {
                        KBChangesView(drivers: d, open: $driverOpen)
                    }
                }
            }
        }
    }

    /// Web `.empty`: «Keine Zahlungen in 2031» (16 px Semibold) und Text 14 px
    private func noPayments(_ e: (title: String, text: String), hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: e.title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KColor.ink)
            Text(verbatim: e.text)
                .font(.system(size: 14))
                .lineSpacing(14 * 0.4)
                .foregroundStyle(KColor.ink2)
            if let h = hint { hintText(h) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 46)
        .padding(.horizontal, 6)
    }

    /// Web `.note` (12.5 px, Zeilenhöhe 1.55)
    private func hintText(_ h: String) -> some View {
        Text(verbatim: h)
            .font(.system(size: 12.5))
            .lineSpacing(12.5 * 0.35)
            .foregroundStyle(KColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
    }

    /// Leerseite emptyStat (ohne Jahresleiste)
    private var emptyPage: some View {
        ScrollView {
            VStack(spacing: 0) {
                KTabHeader(title: "Kosten")
                    .padding(.horizontal, KBM.side)
                    .kContentWidth()
                EmptyHero(symbol: "chart.bar",
                          title: "Dein Monat,\nim Voraus geplant",
                          text: "Sobald Verträge da sind, siehst du hier, was wann abgebucht wird.",
                          hooks: ["Was geht nächsten Monat wirklich weg?",
                                  "Jahresrechnungen, bevor sie dich treffen",
                                  "Teurer als letztes Jahr? Sofort sichtbar"],
                          buttonTitle: "Ersten Vertrag erfassen",
                          action: { model.present(.contractForm(.new(prefill: nil))) })
                    // Web `.esv.eh` (padding-top 36 steckt schon in EmptyHero), Seitenrand `.wrap` 17
                    .padding(.horizontal, KBM.side)
                    .padding(.bottom, 24)
                    .kContentWidth()
            }
        }
        .kTabPage(title: "Kosten")
    }

    /// Nach einem Filter- oder Kostenartwechsel: hat der gewählte Monat nichts, den nächsten Monat mit Zahlungen wählen.
    private func autoSelectMonth() {
        let calc = model.calc
        let cy = KBYearCache.costYear(calc, year: model.selectedYear, filter: model.costFilter, split: .category)
        let m = calc.costKindAutoMonth(calc.costKindYear(cy, filter: model.costFilter), current: model.selectedMonth)
        if m != model.selectedMonth { model.selectedMonth = m }
    }
}
