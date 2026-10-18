import SwiftUI
import KontivoCore

/// Tab «Kosten»: Kopf mit Jahr und Bericht, Filter, Monatskarte (Diagramm), Liste des Monats, «Entwicklung und Preistreiber».
struct CostsTab: View {
    @Environment(AppModel.self) private var model
    /// Liste «Fällig im»: nach Betrag statt Datum
    @State private var listByAmount = false
    /// «Bereits bezahlt» aufgeklappt
    @State private var showPaid = false
    /// Zweite Filterzeile (Kategorie/Vertragspartner) offen
    @State private var moreFilters = false
    /// Offene Werteliste eines Filters
    @State private var pick: KBPickDim?
    /// Aufgeklappte Kategorie in «Entwicklung und Preistreiber» (Web `state.ptOpen`)
    @State private var driverOpen: String?

    var body: some View {
        let hasContracts = !model.data.contracts.isEmpty
        Group {
            if hasContracts {
                content
            } else {
                emptyPage
            }
        }
        .kPageBackground()
        .sheet(item: $pick) { p in
            KBFilterPickSheet(dim: p.dim)
                .environment(model)
        }
        .onChange(of: model.costFilter) { _, _ in autoSelectMonth() }
        .onAppear { dropStalePerson() }
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
        return KBPage(title: "Kosten", miniTitle: "Kosten · " + String(year)) {
            KTabHeader(title: "Kosten") { KBYearNav(report: { openReport() }) }
            KBCostFilterBar(moreFilters: $moreFilters, pick: $pick)
            if cy.paymentCount == 0 {
                noPayments(year: year, hint: cy.noStartHint)
            } else {
                KBCostMonthCard(cy: cy, month: month)
                    .padding(.top, 14)
                if let h = cy.noStartHint {
                    hintText(h)
                }
                KBCostMonthList(items: cy.months[month - 1].items, month: month,
                                byAmount: $listByAmount, showPaid: $showPaid)
                    .id("kbList")
                KBCostDriversView(year: year, open: $driverOpen)
            }
        }
    }

    /// Web `.empty`: «Keine Zahlungen in 2031» (16 px Semibold) und Text 14 px
    private func noPayments(year: Int, hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: "Keine Zahlungen in " + String(year))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KColor.ink)
            Text("Für dieses Jahr sind keine Zahlungen erfasst oder berechenbar.")
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
                    .padding(.top, 36)
                    .padding(.bottom, 24)
                    .kContentWidth()
            }
        }
        .kTabPage(title: "Kosten")
    }

    /// Nach einem Filterwechsel: hat der gewählte Monat nichts, den nächsten Monat mit Zahlungen wählen.
    private func autoSelectMonth() {
        let calc = model.calc
        let cy = KBYearCache.costYear(calc, year: model.selectedYear, filter: model.costFilter, split: .category)
        let m = calc.kbAutoMonth(cy, current: model.selectedMonth)
        if m != model.selectedMonth { model.selectedMonth = m }
    }
}

/// Werteliste eines Filters (Kategorie, Vertragspartner, Inhaber)
struct KBPickDim: Identifiable, Hashable {
    let dim: Calc.FilterDimension
    var id: String { dim.rawValue }
}

// MARK: - Monatskarte

struct KBCostMonthCard: View {
    @Environment(AppModel.self) private var model
    let cy: Calc.CostYear
    let month: Int

    var body: some View {
        let calc = model.calc
        let home = calc.home.rawValue
        let m = cy.months[month - 1]
        let cmp = KBYearCache.monthComparison(calc, year: cy.year, month: month, filter: model.costFilter, monthSum: m.sum, items: m.items)
        KBPagingCard {
            KBCardHeader(year: cy.year, month: month, trailing: model.costFilter.count > 0 ? calc.kbFilterLabel(model.costFilter) : "")
            KBBigAmount(value: m.sum, currency: home)
            if let c = cmp {
                KBCompareLine(text: c.text, arrow: c.trend.kbArrow, tone: c.trend)
            }
            paidOpen(m)
            chartArea(home: home)
            KBCardRow(top: 16) {
                HStack(alignment: .top, spacing: 12) {
                    KBStatCell(label: "Ø pro Monat", value: Format.money0(cy.average))
                    KBStatCell(label: "Total " + String(cy.year), value: Format.money0(cy.total), trailing: true)
                }
            }
        }
    }

    private func paidOpen(_ m: Calc.CostMonth) -> some View {
        Group {
            if m.items.isEmpty {
                // Web `.krow.kempty`
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle().fill(KColor.line).frame(height: 1)
                    Text("In diesem Monat ist nichts fällig.")
                        .font(.system(size: 13))
                        .foregroundStyle(KColor.ink3)
                        .padding(.top, 14)
                }
                .padding(.top, 18)
            } else {
                KBCardRow {
                    HStack(alignment: .top, spacing: 12) {
                        KBStatCell(label: "Bezahlt", value: Format.money(m.paid), dot: KColor.teal,
                                   check: m.open < 0.005, muted: m.paid < 0.005)
                        KBStatCell(label: "Offen", value: Format.money(m.open), trailing: true,
                                   dot: KBColor.openDot, muted: m.open < 0.005)
                    }
                }
            }
        }
    }

    private func chartArea(home: String) -> some View {
        let m = cy.months[month - 1]
        let label = "Zahlungen pro Monat " + String(cy.year)
        let value = Format.monthNames[month - 1] + " " + String(cy.year) + ": " + Format.money(m.sum) + " " + home
        return VStack(spacing: 0) {
            KBCostChart(months: cy.months, selected: month, average: cy.average, total: cy.total, maxMonth: cy.maxMonth)
                .frame(height: 170)
            KBMonthLabels(year: cy.year, selected: month, today: model.today)
        }
        .contentShape(Rectangle())
        .kbScrubArea()
        .kbMonthAdjustable(model, label: label, value: value)
        .padding(.trailing, 16)
        .padding(.top, 22)
        .accessibilityIdentifier("costs.chart")
    }
}

/// Balken je Monat (Web `.chart`, 170 pt mit Grundlinie): unten bezahlt, oben offen; gewählter Monat Messing,
/// vergangene blass Messing, künftige grau.
struct KBCostChart: View {
    let months: [Calc.CostMonth]
    let selected: Int
    let average: Double
    let total: Double
    let maxMonth: Double

    var body: some View {
        let mx = maxMonth > 0 ? maxMonth : 1
        GeometryReader { g in
            let h = g.size.height - 1
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        column(months[i], on: i + 1 == selected, h: h, mx: mx)
                    }
                }
                .frame(height: h)
                .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(KColor.line).frame(height: 1)
                if total != 0 {
                    KBAverageLine(fraction: CGFloat(average / mx))
                        .frame(height: h)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func column(_ m: Calc.CostMonth, on: Bool, h: CGFloat, mx: Double) -> some View {
        let zero = m.sum == 0
        let op = zero ? 0 : CGFloat(max(0, m.open) / mx) * h
        let pd = zero ? 0 : CGFloat(max(0, m.paid) / mx) * h
        let capOpen = m.open > 0
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            UnevenRoundedRectangle(topLeadingRadius: capOpen ? 4 : 0, topTrailingRadius: capOpen ? 4 : 0, style: .circular)
                .fill(on ? KColor.brass : KBColor.barFuture)
                .frame(height: op)
            UnevenRoundedRectangle(topLeadingRadius: capOpen ? 0 : 4, topTrailingRadius: capOpen ? 0 : 4, style: .circular)
                .fill(on ? KColor.brass : KBColor.barPast)
                .frame(height: pd)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Liste «Fällig im {Monat}»

struct KBCostMonthList: View {
    @Environment(AppModel.self) private var model
    let items: [Calc.CostItem]
    let month: Int
    @Binding var byAmount: Bool
    @Binding var showPaid: Bool

    var body: some View {
        let parts = model.calc.kbOpenPaid(items, byAmount: byAmount)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                Text(verbatim: "Fällig im " + Format.monthNames[month - 1])
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                if items.count > 1 {
                    KBSegment(options: ["Datum", "Betrag"], selected: Binding(get: { byAmount ? 1 : 0 }, set: { byAmount = $0 == 1 }))
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Sortierung")
                }
            }
            .frame(minHeight: 31.9)
            .padding(.top, 20)
            .padding(.bottom, 6)
            KBListBlock {
                if items.isEmpty {
                    Text("In diesem Monat ist nichts fällig.")
                        .font(.system(size: 14))
                        .foregroundStyle(KColor.ink2)
                        .padding(.vertical, 14)
                } else {
                    rows(parts.open, dividerFirst: false)
                    if !parts.open.isEmpty && !parts.paid.isEmpty {
                        KBRowDivider()
                        KBFoldButton(title: "Bereits bezahlt (" + String(parts.paid.count) + ")", expanded: showPaid) {
                            withAnimation(.easeInOut(duration: 0.2)) { showPaid.toggle() }
                        }
                    }
                    if showPaid || parts.open.isEmpty {
                        rows(parts.paid, dividerFirst: !parts.open.isEmpty)
                    }
                }
            }
        }
    }

    private func rows(_ list: [Calc.CostItem], dividerFirst: Bool) -> some View {
        ForEach(Array(list.enumerated()), id: \.offset) { idx, it in
            if idx > 0 || dividerFirst { KBRowDivider() }
            KBCostRow(item: it)
        }
    }
}

/// Zeile einer Zahlung (Web `.mrows2 .mrow`): Kachel 34, Name rund 16 Semibold, Zweitzeile 12.5, Betrag 16 Semibold
struct KBCostRow: View {
    @Environment(AppModel.self) private var model
    let item: Calc.CostItem

    var body: some View {
        if let c = model.data.contract(item.contractID) {
            let calc = model.calc
            let past = item.date < calc.today
            let status = calc.kbPaymentStatus(item.date)
            let sub = calc.kbCostSubline(item)
            let amount = item.amount < 0 ? Format.minus + Format.money(-item.amount, c.currency) : Format.money(item.amount, c.currency)
            Button {
                model.present(.contractDetail(c.id))
            } label: {
                HStack(spacing: 12) {
                    MarkView(contract: c, data: model.data, size: 34)
                        .opacity(past ? 0.7 : 1)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: model.data.title(of: c))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(past ? KColor.ink2 : KColor.ink)
                            .lineLimit(1)
                            .frame(height: 20)
                        if !sub.isEmpty {
                            Text(verbatim: sub)
                                .font(.system(size: 12.5))
                                .foregroundStyle(KColor.ink2)
                                .lineLimit(1)
                                .frame(height: 18.1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(verbatim: amount)
                                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                                .foregroundStyle(past ? KColor.ink2 : KColor.ink)
                            Text(verbatim: c.currency.rawValue)
                                .font(.system(size: 11))
                                .foregroundStyle(KColor.ink2)
                        }
                        .frame(height: 23.2)
                        Text(verbatim: status.text)
                            .font(.system(size: 12.5, weight: status.warn ? .semibold : .regular))
                            .foregroundStyle(status.warn ? KColor.warn : KColor.ink3)
                            .frame(height: 18.1)
                    }
                    .layoutPriority(1)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}
