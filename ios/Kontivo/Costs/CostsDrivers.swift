import SwiftUI
import KontivoCore

// MARK: - «Was sich verändert hat» / «Prognose» (Web v248–v252, v257 `ptSection`, eigener Abschnitt unter «Überblick»)

/// Treiber je Kategorie: Kachel, Name, Differenz, Winkel; darunter Chips (Vertrag + Status-Wort, Punkt nach Richtung).
/// Antippen klappt die Verträge mit Grund auf. Verträge ohne Beginn sind im Hinweis antippbar (öffnet den Vertrag).
struct KBChangesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.kbScroll) private var scroll
    let drivers: Calc.CostDrivers
    @Binding var open: String?

    var body: some View {
        let d = drivers
        let H = model.calc.home.rawValue
        let Y = d.year
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: Y > model.today.year ? "Prognose" : "Was sich verändert hat") {
                Text(verbatim: String(Y - 1) + " → " + String(Y))
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink2)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let e = d.emptyNote { KBNote(text: e).padding(.top, 12) }
                ForEach(Array(d.groups.enumerated()), id: \.element.id) { i, g in
                    if i > 0 { KBRowDivider() }
                    groupRow(g, unit: H)
                    if open == g.key { subRows(g, unit: H) }
                }
                if let o = d.othersNote { KBNote(text: o).padding(.top, 2) }
                if !d.noStartContracts.isEmpty { noStart(d) }
            }
            .padding(.top, 2)
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kbSurface(KBM.listRadius)
        }
        .padding(.bottom, 2)
        .id("kbChanges")
    }

    /// «Ohne Vertragsbeginn, deshalb auch für 2025 voll gezählt: Strom ›» – Namen antippbar (Web v251 `.ptlink`)
    private func noStart(_ d: Calc.CostDrivers) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: "Ohne Vertragsbeginn, deshalb auch für " + String(d.year - 1) + " voll gezählt:")
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            KBFlow(spacing: 8, lineSpacing: 2) {
                ForEach(d.noStartContracts, id: \.self) { id in
                    if let c = model.data.contract(id) {
                        Button {
                            model.present(.contractDetail(id))
                        } label: {
                            Text(verbatim: model.data.title(of: c) + " ›")
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(KColor.brass)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("costs.nostart." + model.data.title(of: c))
                    }
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    private func groupRow(_ g: Calc.CostDriverGroup, unit: String) -> some View {
        let on = open == g.key
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { open = on ? nil : g.key }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 12) {
                    categoryMark(g.key, size: 32)
                    Text(verbatim: g.key)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(KColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    KBDelta(value: g.delta, unit: unit, size: 16)
                    Text(verbatim: "›")
                        .font(.system(size: 17))
                        .foregroundStyle(KColor.ink3)
                        .rotationEffect(.degrees(on ? 90 : 0))
                        .frame(width: 12)
                }
                if !g.chips.isEmpty {
                    KBFlow(spacing: 5, lineSpacing: 5) {
                        ForEach(Array(g.chips.enumerated()), id: \.offset) { _, c in chip(c) }
                        if g.moreCount > 0 && !on {
                            Text(verbatim: "+ \(g.moreCount) weitere")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(KColor.ink3)
                                .padding(.vertical, 2)
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.leading, 44)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: g.key))
        .accessibilityValue(Text(verbatim: Calc.driverDeltaText(g.delta).text + " " + unit + ", " + g.why + ", " + (on ? "aufgeklappt" : "zugeklappt")))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("costs.drivers.cat." + g.key)
    }

    /// Chip (Web `.ptch`): grau, Punkt und Status-Wort in der Farbe der Richtung
    private func chip(_ c: Calc.CostDriverChip) -> some View {
        let col: Color = c.tone == .up ? KColor.warn : (c.tone == .down ? KColor.ok : KColor.ink3)
        return HStack(spacing: 5) {
            Circle().fill(col).frame(width: 6, height: 6)
            (Text(verbatim: c.name + " ").foregroundStyle(KColor.ink)
             + Text(verbatim: c.word).fontWeight(.semibold).foregroundStyle(c.tone == .swap ? KColor.ink2 : col))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.ink3.opacity(0.16)))
    }

    private func subRows(_ g: Calc.CostDriverGroup, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(g.changes) { r in
                if let c = model.data.contract(r.contractID) {
                    Button {
                        model.present(.contractDetail(c.id))
                    } label: {
                        HStack(alignment: .center, spacing: 10) {
                            MarkView(contract: c, data: model.data, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(verbatim: model.data.title(of: c))
                                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                                    .foregroundStyle(KColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(verbatim: r.reason)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(KColor.ink2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            KBDelta(value: r.delta, unit: unit, size: 14.5)
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                }
            }
            Button {
                var f = model.costFilter
                f.category = g.key
                model.costFilter = f
                scroll.proxy?.scrollTo("kbTop", anchor: .top)
            } label: {
                Text(verbatim: "Nur " + g.key + " anzeigen ›")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(KColor.teal)
                    .padding(.top, 6)
                    .padding(.bottom, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(KColor.line).frame(width: 2) }
        .padding(.leading, 17)
        .padding(.top, -4)
        .padding(.bottom, 8)
    }

    /// Kachel einer Kategorie (Farbe und Symbol der Kategorie)
    @ViewBuilder
    private func categoryMark(_ name: String, size: CGFloat) -> some View {
        if let cat = model.data.category(named: name) {
            MarkView(category: cat, size: size)
        } else {
            MarkView(logoID: nil, logoBg: nil, colorHex: "#5F666E", symbol: KIcon.symbol(forKey: "Sonstiges"), size: size)
        }
    }
}

/// «+49 CHF» (Web `.ptv`)
struct KBDelta: View {
    let value: Double
    let unit: String
    let size: CGFloat

    var body: some View {
        let t = Calc.driverDeltaText(value)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: t.text)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(t.trend == .up ? KColor.warn : (t.trend == .down ? KColor.ok : KColor.ink))
            Text(verbatim: unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KColor.ink2)
        }
        .fixedSize()
    }
}

/// Zeilenumbruch wie CSS `flex-wrap` (Chips, Links)
struct KBFlow: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        let rows = arrange(subviews, width: w)
        let h = rows.reduce(0) { $0 + $1.h } + lineSpacing * CGFloat(max(0, rows.count - 1))
        let mw = rows.map(\.w).max() ?? 0
        return CGSize(width: proposal.width ?? mw, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for r in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (i, sz) in zip(r.idx, r.sizes) {
                subviews[i].place(at: CGPoint(x: x, y: y + (r.h - sz.height) / 2), proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += r.h + lineSpacing
        }
    }

    private struct Row { var idx: [Int] = []; var sizes: [CGSize] = []; var w: CGFloat = 0; var h: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var cur = Row()
        for (i, s) in subviews.enumerated() {
            var sz = s.sizeThatFits(.unspecified)
            if sz.width > width { sz = s.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if !cur.idx.isEmpty && cur.w + spacing + sz.width > width {
                rows.append(cur)
                cur = Row()
            }
            cur.w += (cur.idx.isEmpty ? 0 : spacing) + sz.width
            cur.h = max(cur.h, sz.height)
            cur.idx.append(i)
            cur.sizes.append(sz)
        }
        if !cur.idx.isEmpty { rows.append(cur) }
        return rows
    }
}

/// Rahmen ohne Beobachtung (Schreiben löst kein Neuzeichnen aus)
final class KBFrameBox {
    var frame: CGRect = .zero
}
