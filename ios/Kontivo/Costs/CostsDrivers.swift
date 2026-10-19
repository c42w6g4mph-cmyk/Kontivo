import SwiftUI
import KontivoCore

// MARK: - «Entwicklung und Preistreiber» (Web v190–v192, `ptSection`)

/// Säulen Vorjahr · aktuelles Jahr · Prognose mit Jahrestotal (Antippen setzt das Jahr der Seite; der Bereich bleibt an derselben
/// Bildschirmstelle), darunter die Treiber je Kategorie; Antippen klappt die Verträge mit Grund auf. Namen und Gründe brechen um.
struct KBCostDriversView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.kbScroll) private var scroll
    @Environment(\.kbMini) private var mini
    let year: Int
    @Binding var open: String?
    /// Lage im sichtbaren Bereich (ohne Neuzeichnen beim Scrollen)
    @State private var box = KBFrameBox()

    static let anchorID = "kbDrivers"

    var body: some View {
        let calc = model.calc
        let d = KBYearCache.drivers(calc, year: year, filter: model.costFilter)
        let H = calc.home.rawValue
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: "Entwicklung und Preistreiber") { EmptyView() }
            VStack(alignment: .leading, spacing: 0) {
                label("Deine Fixkosten pro Jahr in " + H)
                    .padding(.bottom, 6)
                columns(d)
                if !d.comparable {
                    if let n = d.noCompareNote { note(n).padding(.top, 2) }
                } else {
                    label(d.listTitle)
                        .padding(.top, 13)
                        .padding(.bottom, 6)
                    if let e = d.emptyNote { note(e).padding(.top, 2) }
                    ForEach(Array(d.groups.enumerated()), id: \.element.id) { i, g in
                        if i > 0 { KBRowDivider() }
                        groupRow(g, unit: H)
                        if open == g.key { subRows(g, unit: H) }
                    }
                    if let o = d.othersNote { note(o).padding(.top, 2) }
                    if let s = d.noStartNote { note(s).padding(.top, 2) }
                }
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .kbSurface(KBM.listRadius)
            .background(GeometryReader { g in
                let f = g.frame(in: .global)
                Color.clear
                    .onAppear { box.frame = f }
                    .onChange(of: f) { _, n in box.frame = n }
            })
        }
        // Web `.grp` padding-bottom 2
        .padding(.bottom, 2)
        .id(KBCostDriversView.anchorID)
    }

    private func label(_ t: String) -> some View {
        Text(verbatim: t)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(KColor.ink3)
            .padding(.vertical, KBM.pad(18.125, 12.5))
    }

    private func note(_ t: String) -> some View {
        Text(verbatim: t)
            .font(.system(size: 12.5))
            .kLineHeight(12.5, 17.5)
            .foregroundStyle(KColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }

    // MARK: Säulen

    private func columns(_ d: Calc.CostDrivers) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(d.columns) { c in
                Spacer(minLength: 0)
                column(c)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    private func column(_ c: Calc.CostDriverColumn) -> some View {
        Button {
            pickYear(c.year)
        } label: {
            VStack(spacing: 0) {
                Text(verbatim: c.forecast ? "Prognose" : " ")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(KColor.ink3)
                    .frame(height: 14)
                Text(verbatim: Format.money0(c.total))
                    .font(KFont.serif(19, .medium))
                    .tracking(-0.19)
                    .foregroundStyle(c.place == .future ? KColor.ink2 : KColor.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(height: 21.85)
                Text(verbatim: c.deltaText ?? " ")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.trend == .up ? KColor.warn : (c.trend == .down ? KColor.ok : KColor.ink3))
                    .frame(height: 16)
                ZStack(alignment: .bottom) {
                    Color.clear
                    UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 8,
                                           style: .circular)
                        .fill(barColor(c.place))
                        .frame(width: 56, height: 96 * CGFloat(c.height))
                }
                .frame(width: 84, height: 96)
                .padding(.top, 8)
                Text(verbatim: String(c.year))
                    .font(.system(size: 12.5, weight: c.place == .current ? .bold : .regular))
                    .foregroundStyle(c.place == .current ? KColor.teal : KColor.ink3)
                    .frame(height: 18.125)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
            }
            .frame(width: 84)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: c.accessibilityLabel))
        .accessibilityAddTraits(c.place == .current ? .isSelected : [])
        .accessibilityIdentifier("costs.drivers.year." + String(c.year))
    }

    private func barColor(_ p: Calc.CostDriverColumn.Place) -> Color {
        switch p {
        case .current: return KColor.brass
        case .past: return KBColor.ptPast
        case .future: return KBColor.barFuture
        }
    }

    /// Jahr der ganzen Seite setzen; Bereich bleibt an derselben Bildschirmstelle (Web v192)
    private func pickYear(_ y: Int) {
        guard y != model.selectedYear else { return }
        let top = box.frame.minY - (mini?.viewportTop ?? 0)
        let h = box.frame.height
        open = nil
        KBMonthNav.setYear(model, y)
        let s = scroll
        DispatchQueue.main.async {
            s.keep(KBCostDriversView.anchorID, top: top, viewHeight: h)
        }
    }

    // MARK: Treiber je Kategorie

    private func groupRow(_ g: Calc.CostDriverGroup, unit: String) -> some View {
        let on = open == g.key
        return Button {
            open = on ? nil : g.key
        } label: {
            HStack(alignment: .top, spacing: 11) {
                categoryMark(g.key, size: 36)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 2) {
                    // Web `.ptrow .mn` 15.5/20.15, `.mm` 12.5/16.25
                    Text(verbatim: g.key)
                        .font(.system(size: 15.5, weight: .semibold, design: .rounded))
                        .kLineHeight(15.5, 20.15)
                        .foregroundStyle(KColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if !g.why.isEmpty {
                        Text(verbatim: g.why)
                            .font(.system(size: 12.5))
                            .kLineHeight(12.5, 16.25)
                            .foregroundStyle(KColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                delta(g.delta, unit: unit, size: 16)
                    .padding(.top, 2)
                // Web `.aechev`: 17/24.65, 12 breit, Zeichen links
                Text(verbatim: "›")
                    .font(.system(size: 17))
                    .foregroundStyle(KColor.ink3)
                    .rotationEffect(.degrees(on ? 90 : 0))
                    .frame(width: 12, height: 24.65, alignment: .leading)
                    .padding(.top, 4)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityValue(on ? Text("aufgeklappt") : Text("zugeklappt"))
        .accessibilityIdentifier("costs.drivers.cat." + g.key)
    }

    private func subRows(_ g: Calc.CostDriverGroup, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(g.changes) { r in
                if let c = model.data.contract(r.contractID) {
                    Button {
                        model.present(.contractDetail(c.id))
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            MarkView(contract: c, data: model.data, size: 28)
                                .padding(.top, 2)
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
                            delta(r.delta, unit: unit, size: 14.5)
                                .padding(.top, 2)
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

    /// «+49 CHF» (Web `.ptv`)
    private func delta(_ d: Double, unit: String, size: CGFloat) -> some View {
        let t = Calc.driverDeltaText(d)
        return HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(verbatim: t.text)
                .font(.system(size: size, weight: .semibold).monospacedDigit())
                .foregroundStyle(t.trend == .up ? KColor.warn : (t.trend == .down ? KColor.ok : KColor.ink))
            Text(verbatim: unit)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(KColor.ink2)
        }
        // Web `.ptv`: Zeilenhöhe 1.45
        .frame(minHeight: size * 1.45)
        .fixedSize()
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

/// Rahmen ohne Beobachtung (Schreiben löst kein Neuzeichnen aus)
final class KBFrameBox {
    var frame: CGRect = .zero
}
