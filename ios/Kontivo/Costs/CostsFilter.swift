import SwiftUI
import KontivoCore

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
                HStack(spacing: 6) {
                    catPartner(f)
                    if nOther > 0 || f.person != nil {
                        KBClearButton(label: "Filter zurücksetzen") { model.costFilter = Calc.CostFilter() }
                    }
                }
            } else {
                personRow(persons, f: f, nOther: nOther, open: open)
                if open {
                    HStack(spacing: 6) {
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    chips(persons, namer: namer, f: f)
                    moreButton(nOther: nOther, open: open)
                }
                HStack(spacing: 6) {
                    holderSelect(f)
                    moreButton(nOther: nOther, open: open)
                }
            }
        } else {
            HStack(spacing: 6) {
                holderSelect(f)
                moreButton(nOther: nOther, open: open)
            }
        }
    }

    @ViewBuilder
    private func chips(_ persons: [Person], namer: KBHolderNamer, f: Calc.CostFilter) -> some View {
        KBPersonChip(title: "Alle", isOn: f.person == nil) { model.costFilter.person = nil }
        ForEach(persons) { p in
            KBPersonChip(title: namer.display(p.name), isOn: f.person == p.id) { model.costFilter.person = p.id }
        }
    }

    /// Auswahlknopf «Alle Inhaber» bzw. Name (über 12 Zeichen nur der Vorname)
    private func holderSelect(_ f: Calc.CostFilter) -> some View {
        let name = f.person.flatMap { model.data.person($0)?.name } ?? ""
        let shown = name.utf16.count > 12 ? Format.firstName(name) : name
        return KBSelectButton(title: shown.isEmpty ? "Alle Personen" : shown, isOn: f.person != nil) {
            pick = KBPickDim(dim: .holder)
        }
    }

    @ViewBuilder
    private func catPartner(_ f: Calc.CostFilter) -> some View {
        KBSelectButton(title: f.category ?? "Kategorie", isOn: f.category != nil) {
            pick = KBPickDim(dim: .category)
        }
        KBSelectButton(title: f.partner ?? "Vertragspartner", isOn: f.partner != nil) {
            pick = KBPickDim(dim: .partner)
        }
    }

    /// Filter-Knopf (drei Striche) mit Zähler; gesperrt, solange Kategorie/Vertragspartner gesetzt sind
    private func moreButton(nOther: Int, open: Bool) -> some View {
        Button {
            if nOther > 0 {
                model.toast("Erst Kategorie und Vertragspartner zurücksetzen")
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) { moreFilters.toggle() }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(.semibold))
                if nOther > 0 {
                    Text(verbatim: String(nOther))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(nOther > 0 ? Color.white : (open ? KColor.teal : KColor.ink2))
            .frame(minWidth: 36, minHeight: 36)
            .padding(.horizontal, nOther > 0 ? 6 : 0)
            .background(Capsule().fill(nOther > 0 ? KColor.teal : KColor.surface))
            .overlay(Capsule().strokeBorder((nOther > 0 || open) ? KColor.teal : KColor.line, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Weitere Filter")
        .accessibilityValue(Text(verbatim: nOther > 0 ? String(nOther) + " aktiv" : (open ? "aufgeklappt" : "zugeklappt")))
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

struct KBFilterPickSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let dim: Calc.FilterDimension

    var body: some View {
        let calc = model.calc
        let values = calc.kbFilterValues(dim)
        NavigationStack {
            List {
                Section {
                    allRow
                    ForEach(values) { v in
                        valueRow(v)
                            .contextMenu {
                                Button {
                                    select(v)
                                } label: {
                                    Label("Auswählen", systemImage: "checkmark")
                                }
                            } preview: {
                                KBLongPressPreview(popup: calc.kbPopup(dim, key: v.key, personID: v.personID))
                                    .environment(model)
                            }
                    }
                } footer: {
                    if !values.isEmpty {
                        Text("Lange drücken zeigt die Beträge")
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { CloseButton() }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .tint(KColor.teal)
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

    private var allRow: some View {
        Button {
            select(nil)
        } label: {
            HStack {
                Text(verbatim: allTitle).foregroundStyle(KColor.ink)
                Spacer()
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.teal)
                    .opacity(currentIsAll ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(currentIsAll ? .isSelected : [])
    }

    private func valueRow(_ v: Calc.KBFilterValue) -> some View {
        let on = isSelected(v)
        return Button {
            select(v)
        } label: {
            HStack(spacing: 10) {
                Text(verbatim: v.key)
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: v.countText)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink3)
                    .lineLimit(1)
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.teal)
                    .opacity(on ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(on ? .isSelected : [])
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
