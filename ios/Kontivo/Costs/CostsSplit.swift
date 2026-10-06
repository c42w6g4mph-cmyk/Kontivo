import SwiftUI
import Charts
import KontivoCore

// MARK: - Aufteilung nach Kategorie oder Vertragspartner (Ring mit Top 4 + Übrige)

struct KBCostSplitView: View {
    @Environment(AppModel.self) private var model
    let cy: Calc.CostYear
    let month: Int
    @Binding var splitDim: Calc.FilterDimension
    @Binding var splitMonth: Bool
    @Binding var ringSel: String?
    @Binding var showRest: Bool

    var body: some View {
        let calc = model.calc
        let home = calc.home.rawValue
        let groups = splitMonth ? cy.splitMonths[month - 1] : cy.splitYear
        let sp = calc.kbSplit(groups, dim: splitDim)
        let active: String? = ringSel.flatMap { groups[$0] != nil ? $0 : nil }
        let title = "Aufteilung " + (splitMonth ? Format.monthNames[month - 1] + " " + String(cy.year) : String(cy.year))
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: title) { EmptyView() }
            KCard(padding: 14) {
                pickers
                if sp.keys.isEmpty {
                    Text(verbatim: "Im " + Format.monthNames[month - 1] + " ist nichts fällig.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        ring(sp, groups: groups, active: active, home: home)
                        legend(sp, active: active, home: home)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 6)
                    if showRest && !sp.rest.isEmpty {
                        restList(sp, active: active, home: home)
                    }
                }
            }
        }
        .onChange(of: splitDim) { _, _ in showRest = false }
        .onChange(of: splitMonth) { _, _ in showRest = false }
    }

    private func fmt(_ v: Double) -> String { splitMonth ? Format.money(v) : Format.money0(v) }

    // MARK: Segmente

    private var pickers: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                scopePicker
                Spacer(minLength: 0)
                dimPicker
            }
            VStack(alignment: .leading, spacing: 8) {
                scopePicker
                dimPicker
            }
        }
    }

    private var scopePicker: some View {
        Picker("Zeitraum", selection: $splitMonth) {
            Text("Jahr").tag(false)
            Text(verbatim: Format.monthShort[month - 1]).tag(true)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private var dimPicker: some View {
        Picker("Aufteilen nach", selection: $splitDim) {
            Text("Kategorie").tag(Calc.FilterDimension.category)
            Text("Vertragspartner").tag(Calc.FilterDimension.partner)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    // MARK: Ring

    private func ring(_ sp: Calc.KBSplit, groups: [String: Double], active: String?, home: String) -> some View {
        let label: String
        let value: Double
        if let a = active {
            label = a
            value = groups[a] ?? 0
        } else {
            label = "Total " + (splitMonth ? Format.monthShort[month - 1] : String(cy.year))
            value = sp.total
        }
        return KBRing(segments: sp.segments, active: active, centerLabel: label, centerValue: fmt(value), currency: home)
    }

    // MARK: Legende

    private func legend(_ sp: Calc.KBSplit, active: String?, home: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(sp.segments) { s in
                legendRow(s, sp: sp, active: active, home: home)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(_ s: Calc.KBSplitSegment, sp: Calc.KBSplit, active: String?, home: String) -> some View {
        let on = !s.isOther && active == s.key
        let dim = active != nil && !on
        return Button {
            if s.isOther {
                withAnimation(.easeInOut(duration: 0.2)) { showRest.toggle() }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { ringSel = (ringSel == s.key) ? nil : s.key }
            }
        } label: {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(Color(hex: s.colorHex))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(verbatim: s.key)
                            .font(.subheadline.weight(on ? .semibold : .regular))
                            .foregroundStyle(on ? KColor.teal : KColor.ink)
                            .lineLimit(1)
                        if s.isOther {
                            Text(verbatim: showRest ? "▴" : "▾")
                                .font(.caption)
                                .foregroundStyle(KColor.ink3)
                        }
                    }
                    (Text(verbatim: fmt(s.value)).fontWeight(.semibold).foregroundStyle(KColor.ink2)
                     + Text(verbatim: " " + home + " · " + String(sp.percent(s.value)) + " %").foregroundStyle(KColor.ink3)
                     + prevText(s))
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dim ? 0.4 : 1)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityValue(s.isOther ? Text(verbatim: showRest ? "aufgeklappt" : "zugeklappt") : Text(verbatim: ""))
    }

    /// Vorjahr je Gruppe (nur Jahresansicht, nicht «Übrige»): « · wie 2025» bzw. « · +120 vs. 2025» (Web prevTxt)
    private func prevText(_ s: Calc.KBSplitSegment) -> Text {
        guard !splitMonth, !s.isOther, let p = cy.previousText(s.key) else { return Text(verbatim: "") }
        if let d = p.delta {
            return Text(verbatim: " · ").foregroundStyle(KColor.ink3)
                + Text(verbatim: d).foregroundStyle(KBCostMonthCard.color(p.trend))
                + Text(verbatim: " " + p.suffix).foregroundStyle(KColor.ink3)
        }
        return Text(verbatim: " · " + p.suffix).foregroundStyle(KColor.ink3)
    }

    // MARK: Restliste hinter «Übrige»

    private func restList(_ sp: Calc.KBSplit, active: String?, home: String) -> some View {
        VStack(spacing: 0) {
            ForEach(sp.rest, id: \.self) { k in
                KBRowDivider()
                restRow(k, sp: sp, active: active, home: home)
            }
        }
        .padding(.bottom, 2)
    }

    private func restRow(_ k: String, sp: Calc.KBSplit, active: String?, home: String) -> some View {
        let v = sp.values[k] ?? 0
        let on = active == k
        let dim = active != nil && !on
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { ringSel = (ringSel == k) ? nil : k }
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color(hex: Calc.kbOtherColor))
                    .frame(width: 9, height: 9)
                Text(verbatim: k)
                    .font(.subheadline.weight(on ? .semibold : .regular))
                    .foregroundStyle(on ? KColor.teal : KColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                (Text(verbatim: fmt(v)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(KColor.ink)
                 + Text(verbatim: " " + home).font(.caption).foregroundStyle(KColor.ink2))
                    .lineLimit(1)
                Text(verbatim: String(sp.percent(v)) + " %")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(KColor.ink3)
                    .frame(minWidth: 34, alignment: .trailing)
            }
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dim ? 0.45 : 1)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Ring (SectorMark) mit Beschriftung in der Mitte
struct KBRing: View {
    let segments: [Calc.KBSplitSegment]
    let active: String?
    let centerLabel: String
    let centerValue: String
    let currency: String

    var body: some View {
        ZStack {
            Chart(segments) { s in
                SectorMark(angle: .value("Betrag", s.value),
                           innerRadius: .ratio(0.74),
                           angularInset: segments.count > 1 ? 1.2 : 0)
                    .foregroundStyle(Color(hex: s.colorHex))
                    .opacity(active != nil && active != s.key ? 0.3 : 1)
            }
            .chartLegend(.hidden)
            .accessibilityHidden(true)
            VStack(spacing: 1) {
                Text(verbatim: centerLabel)
                    .font(.caption2)
                    .foregroundStyle(KColor.ink3)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                Text(verbatim: centerValue)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(verbatim: currency)
                    .font(.caption2)
                    .foregroundStyle(KColor.ink3)
            }
            .padding(.horizontal, 22)
            .accessibilityElement(children: .combine)
        }
        .frame(width: 128, height: 128)
    }
}
