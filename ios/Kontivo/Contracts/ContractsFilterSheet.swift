import SwiftUI
import KontivoCore

/// Auswahl «Filter» (Web `openFilterSheet` im Auswahlblatt): Kategorie, Vertragspartner, Person – gemeinsam mit «Kosten»
/// (model.costFilter). Antippen zeigt im selben Blatt die Werte (Web `openPick(dim)`).
struct CTFilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var dim: Calc.FilterDimension?

    var body: some View {
        let f = model.costFilter
        Group {
            if let d = dim {
                CTPickSheet(title: CTFilterValues.title(d)) {
                    CTFilterValues(dim: d) { dismiss() }
                }
            } else {
                CTPickSheet(title: "Filter") {
                    VStack(spacing: 6) {
                        CTPickRow(title: "Kategorie", detail: (f.category ?? "Alle") + " ›") { dim = .category }
                        CTPickRow(title: "Vertragspartner", detail: (f.partner ?? "Alle") + " ›") { dim = .partner }
                        CTPickRow(title: "Person", detail: (f.person.flatMap { model.data.person($0)?.name } ?? "Alle") + " ›") { dim = .holder }
                        if f.count > 0 {
                            Button {
                                model.costFilter = Calc.CostFilter()
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
        VStack(alignment: .leading, spacing: 6) {
            CTPickRow(title: allTitle, selected: cur == nil) { select(nil) }
            ForEach(entries) { e in
                CTPickRow(title: e.title,
                          detail: e.active > 0 ? "\(e.active)" + (e.active == 1 ? " aktiver Vertrag" : " aktive Verträge") : "nur beendete",
                          selected: cur == e.key) { select(e.key) }
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
            if !entries.isEmpty {
                Text("Lange drücken zeigt die Beträge")
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
            }
        }
    }

    static func title(_ dim: Calc.FilterDimension) -> String {
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
        // laufendes Probeabo zählt (noch) nicht (Web v157)
        let sum = act.reduce(0.0) { s, c in
            (calc.isPaused(c) || calc.trialOn(c)) ? s : s + calc.monthlyCost(c) * (dim == .holder ? calc.holderShare(c, person: person) : 1)
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
                    let off = calc.isPaused(c) || calc.trialOn(c)
                    HStack(spacing: 10) {
                        MarkView(contract: c, data: data, size: 28)
                        Text(data.title(of: c) + (f < 1 ? " · " + Format.shareText(f) : "") + (off ? (calc.isPaused(c) ? " · pausiert" : " · Probeabo") : ""))
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
