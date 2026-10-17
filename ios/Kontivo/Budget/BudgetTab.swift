import SwiftUI
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
        KBPage(miniTitle: hasIncomes ? "Budget · " + String(model.selectedYear) : "Budget") {
            KBPageHeader(title: "Budget") {
                if hasIncomes { KBYearNav() }
            }
            KBBudgetPersonBar(persons: persons, selected: bh)
            if !hasIncomes, let p = model.data.person(bh) {
                noIncomeForPerson(p)
            } else if !hasIncomes {
                emptyPage(calc)
            } else {
                KBBudgetContent(person: bh, incomeCount: incomes.count, showAllExpenses: $showAllExpenses)
            }
        }
        .kPageBackground()
        .navigationTitle("Budget")
    }

    /// Filter aktiv, aber diese Person hat keine Einnahmen (Web `.empty` + «+ Einnahme erfassen»)
    private func noIncomeForPerson(_ p: Person) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: "Keine Einnahmen für " + p.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                Text("Weise einer Einnahme diese Person als Empfänger zu, dann erscheint hier ihr Budget.")
                    .font(.system(size: 14))
                    .lineSpacing(14 * 0.4)
                    .foregroundStyle(KColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 46)
            .padding(.horizontal, 6)
            Button {
                model.present(.incomeForm(nil))
            } label: {
                Text("+ Einnahme erfassen")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(KColor.teal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .kbSurface(KBM.listRadius)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 20)
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

/// Chips «Alle | Name …» (2–4 Personen, passende Namen, gleich breit); sonst Auswahlknopf «Person» mit «×»; bei einer Person nichts.
struct KBBudgetPersonBar: View {
    @Environment(AppModel.self) private var model
    let persons: [Person]
    let selected: UUID?

    var body: some View {
        let namer = KBHolderNamer(names: persons.map { $0.name }, width: 361)
        Group {
            if namer.ok {
                KBFlexRow(equal: true) {
                    KBPersonChip(title: "Alle", isOn: selected == nil) { model.budgetPerson = nil }
                        .kbFlexGrow(1)
                    ForEach(persons) { p in
                        KBPersonChip(title: namer.display(p.name), isOn: selected == p.id) { model.budgetPerson = p.id }
                            .kbFlexGrow(1)
                    }
                }
                .padding(.top, 12)
            } else if persons.count > 1 {
                selectRow(namer)
                    .padding(.top, 12)
            }
        }
    }

    private func selectRow(_ namer: KBHolderNamer) -> some View {
        let name = selected.flatMap { id in persons.first(where: { $0.id == id })?.name } ?? ""
        let binding = Binding<UUID?>(get: { model.budgetPerson }, set: { model.budgetPerson = $0 })
        return KBFlexRow {
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
            .kbFlexGrow(1)
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
            KBBigAmount(value: bm.free, currency: home, alert: bm.free < 0, signed: true)
            KBBudgetSubline(bm: bm, info: shareInfo(bm, pname: pname))
            if let c = cmp {
                // mehr verfügbar = grüne Fläche (Web-Klasse «down»), weniger = Warnfarbe
                KBCompareLine(text: c.text, arrow: c.trend.kbArrow, tone: c.trend == .up ? .down : (c.trend == .down ? .up : .same))
            }
            KBCardRow {
                HStack(alignment: .top, spacing: 12) {
                    KBStatCell(label: "Einnahmen", value: Format.money(bm.income), muted: bm.income < 0.005)
                    KBStatCell(label: "Fixkosten", value: Format.money(bm.fixed), trailing: true, muted: bm.fixed < 0.005)
                }
            }
            chartArea(home: home)
            KBCardRow(top: 16) {
                HStack(alignment: .top, spacing: 12) {
                    KBStatCell(label: "Ø pro Monat", value: KBBudgetCard.signed0(by.average),
                               valueColor: by.average < 0 ? KColor.warn : nil)
                    KBStatCell(label: "Verfügbar " + String(by.year), value: KBBudgetCard.signed0(by.totalFree), trailing: true,
                               valueColor: by.totalFree < 0 ? KColor.warn : nil)
                }
            }
        }
        .accessibilityIdentifier("budget.card")
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

    private func chartArea(home: String) -> some View {
        let frees = by.months.map { $0.free }
        let hasNeg = frees.contains { $0 < 0 }
        let value = Format.monthNames[month - 1] + ": " + Format.money(by.months[month - 1].free) + " " + home
        return VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 0) {
                KBBudgetChart(months: by.months, selected: month, year: by.year, today: model.today, average: by.average)
                    .frame(height: 170)
                KBMonthLabels(year: by.year, selected: month, today: model.today)
            }
            .contentShape(Rectangle())
            .kbScrubArea()
            .kbMonthAdjustable(model, label: "Verfügbar pro Monat", value: value)
            .padding(.trailing, 16)
            if hasNeg {
                // Web `.clegend`: rechtsbündig, 11 px Tinte 3, Quadrat 10 × 10
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(KBColor.negLegend)
                        .frame(width: 10, height: 10)
                    Text("Defizit")
                        .font(.system(size: 11))
                        .foregroundStyle(KColor.ink3)
                }
                .padding(.top, 8)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.top, 22)
        .accessibilityIdentifier("budget.chart")
    }
}

/// «Verfügbar pro Monat» (Web `.bchart`, 170 pt): Balken ab der Nulllinie, negative hängen darunter; vergangene Monate
/// (bis heute) blass Messing, künftige grau; gewählter Monat Messing (künftig Tinte 72 %).
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
        let rg = (hi - lo) == 0 ? 1 : (hi - lo)
        let zp = CGFloat(-lo / rg)
        GeometryReader { g in
            let H = g.size.height
            ZStack(alignment: .topLeading) {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(0..<12, id: \.self) { i in
                        bar(i, rg: rg, zp: zp, H: H)
                    }
                }
                Rectangle().fill(KColor.line).frame(height: 1)
                    .offset(y: H * (1 - zp) - 1)
                if abs(average) > 0.005 {
                    KBAverageLine(fraction: zp + CGFloat(average / rg))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func bar(_ i: Int, rg: Double, zp: CGFloat, H: CGFloat) -> some View {
        let f = months[i].free
        let neg = f < 0
        let h = f == 0 ? 0 : max(CGFloat(abs(f) / rg), 0.008) * H
        let past = year < today.year || (year == today.year && i + 1 <= today.month)
        let on = i + 1 == selected
        let bottom = neg ? zp * H - h : zp * H
        return ZStack(alignment: .bottom) {
            Color.clear
            UnevenRoundedRectangle(topLeadingRadius: neg ? 0 : 4, bottomLeadingRadius: neg ? 4 : 0,
                                   bottomTrailingRadius: neg ? 4 : 0, topTrailingRadius: neg ? 0 : 4, style: .circular)
                .fill(KBBudgetChart.color(past: past, on: on, negative: neg))
                .frame(height: h)
                .padding(.bottom, bottom)
        }
        .frame(maxWidth: .infinity)
        .frame(height: H)
    }

    /// Web: `.bcol .bp` (auch negativ) blass Messing, gewählt Messing; `.bo` grau, gewählt Tinte 72 %; `.bo.neg` Warnfarbe 22 %/62 %
    static func color(past: Bool, on: Bool, negative: Bool) -> Color {
        if past { return on ? KColor.brass : KBColor.budgetPast }
        if negative { return on ? KBColor.negFutureOn : KBColor.negFuture }
        return on ? KBColor.budgetFutureOn : KBColor.barFuture
    }
}

// MARK: - «Einnahmen {Monat}» (Web `.ilist`)

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
            KBListBlock(horizontal: 0, radius: KBM.listRadius) {
                if rows.isEmpty {
                    Text(verbatim: "Keine Einnahmen im " + Format.monthNames[month - 1])
                        .font(.system(size: 14))
                        .foregroundStyle(KColor.ink3)
                        .padding(13)
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
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(KColor.teal)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11 + KBM.pad(20.3, 14))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Einnahme erfassen")
                    .accessibilityIdentifier("budget.addIncome")
                    Spacer(minLength: 8)
                    Button {
                        model.present(.incomesAll)
                    } label: {
                        Text(verbatim: "Alle Einnahmen (" + String(incomeCount) + ") ›")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(KColor.ink2)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 11 + KBM.pad(20.3, 14))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("budget.allIncomes")
                }
            }
        }
    }

    @ViewBuilder
    private func incomeRow(_ r: Calc.KBIncomeRow, home: Currency) -> some View {
        if let i = model.data.income(r.incomeID) {
            // Zweitzeile Person(en) · Rhythmus (Web v156/v159), Antippen öffnet die Einnahme-Ansicht (Web v155)
            let sub = model.calc.kbIncomeSubline(i)
            Button {
                model.present(.incomeDetail(i.id))
            } label: {
                KBIncomeRowLabel(income: i, title: i.title, sub: sub, amount: Format.money(r.amount, i.currency),
                                 currency: i.currency != home ? i.currency.rawValue : nil)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Zeile einer Einnahme (Web `.irow`): Kachel 32, Name 15 Medium, Zweitzeile 12 Tinte 2, Betrag 15 Semibold
struct KBIncomeRowLabel: View {
    let income: Income
    let title: String
    let sub: String
    let amount: String
    let currency: String?
    /// Zweitzeile in Tinte 3 (Web `.it em` in «Alle Einnahmen»)
    var subMuted = false

    var body: some View {
        HStack(spacing: 11) {
            MarkView(income: income, size: 32)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .frame(height: 21.75)
                if !sub.isEmpty {
                    Text(verbatim: sub)
                        .font(.system(size: 12))
                        .foregroundStyle(subMuted ? KColor.ink3 : KColor.ink2)
                        .lineLimit(1)
                        .frame(height: 17.4)
                }
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(verbatim: amount)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(KColor.ink)
                if let c = currency {
                    Text(verbatim: c)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(KColor.ink3)
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .frame(minHeight: 59.1)
        .contentShape(Rectangle())
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
                        .font(.system(size: 14))
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

    /// «Einnahmen» / «− Ausgaben» / «= Verfügbar» (Web `.xsum`, 14 px)
    private func sumBlock(home: String) -> some View {
        VStack(spacing: 0) {
            sumLine("Einnahmen", KBBudgetExpenseList.moneyS(bm.income))
            sumLine(Format.minus + " Ausgaben", KBBudgetExpenseList.moneyS(bm.fixed))
            VStack(spacing: 0) {
                Rectangle().fill(KColor.line).frame(height: 1)
                sumLine("= Verfügbar", KBBudgetExpenseList.moneyS(bm.free) + " " + home, total: true)
                    .padding(.top, 4)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .kbSurface(KBM.listRadius)
        .accessibilityElement(children: .combine)
    }

    /// Web `moneyS`: typografisches Minus
    static func moneyS(_ v: Double) -> String { (v < -0.004 ? Format.minus : "") + Format.money(abs(v)) }

    private func sumLine(_ label: String, _ value: String, total: Bool = false) -> some View {
        HStack {
            Text(verbatim: label)
                .font(.system(size: 14, weight: total ? .semibold : .regular))
                .foregroundStyle(total ? KColor.ink : KColor.ink2)
            Spacer(minLength: 8)
            Text(verbatim: value)
                .font(.system(size: 14, weight: total ? .bold : .medium).monospacedDigit())
                .foregroundStyle(KColor.ink)
        }
        .padding(.vertical, 3 + KBM.pad(20.3, 14))
    }
}

/// Zeile in «Ausgaben»: Betrag in Hauptwährung, darunter die Kategorie (Web `.mrows2 .mrow`)
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
                    MarkView(contract: c, data: model.data, size: 34)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: model.data.title(of: c))
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(KColor.ink)
                            .lineLimit(1)
                            .frame(height: 20)
                        if !sub.isEmpty {
                            Text(verbatim: sub)
                                .font(.system(size: 12.5))
                                .foregroundStyle(KColor.ink2)
                                .lineLimit(1)
                                .frame(height: 18.1)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(verbatim: amount)
                            .font(.system(size: 16, weight: .semibold).monospacedDigit())
                            .foregroundStyle(KColor.ink)
                            .frame(height: 23.2)
                        Text(verbatim: c.categoryNameOrDefault(model.data))
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink3)
                            .lineLimit(1)
                            .frame(height: 18.1)
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

extension Contract {
    /// Kategoriename wie Web `c.cat || "Sonstiges"`
    func categoryNameOrDefault(_ data: AppData) -> String {
        let n = data.category(categoryID)?.name ?? ""
        return n.isEmpty ? "Sonstiges" : n
    }
}

// MARK: - «Fair geteilt?» (Web .fgcard): Balken = Anteil an den Fixkosten, Strich = Anteil an den Einnahmen

struct KBFairShareView: View {
    @Environment(AppModel.self) private var model
    let rows: [Calc.FairRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: Calc.fairTitle, amount: Calc.fairSubtitle)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.personID) { idx, r in
                    if idx > 0 { KBRowDivider() }
                    HStack(spacing: 12) {
                        PersonAvatar(person: model.data.person(r.personID), size: 38)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: r.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(KColor.ink)
                                .lineLimit(1)
                                .frame(height: 21.75)
                            Text(verbatim: r.subline)
                                .font(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(KColor.ink3)
                                .lineLimit(1)
                                .frame(height: 18.1)
                            GeometryReader { g in
                                let w = g.size.width
                                ZStack(alignment: .leading) {
                                    Capsule().fill(KColor.line).frame(height: 8)
                                    Capsule().fill(KColor.teal.opacity(0.45)).frame(width: w * CGFloat(r.fixedPercent) / 100, height: 8)
                                    RoundedRectangle(cornerRadius: 2).fill(KColor.ink).frame(width: 3, height: 16)
                                        .offset(x: w * CGFloat(r.incomePercent) / 100 - 1.5)
                                }
                                .frame(height: 16)
                            }
                            .frame(height: 16)
                            .padding(.top, 2)
                            .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
                Text(verbatim: Calc.fairHint)
                    .font(.system(size: 12.5))
                    .lineSpacing(12.5 * 0.25)
                    .foregroundStyle(KColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .kbSurface(KBM.listRadius)
        }
        .accessibilityIdentifier("budget.fair")
    }
}
