import SwiftUI
import Charts
import KontivoCore

/// Tab «Kosten»: Zahlungen pro Monat (Diagramm), Filter, Liste des Monats, Aufteilung.
struct CostsTab: View {
    @Environment(AppModel.self) private var model
    /// Liste «Fällig im»: nach Betrag statt Datum
    @State private var listByAmount = false
    /// «Bereits bezahlt» aufgeklappt
    @State private var showPaid = false
    /// Aufteilung nach Kategorie oder Vertragspartner
    @State private var splitDim: Calc.FilterDimension = .category
    /// Aufteilung für den Monat statt das Jahr
    @State private var splitMonth = false
    /// Gewähltes Segment im Ring
    @State private var ringSel: String?
    /// «Übrige» aufgeklappt
    @State private var showRest = false
    /// Zweite Filterzeile (Kategorie/Vertragspartner) offen
    @State private var moreFilters = false
    /// Offene Werteliste eines Filters
    @State private var pick: KBPickDim?

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
        .navigationTitle("Kosten")
        .toolbar {
            if hasContracts {
                ToolbarItem(placement: .topBarTrailing) { KBYearNav() }
            }
        }
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

    // MARK: Inhalt

    private var content: some View {
        let calc = model.calc
        let year = model.selectedYear
        let month = KBMonthNav.month(model)
        let cy = KBYearCache.costYear(calc, year: year, filter: model.costFilter, split: splitDim)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
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
                    KBCostSplitView(cy: cy, month: month, splitDim: $splitDim, splitMonth: $splitMonth,
                                    ringSel: $ringSel, showRest: $showRest)
                }
            }
            .padding(.horizontal, KMetric.gutter)
            .padding(.bottom, 28)
            .kContentWidth()
        }
    }

    private func noPayments(year: Int, hint: String?) -> some View {
        VStack(spacing: 6) {
            Text(verbatim: "Keine Zahlungen in " + String(year))
                .font(.headline)
                .foregroundStyle(KColor.ink)
            Text("Für dieses Jahr sind keine Zahlungen erfasst oder berechenbar.")
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
            if let h = hint { hintText(h) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func hintText(_ h: String) -> some View {
        Text(verbatim: h)
            .font(.footnote)
            .foregroundStyle(KColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }

    /// Leerseite emptyStat (ohne Jahresleiste)
    private var emptyPage: some View {
        ScrollView {
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

    /// Nach einem Filterwechsel: hat der gewählte Monat nichts, den nächsten Monat mit Zahlungen wählen.
    private func autoSelectMonth() {
        let calc = model.calc
        let cy = KBYearCache.costYear(calc, year: model.selectedYear, filter: model.costFilter, split: splitDim)
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
            KBCardHeader(year: cy.year, month: month, trailing: calc.kbFilterLabel(model.costFilter))
            KBBigAmount(value: m.sum, currency: home)
            if let c = cmp {
                KBCompareLine(text: c.text, arrow: c.trend.kbArrow, color: KBCostMonthCard.color(c.trend))
            }
            paidOpen(m)
            chartArea(home: home)
            KBCardRow(top: 16) {
                HStack(alignment: .top) {
                    KBStatCell(label: "Ø pro Monat", value: Format.money0(cy.average))
                    KBStatCell(label: "Total " + String(cy.year), value: Format.money0(cy.total), trailing: true)
                }
            }
        }
    }

    /// Mehr Kosten = Warnfarbe, weniger = Grün
    static func color(_ t: Calc.Trend) -> Color {
        switch t {
        case .up: return KColor.warn
        case .down: return KColor.ok
        case .same: return KColor.ink2
        }
    }

    private func paidOpen(_ m: Calc.CostMonth) -> some View {
        KBCardRow {
            if m.items.isEmpty {
                Text("In diesem Monat ist nichts fällig.")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink3)
            } else {
                HStack(alignment: .top) {
                    KBStatCell(label: "Bezahlt", value: Format.money(m.paid), dot: KColor.teal,
                               check: m.open < 0.005, muted: m.paid < 0.005)
                    KBStatCell(label: "Offen", value: Format.money(m.open), trailing: true,
                               dot: KColor.ink.opacity(0.38), muted: m.open < 0.005)
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
                .frame(height: 140)
            KBMonthLabels(year: cy.year, selected: month, today: model.today)
        }
        .contentShape(Rectangle())
        .kbScrubArea()
        .kbMonthAdjustable(model, label: label, value: value)
        .padding(.trailing, 16)
        .padding(.top, 30)
    }
}

/// Balken je Monat: unten bezahlt (Teal), oben offen (Tinte); gewählter Monat kräftig, übrige blass.
struct KBCostChart: View {
    let months: [Calc.CostMonth]
    let selected: Int
    let average: Double
    let total: Double
    let maxMonth: Double

    var body: some View {
        Chart {
            ForEach(0..<12, id: \.self) { i in
                bars(i)
            }
            if total != 0 {
                RuleMark(y: .value("Ø", average))
                    .foregroundStyle(KColor.ink2.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: Format.monthShort)
        .chartYScale(domain: 0...(maxMonth > 0 ? maxMonth : 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                averageLabel(proxy: proxy, geo: geo)
            }
        }
        .accessibilityHidden(true)
    }

    @ChartContentBuilder
    private func bars(_ i: Int) -> some ChartContent {
        let paid = max(0, months[i].paid)
        let open = max(0, months[i].open)
        let top = paid + open
        let on = i + 1 == selected
        let x = Format.monthShort[i]
        if top > 0 {
            BarMark(x: .value("Monat", x), yStart: .value("Von", 0.0), yEnd: .value("Bis", top), width: .ratio(0.8))
                .foregroundStyle(open > 0 ? KBCostChart.openColor(on) : KBCostChart.paidColor(on))
                .cornerRadius(4, style: .continuous)
        }
        if open > 0 && paid > 0 {
            BarMark(x: .value("Monat", x), yStart: .value("Von", 0.0), yEnd: .value("Bis", paid), width: .ratio(0.8))
                .foregroundStyle(KBCostChart.paidColor(on))
        }
    }

    static func paidColor(_ on: Bool) -> Color { on ? KColor.teal : KColor.teal.opacity(0.34) }
    static func openColor(_ on: Bool) -> Color { KColor.ink.opacity(on ? 0.72 : 0.12) }

    @ViewBuilder
    private func averageLabel(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if total != 0, let pf = proxy.plotFrame, let y = proxy.position(forY: average) {
            let r = geo[pf]
            Text(verbatim: "Ø")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(KColor.ink3)
                .position(x: r.maxX + 9, y: r.minY + y)
        }
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
            KBGroupHeader(title: "Fällig im " + Format.monthNames[month - 1]) {
                if items.count > 1 {
                    Picker("Sortierung", selection: $byAmount) {
                        Text("Datum").tag(false)
                        Text("Betrag").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .controlSize(.small)
                }
            }
            KBListBlock {
                if items.isEmpty {
                    Text("In diesem Monat ist nichts fällig.")
                        .font(.subheadline)
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

/// Zeile einer Zahlung (mrow)
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
                    MarkView(contract: c, data: model.data, size: 40)
                        .opacity(past ? 0.7 : 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: model.data.title(of: c))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(past ? KColor.ink2 : KColor.ink)
                            .lineLimit(1)
                        if !sub.isEmpty {
                            Text(verbatim: sub)
                                .font(.footnote)
                                .foregroundStyle(KColor.ink2)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(verbatim: amount)
                                .font(.body.weight(.semibold).monospacedDigit())
                                .foregroundStyle(past ? KColor.ink2 : KColor.ink)
                            Text(verbatim: c.currency.rawValue)
                                .font(.caption2)
                                .foregroundStyle(KColor.ink2)
                        }
                        Text(verbatim: status.text)
                            .font(.caption.weight(status.warn ? .semibold : .regular))
                            .foregroundStyle(status.warn ? KColor.warn : KColor.ink3)
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
