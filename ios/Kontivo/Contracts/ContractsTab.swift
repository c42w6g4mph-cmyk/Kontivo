import SwiftUI
import KontivoCore

/// Tab «Verträge»: Kopf mit Monatssumme, Suche, Filter, Sortierung mit Gruppen, Archiv, Leerseite.
struct ContractsTab: View {
    @Environment(AppModel.self) private var model
    @State private var showFilter = false
    @State private var pauseTarget: CTIDItem?

    var body: some View {
        @Bindable var model = model
        Group {
            if model.data.contracts.isEmpty {
                CTEmptyContracts()
            } else {
                CTContractsList(showFilter: $showFilter, pauseTarget: $pauseTarget)
                    .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Suchen")
            }
        }
        .navigationTitle("Verträge")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.present(.contractForm(.new(prefill: nil)))
                } label: {
                    Image(systemName: "plus")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel("Vertrag anlegen")
            }
        }
        .sheet(isPresented: $showFilter) {
            CTFilterSheet()
                .environment(model)
        }
        .sheet(item: $pauseTarget) { t in
            CTPauseSheet(contractID: t.id)
                .environment(model)
        }
    }
}

// MARK: - Liste

private struct CTContractsList: View {
    @Environment(AppModel.self) private var model
    @Binding var showFilter: Bool
    @Binding var pauseTarget: CTIDItem?

    var body: some View {
        let content = CTListContent.build(data: model.data, calc: model.calc, filter: model.costFilter,
                                          hero: model.heroFilter, search: model.searchText)
        GeometryReader { geo in
            List {
                topSection(content)
                if content.groups.isEmpty {
                    Section {
                        CTNoHitsView(content: content)
                            .listRowBackground(Color.clear)
                    }
                }
                ForEach(content.groups) { g in
                    Section {
                        ForEach(g.contracts) { c in
                            row(c, mode: g.mode)
                        }
                    } header: {
                        if let t = g.title {
                            CTGroupHeader(title: t, sum: g.sum)
                        }
                    }
                }
                if !content.archive.isEmpty {
                    archiveSection(content.archive)
                }
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .scrollContentBackground(.hidden)
            .contentMargins(.horizontal, max(0, (geo.size.width - KMetric.maxContent) / 2), for: .scrollContent)
        }
        .kPageBackground()
    }

    @ViewBuilder
    private func topSection(_ content: CTListContent) -> some View {
        Section {
            CTHeroView()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 8, trailing: 4))
                .listRowSeparator(.hidden)
            CTListControls(showFilter: $showFilter)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                .listRowSeparator(.hidden)
            if !content.tags.isEmpty {
                CTFilterTagBar(tags: content.tags)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 4, trailing: 4))
                    .listRowSeparator(.hidden)
            }
        }
    }

    private func row(_ c: Contract, mode: CTCardMode) -> some View {
        Button {
            model.present(.contractDetail(c.id))
        } label: {
            ContractCardRow(contract: c, mode: mode)
        }
        .listRowBackground(KColor.surface)
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 14))
        .modifier(CTCardActions(contract: c, pauseTarget: $pauseTarget))
    }

    @ViewBuilder
    private func archiveSection(_ list: [Contract]) -> some View {
        let open = model.showArchive
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { model.showArchive.toggle() }
            } label: {
                HStack {
                    Text("Archiv")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KColor.ink)
                    Spacer()
                    Text("\(list.count)" + (list.count == 1 ? " beendeter Vertrag" : " beendete Verträge"))
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .listRowBackground(KColor.surface)
            .accessibilityHint(open ? "Zuklappen" : "Aufklappen")
            if open {
                ForEach(list) { c in
                    row(c, mode: .list)
                }
            }
        }
    }
}

// MARK: - Inhalt berechnen (renderView, tab list)

struct CTGroup: Identifiable {
    var id: String
    var title: String?
    var sum: String?
    var mode: CTCardMode
    var contracts: [Contract]
}

struct CTFilterTag: Identifiable, Hashable {
    enum Kind: Hashable { case hero, category, partner, person }
    var kind: Kind
    var text: String
    var id: String { "\(kind)-\(text)" }
}

struct CTListContent {
    var groups: [CTGroup] = []
    var archive: [Contract] = []
    var tags: [CTFilterTag] = []
    /// Suchtext (getrimmt), wenn gesucht wird
    var query = ""
    /// Filtertext «Kategorie · Vertragspartner · Person»
    var filterLabel = ""

    static func build(data: AppData, calc: Calc, filter: Calc.CostFilter, hero: HeroFilter?, search: String) -> CTListContent {
        var out = CTListContent()
        let qRaw = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let q = qRaw.lowercased()
        out.query = qRaw
        func matchesSearch(_ c: Contract) -> Bool {
            if q.isEmpty { return true }
            let hay = [c.label, data.partnerName(of: c), data.category(c.categoryID)?.name ?? "",
                       data.holderNames(of: c).joined(separator: " "), c.customerNo, c.contractNo, c.note]
                .joined(separator: " ").lowercased()
            return hay.contains(q)
        }
        var a = calc.active.filter(matchesSearch)
        let fc = filter.count
        if fc > 0 { a = a.filter { calc.matches($0, filter) } }
        switch hero {
        case .future: a = a.filter { calc.notStarted($0) }
        case .paused: a = a.filter { calc.isPaused($0) }
        case .active: a = a.filter { !calc.notStarted($0) && !calc.isPaused($0) }
        case nil: break
        }
        var arc = calc.archived.filter(matchesSearch)
        if fc > 0 { arc = arc.filter { calc.matches($0, filter) } }
        out.archive = arc

        // Leiste aktiver Filter
        if let h = hero {
            let t: String
            switch h {
            case .future: t = "Noch nicht aktiv"
            case .paused: t = "Pausiert"
            case .active: t = "Aktiv"
            }
            out.tags.append(CTFilterTag(kind: .hero, text: t))
        }
        var labels: [String] = []
        if let k = filter.category {
            out.tags.append(CTFilterTag(kind: .category, text: k))
            labels.append(k)
        }
        if let k = filter.partner {
            out.tags.append(CTFilterTag(kind: .partner, text: k))
            labels.append(k)
        }
        if let p = filter.person {
            let n = data.person(p)?.name ?? "?"
            out.tags.append(CTFilterTag(kind: .person, text: n))
            labels.append(n)
        }
        out.filterLabel = labels.joined(separator: " · ")

        if a.isEmpty { return out }
        out.groups = groups(a, data: data, calc: calc)
        return out
    }

    private static func groups(_ a: [Contract], data: AppData, calc: Calc) -> [CTGroup] {
        let home = data.settings.homeCurrency.rawValue
        var cost: [UUID: Double] = [:]
        for c in a { cost[c.id] = calc.monthlyCost(c) }
        let byCost: (Contract, Contract) -> Bool = { (cost[$0.id] ?? 0) > (cost[$1.id] ?? 0) }
        func defaultSum(_ list: [Contract]) -> String {
            let s = list.reduce(0.0) { $0 + (calc.isPaused($1) ? 0 : (cost[$1.id] ?? 0)) }
            return Format.money(s) + " " + home + "/Mt."
        }
        var out: [CTGroup] = []
        switch data.settings.sort {
        case .cost:
            out.append(CTGroup(id: "cost", title: nil, sum: nil, mode: .cost, contracts: a.ctStableSorted(by: byCost)))

        case .partner:
            let sorted = a.ctStableSorted { Format.lessDE(data.partnerName(of: $0), data.partnerName(of: $1)) }
            var order: [String] = []
            var by: [String: [Contract]] = [:]
            for c in sorted {
                let pn = data.partnerName(of: c).trimmingCharacters(in: .whitespaces)
                let L = pn.first.map { String($0).uppercased() } ?? "#"
                if by[L] == nil { order.append(L) }
                by[L, default: []].append(c)
            }
            for L in order {
                out.append(CTGroup(id: "p-" + L, title: L, sum: nil, mode: .list, contracts: by[L] ?? []))
            }

        case .due:
            var nd: [UUID: Day] = [:]
            for c in a { if let d = calc.nextDue(c) { nd[c.id] = d } }
            let withD = a.filter { nd[$0.id] != nil }.ctStableSorted { nd[$0.id]! < nd[$1.id]! }
            var order: [String] = []
            var by: [String: [Contract]] = [:]
            for c in withD {
                let k = Format.monthYear(nd[c.id]!)
                if by[k] == nil { order.append(k) }
                by[k, default: []].append(c)
            }
            for k in order {
                let list = by[k] ?? []
                let s = list.reduce(0.0) { $0 + calc.conv(calc.priceAt($1, nd[$1.id]!), $1.currency) }
                out.append(CTGroup(id: "d-" + k, title: k, sum: Format.money(s) + " " + home, mode: .pay, contracts: list))
            }
            let noD = a.filter { nd[$0.id] == nil }
            if !noD.isEmpty {
                out.append(CTGroup(id: "d-none", title: "Ohne Zahlungstermin", sum: defaultSum(noD), mode: .list, contracts: noD))
            }

        case .holder:
            var order: [String] = []
            var by: [String: [Contract]] = [:]
            for c in a.ctStableSorted(by: byCost) {
                let names = data.holderNames(of: c)
                let k = names.isEmpty ? "Ohne Inhaber" : names.joined(separator: " & ")
                if by[k] == nil { order.append(k) }
                by[k, default: []].append(c)
            }
            let de = Locale(identifier: "de_CH")
            for k in order.ctStableSorted(by: { $0.compare($1, locale: de) == .orderedAscending }) {
                let list = by[k] ?? []
                out.append(CTGroup(id: "h-" + k, title: k, sum: defaultSum(list), mode: .list, contracts: list))
            }

        case .category:
            var order: [String] = []
            var by: [String: [Contract]] = [:]
            for c in a {
                let n = data.category(c.categoryID)?.name ?? ""
                let k = n.isEmpty ? "Sonstiges" : n
                if by[k] == nil { order.append(k) }
                by[k, default: []].append(c)
            }
            let names = data.categories.map { $0.name }
            let keys = names + order.filter { !names.contains($0) }
            for k in keys {
                guard let list = by[k] else { continue }
                out.append(CTGroup(id: "c-" + k, title: k, sum: defaultSum(list), mode: .list, contracts: list.ctStableSorted(by: byCost)))
            }
        }
        return out
    }
}

// MARK: - Kopf (Hero)

private struct CTHeroView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let h = model.calc.hero()
        VStack(alignment: .leading, spacing: 4) {
            Text("Aktuelle Fixkosten pro Monat")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KColor.ink2)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Format.money(h.monthlyTotal))
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(model.data.settings.homeCurrency.rawValue)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(KColor.ink2)
            }
            .accessibilityElement(children: .combine)
            Text(h.subtitle)
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
                .monospacedDigit()
            if h.showsChips {
                CTFlowLayout(spacing: 8, lineSpacing: 8) {
                    chip(h.activeCount, " aktiv ›", .active)
                    if h.pausedCount > 0 { chip(h.pausedCount, " pausiert ›", .paused) }
                    if h.futureCount > 0 { chip(h.futureCount, " noch nicht aktiv ›", .future) }
                }
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chip(_ n: Int, _ text: String, _ f: HeroFilter) -> some View {
        let on = model.heroFilter == f
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.heroFilter = on ? nil : f
            }
        } label: {
            (Text("\(n)").bold() + Text(text))
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(on ? Color.white : KColor.teal)
                .background(Capsule().fill(on ? KColor.teal : KColor.teal.opacity(0.11)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Filter- und Sortierknopf

private struct CTListControls: View {
    @Environment(AppModel.self) private var model
    @Binding var showFilter: Bool

    var body: some View {
        let n = model.costFilter.count
        let sort = model.data.settings.sort
        HStack(spacing: 10) {
            Button {
                showFilter = true
            } label: {
                Label("Filter" + (n > 0 ? " · \(n)" : ""), systemImage: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(n > 0 ? .semibold : .regular))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .foregroundStyle(n > 0 ? Color.white : KColor.ink)
                    .background(Capsule().fill(n > 0 ? KColor.teal : KColor.field))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter" + (n > 0 ? ", \(n) aktiv" : ""))
            Spacer(minLength: 4)
            Menu {
                Section("Sortieren nach") {
                    ForEach(ContractSort.pickerOrder, id: \.self) { s in
                        Button {
                            if s != sort { model.update { $0.settings.sort = s } }
                        } label: {
                            if s == sort {
                                Label(s.optionLabel, systemImage: "checkmark")
                            } else {
                                Text(s.optionLabel)
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.arrow.down")
                    (Text("Sortiert ").foregroundStyle(KColor.ink2) + Text(sort.shortLabel).bold())
                }
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(KColor.ink)
                .background(Capsule().fill(KColor.field))
            }
            .accessibilityLabel("Sortierung ändern, sortiert nach " + sort.shortLabel)
        }
    }
}

// MARK: - Aktive Filter

private struct CTFilterTagBar: View {
    @Environment(AppModel.self) private var model
    let tags: [CTFilterTag]

    var body: some View {
        CTFlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tags) { t in
                Button {
                    remove(t)
                } label: {
                    HStack(spacing: 5) {
                        Text(t.text).lineLimit(1)
                        Image(systemName: "xmark")
                            .font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 11).padding(.vertical, 6)
                    .foregroundStyle(KColor.teal)
                    .background(Capsule().fill(KColor.teal.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t.kind == .hero ? "Filter entfernen" : "Filter \(t.text) entfernen")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func remove(_ t: CTFilterTag) {
        withAnimation(.easeInOut(duration: 0.15)) {
            switch t.kind {
            case .hero: model.heroFilter = nil
            case .category: model.costFilter.category = nil
            case .partner: model.costFilter.partner = nil
            case .person: model.costFilter.person = nil
            }
        }
    }
}

// MARK: - Gruppenkopf

private struct CTGroupHeader: View {
    let title: String
    let sum: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KColor.ink2)
            Spacer()
            if let s = sum {
                Text(s)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(KColor.ink2)
            }
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Keine Treffer / Willkommen

private struct CTNoHitsView: View {
    let content: CTListContent

    var body: some View {
        VStack(spacing: 8) {
            if !content.query.isEmpty {
                Text("Keine Treffer").font(.headline).foregroundStyle(KColor.ink)
                Text("Für «" + content.query + "» gibt es keinen aktiven Vertrag.")
                    .font(.subheadline).foregroundStyle(KColor.ink2)
            } else if !content.filterLabel.isEmpty {
                Text("Keine Treffer").font(.headline).foregroundStyle(KColor.ink)
                Text("Für «" + content.filterLabel + "» gibt es keinen aktiven Vertrag.")
                    .font(.subheadline).foregroundStyle(KColor.ink2)
            } else {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
                Text("Willkommen bei Kontivo").font(.headline).foregroundStyle(KColor.ink)
                Text("Fixkosten, Verträge und Fristen – klar im Griff.\nTippe oben auf + und leg den ersten Vertrag an. Mit «Aus Katalog wählen» geht es am schnellsten.")
                    .font(.subheadline).foregroundStyle(KColor.ink2)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Leerseite (emptyList)

private struct CTEmptyContracts: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            EmptyHero(
                symbol: "doc.text",
                title: "Jeden Vertrag im Griff.\nJede Frist im Blick.",
                text: "Erfasse einen Vertrag, den Rest übernimmt Kontivo.",
                hooks: ["Nie wieder ein Jahr zu viel bezahlen",
                        "Kein Vertrag verlängert sich mehr ungewollt",
                        "Kündigungsschreiben in einer Minute"],
                buttonTitle: "Ersten Vertrag erfassen",
                action: { model.present(.contractForm(.new(prefill: nil))) },
                footer: AnyView(footer)
            )
            .padding(.vertical, 32)
            .kContentWidth()
        }
        .kPageBackground()
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Label {
                Text("Ohne Bankanbindung. Deine Daten bleiben auf deinem Gerät.")
            } icon: {
                Image(systemName: "checkmark.shield")
            }
            .font(.footnote)
            .foregroundStyle(KColor.ink2)
            .multilineTextAlignment(.leading)
            Button("Ich habe ein Backup") {
                model.goTab(.more)
            }
            .font(.subheadline.weight(.semibold))
        }
        .padding(.top, 8)
    }
}
