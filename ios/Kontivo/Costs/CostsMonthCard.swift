import SwiftUI
import KontivoCore

// MARK: - Monatskarte (Web `.kcard` in `renderStat`, v230/v234 Kostenart)

struct KBCostMonthCard: View {
    @Environment(AppModel.self) private var model
    let cy: Calc.CostYear
    let ky: Calc.CostKindYear
    let month: Int

    var body: some View {
        let calc = model.calc
        let home = calc.home.rawValue
        let m = cy.months[month - 1]
        let km = ky.months[month - 1]
        KBPagingCard {
            KBCardHeader(year: cy.year, month: month, trailing: model.costFilter.count > 0 ? calc.kbFilterLabel(model.costFilter) : "")
            KBBigAmount(value: km.total, currency: home)
            if ky.kind == .fix {
                if let c = KBYearCache.monthComparison(calc, year: cy.year, month: month, filter: model.costFilter, monthSum: m.sum, items: m.items) {
                    KBCompareLine(text: c.text, arrow: c.trend.kbArrow, tone: c.trend)
                }
            } else if let s = calc.costKindSubline(ky, month: month) {
                KBCompareLine(text: s, arrow: nil, tone: .same)
            }
            splitRow(m, km)
            chartArea(home: home)
            KBCardRow(top: 16) {
                HStack(alignment: .top, spacing: 12) {
                    KBStatCell(label: "Ø pro Monat", value: Format.money0(ky.average))
                    KBStatCell(label: "Total " + String(cy.year), value: Format.money0(ky.total), trailing: true)
                }
            }
        }
    }

    /// Zweite Zeile: Fixkosten | Variabel (Alle Kosten), Einträge | Total (Variable Kosten), sonst Bezahlt | Offen
    @ViewBuilder
    private func splitRow(_ m: Calc.CostMonth, _ km: Calc.CostKindMonth) -> some View {
        if ky.kind == .all && ky.usesVariable {
            KBCardRow {
                HStack(alignment: .top, spacing: 12) {
                    KBStatCell(label: "Fixkosten", value: Format.money(km.fixed))
                    KBStatCell(label: "Variabel", value: Format.money(km.variable), trailing: true)
                }
            }
        } else if ky.kind == .variable {
            KBCardRow {
                HStack(alignment: .top, spacing: 12) {
                    KBStatCell(label: "Einträge",
                               value: String(model.calc.variableCount(year: cy.year, month: month, person: model.costFilter.person)))
                    KBStatCell(label: "Total " + String(cy.year), value: Format.money0(ky.total), trailing: true)
                }
            }
        } else if m.items.isEmpty {
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

    private func chartArea(home: String) -> some View {
        let km = ky.months[month - 1]
        let label = "Zahlungen pro Monat " + String(cy.year)
        let value = Format.monthNames[month - 1] + " " + String(cy.year) + ": " + Format.money(km.total) + " " + home
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                KBCostChart(months: cy.months, kinds: ky, selected: month)
                    .frame(height: 170)
                KBMonthLabels(year: cy.year, selected: month, today: model.today)
            }
            .contentShape(Rectangle())
            .kbScrubArea()
            .kbMonthAdjustable(model, label: label, value: value)
            .padding(.trailing, 16)
            .accessibilityIdentifier("costs.chart")
            if !ky.legend.isEmpty {
                KBKindLegend(items: ky.legend)
            } else if let n = ky.filterNote {
                Text(verbatim: n)
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
        .padding(.top, 22)
    }
}

/// Legende unter dem Diagramm (Web `.vleg`): Fixkosten grau, variabel schraffiert
struct KBKindLegend: View {
    let items: [Calc.CostKindYear.LegendItem]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(items, id: \.self) { it in
                HStack(spacing: 6) {
                    Group {
                        if it == .fixed {
                            RoundedRectangle(cornerRadius: 3).fill(KBColor.mix(KColor.ink, 0.16, KColor.surface))
                        } else {
                            KBHatch(on: false).clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    .frame(width: 10, height: 10)
                    Text(verbatim: it.title)
                        .font(.system(size: 12.5))
                        .foregroundStyle(KColor.ink2)
                }
            }
        }
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Schraffur der variablen Kosten (Web `.col i.vr`: 135°, je 3 pt Messing hell/blass; gewählter Monat kräftiger)
struct KBHatch: View {
    let on: Bool

    var body: some View {
        let a = on ? KColor.brass : KBColor.mix(KColor.brass, 0.5, KColor.surface)
        let b = KBColor.mix(KColor.brass, on ? 0.45 : 0.16, KColor.surface)
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(b))
            // Streifen quer zur Richtung 135° (nach rechts unten), Periode 6 pt entlang dieser Richtung
            let step: CGFloat = 6 * CGFloat(2).squareRoot()
            let w: CGFloat = 3 * CGFloat(2).squareRoot()
            var x = -size.height
            while x < size.width + size.height {
                var p = Path()
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: x + w, y: 0))
                p.addLine(to: CGPoint(x: x + w - size.height, y: size.height))
                p.addLine(to: CGPoint(x: x - size.height, y: size.height))
                p.closeSubpath()
                ctx.fill(p, with: .color(a))
                x += step
            }
        }
    }
}

/// Balken je Monat (Web `.chart`, 170 pt mit Grundlinie): oben variabel (schraffiert), dann offen, unten bezahlt;
/// gewählter Monat Messing, vergangene blass Messing, künftige grau.
struct KBCostChart: View {
    let months: [Calc.CostMonth]
    let kinds: Calc.CostKindYear
    let selected: Int

    var body: some View {
        let mx = kinds.maxMonth > 0 ? kinds.maxMonth : 1
        GeometryReader { g in
            let h = g.size.height - 1
            ZStack(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        column(months[i], kinds.months[i], on: i + 1 == selected, h: h, mx: mx)
                    }
                }
                .frame(height: h)
                .frame(maxHeight: .infinity, alignment: .top)
                Rectangle().fill(KColor.line).frame(height: 1)
                if kinds.total != 0 {
                    KBAverageLine(fraction: CGFloat(kinds.average / mx))
                        .frame(height: h)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func column(_ m: Calc.CostMonth, _ k: Calc.CostKindMonth, on: Bool, h: CGFloat, mx: Double) -> some View {
        let zero = k.total == 0
        let fix = kinds.kind != .variable
        let vr = zero ? 0 : CGFloat(max(0, k.variable) / mx) * h
        let op = zero || !fix ? 0 : CGFloat(max(0, m.open) / mx) * h
        let pd = zero || !fix ? 0 : CGFloat(max(0, m.paid) / mx) * h
        let hasV = k.variable > 0.005
        let capOpen = m.open > 0 && !hasV
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            if hasV {
                KBHatch(on: on)
                    .frame(height: vr)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .circular))
            }
            UnevenRoundedRectangle(topLeadingRadius: capOpen ? 4 : 0, topTrailingRadius: capOpen ? 4 : 0, style: .circular)
                .fill(on ? KColor.brass : KBColor.barFuture)
                .frame(height: op)
            UnevenRoundedRectangle(topLeadingRadius: capOpen || hasV ? 0 : 4, topTrailingRadius: capOpen || hasV ? 0 : 4, style: .circular)
                .fill(on ? KColor.brass : KBColor.barPast)
                .frame(height: pd)
        }
        .frame(maxWidth: .infinity)
    }
}
