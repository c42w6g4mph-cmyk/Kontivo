import SwiftUI
import KontivoCore

/// Auswahl «Filter» (openFilterSheet): Kategorie, Vertragspartner, Inhaber – gemeinsam mit «Kosten» (model.costFilter).
struct CTFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let f = model.costFilter
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: Calc.FilterDimension.category) {
                        row("Kategorie", f.category ?? "Alle")
                    }
                    NavigationLink(value: Calc.FilterDimension.partner) {
                        row("Vertragspartner", f.partner ?? "Alle")
                    }
                    NavigationLink(value: Calc.FilterDimension.holder) {
                        row("Person", f.person.flatMap { model.data.person($0)?.name } ?? "Alle")
                    }
                }
                .listRowBackground(KColor.surface)
                if f.count > 0 {
                    Section {
                        Button("Alle Filter zurücksetzen") {
                            model.costFilter = Calc.CostFilter()
                            dismiss()
                        }
                        .foregroundStyle(KColor.alert)
                    }
                    .listRowBackground(KColor.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper)
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Calc.FilterDimension.self) { dim in
                CTFilterValues(dim: dim) { dismiss() }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { CloseButton() }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(KColor.ink)
            Spacer()
            Text(value)
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
        }
    }
}

/// Ein Filterwert mit Anzahl aktiver Verträge
struct CTFilterEntry: Identifiable, Hashable {
    /// Kategorie-/Vertragspartner-Schlüssel (statKey) bzw. Personen-ID
    var key: String
    var title: String
    var active: Int
    var id: String { key }
}

/// Werteliste einer Filterdimension (openPick(cat|partner|holder))
struct CTFilterValues: View {
    @Environment(AppModel.self) private var model
    let dim: Calc.FilterDimension
    let onDone: () -> Void

    var body: some View {
        let entries = CTFilterValues.entries(dim, data: model.data, calc: model.calc)
        let cur = currentKey
        List {
            Section {
                Button {
                    select(nil)
                } label: {
                    HStack {
                        Text(allTitle).foregroundStyle(KColor.ink)
                        Spacer()
                        if cur == nil { Image(systemName: "checkmark").foregroundStyle(KColor.teal) }
                    }
                }
                ForEach(entries) { e in
                    Button {
                        select(e.key)
                    } label: {
                        HStack(spacing: 8) {
                            Text(e.title)
                                .foregroundStyle(KColor.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(e.active > 0 ? "\(e.active)" + (e.active == 1 ? " aktiver Vertrag" : " aktive Verträge") : "nur beendete")
                                .font(.subheadline)
                                .foregroundStyle(KColor.ink2)
                            if cur == e.key { Image(systemName: "checkmark").foregroundStyle(KColor.teal) }
                        }
                    }
                    .contextMenu {
                        Button {
                            select(e.key)
                        } label: {
                            Label("Auswählen", systemImage: "line.3.horizontal.decrease")
                        }
                    } preview: {
                        CTFilterPopup(dim: dim, entry: e)
                            .environment(model)
                    }
                }
            } footer: {
                if !entries.isEmpty {
                    Text("Lange drücken zeigt die Beträge")
                }
            }
            .listRowBackground(KColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(KColor.paper)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
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

    private var currentKey: String? {
        switch dim {
        case .category: return model.costFilter.category
        case .partner: return model.costFilter.partner
        case .holder: return model.costFilter.person?.uuidString
        }
    }

    private func select(_ key: String?) {
        switch dim {
        case .category: model.costFilter.category = key
        case .partner: model.costFilter.partner = key
        case .holder: model.costFilter.person = key.flatMap { UUID(uuidString: $0) }
        }
        onDone()
    }

    /// Alle Werte aus allen Verträgen (auch archivierten), mit Anzahl aktiver Verträge.
    static func entries(_ dim: Calc.FilterDimension, data: AppData, calc: Calc) -> [CTFilterEntry] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var act: [String: Int] = [:]
        for c in data.contracts {
            let on = c.status != .cancelled && !calc.isEnded(c)
            var ks: [(String, String)] = []
            if dim == .holder {
                for h in c.holderIDs {
                    if let p = data.person(h) { ks.append((h.uuidString, p.name)) }
                }
            } else {
                let k = calc.statKey(c, dim)
                ks.append((k, k))
            }
            for (k, t) in ks where !k.isEmpty {
                if titles[k] == nil {
                    order.append(k)
                    titles[k] = t
                }
                if on { act[k, default: 0] += 1 }
            }
        }
        var list = order.map { CTFilterEntry(key: $0, title: titles[$0] ?? $0, active: act[$0] ?? 0) }
        if dim == .category {
            let names = data.categories.map { $0.name }
            list = list.ctStableSorted { a, b in
                (names.firstIndex(of: a.key) ?? 99) < (names.firstIndex(of: b.key) ?? 99)
            }
        } else {
            list = list.ctStableSorted { Format.lessDE($0.title, $1.title) }
        }
        return list
    }
}

/// Pop-up bei langem Drücken: aktive Verträge des Werts mit Monatsbeträgen (showLpop)
private struct CTFilterPopup: View {
    @Environment(AppModel.self) private var model
    let dim: Calc.FilterDimension
    let entry: CTFilterEntry

    var body: some View {
        let data = model.data
        let calc = model.calc
        let home = data.settings.homeCurrency.rawValue
        let person = dim == .holder ? UUID(uuidString: entry.key) : nil
        let all = data.contracts.filter { c in
            if dim == .holder { return person.map { c.holderIDs.contains($0) } ?? false }
            return calc.statKey(c, dim) == entry.key
        }
        let act = all.filter { $0.status != .cancelled && !calc.isEnded($0) }
            .ctStableSorted { calc.monthlyCost($0) > calc.monthlyCost($1) }
        let nOld = all.count - act.count
        let sum = act.reduce(0.0) { s, c in
            calc.isPaused(c) ? s : s + calc.monthlyCost(c) * (dim == .holder ? calc.holderShare(c, person: person) : 1)
        }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.title).font(.headline).foregroundStyle(KColor.ink).lineLimit(1)
                Spacer()
                Text(home + "/Mt.").font(.footnote).foregroundStyle(KColor.ink2)
            }
            if act.isEmpty {
                Text("Keine aktiven Verträge.").font(.subheadline).foregroundStyle(KColor.ink2)
            } else {
                ForEach(act) { c in
                    let f = dim == .holder ? calc.holderShare(c, person: person) : 1
                    let off = calc.isPaused(c)
                    HStack(spacing: 10) {
                        MarkView(contract: c, data: data, size: 28)
                        Text(data.title(of: c) + (f < 1 ? " · " + Format.shareText(f) : "") + (off ? " · pausiert" : ""))
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(Format.money(calc.monthlyCost(c) * f))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(off ? KColor.ink3 : KColor.ink)
                    .opacity(off ? 0.7 : 1)
                }
                Divider()
                HStack {
                    Text("Total pro Monat").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(Format.money(sum) + " " + home).font(.subheadline.weight(.bold)).monospacedDigit()
                }
                .foregroundStyle(KColor.ink)
            }
            if nOld > 0 {
                Text("\(nOld)" + (nOld == 1 ? " beendeter Vertrag" : " beendete Verträge") + " nicht mitgezählt")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
            }
        }
        .padding(16)
        .frame(width: 330)
        .background(KColor.surface)
    }
}
