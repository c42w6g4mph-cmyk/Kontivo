import SwiftUI
import KontivoCore

/// Tab «Verträge» (Web v224): Titelzeile mit Plus, Summe «Fixkosten pro Monat» in Serif, Suche mit Filter/Sortierung als Symbol,
/// Gruppen als eine gerundete Fläche (auch ohne Überschrift) mit Trennlinien über die ganze Breite, Archiv, Leerseite.
/// Masse aus den berechneten Styles der Web-App (Viewport 402 pt): Seitenrand 17, Titel 30/600, Summe 50 Serif.
struct ContractsTab: View {
    @Environment(AppModel.self) private var model
    @State private var showFilter = false
    @State private var pauseTarget: CTIDItem?
    @State private var cancelledTarget: CTIDItem?

    var body: some View {
        Group {
            if model.data.contracts.isEmpty {
                CTEmptyContracts()
            } else {
                CTContractsList(showFilter: $showFilter, pauseTarget: $pauseTarget, cancelledTarget: $cancelledTarget)
            }
        }
        // Titelzeile gehört zur Seite (scrollt mit, Web `.top`), keine Navigationsleiste, Mini-Kopfzeile beim Scrollen
        .kTabPage(title: "Verträge")
        .sheet(isPresented: $showFilter) {
            CTFilterSheet()
                .environment(model)
        }
        .sheet(item: $pauseTarget) { t in
            CTPauseSheet(contractID: t.id)
                .environment(model)
        }
        .ctAlreadyCancelledSheet($cancelledTarget)
        #if DEBUG
        .onAppear { CTUITestSeed.applyIfNeeded(model) }
        #endif
    }
}

// MARK: - Masse (Web, berechnet)

enum CTListMetric {
    /// Seitenrand (Web `.wrap` padding 17 = `KMetric.gutter`)
    static let side: CGFloat = KMetric.gutter
    /// Rand bei breiten Fenstern (iPad): Inhalt mittig mit max. Breite
    static func side(for width: CGFloat) -> CGFloat { max(side, (width - KMetric.maxContent) / 2 + side) }
    /// Radius der Gruppenfläche (Design v164: 16)
    static let groupRadius: CGFloat = KMetric.groupRadius
}

extension View {
    /// Zeile ohne Hintergrund, Trennlinie und Mindesthöhe (Liste als freie Seite)
    func ctPlainRow(_ side: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: side, bottom: 0, trailing: side))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    /// Einzeiliger Text mit Zeilenhöhe der Web-App (CSS line-height), Glyphen mittig wie im Browser
    func ctLine(_ h: CGFloat) -> some View {
        frame(minHeight: h)
    }
}

// MARK: - Titelzeile (Web `.top`: min-height 57, padding-top 17, h1 30/600 −0.015em, Plus 40 Messing)

/// Seitentitel mit Plus-Knopf: gemeinsame Titelzeile `KTabHeader` (Bereich design) mit dem Plus-Menü im `KAddButton`-Look.
struct CTPageHeader: View {
    let title: String

    var body: some View {
        KTabHeader(title: title) {
            // Plus-Menü: Vertrag erfassen | Aus Kontoauszug | Einnahme (Bereich import, Import/AddMenu.swift)
            AddMenuButton()
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(KColor.onBrass)
                .tint(KColor.onBrass)
                .frame(width: 40, height: 40)
                .background(Circle().fill(KColor.brassFab))
                .contentShape(Circle())
        }
    }
}

// MARK: - Liste

private struct CTContractsList: View {
    @Environment(AppModel.self) private var model
    @Binding var showFilter: Bool
    @Binding var pauseTarget: CTIDItem?
    @Binding var cancelledTarget: CTIDItem?

    var body: some View {
        let calc = model.calc
        let h = calc.hero(filter: model.costFilter)
        // Web: Hero-Filter zurücksetzen, sobald sein Zähler 0 ist (z.B. letzter pausierter Vertrag fortgesetzt)
        let hero = CTListContent.effectiveHero(model.heroFilter, h)
        let content = CTListContent.build(data: model.data, calc: calc, filter: model.costFilter,
                                          hero: hero, search: model.searchText)
        GeometryReader { geo in
            let side = CTListMetric.side(for: geo.size.width)
            List {
                CTPageHeader(title: "Verträge").ctPlainRow(side)
                CTHeroView(width: geo.size.width - 2 * side).ctPlainRow(side)
                CTListControls(showFilter: $showFilter).ctPlainRow(side)
                if !content.tags.isEmpty {
                    CTFilterTagBar(tags: content.tags)
                        .padding(.top, 10)
                        .ctPlainRow(side)
                }
                if content.groups.isEmpty {
                    CTNoHitsView(content: content).ctPlainRow(side)
                }
                ForEach(Array(content.groups.enumerated()), id: \.element.id) { gi, g in
                    // Web `.grp`: padding 20 0 2; Kopf 12 px, Abstand 6 darunter
                    CTGroupHeader(title: g.title, sum: g.sum)
                        .padding(.top, gi == 0 ? 20 : 22)
                        .ctPlainRow(side)
                    ForEach(Array(g.contracts.enumerated()), id: \.element.id) { i, c in
                        row(c, mode: g.mode, first: i == 0, last: i == g.contracts.count - 1, side: side)
                    }
                }
                if !content.archive.isEmpty {
                    archiveRows(content.archive, side: side, afterGroups: !content.groups.isEmpty)
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
        .onAppear { syncHero(h) }
        .onChange(of: h) { _, new in syncHero(new) }
    }

    /// Ungültigen Hero-Filter auch im Modell entfernen (damit das Tag verschwindet)
    private func syncHero(_ h: Calc.Hero) {
        let e = CTListContent.effectiveHero(model.heroFilter, h)
        if e != model.heroFilter { model.heroFilter = e }
    }

    private func row(_ c: Contract, mode: CTCardMode, first: Bool, last: Bool, side: CGFloat) -> some View {
        Button {
            model.present(.contractDetail(c.id))
        } label: {
            ContractCardRow(contract: c, mode: mode)
        }
        .buttonStyle(CTCardButtonStyle())
        .listRowInsets(EdgeInsets(top: 0, leading: side, bottom: 0, trailing: side))
        .listRowSeparator(.hidden)
        .listRowBackground(CTGroupSurface(first: first, last: last).padding(.horizontal, side))
        .modifier(CTCardActions(contract: c, pauseTarget: $pauseTarget, cancelledTarget: $cancelledTarget))
    }

    @ViewBuilder
    private func archiveRows(_ list: [Contract], side: CGFloat, afterGroups: Bool) -> some View {
        let open = model.showArchive
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { model.showArchive.toggle() }
        } label: {
            CTArchiveToggle(count: list.count, open: open)
        }
        .buttonStyle(.plain)
        .padding(.top, afterGroups ? 26 : 24)
        .ctPlainRow(side)
        .accessibilityHint(open ? "Zuklappen" : "Aufklappen")
        if open {
            Color.clear.frame(height: 8).ctPlainRow(side)
            ForEach(Array(list.enumerated()), id: \.element.id) { i, c in
                row(c, mode: .list, first: i == 0, last: i == list.count - 1, side: side)
            }
        }
    }
}

/// Fläche einer Karte in der Gruppe: oben/unten gerundet (16), Trennlinie 1 pt über die ganze Breite (Web v183)
struct CTGroupSurface: View {
    let first: Bool
    let last: Bool

    var body: some View {
        let r = CTListMetric.groupRadius
        UnevenRoundedRectangle(topLeadingRadius: first ? r : 0, bottomLeadingRadius: last ? r : 0,
                               bottomTrailingRadius: last ? r : 0, topTrailingRadius: first ? r : 0, style: .continuous)
            .fill(KColor.surface)
            .overlay(alignment: .top) {
                if !first { Rectangle().fill(KColor.line).frame(height: 1) }
            }
    }
}

/// Karte ohne Hervorhebung des Systems; gedrückt leicht abgedunkelt (Web :active)
struct CTCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Archiv-Knopf (Web `.archtoggle`)

private struct CTArchiveToggle: View {
    let count: Int
    let open: Bool

    var body: some View {
        HStack(alignment: .center) {
            Text("Archiv")
                .font(.system(size: 14))
                .foregroundStyle(KColor.ink)
                .ctLine(20.3)
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                Text("\(count)" + (count == 1 ? " beendeter Vertrag" : " beendete Verträge"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                CTChevron(up: open)
                    .stroke(KColor.ink3, style: StrokeStyle(lineWidth: 1.6, lineCap: .square))
                    .frame(width: 9.9, height: 4.95)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Winkel «v» (Web: Rahmen rechts/unten eines 7×7-Quadrats, um 45° gedreht)
struct CTChevron: Shape {
    var up = false
    func path(in r: CGRect) -> Path {
        var p = Path()
        if up {
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        }
        return p
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

    /// Hero-Filter nur, solange sein Zähler > 0 ist (Web renderHero, Kern `Calc.effectiveHeroStatus`)
    static func effectiveHero(_ hero: HeroFilter?, _ h: Calc.Hero) -> HeroFilter? {
        let s = Calc.effectiveHeroStatus(hero.flatMap { Calc.HeroStatus(rawValue: $0.rawValue) },
                                         active: h.activeCount, paused: h.pausedCount, future: h.futureCount)
        return s.flatMap { HeroFilter(rawValue: $0.rawValue) }
    }

    static func heroLabel(_ h: HeroFilter) -> String {
        switch h {
        case .future: return "Noch nicht aktiv"
        case .paused: return "Pausiert"
        case .active: return "Aktiv"
        }
    }

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

        // Leiste aktiver Filter; Text «Für «Pausiert · Versicherung» …» wie Web (Hero zuerst)
        var labels: [String] = []
        if let h = hero {
            let t = heroLabel(h)
            out.tags.append(CTFilterTag(kind: .hero, text: t))
            labels.append(t)
        }
        var fl: [String] = []
        if let k = filter.category {
            out.tags.append(CTFilterTag(kind: .category, text: k))
            fl.append(k)
        }
        if let k = filter.partner {
            out.tags.append(CTFilterTag(kind: .partner, text: k))
            fl.append(k)
        }
        if let p = filter.person {
            let n = data.person(p)?.name ?? "?"
            out.tags.append(CTFilterTag(kind: .person, text: n))
            fl.append(n)
        }
        if !fl.isEmpty { labels.append(fl.joined(separator: " · ")) }
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
        /// Web `group(title, list)`: Summe wie oben (ohne pausierte, noch nicht aktive, laufende Probeabos);
        /// erst ab 2 Verträgen (v183); nur pausierte/noch nicht aktive: Zustand statt «0.00 CHF/Mt.»
        func defaultSum(_ list: [Contract]) -> String {
            let s = list.reduce(0.0) { $0 + (calc.countsMonthly($1) ? (cost[$1.id] ?? 0) : 0) }
            if s < 0.005 && !list.isEmpty {
                if list.allSatisfy({ calc.isPaused($0) }) { return "pausiert" }
                if list.allSatisfy({ calc.notStarted($0) }) { return "noch nicht aktiv" }
                if list.allSatisfy({ calc.isPaused($0) || calc.notStarted($0) }) { return "pausiert / noch nicht aktiv" }
            }
            if list.count < 2 { return "" }
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
                // Schlüssel in der Reihenfolge der Inhaber-Liste (A & B = B & A)
                let names = data.persons.filter { c.holderIDs.contains($0.id) }.map(\.name)
                let k = names.isEmpty ? "Ohne Person" : names.joined(separator: " & ")
                if by[k] == nil { order.append(k) }
                by[k, default: []].append(c)
            }
            let de = Locale(identifier: "de_CH")
            let none = "Ohne Person"
            // «Ohne Person» am Ende, sonst alphabetisch
            for k in order.ctStableSorted(by: { x, y in
                if (x == none) != (y == none) { return y == none }
                return x.compare(y, locale: de) == .orderedAscending
            }) {
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

// MARK: - Summe oben (Web v189 `renderHero`)

private struct CTHeroView: View {
    @Environment(AppModel.self) private var model
    /// Inhaltsbreite (Web `.big`: clamp(42px, 12.5vw, 50px))
    let width: CGFloat

    var body: some View {
        let calc = model.calc
        let h = calc.hero(filter: model.costFilter)
        let hf = CTListContent.effectiveHero(model.heroFilter, h)
        // Summe, Beschriftung und Unterzeile je Status-Filter (Web v189, Kern `Calc.hero(filter:status:)`)
        let t = calc.hero(filter: model.costFilter, status: hf.flatMap { Calc.HeroStatus(rawValue: $0.rawValue) })
        let big = min(50, max(42, (width + 2 * CTListMetric.side) * 0.125))
        VStack(alignment: .leading, spacing: 0) {
            Text(t.label)
                .font(.system(size: 13))
                .foregroundStyle(KColor.ink2)
                .ctLine(18.85)
                .padding(.bottom, 8)
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(Format.money(t.monthlyTotal))
                    .font(KFont.serif(big, .medium))
                    .tracking(-0.01 * big)
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityIdentifier("hero.sum")
                Text(model.data.settings.homeCurrency.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KColor.ink2)
            }
            .frame(height: 50)
            .accessibilityElement(children: .combine)
            Text(t.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(KColor.ink2)
                .monospacedDigit()
                .lineSpacing(3.6)
                .padding(.top, 6)
                .frame(minHeight: 20.3 + 6, alignment: .bottom)
            if h.showsChips {
                CTFlowLayout(spacing: 6, lineSpacing: 6) {
                    chip(h.activeCount, " aktiv ›", .active)
                    if h.pausedCount > 0 { chip(h.pausedCount, " pausiert ›", .paused) }
                    if h.futureCount > 0 { chip(h.futureCount, " noch nicht aktiv ›", .future) }
                }
                .padding(.top, 11)
            } else {
                Color.clear.frame(height: 11)
            }
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Web `.hchip.act`: 13 px, Innenabstand 6/11, Radius 10 (v164), Messing 11 % bzw. gefüllt
    private func chip(_ n: Int, _ text: String, _ f: HeroFilter) -> some View {
        let on = model.heroFilter == f
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                model.heroFilter = on ? nil : f
            }
        } label: {
            (Text("\(n)").fontWeight(.semibold) + Text(text))
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

// MARK: - Suche, Filter- und Sortierknopf (Web `.searchrow`: 38 hoch, Abstand 6, Knöpfe nur Symbol 42 × 38)

private struct CTListControls: View {
    @Environment(AppModel.self) private var model
    @Binding var showFilter: Bool
    @FocusState private var focused: Bool
    @State private var showSort = false

    var body: some View {
        @Bindable var model = model
        let n = model.costFilter.count
        let sort = model.data.settings.sort
        HStack(alignment: .top, spacing: 6) {
            // Suchfeld: 42 hoch mit Rahmen (ragt 4 pt unter die Knöpfe, wie im Web), Radius 12
            HStack(spacing: 0) {
                CTIcon.search(17)
                    .foregroundStyle(KColor.ink3)
                    .padding(.leading, 12)
                    .padding(.trailing, 7)
                TextField("", text: $model.searchText, prompt: Text("Suchen").foregroundColor(KColor.ink3))
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($focused)
                    .accessibilityLabel("Verträge durchsuchen")
                    .accessibilityIdentifier("contracts.search")
                if !model.searchText.isEmpty {
                    Button {
                        model.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(KColor.ink3)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Suche löschen")
                    .padding(.leading, 6)
                }
                Spacer(minLength: 12)
            }
            .frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(focused ? KColor.ink2 : KColor.line, lineWidth: 1))
            .frame(height: 38, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            Button {
                showFilter = true
            } label: {
                // Web: aktiver Filter färbt den Knopf (Symbol weiss auf Fläche); hier Symbol in Messing, damit es sichtbar bleibt
                CTIcon.filter(16)
                    .foregroundStyle(n > 0 ? KColor.teal : KColor.ink2)
                    .frame(width: 42, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
                    .overlay(alignment: .topTrailing) {
                        if n > 0 {
                            Circle().fill(KColor.brassFab).frame(width: 7, height: 7).offset(x: -8, y: 8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filter" + (n > 0 ? ", \(n) aktiv" : ""))
            .accessibilityIdentifier("contracts.filter")

            // Web: Auswahlblatt «Sortieren nach» (openPick("sort"))
            Button {
                showSort = true
            } label: {
                CTIcon.sort(16)
                    .foregroundStyle(KColor.ink2)
                    .frame(width: 42, height: 38)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sortierung ändern, sortiert nach " + sort.shortLabel)
        }
        .frame(height: 38, alignment: .top)
        .padding(.top, 14)
        .sheet(isPresented: $showSort) {
            CTSortSheet()
                .environment(model)
        }
    }
}

// MARK: - Aktive Filter (Web `.ftag`: 12.5/600, Innenabstand 6 8 6 12, Messing 12 %)

private struct CTFilterTagBar: View {
    @Environment(AppModel.self) private var model
    let tags: [CTFilterTag]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags) { t in
                    Button {
                        remove(t)
                    } label: {
                        HStack(spacing: 6) {
                            // Web max-width 170 (inkl. Innenabstand und ×)
                            Text(t.text).lineLimit(1).truncationMode(.tail)
                                .font(.system(size: 12.5, weight: .semibold))
                                .frame(maxWidth: 170 - 20 - 16, alignment: .leading)
                            Text("×").font(.system(size: 16, weight: .semibold))
                        }
                        .ctLine(18.1)
                        .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 6)
                        .foregroundStyle(KColor.teal)
                        .background(Capsule().fill(KColor.teal.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.kind == .hero ? "Filter entfernen" : "Filter \(t.text) entfernen")
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
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

// MARK: - Gruppenkopf (Web `.grphead`: 12 px, Titel 600 Tinte, Summe Tinte 2; ohne Titel nur Abstand)

private struct CTGroupHeader: View {
    let title: String?
    let sum: String?

    var body: some View {
        if let title {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                Spacer(minLength: 8)
                if let s = sum, !s.isEmpty {
                    Text(s)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(KColor.ink2)
                }
            }
            .ctLine(17.4)
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        } else {
            Color.clear.frame(height: 0)
        }
    }
}

// MARK: - Keine Treffer / Keine laufenden Verträge (Web `.empty`: 46 6, 14 px, Titel 16/600)

private struct CTNoHitsView: View {
    let content: CTListContent

    var body: some View {
        let (title, text): (String, String) = {
            if !content.query.isEmpty {
                return ("Keine Treffer", "Für «" + content.query + "» gibt es keinen aktiven Vertrag.")
            } else if !content.filterLabel.isEmpty {
                return ("Keine Treffer", "Für «" + content.filterLabel + "» gibt es keinen aktiven Vertrag.")
            }
            // Keine Suche, kein Filter, keine aktiven Verträge: alle liegen im Archiv
            return ("Keine laufenden Verträge",
                    "Alle Verträge sind gekündigt oder abgelaufen und liegen im Archiv. Tippe oben auf + für einen neuen Vertrag.")
        }()
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(KColor.ink)
            Text(text).font(.system(size: 14)).foregroundStyle(KColor.ink2).lineSpacing(5.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 46).padding(.horizontal, 6)
    }
}

// MARK: - Leerseite (emptyList)

private struct CTEmptyContracts: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    CTPageHeader(title: "Verträge")
                        .padding(.horizontal, CTListMetric.side(for: geo.size.width))
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
                    .padding(.bottom, 32)
                    .kContentWidth()
                }
            }
        }
        .kPageBackground()
    }

    /// Web `.espriv` (12.5 pt `--ink2`, Schild 16 pt grün, Abstand 7, max. 36ch, 12 über) und `.eslink` (15 pt Medium Messing)
    private var footer: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                KIcon.view("ic.shield", 16)
                    .foregroundStyle(KColor.ok)
                    .accessibilityHidden(true)
                Text("Ohne Bankanbindung. Deine Daten bleiben auf deinem Gerät.")
                    .font(KFont.text(12.5))
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.leading)
                    .kLineHeight(12.5, 16.875)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 284)
            .padding(.top, 12)
            Button("Ich habe ein Backup") {
                MoreRequests.openBackupImport(model)
            }
            .buttonStyle(.plain)
            .font(KFont.text(15, .medium))
            .foregroundStyle(KColor.teal)
            .padding(.vertical, 4).padding(.horizontal, 8)
            .padding(.top, 12)
        }
    }
}
