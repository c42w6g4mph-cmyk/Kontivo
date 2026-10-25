import SwiftUI
import KontivoCore

// Budget mit variablen Kosten (Web v226/v227/v238/v239/v256): Kostenart-Auswahl, Kopfzeile Einnahmen · Fixkosten · Variabel,
// Liste «Variable Kosten {Monat}», Summenrechnung als eigene Karte. Rechnung: KontivoCore/VariableCostRules.swift.

/// Auswahl «Alle Kosten · Fixkosten · Ohne Kosten» (Web `BART`, `data-bart`): nur mit erfassten variablen Kosten (v256);
/// Standard «Fixkosten» nicht hervorgehoben, gespeichert in `settings.budgetKind`.
struct KBBudgetKindMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let cur = model.calc.budgetKind
        let binding = Binding<BudgetKind>(get: { cur }, set: { k in
            if k != model.data.settings.budgetKind { model.update { $0.settings.budgetKind = k } }
        })
        Menu {
            Picker("Kostenart", selection: binding) {
                ForEach([BudgetKind.all, .fix, .none], id: \.self) { k in
                    VStack {
                        Text(verbatim: k.title)
                        Text(verbatim: k.subtitle)
                    }
                    .tag(k)
                }
            }
            .pickerStyle(.inline)
        } label: {
            KBSelectLabel(title: cur.title, isOn: cur != .fix)
        }
        .accessibilityLabel("Kostenart")
        .accessibilityValue(Text(verbatim: cur.title))
        .accessibilityIdentifier("budget.kind")
    }
}

/// Zeile unter der Kopfzahl (Web `.krow` / `.krow3`): Einnahmen | Fixkosten (nicht bei «Ohne Kosten») | Variabel (wenn abgezogen)
struct KBBudgetCardRow: View {
    let bm: Calc.BudgetMonth

    var body: some View {
        let three = bm.variable > 0.005
        KBCardRow {
            HStack(alignment: .top, spacing: three ? 8 : 12) {
                cell("Einnahmen", bm.income, .leading)
                if bm.countsFixed {
                    cell("Fixkosten", bm.fixed, three ? .center : .trailing)
                }
                if three {
                    cell("Variabel", bm.variable, .trailing)
                } else if !bm.countsFixed {
                    Spacer(minLength: 0)
                }
            }
        }
    }

    /// Wie `KBStatCell`, mit mittiger Spalte bei drei Werten (Web `.krow3 .kc:nth-child(2)`)
    private func cell(_ label: String, _ v: Double, _ a: HorizontalAlignment) -> some View {
        let frame: Alignment = a == .leading ? .leading : (a == .center ? .center : .trailing)
        return VStack(alignment: a, spacing: 4) {
            Text(verbatim: label)
                .font(.system(size: 11.5))
                .foregroundStyle(KColor.ink3)
                .lineLimit(1)
                .padding(.vertical, KBM.pad(16.675, 11.5))
            Text(verbatim: Format.money(v))
                .font(KFont.serif(17, .medium))
                .tracking(-0.17)
                .foregroundStyle(v < 0.005 ? KColor.ink3 : KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: 24.65)
        }
        .frame(maxWidth: .infinity, alignment: frame)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - «Variable Kosten {Monat}» (Web `varGroupHtml`)

struct KBBudgetVariableList: View {
    @Environment(AppModel.self) private var model
    let year: Int
    let month: Int
    let person: UUID?

    var body: some View {
        let calc = model.calc
        let rows = calc.budgetVariableRows(year: year, month: month, person: person)
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                KBGroupHeader(title: "Variable Kosten " + Format.monthNames[month - 1],
                              amount: Format.money(rows.reduce(0.0) { $0 + $1.value }) + " " + calc.home.rawValue)
                KBListBlock {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                        if idx > 0 { KBRowDivider() }
                        row(r)
                    }
                }
            }
            .padding(.bottom, 2)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("budget.variable")
        }
    }

    @ViewBuilder
    private func row(_ r: Calc.BudgetVariableRow) -> some View {
        if let v = model.data.variableCost(r.variableID) {
            Button {
                model.present(.variableDetail(v.id))
            } label: {
                HStack(spacing: 12) {
                    MarkView(variable: v, size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: r.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(KColor.ink)
                            .lineLimit(1)
                            .frame(height: 20)
                        Text(verbatim: r.sub)
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink2)
                            .lineLimit(1)
                            .frame(height: 18.1)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: Format.money(r.value))
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(KColor.ink)
                            .frame(height: 23.2)
                        Text("geschätzt")
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink3)
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

// MARK: - Summenrechnung (Web `.xsum` als eigene Karte, v227)

/// «Einnahmen − Ausgaben = Verfügbar» bzw. mit variablen Kosten «− Fixkosten = Nach Fixkosten − Variable Kosten = Verfügbar»
struct KBBudgetSumBlock: View {
    @Environment(AppModel.self) private var model
    let bm: Calc.BudgetMonth

    var body: some View {
        let calc = model.calc
        let home = calc.home.rawValue
        VStack(spacing: 0) {
            ForEach(Array(calc.budgetSumLines(bm).enumerated()), id: \.offset) { _, l in
                if l.isTotal || l.isSubtotal {
                    VStack(spacing: 0) {
                        Rectangle().fill(KColor.line).frame(height: 1)
                        line(l, home: home).padding(.top, 4)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, l.isSubtotal ? 4 : 0)
                } else {
                    line(l, home: home)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .kbSurface(KBM.listRadius)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("budget.sum")
        // Web: eigene `.grp` (20 oben) mit `.xsum` (8 oben)
        .padding(.top, 28)
        .padding(.bottom, 2)
    }

    private func line(_ l: Calc.BudgetSumLine, home: String) -> some View {
        let v = (l.value < -0.004 ? Format.minus : "") + Format.money(abs(l.value)) + (l.isTotal ? " " + home : "")
        let strong = l.isTotal || l.isSubtotal
        return HStack {
            Text(verbatim: l.label)
                .font(.system(size: 14, weight: l.isTotal ? .semibold : (l.isSubtotal ? .medium : .regular)))
                .foregroundStyle(strong ? KColor.ink : KColor.ink2)
            Spacer(minLength: 8)
            Text(verbatim: v)
                .font(.system(size: 14, weight: l.isTotal ? .bold : (l.isSubtotal ? .semibold : .medium)).monospacedDigit())
                .foregroundStyle(KColor.ink)
        }
        .padding(.vertical, 3 + KBM.pad(20.3, 14))
    }
}
