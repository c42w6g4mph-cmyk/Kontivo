import SwiftUI
import KontivoCore

// MARK: - Flex-Zeile wie CSS `display:flex` (flex: grow 1 auto, `.on` grow 2, Knöpfe fest)

private struct KBFlexGrow: LayoutValueKey {
    static let defaultValue: CGFloat = 0
}

extension View {
    /// Anteil am freien Platz (CSS `flex-grow`); 0 = feste Breite
    func kbFlexGrow(_ g: CGFloat) -> some View { layoutValue(key: KBFlexGrow.self, value: g) }
}

/// Verteilt den freien Platz nach `flex-grow` (Basis = ideale Breite); zu wenig Platz schrumpft die dehnbaren Elemente gleichmässig.
struct KBFlexRow: Layout {
    var spacing: CGFloat = 6
    /// true: alle dehnbaren Elemente gleich breit (CSS `flex:1 1 0`)
    var equal = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        let w = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width } + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let n = subviews.count
        guard n > 0 else { return }
        let grows = subviews.map { $0[KBFlexGrow.self] }
        let base = subviews.enumerated().map { i, s in (equal && grows[i] > 0) ? 0 : s.sizeThatFits(.unspecified).width }
        let free = bounds.width - spacing * CGFloat(n - 1) - base.reduce(0, +)
        let gsum = grows.reduce(0, +)
        var widths = base
        if gsum > 0 {
            if free >= 0 {
                for i in 0..<n where grows[i] > 0 { widths[i] += free * grows[i] / gsum }
            } else {
                // schrumpfen nach Basisbreite (CSS flex-shrink 1)
                let shrinkBase = (0..<n).filter { grows[$0] > 0 }.reduce(0) { $0 + base[$1] }
                for i in 0..<n where grows[i] > 0 && shrinkBase > 0 { widths[i] = max(0, base[i] + free * base[i] / shrinkBase) }
            }
        }
        var x = bounds.minX
        for i in 0..<n {
            let sz = subviews[i].sizeThatFits(ProposedViewSize(width: widths[i], height: bounds.height))
            subviews[i].place(at: CGPoint(x: x, y: bounds.midY - sz.height / 2), anchor: .topLeading,
                              proposal: ProposedViewSize(width: widths[i], height: sz.height))
            x += widths[i] + spacing
        }
    }
}

// MARK: - Filterleiste «Kosten» (statFilterBar)

/// Personen als Chips «Alle | Name …» mit Filter-Knopf; bei nur einer Person direkt Kategorie/Vertragspartner;
/// bei mehr als 4 Personen oder langen Namen ein Auswahlknopf.
struct KBCostFilterBar: View {
    @Environment(AppModel.self) private var model
    @Binding var moreFilters: Bool
    @Binding var pick: KBPickDim?

    var body: some View {
        let calc = model.calc
        let f = model.costFilter
        let persons = calc.kbCostPersons(filterPerson: f.person)
        let nOther = (f.category != nil ? 1 : 0) + (f.partner != nil ? 1 : 0)
        let open = moreFilters || nOther > 0
        VStack(spacing: 6) {
            if persons.count <= 1 {
                KBFlexRow {
                    catPartner(f)
                    if nOther > 0 {
                        KBClearButton(label: "Filter zurücksetzen") { model.costFilter = Calc.CostFilter() }
                    }
                }
            } else {
                personRow(persons, f: f, nOther: nOther, open: open)
                if open {
                    KBFlexRow {
                        catPartner(f)
                        if nOther > 0 {
                            KBClearButton(label: "Kategorie und Vertragspartner zurücksetzen") { clearOther() }
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private func personRow(_ persons: [Person], f: Calc.CostFilter, nOther: Int, open: Bool) -> some View {
        let namer = KBHolderNamer(names: persons.map { $0.name }, width: 318)
        if namer.ok {
            KBFlexRow(equal: true) {
                KBPersonChip(title: "Alle", isOn: f.person == nil) { model.costFilter.person = nil }
                    .kbFlexGrow(1)
                ForEach(persons) { p in
                    KBPersonChip(title: namer.display(p.name), isOn: f.person == p.id) { model.costFilter.person = p.id }
                        .kbFlexGrow(1)
                }
                moreButton(nOther: nOther, open: open)
            }
        } else {
            KBFlexRow {
                holderSelect(f)
                moreButton(nOther: nOther, open: open)
            }
        }
    }

    /// Auswahlknopf «Alle Personen» bzw. Name (über 12 Zeichen nur der Vorname)
    private func holderSelect(_ f: Calc.CostFilter) -> some View {
        let name = f.person.flatMap { model.data.person($0)?.name } ?? ""
        let shown = name.utf16.count > 12 ? Format.firstName(name) : name
        return KBSelectButton(title: shown.isEmpty ? "Alle Personen" : shown, isOn: f.person != nil) {
            pick = KBPickDim(dim: .holder)
        }
        .kbFlexGrow(f.person != nil ? 2 : 1)
    }

    @ViewBuilder
    private func catPartner(_ f: Calc.CostFilter) -> some View {
        KBSelectButton(title: f.category ?? "Kategorie", isOn: f.category != nil) {
            pick = KBPickDim(dim: .category)
        }
        .kbFlexGrow(f.category != nil ? 2 : 1)
        .accessibilityIdentifier("costs.filter.category")
        KBSelectButton(title: f.partner ?? "Vertragspartner", isOn: f.partner != nil) {
            pick = KBPickDim(dim: .partner)
        }
        .kbFlexGrow(f.partner != nil ? 2 : 1)
        .accessibilityIdentifier("costs.filter.partner")
    }

    /// Filter-Knopf (Web `.fmore`, 36 pt rund) mit Zähler; gesperrt, solange Kategorie/Vertragspartner gesetzt sind
    private func moreButton(nOther: Int, open: Bool) -> some View {
        Button {
            if nOther > 0 {
                model.toast("Erst Kategorie und Vertragspartner zurücksetzen")
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) { moreFilters.toggle() }
        } label: {
            KBFilterGlyph()
                .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round))
                .frame(width: 17, height: 17)
                .foregroundStyle(nOther > 0 ? Color.white : (open ? KColor.teal : KColor.ink2))
                .frame(width: 36, height: 36)
                .background(Circle().fill(nOther > 0 ? KColor.tealFill : KColor.surface))
                .overlay(Circle().strokeBorder((nOther > 0 || open) ? KColor.teal : KColor.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if nOther > 0 {
                        Text(verbatim: String(nOther))
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(KColor.alertFill))
                            .overlay(Capsule().strokeBorder(KColor.paper, lineWidth: 2).padding(-2))
                            .offset(x: 4, y: -4)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Weitere Filter")
        .accessibilityValue(Text(verbatim: nOther > 0 ? String(nOther) + " aktiv" : (open ? "aufgeklappt" : "zugeklappt")))
        .accessibilityIdentifier("costs.filter.more")
    }

    private func clearOther() {
        var f = model.costFilter
        f.category = nil
        f.partner = nil
        model.costFilter = f
        withAnimation(.easeInOut(duration: 0.2)) { moreFilters = false }
    }
}

// MARK: - Werteliste eines Filters (openPick)

/// Auswahl wie Web `#sheetPick`: Titel 22 px, Zeilen als gerundete Flächen (gewählt Messing), im Tab «Kosten» mit Jahresbetrag
/// und Anteil (grösste zuerst, v190), lange drücken zeigt die Beträge.
struct KBFilterPickSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dim: Calc.FilterDimension

    var body: some View {
        let calc = model.calc
        let values = calc.kbFilterValuesWithAmounts(dim, year: model.selectedYear, filter: model.costFilter)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(verbatim: title)
                        .font(KFont.title(22))
                        .tracking(-0.264)
                        .foregroundStyle(KColor.ink)
                        .padding(.top, 2)
                    Spacer()
                    Button { dismiss() } label: {
                        Text(verbatim: "×")
                            .font(.system(size: 22))
                            .foregroundStyle(KColor.ink2)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(KColor.sunken))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Schliessen")
                }
                VStack(spacing: 6) {
                    row(key: allTitle, text: "", on: currentIsAll) { select(nil) }
                    ForEach(values) { v in
                        row(key: v.value.key, text: v.text, on: isSelected(v.value)) { select(v.value) }
                            .contextMenu {
                                Button {
                                    select(v.value)
                                } label: {
                                    Label("Auswählen", systemImage: "checkmark")
                                }
                            } preview: {
                                KBLongPressPreview(popup: calc.kbPopup(dim, key: v.value.key, personID: v.value.personID))
                                    .environment(model)
                            }
                    }
                }
                .padding(.top, 12)
                if !values.isEmpty {
                    Text("Lange drücken zeigt die Beträge")
                        .font(.system(size: 12))
                        .foregroundStyle(KColor.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(.horizontal, KBM.side)
            .padding(.top, 20)
            .padding(.bottom, 18)
        }
        .background(KColor.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(KColor.teal)
    }

    private func row(key: String, text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(verbatim: key)
                    .font(.system(size: 16, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? Color.white : KColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if !text.isEmpty {
                    Text(verbatim: text)
                        .font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.white.opacity(0.8) : KColor.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13 + KBM.pad(23.2, 16))
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? KColor.tealFill : KColor.field))
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var title: String {
        switch dim {
        case .category: return "Kategorie"
        case .partner: return "Vertragspartner"
        case .holder: return "Person"
        }
    }

    private var allTitle: String {
        switch dim {
        case .category: return "Alle Kategorien"
        case .partner: return "Alle Vertragspartner"
        case .holder: return "Alle Personen"
        }
    }

    private var currentIsAll: Bool {
        let f = model.costFilter
        switch dim {
        case .category: return f.category == nil
        case .partner: return f.partner == nil
        case .holder: return f.person == nil
        }
    }

    private func isSelected(_ v: Calc.KBFilterValue) -> Bool {
        let f = model.costFilter
        switch dim {
        case .category: return f.category == v.key
        case .partner: return f.partner == v.key
        case .holder: return v.personID != nil && f.person == v.personID
        }
    }

    private func select(_ v: Calc.KBFilterValue?) {
        var f = model.costFilter
        switch dim {
        case .category: f.category = v?.key
        case .partner: f.partner = v?.key
        case .holder: f.person = v?.personID
        }
        model.costFilter = f
        dismiss()
    }
}

// MARK: - Pop-up bei langem Drücken (showLpop)

/// Aktive Verträge eines Filterwerts mit Monatsbetrag und Total (Vorschau des Kontextmenüs).
struct KBLongPressPreview: View {
    @Environment(AppModel.self) private var model
    let popup: Calc.KBPopup

    var body: some View {
        let home = model.data.settings.homeCurrency.rawValue
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(verbatim: popup.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(2)
                Spacer(minLength: 10)
                Text(verbatim: home + "/Mt.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(KColor.ink3)
            }
            .padding(.bottom, 8)
            if popup.rows.isEmpty {
                Text("Keine aktiven Verträge.")
                    .font(.caption)
                    .foregroundStyle(KColor.ink3)
                    .padding(.vertical, 4)
            } else {
                ForEach(popup.rows) { r in
                    row(r)
                }
                Rectangle().fill(KColor.line).frame(height: 0.5).padding(.top, 6)
                HStack {
                    Text("Total pro Monat")
                    Spacer(minLength: 10)
                    Text(verbatim: Format.money(popup.total) + " " + home)
                        .monospacedDigit()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(KColor.ink)
                .padding(.top, 8)
            }
            if let e = popup.endedText {
                Text(verbatim: e)
                    .font(.caption)
                    .foregroundStyle(KColor.ink3)
                    .padding(.top, 6)
            }
        }
        .padding(16)
        .frame(width: 340, alignment: .leading)
        .background(KColor.surface)
    }

    @ViewBuilder
    private func row(_ r: Calc.KBPopupRow) -> some View {
        HStack(spacing: 10) {
            if let c = model.data.contract(r.contractID) {
                MarkView(contract: c, data: model.data, size: 30)
            }
            Text(verbatim: r.text)
                .font(.subheadline)
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: Format.money(r.value))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(KColor.ink)
        }
        .padding(.vertical, 6)
        .opacity(r.paused ? 0.55 : 1)
    }
}
