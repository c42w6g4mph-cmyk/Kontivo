import SwiftUI
import Charts
import KontivoCore

/// Tab «Budget»: Einnahmen − Fixkosten = verfügbar, pro Monat und Person.
struct BudgetTab: View {
    @Environment(AppModel.self) private var model
    /// «Alle n anzeigen» in «Ausgaben» (gilt für alle Monate)
    @State private var showAllExpenses = false

    var body: some View {
        let calc = model.calc
        let persons = model.data.persons
        let bh: UUID? = model.budgetPerson.flatMap { id in persons.contains(where: { $0.id == id }) ? id : nil }
        let incomes = calc.kbBudgetIncomes(person: bh)
        let hasIncomes = !incomes.isEmpty
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                KBBudgetPersonBar(persons: persons, selected: bh)
                if !hasIncomes, let p = model.data.person(bh) {
                    noIncomeForPerson(p)
                } else if !hasIncomes {
                    emptyPage(calc)
                } else {
                    KBBudgetContent(person: bh, incomeCount: incomes.count, showAllExpenses: $showAllExpenses)
                }
            }
            .padding(.horizontal, KMetric.gutter)
            .padding(.bottom, 28)
            .kContentWidth()
        }
        .kPageBackground()
        .navigationTitle("Budget")
        .toolbar {
            if hasIncomes {
                ToolbarItem(placement: .topBarTrailing) { KBYearNav() }
            }
        }
    }

    /// Filter aktiv, aber diese Person hat keine Einnahmen
    private func noIncomeForPerson(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 6) {
                Text(verbatim: "Keine Einnahmen für " + p.name)
                    .font(.headline)
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.center)
                Text("Weise einer Einnahme diese Person als Empfänger zu, dann erscheint hier ihr Budget.")
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            KBListBlock {
                Button {
                    model.present(.incomeForm(nil))
                } label: {
                    Text("+ Einnahme erfassen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KColor.teal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Leerseite budgetEmpty
    private func emptyPage(_ calc: Calc) -> some View {
        EmptyHero(symbol: "wallet.pass",
                  title: "Weisst du, was dir\njeden Monat bleibt?",
                  text: calc.kbBudgetEmptyText(),
                  hooks: ["Lohn rein, Fixkosten raus: der Rest gehört dir",
                          "Was bleibt dir übrig? Sofort sichtbar",
                          "Fair geteilt: wer zahlt wie viel im Haushalt"],
                  buttonTitle: "Einnahme erfassen",
                  action: { model.present(.incomeForm(nil)) })
            .padding(.top, 36)
            .padding(.bottom, 24)
    }
}

// MARK: - Personenfilter

/// Chips «Alle | Name …» (2–4 Personen, passende Namen); sonst Auswahlknopf «Inhaber» mit «×»; bei einer Person nichts.
struct KBBudgetPersonBar: View {
    @Environment(AppModel.self) private var model
    let persons: [Person]
    let selected: UUID?

    var body: some View {
        let namer = KBHolderNamer(names: persons.map { $0.name }, width: 361)
        Group {
            if namer.ok {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { chips(namer) }
                    selectRow(namer)
                }
                .padding(.top, 12)
            } else if persons.count > 1 {
                selectRow(namer)
                    .padding(.top, 12)
            }
        }
    }

    @ViewBuilder
    private func chips(_ namer: KBHolderNamer) -> some View {
        KBPersonChip(title: "Alle", isOn: selected == nil) { model.budgetPerson = nil }
        ForEach(persons) { p in
            KBPersonChip(title: namer.display(p.name), isOn: selected == p.id) { model.budgetPerson = p.id }
        }
    }

    private func selectRow(_ namer: KBHolderNamer) -> some View {
        let name = selected.flatMap { id in persons.first(where: { $0.id == id })?.name } ?? ""
        let binding = Binding<UUID?>(get: { model.budgetPerson }, set: { model.budgetPerson = $0 })
        return HStack(spacing: 6) {
            Menu {
                Picker("Person", selection: binding) {
                    Text("Alle Personen").tag(UUID?.none)
                    ForEach(persons) { p in
                        Text(verbatim: p.name).tag(UUID?.some(p.id))
                    }
                }
                .pickerStyle(.inline)
                Section {
                    Text("Gemeinsame Verträge und Einnahmen zählen anteilig.")
                }
            } label: {
                KBSelectLabel(title: name.isEmpty ? "Person" : namer.display(name), isOn: selected != nil)
            }
            .accessibilityLabel("Person")
            .accessibilityValue(Text(verbatim: name.isEmpty ? "Alle Personen" : name))
            if selected != nil {
                KBClearButton(label: "Filter zurücksetzen") { model.budgetPerson = nil }
            }
        }
    }
}

// MARK: - Inhalt mit Einnahmen

struct KBBudgetContent: View {
    @Environment(AppModel.self) private var model
    let person: UUID?
    let incomeCount: Int
    @Binding var showAllExpenses: Bool

    var body: some View {
        let calc = model.calc
        let year = model.selectedYear
        let month = KBMonthNav.month(model)
        let by = KBYearCache.budgetYear(calc, year: year, person: person)
        let bm = by.months[month - 1]
        VStack(alignment: .leading, spacing: 0) {
            KBBudgetCard(by: by, month: month, person: person)
                .padding(.top, 14)
            if person == nil, let rows = calc.fairShare() { KBFairShareView(rows: rows) }
            KBBudgetIncomeList(year: year, month: month, person: person, incomeCount: incomeCount, monthIncome: bm.income)
            KBBudgetExpenseList(year: year, month: month, person: person, bm: bm, showAll: $showAllExpenses)
        }
    }
}

// MARK: - Karte «Verfügbar»

struct KBBudgetCard: View {
    @Environment(AppModel.self) private var model
    let by: Calc.BudgetYear
    let month: Int
    let person: UUID?

    var body: some View {
        let calc = model.calc
        let home = calc.home.rawValue
        let bm = by.months[month - 1]
        let cmp = KBYearCache.budgetComparison(calc, year: by.year, month: month, person: person, free: bm.free)
        let namer = KBHolderNamer(names: model.data.persons.map { $0.name }, width: 361)
        let pname = model.data.person(person)?.name ?? ""
        KBPagingCard {
            KBCardHeader(year: by.year, month: month, trailing: pname.isEmpty ? "" : namer.display(pname))
            KBBigAmount(value: bm.free, currency: home, alert: bm.free < 0)
            KBBudgetSubline(bm: bm, info: shareInfo(bm, pname: pname))
            if let c = cmp {
                KBCompareLine(text: c.text, arrow: c.trend.kbArrow, color: KBBudgetCard.color(c.trend))
            }
            KBCardRow {
                HStack(alignment: .top) {
                    KBStatCell(label: "Einnahmen", value: Format.money(bm.income), muted: bm.income < 0.005)
                    KBStatCell(label: "Fixkosten", value: Format.money(bm.fixed), trailing: true, muted: bm.fixed < 0.005)
                }
            }
            chartArea(home: home)
            KBCardRow(top: 16) {
                HStack(alignment: .top) {
                    KBStatCell(label: "Ø pro Monat", value: KBBudgetCard.signed0(by.average),
                               valueColor: by.average < 0 ? KColor.warn : nil)
                    KBStatCell(label: "Verfügbar " + String(by.year), value: KBBudgetCard.signed0(by.totalFree), trailing: true,
                               valueColor: by.totalFree < 0 ? KColor.warn : nil)
                }
            }
        }
    }

    /// Einordnung «x % der Einnahmen»: Wert des Monats (auch negativ), dazu Jahresschnitt (Web state._fq)
    private func shareInfo(_ bm: Calc.BudgetMonth, pname: String) -> BudgetShareInfo? {
        guard bm.income > 0.005 else { return nil }
        let q = Int(Format.jsRound(bm.free / bm.income * 100))
        let avg: Int? = by.totalIncome > 0.005 ? Int(Format.jsRound(by.totalFree / by.totalIncome * 100)) : nil
        return BudgetShareInfo(percent: q, average: avg, year: by.year, monthLabel: Format.monthNames[month - 1] + " " + String(by.year),
                               personName: pname, person: person, income: bm.income, free: bm.free)
    }

    /// «verfügbar nach Fixkosten · 23 % der Einnahmen» (auch «−12 %»)
    static func subline(_ bm: Calc.BudgetMonth) -> String {
        var s = "verfügbar nach Fixkosten"
        if bm.income > 0.005 {
            let q = Int(Format.jsRound(bm.free / bm.income * 100))
            s += " · " + BudgetShare.percentText(q).replacingOccurrences(of: "\u{00A0}", with: " ") + " der Einnahmen"
        }
        return s
    }

    /// Ganze Einheiten mit «−» bei negativem Wert
    static func signed0(_ v: Double) -> String {
        (v < 0 ? Format.minus : "") + Format.money0(abs(v))
    }

    /// Farbe invers: mehr verfügbar = Grün, weniger = Warnfarbe
    static func color(_ t: Calc.Trend) -> Color {
        switch t {
        case .up: return KColor.ok
        case .down: return KColor.warn
        case .same: return KColor.ink2
        }
    }

    private func chartArea(home: String) -> some View {
        let frees = by.months.map { $0.free }
        let hasNeg = frees.contains { $0 < 0 }
        let value = Format.monthNames[month - 1] + ": " + Format.money(by.months[month - 1].free) + " " + home
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                KBBudgetChart(months: by.months, selected: month, year: by.year, today: model.today, average: by.average)
                    .frame(height: 140)
                KBMonthLabels(year: by.year, selected: month, today: model.today)
            }
            .contentShape(Rectangle())
            .kbScrubArea()
            .kbMonthAdjustable(model, label: "Verfügbar pro Monat", value: value)
            .padding(.trailing, 16)
            if hasNeg {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(KColor.alert.opacity(0.45))
                        .frame(width: 10, height: 10)
                    Text("Defizit")
                        .font(.caption2)
                        .foregroundStyle(KColor.ink3)
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 34)
    }
}

/// «Verfügbar pro Monat»: Balken ab der Nulllinie, negative hängen darunter; vergangene Monate kräftig.
struct KBBudgetChart: View {
    let months: [Calc.BudgetMonth]
    let selected: Int
    let year: Int
    let today: Day
    let average: Double

    var body: some View {
        let frees = months.map { $0.free }
        let hi = max(0, frees.max() ?? 0)
        let lo = min(0, frees.min() ?? 0)
        let range = (hi - lo) == 0 ? 1 : (hi - lo)
        Chart {
            ForEach(0..<12, id: \.self) { i in
                bar(i, range: range)
            }
            RuleMark(y: .value("Null", 0.0))
                .foregroundStyle(KColor.line)
                .lineStyle(StrokeStyle(lineWidth: 1))
            if abs(average) > 0.005 {
                RuleMark(y: .value("Ø", average))
                    .foregroundStyle(KColor.ink2.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: Format.monthShort)
        .chartYScale(domain: lo...(hi > lo ? hi : lo + 1))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                averageLabel(proxy: proxy, geo: geo)
            }
        }
        .accessibilityHidden(true)
    }

    @ChartContentBuilder
    private func bar(_ i: Int, range: Double) -> some ChartContent {
        let f = months[i].free
        let h = max(abs(f), range * 0.008)
        let past = year < today.year || (year == today.year && i + 1 <= today.month)
        let on = i + 1 == selected
        if f != 0 {
            BarMark(x: .value("Monat", Format.monthShort[i]), yStart: .value("Null", 0.0),
                    yEnd: .value("Verfügbar", f < 0 ? -h : h), width: .ratio(0.8))
                .foregroundStyle(KBBudgetChart.color(past: past, on: on, negative: f < 0))
                .cornerRadius(4, style: .continuous)
        }
    }

    static func color(past: Bool, on: Bool, negative: Bool) -> Color {
        if negative {
            if past { return on ? KColor.alert : KColor.alert.opacity(0.45) }
            return KColor.alert.opacity(on ? 0.62 : 0.22)
        }
        if past { return on ? KColor.teal : KColor.teal.opacity(0.30) }
        return KColor.ink.opacity(on ? 0.72 : 0.12)
    }

    @ViewBuilder
    private func averageLabel(proxy: ChartProxy, geo: GeometryProxy) -> some View {
        if abs(average) > 0.005, let pf = proxy.plotFrame, let y = proxy.position(forY: average) {
            let r = geo[pf]
            Text(verbatim: "Ø")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(KColor.ink3)
                .position(x: r.maxX + 9, y: r.minY + y)
        }
    }
}

// MARK: - «Einnahmen {Monat}»

struct KBBudgetIncomeList: View {
    @Environment(AppModel.self) private var model
    let year: Int
    let month: Int
    let person: UUID?
    let incomeCount: Int
    let monthIncome: Double

    var body: some View {
        let calc = model.calc
        let home = calc.home
        let rows = calc.kbIncomeRows(year: year, month: month, person: person)
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: "Einnahmen " + Format.monthNames[month - 1],
                          amount: Format.money(monthIncome) + " " + home.rawValue)
            KBListBlock(horizontal: 13) {
                if rows.isEmpty {
                    Text(verbatim: "Keine Einnahmen im " + Format.monthNames[month - 1])
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink3)
                        .padding(.vertical, 13)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                        if idx > 0 { KBRowDivider() }
                        incomeRow(r, home: home)
                    }
                }
                KBRowDivider()
                HStack {
                    Button {
                        model.present(.incomeForm(nil))
                    } label: {
                        Text("+ Einnahme")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KColor.teal)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Einnahme erfassen")
                    Spacer(minLength: 8)
                    Button {
                        model.present(.incomesAll)
                    } label: {
                        Text(verbatim: "Alle Einnahmen (" + String(incomeCount) + ") ›")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(KColor.ink2)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func incomeRow(_ r: Calc.KBIncomeRow, home: Currency) -> some View {
        if let i = model.data.income(r.incomeID) {
            Button {
                model.present(.incomeForm(i.id))
            } label: {
                HStack(spacing: 11) {
                    MarkView(income: i, size: 32)
                    Text(verbatim: i.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(verbatim: Format.money(r.amount, i.currency))
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(KColor.ink)
                        if i.currency != home {
                            Text(verbatim: i.currency.rawValue)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(KColor.ink3)
                        }
                    }
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}

// MARK: - «Ausgaben {Monat}» mit Summenblock

struct KBBudgetExpenseList: View {
    @Environment(AppModel.self) private var model
    let year: Int
    let month: Int
    let person: UUID?
    let bm: Calc.BudgetMonth
    @Binding var showAll: Bool

    private static let limit = 5

    var body: some View {
        let calc = model.calc
        let home = calc.home.rawValue
        let rows = calc.kbExpenseRows(year: year, month: month, person: person)
        let total = rows.reduce(0.0) { $0 + $1.value }
        let more = rows.count - KBBudgetExpenseList.limit
        let all = showAll || more <= 1
        let shown = all ? rows : Array(rows.prefix(KBBudgetExpenseList.limit))
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: "Ausgaben " + Format.monthNames[month - 1],
                          amount: Format.money(total) + " " + home)
            KBListBlock {
                if rows.isEmpty {
                    Text(verbatim: "Keine Ausgaben im " + Format.monthNames[month - 1])
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .padding(.vertical, 14)
                } else {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { idx, r in
                        if idx > 0 { KBRowDivider() }
                        KBExpenseRowView(row: r)
                    }
                }
                if rows.count > KBBudgetExpenseList.limit && more > 1 {
                    KBRowDivider()
                    KBFoldButton(title: all ? "Nur die grössten 5" : "Alle " + String(rows.count) + " anzeigen", expanded: all) {
                        withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                    }
                }
            }
            sumBlock(home: home)
                .padding(.top, 8)
        }
    }

    /// «Einnahmen» / «− Ausgaben» / «= Verfügbar»
    private func sumBlock(home: String) -> some View {
        VStack(spacing: 6) {
            sumLine("Einnahmen", Format.money(bm.income))
            sumLine(Format.minus + " Ausgaben", Format.money(bm.fixed))
            Rectangle().fill(KColor.line).frame(height: 0.5)
            sumLine("= Verfügbar", Format.money(bm.free) + " " + home, bold: true)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
        .overlay(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private func sumLine(_ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack {
            Text(verbatim: label)
                .foregroundStyle(bold ? KColor.ink : KColor.ink2)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .monospacedDigit()
                .foregroundStyle(KColor.ink)
        }
        .font(.subheadline.weight(bold ? .semibold : .regular))
    }
}

/// Zeile in «Ausgaben»: Betrag in Hauptwährung, darunter die Kategorie
struct KBExpenseRowView: View {
    @Environment(AppModel.self) private var model
    let row: Calc.KBExpenseRow

    var body: some View {
        if let c = model.data.contract(row.contractID) {
            let calc = model.calc
            let sub = calc.kbExpenseSubline(row)
            let amount = row.value < 0 ? Format.minus + Format.money(-row.value) : Format.money(row.value)
            Button {
                model.present(.contractDetail(c.id))
            } label: {
                HStack(spacing: 12) {
                    MarkView(contract: c, data: model.data, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: model.data.title(of: c))
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundStyle(KColor.ink)
                            .lineLimit(1)
                        if !sub.isEmpty {
                            Text(verbatim: sub)
                                .font(.footnote)
                                .foregroundStyle(KColor.ink2)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(verbatim: amount)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(KColor.ink)
                        Text(verbatim: calc.statKey(c, .category))
                            .font(.caption)
                            .foregroundStyle(KColor.ink3)
                            .lineLimit(1)
                    }
                    .layoutPriority(1)
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}


// MARK: - «Fair geteilt?» (Web .fgcard): Balken = Anteil an den Fixkosten, Strich = Anteil an den Einnahmen

struct KBFairShareView: View {
    @Environment(AppModel.self) private var model
    let rows: [Calc.FairRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: Calc.fairTitle, amount: Calc.fairSubtitle)
            KBListBlock {
                ForEach(Array(rows.enumerated()), id: \.element.personID) { idx, r in
                    if idx > 0 { KBRowDivider() }
                    HStack(spacing: 12) {
                        if let p = model.data.person(r.personID) { PersonAvatar(person: p, size: 36) }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: r.name).font(.subheadline.weight(.semibold)).foregroundStyle(KColor.ink).lineLimit(1)
                            Text(verbatim: r.subline).font(.caption.monospacedDigit()).foregroundStyle(KColor.ink3).lineLimit(1)
                            GeometryReader { g in
                                let w = g.size.width
                                ZStack(alignment: .leading) {
                                    Capsule().fill(KColor.line).frame(height: 8)
                                    Capsule().fill(KColor.teal.opacity(0.55)).frame(width: w * CGFloat(r.fixedPercent) / 100, height: 8)
                                    Rectangle().fill(KColor.ink).frame(width: 2, height: 14).offset(x: w * CGFloat(r.incomePercent) / 100 - 1)
                                }
                                .frame(height: 14)
                            }
                            .frame(height: 14)
                            .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
                Text(verbatim: Calc.fairHint).font(.caption).foregroundStyle(KColor.ink3).padding(.vertical, 8)
            }
        }
        .accessibilityIdentifier("budget.fair")
    }
}
