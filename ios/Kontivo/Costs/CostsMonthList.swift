import SwiftUI
import KontivoCore

// MARK: - Liste «Fällig im {Monat}» (Web v245: eine durchgehende Liste, bereits bezahlte ausgegraut)

struct KBCostMonthList: View {
    @Environment(AppModel.self) private var model
    let items: [Calc.CostItem]
    let month: Int
    @Binding var byAmount: Bool

    var body: some View {
        let list = byAmount ? items.stableSortedKB { $0.value > $1.value } : items.stableSortedKB { $0.date < $1.date }
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
                    ForEach(Array(list.enumerated()), id: \.offset) { idx, it in
                        if idx > 0 { KBRowDivider() }
                        KBCostRow(item: it)
                    }
                }
            }
        }
        // Web `.grp` padding-bottom 2
        .padding(.bottom, 2)
    }
}

extension Array {
    /// Stabil sortieren (gleiche Elemente behalten ihre Reihenfolge, wie `Array.prototype.sort` in der Web-App)
    func stableSortedKB(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in less(a.element, b.element) || (!less(b.element, a.element) && a.offset < b.offset) }.map(\.element)
    }
}

/// Zeile einer Zahlung (Web `.mrows2 .mrow`): Kachel 34, Name rund 16 Semibold, Zweitzeile 12.5, Betrag 16 Semibold;
/// bezahlt (vor heute): Name und Betrag Tinte 2, Kachel 45 %, Text 50 % (Web `.mrow.past`). Status «heute» bzw. Datum.
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
                        .opacity(past ? 0.45 : 1)
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
                    .opacity(past ? 0.5 : 1)
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
                    .opacity(past ? 0.5 : 1)
                    .layoutPriority(1)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(past ? Text("bezahlt") : Text(""))
        }
    }
}

// MARK: - «Variable Kosten {Monat}» (Web v230 `varGroupHtml`)

/// Eigene Liste der variablen Kosten des Monats mit Personenfilter; zählt nicht in die Fixkosten-Summen.
struct KBVariableList: View {
    @Environment(AppModel.self) private var model
    let group: Calc.VariableCostGroup

    var body: some View {
        let home = model.calc.home.rawValue
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: group.title, amount: Format.money(group.total) + " " + home)
            KBListBlock {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { idx, r in
                    if idx > 0 { KBRowDivider() }
                    row(r)
                }
            }
        }
        .padding(.bottom, 2)
        .accessibilityIdentifier("costs.vars")
    }

    private func row(_ r: Calc.VariableCostRow) -> some View {
        let v = model.data.variableCosts.first { $0.id == r.id }
        return Button {
            model.present(.variableDetail(r.id))
        } label: {
            HStack(spacing: 12) {
                MarkView(logoID: v?.logoID, logoBg: v?.logoBg, colorHex: v?.icon.colorHex ?? VarIcon.sonst.colorHex,
                         symbol: "ic.var." + (v?.icon ?? .sonst).rawValue, size: 34)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: r.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                        .frame(height: 20)
                    Text(verbatim: r.subline)
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
