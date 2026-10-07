import SwiftUI
import Charts
import KontivoCore

// MARK: - «Aufteilung und Entwicklung» (Web 64ccf42 + 5a60137, Variante P2)
// Eine Karte: Segmente oben, Kopf «Entwicklung 2024–2026» mit Chip «↓ 5 % vs. 2025», waagrechte Jahresbalken (aktuelles Jahr
// und bis zu 2 Vorjahre, nach Gruppen eingefärbt), Liste je Gruppe (Top 4 + Übrige) mit Anteil und Veränderung.
// Zeile antippen klappt den Verlauf als Säulen auf, darin «Nur … anzeigen» setzt den Filter.

struct KBCostSplitView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cy: Calc.CostYear
    let month: Int
    @Binding var splitDim: Calc.FilterDimension
    @Binding var splitMonth: Bool
    @Binding var ringSel: String?
    @Binding var showRest: Bool

    var body: some View {
        let calc = model.calc
        let home = calc.home.rawValue
        let ev = calc.costEvolution(year: cy.year, month: splitMonth ? month : nil, filter: model.costFilter, dim: splitDim)
        let active: String? = ringSel.flatMap { k in ev.keys.contains(k) ? k : nil }
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: "Aufteilung und Entwicklung") { EmptyView() }
            KCard(padding: 14) {
                pickers
                if ev.keys.isEmpty {
                    Text(verbatim: "Im " + Format.monthNames[month - 1] + " ist nichts fällig.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .padding(.top, 18)
                        .padding(.bottom, 6)
                } else {
                    header(ev)
                    bars(ev, home: home)
                    if let n = ev.note {
                        Text(verbatim: n).font(.caption).foregroundStyle(KColor.ink3).padding(.top, 6)
                    }
                    VStack(spacing: 0) {
                        ForEach(ev.rows) { r in
                            KBRowDivider()
                            row(r, ev: ev, active: active, home: home)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .onChange(of: splitDim) { _, _ in showRest = false; ringSel = nil }
        .onChange(of: splitMonth) { _, _ in showRest = false }
    }

    private func fmt(_ v: Double) -> String { splitMonth ? Format.money(v) : Format.money0(v) }

    private func trendColor(_ t: Calc.CostTrend) -> Color {
        switch t {
        case .up: return KColor.warn
        case .down: return KColor.ok
        default: return KColor.ink3
        }
    }

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

    // MARK: Kopf und Jahresbalken

    private func header(_ ev: Calc.CostEvolution) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(verbatim: ev.title).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink)
            Spacer(minLength: 8)
            if let chip = ev.chip {
                Text(verbatim: chip)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(trendColor(ev.chipTrend))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(trendColor(ev.chipTrend).opacity(0.14)))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func bars(_ ev: Calc.CostEvolution, home: String) -> some View {
        VStack(spacing: 7) {
            ForEach(ev.bars) { b in
                HStack(spacing: 8) {
                    Text(verbatim: String(b.year))
                        .font(.caption.monospacedDigit().weight(b.isCurrent ? .semibold : .regular))
                        .foregroundStyle(b.isCurrent ? KColor.ink : KColor.ink2)
                        .frame(width: 36, alignment: .leading)
                    GeometryReader { geo in
                        HStack(spacing: 1.5) {
                            ForEach(ev.segments) { sg in
                                let v = ev.value(b.groups, sg)
                                if v > 0.004 {
                                    Rectangle().fill(Color(hex: sg.colorHex))
                                        .frame(width: max(1, geo.size.width * CGFloat(b.total / ev.maxTotal) * CGFloat(v / max(b.total, 0.0001)) - 1.5))
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .opacity(b.isCurrent ? 1 : 0.5)
                    }
                    .frame(height: 12)
                    Text(verbatim: fmt(b.total))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(b.isCurrent ? KColor.ink : KColor.ink2)
                        .frame(minWidth: 52, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: ev.bars.map { (splitMonth ? Format.monthNames[month - 1] + " " : "") + String($0.year) + ": " + fmt($0.total) + " " + home }.joined(separator: ", ")))
    }

    // MARK: Liste

    @ViewBuilder private func row(_ r: Calc.CostEvoRow, ev: Calc.CostEvolution, active: String?, home: String) -> some View {
        let s = r.segment
        let on = s.isOther ? showRest : active == s.key
        let fk = splitDim == .category ? model.costFilter.category : model.costFilter.partner
        let dim = fk != nil && (s.isOther || s.key != fk)
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                if s.isOther { showRest.toggle() } else { ringSel = (ringSel == s.key) ? nil : s.key }
            }
        } label: {
            HStack(spacing: 12) {
                mark(s, ev: ev)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: s.key)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        Text(verbatim: String(r.percent) + " %").foregroundStyle(KColor.ink2)
                        if let ch = r.change {
                            Text(verbatim: "·").foregroundStyle(KColor.ink3)
                            Text(verbatim: ch).foregroundStyle(trendColor(r.trend))
                        }
                    }
                    .font(.footnote.monospacedDigit())
                }
                Spacer(minLength: 8)
                (Text(verbatim: fmt(r.value)).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(KColor.ink)
                 + Text(verbatim: " " + home).font(.caption).foregroundStyle(KColor.ink2))
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
                    .rotationEffect(.degrees(on ? 90 : 0))
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(dim ? 0.45 : 1)
        .accessibilityValue(Text(verbatim: on ? "aufgeklappt" : "zugeklappt"))
        if on && !s.isOther {
            history(r, ev: ev, isFilter: fk == s.key)
                .transition(.opacity)
        }
        if on && s.isOther {
            VStack(spacing: 0) {
                ForEach(Array(ev.rest.enumerated()), id: \.offset) { _, x in
                    Button { setFilter(x.key) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(Color(hex: Calc.kbOtherColor)).frame(width: 9, height: 9)
                            Text(verbatim: x.key).font(.subheadline).foregroundStyle(KColor.ink).lineLimit(1)
                            Spacer(minLength: 8)
                            (Text(verbatim: fmt(x.value)).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(KColor.ink)
                             + Text(verbatim: " " + home).font(.caption).foregroundStyle(KColor.ink2))
                            Text(verbatim: String(x.percent) + " %").font(.caption.monospacedDigit()).foregroundStyle(KColor.ink3)
                                .frame(minWidth: 34, alignment: .trailing)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 52)
        }
    }

    /// Symbol: Kategorie bzw. Logo/Farbe des Vertragspartners; «Übrige» als 2×2-Farbsymbol der nächsten Gruppen.
    @ViewBuilder private func mark(_ s: Calc.KBSplitSegment, ev: Calc.CostEvolution) -> some View {
        let calc = model.calc
        if s.isOther {
            let nTop = ev.segments.filter { !$0.isOther }.count
            let cols = (0..<4).map { i -> String in
                guard i < ev.rest.count else { return Calc.kbOtherColor }
                return splitDim == .category ? calc.kbCategoryColor(ev.rest[i].key) : Calc.kbPartnerPalette[(nTop + i) % Calc.kbPartnerPalette.count]
            }
            LazyVGrid(columns: [GridItem(.fixed(18), spacing: 2), GridItem(.fixed(18), spacing: 2)], spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color(hex: cols[i])).frame(width: 18, height: 18)
                }
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)
        } else if splitDim == .category {
            MarkView(logoID: nil, logoBg: nil, colorHex: s.colorHex, symbol: KIcon.symbol(for: model.data.category(named: s.key)), size: 40)
        } else if let c = model.data.contracts.first(where: { calc.statKey($0, .partner) == s.key }) {
            if model.data.logo(of: c) != nil {
                MarkView(contract: c, data: model.data, size: 40)
            } else {
                MarkView(logoID: nil, logoBg: nil, colorHex: s.colorHex, symbol: KIcon.symbol(for: model.data.category(c.categoryID)), size: 40)
            }
        } else {
            MarkView(logoID: nil, logoBg: nil, colorHex: s.colorHex, symbol: KIcon.symbol(for: nil), size: 40)
        }
    }

    /// Verlauf als Säulen ab null mit Beträgen, darunter «Nur … anzeigen ›» bzw. «Filter aufheben».
    private func history(_ r: Calc.CostEvoRow, ev: Calc.CostEvolution, isFilter: Bool) -> some View {
        let mx = max(r.series.map { $0.value }.max() ?? 1, 0.0001)
        return VStack(alignment: .leading, spacing: 8) {
            if r.series.count < 2 {
                Text("Noch keine Vorjahre zum Vergleich.").font(.caption).foregroundStyle(KColor.ink3)
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(r.series.enumerated()), id: \.offset) { i, p in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color(hex: r.segment.colorHex).opacity(i == r.series.count - 1 ? 1 : 0.5))
                                .frame(height: max(2, 56 * CGFloat(p.value / mx)))
                            Text(verbatim: String(p.year)).font(.caption2).foregroundStyle(KColor.ink3)
                            Text(verbatim: fmt(p.value)).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(KColor.ink)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 96, alignment: .bottom)
                .accessibilityElement(children: .combine)
            }
            Button {
                if isFilter { setFilter(nil) } else { setFilter(r.segment.key) }
            } label: {
                Text(verbatim: isFilter ? "Filter aufheben" : "Nur " + r.segment.key + " anzeigen ›")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 52)
        .padding(.bottom, 10)
    }

    private func setFilter(_ key: String?) {
        if splitDim == .category { model.costFilter.category = key } else { model.costFilter.partner = key }
        ringSel = nil
        showRest = false
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
