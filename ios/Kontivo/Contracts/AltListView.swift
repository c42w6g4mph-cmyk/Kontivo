import SwiftUI
import KontivoCore

/// Verträge-Tab, Ansichten «Einnahmen» und «Variabel» (Web v231–v233 `renderAltList`): Kopfzahl mit Status-Chips, Reiter,
/// Suche mit Filter/Sortierung, Filter-Etiketten, Gruppen wie bei den Verträgen, Archiv beendeter Einträge.
/// Rechnung und Texte: `Calc.altList` (KontivoCore/AltList.swift).
struct AltListView: View {
    @Environment(AppModel.self) private var model
    let mode: ListMode
    @Binding var showFilter: Bool

    var body: some View {
        let calc = model.calc
        let f = model.alt.filter(mode)
        let content = calc.altList(mode, filter: f, status: model.alt.status[mode], search: model.searchText)
        GeometryReader { geo in
            let side = CTListMetric.side(for: geo.size.width)
            List {
                CTPageHeader(title: "Verträge").ctPlainRow(side)
                AltHeroView(mode: mode, content: content, width: geo.size.width - 2 * side).ctPlainRow(side)
                CTModeTabs().ctPlainRow(side)
                CTListControls(showFilter: $showFilter).ctPlainRow(side)
                if content.isEmpty {
                    CTEmptyText(title: content.emptyTitle, text: content.emptyText).ctPlainRow(side)
                } else {
                    let tags = tagList(content, f)
                    if !tags.isEmpty {
                        CTFilterTagBar(tags: tags) { removeTag($0) }
                            .padding(.top, 10)
                            .ctPlainRow(side)
                    }
                    ForEach(Array(content.groups.enumerated()), id: \.element.id) { gi, g in
                        CTGroupHeader(title: g.title, sum: g.sum)
                            .padding(.top, gi == 0 ? 20 : 22)
                            .ctPlainRow(side)
                        ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, r in
                            row(r, first: i == 0, last: i == g.rows.count - 1, side: side)
                        }
                    }
                    if let t = content.noHits {
                        CTEmptyText(title: "Keine Treffer", text: t).ctPlainRow(side)
                    }
                    if !content.archive.isEmpty {
                        archiveRows(content, side: side)
                    }
                    if let h = content.hint {
                        // Web `.vhint`: 12.5 px Tinte 3, Zeile 1.4, 10 oben
                        Text(verbatim: h)
                            .font(.system(size: 12.5))
                            .kLineHeight(12.5, 17.5)
                            .foregroundStyle(KColor.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                            .padding(.horizontal, 4)
                            .ctPlainRow(side)
                    }
                }
                Color.clear.frame(height: 24).ctPlainRow(side)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .listRowSpacing(0)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .kPageBackground()
        .onAppear { syncStatus(content.status) }
        .onChange(of: content.status) { _, s in syncStatus(s) }
    }

    /// Ungültigen Status-Chip auch im Modell entfernen (Web: `state.heroFA[m] = ""`)
    private func syncStatus(_ s: AltStatus?) {
        if model.alt.status[mode] != s { model.alt.status[mode] = s }
    }

    private func tagList(_ c: AltListContent, _ f: AltFilter) -> [CTFilterTag] {
        var out: [CTFilterTag] = []
        if let s = c.status { out.append(CTFilterTag(kind: .hero, text: s.label)) }
        for d in AltDimension.dims(mode) {
            if let v = f[d] { out.append(CTFilterTag(kind: .alt(d), text: v)) }
        }
        return out
    }

    private func removeTag(_ t: CTFilterTag) {
        switch t.kind {
        case .hero: model.alt.status[mode] = nil
        case .alt(let d): model.alt.filters[mode, default: AltFilter()][d] = nil
        default: break
        }
    }

    private func row(_ r: AltRow, first: Bool, last: Bool, side: CGFloat) -> some View {
        Button {
            model.present(mode == .incomes ? .incomeDetail(r.id) : .variableDetail(r.id))
        } label: {
            AltCardRow(row: r, mode: mode)
        }
        .buttonStyle(CTCardButtonStyle())
        .listRowInsets(EdgeInsets(top: 0, leading: side, bottom: 0, trailing: side))
        .listRowSeparator(.hidden)
        .listRowBackground(CTGroupSurface(first: first, last: last).padding(.horizontal, side))
    }

    @ViewBuilder
    private func archiveRows(_ c: AltListContent, side: CGFloat) -> some View {
        let open = model.alt.archiveOpen.contains(mode)
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if open { model.alt.archiveOpen.remove(mode) } else { model.alt.archiveOpen.insert(mode) }
            }
        } label: {
            CTArchiveToggle(text: c.archiveText, open: open)
        }
        .buttonStyle(.plain)
        .padding(.top, c.groups.isEmpty ? 24 : 26)
        .ctPlainRow(side)
        .accessibilityHint(open ? "Zuklappen" : "Aufklappen")
        if open {
            Color.clear.frame(height: 8).ctPlainRow(side)
            ForEach(Array(c.archive.enumerated()), id: \.element.id) { i, r in
                row(r, first: i == 0, last: i == c.archive.count - 1, side: side)
            }
        }
    }
}

// MARK: - Karte (Web `.card` in `renderAltList`)

/// Einnahme bzw. variable Kosten: Kachel 50 | Titel, Zweitzeile, Etikett | Betrag mit Währung, Rhythmus bzw. «pro Monat»
struct AltCardRow: View {
    @Environment(AppModel.self) private var model
    let row: AltRow
    let mode: ListMode

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            mark
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: row.title)
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(13 / 14.5)
                    .ctLine(18.125)
                    .padding(.bottom, 1)
                if !row.meta.isEmpty {
                    Text(verbatim: row.meta)
                        .font(.system(size: 12))
                        .foregroundStyle(KColor.ink2)
                        .lineLimit(1)
                        .ctLine(17.4)
                }
                if let t = row.tag {
                    CTTag(text: t).padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: Format.money(row.amount, row.currency))
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(KColor.ink)
                    Text(verbatim: row.currency.rawValue)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(KColor.ink2)
                }
                .lineLimit(1)
                .ctLine(21.75)
                if let s = row.sub {
                    Text(verbatim: s)
                        .font(.system(size: 10.5))
                        .foregroundStyle(KColor.ink2)
                        .lineLimit(1)
                        .ctLine(15.225)
                }
            }
            .fixedSize()
        }
        .padding(.top, 9).padding(.bottom, 9).padding(.leading, 6).padding(.trailing, 8)
        .frame(minHeight: 68)
        .opacity(row.ended ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var mark: some View {
        if mode == .incomes, let i = model.data.income(row.id) {
            MarkView(income: i, size: 50)
        } else if let v = model.data.variableCost(row.id) {
            MarkView(variable: v, size: 50)
        } else {
            Color.clear.frame(width: 50, height: 50)
        }
    }
}

// MARK: - Kopfzahl (Web `.hero` in `renderAltList`)

private struct AltHeroView: View {
    @Environment(AppModel.self) private var model
    let mode: ListMode
    let content: AltListContent
    let width: CGFloat

    var body: some View {
        let big = min(50, max(42, (width + 2 * CTListMetric.side) * 0.125))
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: content.heroLabel)
                .font(.system(size: 13))
                .foregroundStyle(KColor.ink2)
                .ctLine(18.85)
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(verbatim: Format.money(content.heroSum))
                    .font(KFont.serif(big, .medium))
                    .tracking(-0.01 * big)
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("hero.sum")
                Text(verbatim: model.data.settings.homeCurrency.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KColor.ink2)
            }
            .frame(height: 50)
            .accessibilityElement(children: .combine)
            Text(verbatim: content.heroSub)
                .font(.system(size: 14))
                .foregroundStyle(KColor.ink2)
                .monospacedDigit()
                .lineSpacing(3.6)
                .padding(.top, 6)
                .frame(minHeight: 20.3 + 6, alignment: .bottom)
                .accessibilityIdentifier("hero.sub")
            if content.showsChips && !content.isEmpty {
                HStack(spacing: 6) {
                    chip(content.activeCount, " aktiv ›", .active)
                    chip(content.futureCount, " noch nicht aktiv ›", .future)
                }
                .padding(.top, 12)
            } else {
                Color.clear.frame(height: 11)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Web `.hchip.act`: 13 px, Messing 11 % bzw. gefüllt; erneutes Antippen hebt den Filter auf
    private func chip(_ n: Int, _ text: String, _ s: AltStatus) -> some View {
        let on = content.status == s
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.alt.status[mode] = on ? nil : s
            }
        } label: {
            (Text(verbatim: "\(n)").fontWeight(.semibold) + Text(verbatim: text))
                .font(.system(size: 13))
                .ctLine(15.6)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : KColor.teal)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? KColor.tealFill : KColor.teal.opacity(0.11)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Filter und Sortierung (Web `openAltFilter`, `openAltPick`)

/// «Filter»: Art/Quelle/Person bzw. Art/Person; Antippen zeigt die Werte im selben Blatt
struct AltFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: ListMode
    @State private var dim: AltDimension?

    var body: some View {
        let f = model.alt.filter(mode)
        Group {
            if let d = dim {
                CTPickSheet(title: d.title(mode)) {
                    VStack(alignment: .leading, spacing: 6) {
                        CTPickRow(title: "Alle", selected: f[d] == nil) { select(d, nil) }
                        ForEach(model.calc.altFilterValues(mode, d)) { v in
                            CTPickRow(title: v.key, detail: v.detail, selected: f[d] == v.key) { select(d, v.key) }
                        }
                    }
                }
            } else {
                CTPickSheet(title: "Filter") {
                    VStack(spacing: 6) {
                        ForEach(AltDimension.dims(mode), id: \.self) { d in
                            CTPickRow(title: d.title(mode), detail: (f[d] ?? "Alle") + " ›") { dim = d }
                        }
                        if f.count(mode) > 0 {
                            Button {
                                model.alt.filters[mode] = AltFilter()
                                dismiss()
                            } label: {
                                Text("Alle Filter zurücksetzen")
                                    .font(.system(size: 16))
                                    .foregroundStyle(KColor.alert)
                                    .padding(.vertical, 13).padding(.horizontal, 14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.field))
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("filter.sheet")
        .presentationDetents([.medium, .large])
    }

    private func select(_ d: AltDimension, _ key: String?) {
        model.alt.filters[mode, default: AltFilter()][d] = key
        dismiss()
    }
}

/// «Sortieren nach» der Ansicht; gespeichert in den Einstellungen (Web `settings.sortI`/`sortV`)
struct AltSortSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: ListMode

    var body: some View {
        let cur = model.calc.altSort(mode)
        CTPickSheet(title: "Sortieren nach") {
            VStack(spacing: 6) {
                ForEach(Array(AltSort.options(mode).enumerated()), id: \.offset) { _, o in
                    CTPickRow(title: o.label, selected: o.sort == cur) {
                        if o.sort != cur {
                            let m = mode
                            model.update { d in
                                if m == .incomes { d.settings.incomeSort = o.sort.rawValue } else { d.settings.variableSort = o.sort.rawValue }
                            }
                        }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
