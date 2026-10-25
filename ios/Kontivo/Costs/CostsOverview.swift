import SwiftUI
import KontivoCore

// MARK: - «Überblick» (Web v254 `ptSection`): Umschalter Jahre · Kategorien

/// Ansicht im Überblick (Web `state.ptView`)
enum KBOverviewView: String, Hashable {
    case years, categories
}

/// Karte «Überblick»: Säulen Vorjahr · aktuelles Jahr · Prognose (Antippen setzt das Jahr der Seite; der Bereich bleibt an derselben
/// Bildschirmstelle) oder Kategorien-Donut (Legende antippen = nur diese Kategorie). Ohne Vorjahr der Hinweis in der Karte.
struct KBOverviewCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.kbScroll) private var scroll
    @Environment(\.kbMini) private var mini
    let year: Int
    let drivers: Calc.CostDrivers
    @Binding var view: KBOverviewView
    /// Aufgeklappte Kategorie in «Was sich verändert hat» (beim Jahreswechsel zu)
    @Binding var open: String?
    /// Lage im sichtbaren Bereich (ohne Neuzeichnen beim Scrollen)
    @State private var box = KBFrameBox()

    static let anchorID = "kbDrivers"

    var body: some View {
        let H = model.calc.home.rawValue
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: "Überblick") { EmptyView() }
            VStack(alignment: .leading, spacing: 0) {
                segment
                    .padding(.top, -4)
                    .padding(.bottom, 12)
                if view == .categories {
                    KBDonutView(donut: KBYearCache.donut(model.calc, year: year, filter: model.costFilter), unit: H)
                } else {
                    Text(verbatim: "Deine Fixkosten pro Jahr in " + H)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(KColor.ink3)
                        .padding(.vertical, KBM.pad(18.125, 12.5))
                        .padding(.bottom, 6)
                    columns(drivers)
                }
                if !drivers.comparable, let n = drivers.noCompareNote {
                    KBNote(text: n).padding(.top, 2)
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
        .padding(.bottom, 2)
        .id(KBOverviewCard.anchorID)
    }

    /// Reiter «Jahre | Kategorien» (Web `.ptseg`): unterstrichen in Messing
    private var segment: some View {
        HStack(spacing: 20) {
            tab("Jahre", .years)
            tab("Kategorien", .categories)
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ansicht")
    }

    private func tab(_ t: String, _ v: KBOverviewView) -> some View {
        let on = view == v
        return Button {
            view = v
        } label: {
            Text(verbatim: t)
                .font(.system(size: 14.5, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? KColor.ink : KColor.ink2)
                .padding(.top, 6)
                .padding(.bottom, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(on ? KColor.brass : .clear).frame(height: 2.5)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("costs.overview." + v.rawValue)
    }

    // MARK: Säulen (Web `.ptcols`, ohne Grundlinie seit v257)

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
        .padding(.bottom, 8)
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
            s.keep(KBOverviewCard.anchorID, top: top, viewHeight: h)
        }
    }
}

/// Hinweis (Web `.ptnote`: 12.5 px Tinte 3, Zeilenhöhe 1.4)
struct KBNote: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12.5))
            .kLineHeight(12.5, 17.5)
            .foregroundStyle(KColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 10)
    }
}

// MARK: - Kategorien-Donut (Web v254 `ptDonut`, v255 Legende passt Schrift an)

struct KBDonutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.kbScroll) private var scroll
    let donut: Calc.CostDonut
    let unit: String

    var body: some View {
        if let e = donut.emptyNote {
            KBNote(text: e)
        } else {
            HStack(alignment: .center, spacing: 16) {
                ring
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(donut.slices) { s in legendRow(s) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
            .padding(.bottom, 14)
        }
    }

    private func color(_ s: Calc.CostDonutSlice) -> Color {
        s.colorHex.map { Color(hex: $0) } ?? KColor.ink3
    }

    /// Ring 128 pt, Breite 16 % (Web `.ptdn:after inset 16 %`), Lücken 0.8° zwischen den Stücken
    private var ring: some View {
        let T = max(donut.total, 0.0001)
        let gap = donut.slices.count > 1 ? 0.8 / 360 : 0
        var acc = 0.0
        let parts: [(a: Double, b: Double, c: Color)] = donut.slices.map { s in
            let a = acc / T, b = (acc + s.value) / T
            acc += s.value
            return (a + gap, b, color(s))
        }
        return ZStack {
            ForEach(Array(parts.enumerated()), id: \.offset) { _, p in
                Circle()
                    .trim(from: p.a, to: max(p.a, p.b))
                    .stroke(p.c, style: StrokeStyle(lineWidth: 128 * 0.16, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
                    .padding(128 * 0.08)
            }
            VStack(spacing: 0) {
                Text(verbatim: Format.money0(donut.total))
                    .font(KFont.serif(19, .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(verbatim: unit + " " + String(donut.year))
                    .font(.system(size: 11.5))
                    .foregroundStyle(KColor.ink3)
            }
            .foregroundStyle(KColor.ink)
            .padding(.horizontal, 24)
        }
        .frame(width: 128, height: 128)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Fixkosten " + String(donut.year) + " nach Kategorie"))
        .accessibilityValue(Text(verbatim: donut.slices.map { $0.key + " " + $0.percentText }.joined(separator: ", ")))
    }

    @ViewBuilder
    private func legendRow(_ s: Calc.CostDonutSlice) -> some View {
        let content = HStack(spacing: 8) {
            Circle().fill(color(s)).frame(width: 9, height: 9)
            // Name einzeilig; zu lang → Schrift bis 11 pt kleiner (Web v255), erst dann gekürzt
            Text(verbatim: s.key)
                .font(.system(size: 13.5))
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(11 / 13.5)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: s.percentText)
                .font(.system(size: 13.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(KColor.ink2)
                .fixedSize()
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        if s.isRest {
            content.accessibilityElement(children: .combine)
        } else {
            Button {
                var f = model.costFilter
                f.category = s.key
                model.costFilter = f
                scroll.proxy?.scrollTo("kbTop", anchor: .top)
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "Nur " + s.key + " anzeigen"))
            .accessibilityValue(Text(verbatim: s.percentText))
            .accessibilityIdentifier("costs.donut." + s.key)
        }
    }
}
