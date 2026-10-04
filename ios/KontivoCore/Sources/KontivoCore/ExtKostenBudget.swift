import Foundation

// Bereich «Kosten» und «Budget»: reine Logik (nur Foundation), 1:1 zur Web-App (renderStat, renderBudget,
// statFilterBar, openPick, showLpop, openIncAll, Einnahmen-Formular). Alle Namen mit Präfix KB/kb,
// damit sie nicht mit Erweiterungen anderer Bereiche kollidieren.

// MARK: - Texte und Eingaben

public enum KBText {
    /// «Sonderzahlung» bzw. «Gutschrift» (Betrag < 0), plus « · Notiz» (`exLabel`).
    public static func extraLabel(_ x: ExtraPayment) -> String {
        (x.amount < 0 ? "Gutschrift" : "Sonderzahlung") + (x.note.isEmpty ? "" : " · " + x.note)
    }

    /// «1 beendeter Vertrag» / «3 beendete Verträge» … « nicht mitgezählt».
    public static func endedText(_ n: Int) -> String {
        "\(n)" + (n == 1 ? " beendeter Vertrag" : " beendete Verträge") + " nicht mitgezählt"
    }

    /// Betrag aus einem Eingabefeld lesen: gemeinsamer Zahlenleser `Format.parseNum` (1:1 Web-`parseNum`).
    /// Leer oder unlesbar → nil.
    public static func parseAmount(_ s: String) -> Double? {
        Format.parseNum(s)
    }
}

// MARK: - Personen-Chips (holderNamer)

/// Namen für Personen-Chips kürzen, bis sie in die Zeile passen (`holderNamer` der Web-App).
/// `ok`: Chips möglich (2–4 Personen und die Kurznamen passen in die Breite).
public struct KBHolderNamer: Hashable, Sendable {
    public let ok: Bool
    private let useFirst: Bool
    private let clash: Bool

    public init(names: [String], width: Double) {
        let n = names.count
        let fit = Int(((width / Double(n + 1) - 28) / 8.2).rounded(.down))
        let uf = names.contains { $0.utf16.count > fit }
        let fn = names.map { Format.firstName($0) }
        var seen = Set<String>()
        var cl = false
        for f in fn {
            if seen.contains(f) { cl = true }
            seen.insert(f)
        }
        useFirst = uf
        clash = cl
        let total = names.reduce(0) { $0 + KBHolderNamer.display($1, useFirst: uf, clash: cl).utf16.count }
        ok = n > 1 && n <= 4 && total <= Int((28 * width / 361).rounded(.down))
    }

    /// Kurzname: unverändert, sonst Vorname bzw. «Vorname N.» bei gleichen Vornamen.
    public func display(_ name: String) -> String {
        KBHolderNamer.display(name, useFirst: useFirst, clash: clash)
    }

    static func display(_ h: String, useFirst: Bool, clash: Bool) -> String {
        if !useFirst { return h }
        let w = h.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = w.first else { return h }
        if clash && w.count > 1, let last = w.last, let ch = last.first {
            return first + " " + String(ch) + "."
        }
        return first
    }
}

// MARK: - Monat wechseln

public enum KBMonthMath {
    /// Verboten ist nur ein Schritt über Dezember hinaus, wenn das Jahr ≥ aktuelles Jahr + 5 (`canShift`).
    public static func canShift(year: Int, month: Int, step: Int, currentYear: Int) -> Bool {
        let m = Swift.min(12, Swift.max(1, month)) + step
        return !(m > 12 && year >= currentYear + 5)
    }

    /// Monat ± step, über Dezember/Januar ins Nachbarjahr (`shiftMonth`).
    public static func shifted(year: Int, month: Int, step: Int) -> (year: Int, month: Int) {
        var m = Swift.min(12, Swift.max(1, month)) + step
        var y = year
        while m > 12 { m -= 12; y += 1 }
        while m < 1 { m += 12; y -= 1 }
        return (y, m)
    }
}

// MARK: - Kosten

extension Calc {
    /// Statuszeile einer Zahlung in «Fällig im»: «am 03.10.26», «heute fällig», «in 3 Tagen» (warn), «fällig 20.10.26».
    public func kbPaymentStatus(_ d: Day) -> (text: String, warn: Bool) {
        if d < today { return ("am " + Format.fmtShort(d), false) }
        let dn = today.days(to: d)
        if dn == 0 { return ("heute fällig", false) }
        if dn <= 7 { return ("in \(dn)" + (dn == 1 ? " Tag" : " Tagen"), true) }
        return ("fällig " + Format.fmtShort(d), false)
    }

    /// Zweitzeile einer Zahlung in «Fällig im»: «Anteil 50 %» · Vertragspartner · «Sonderzahlung · Notiz».
    public func kbCostSubline(_ it: CostItem) -> String {
        guard let c = data.contract(it.contractID) else { return "" }
        let parts = [it.share < 1 ? Format.shareText(it.share) : "", data.meta(of: c), it.extra.map(KBText.extraLabel) ?? ""]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Zahlungen des Monats: offen (ab heute) und bezahlt (vor heute), nach Datum bzw. Betrag absteigend.
    public func kbOpenPaid(_ items: [CostItem], byAmount: Bool) -> (open: [CostItem], paid: [CostItem]) {
        var o = items.filter { $0.date >= today }.stableSorted { $0.date < $1.date }
        var p = items.filter { $0.date < today }.stableSorted { $0.date < $1.date }
        if byAmount {
            o = o.stableSorted { $0.value > $1.value }
            p = p.stableSorted { $0.value > $1.value }
        }
        return (o, p)
    }

    /// Aktive Filter als Text (`fltLabel`): Werte mit « · ».
    public func kbFilterLabel(_ f: CostFilter) -> String {
        let person = f.person.flatMap { data.person($0)?.name } ?? ""
        return [f.category ?? "", f.partner ?? "", person].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Personen der Filterleiste in «Kosten»: Inhaber mit mindestens einem Vertrag (+ gefilterte Person).
    public func kbCostPersons(filterPerson: UUID?) -> [Person] {
        var used = Set<UUID>()
        for c in data.contracts { for h in c.holderIDs { used.insert(h) } }
        var list = data.persons.filter { used.contains($0.id) }
        if let fp = filterPerson, !list.contains(where: { $0.id == fp }), let p = data.person(fp) { list.append(p) }
        return list
    }

    /// Automatische Monatswahl nach einem Filterwechsel (`autoSel`): hat der gewählte Monat nichts und das Jahr
    /// etwas, gilt der nächste Monat (vorwärts, zyklisch) mit Zahlungen. Rückgabe 1–12.
    public func kbAutoMonth(_ cy: CostYear, current month: Int) -> Int {
        let sel = Swift.min(11, Swift.max(0, month - 1))
        if cy.months[sel].sum == 0 && cy.total != 0 {
            for j in 0..<12 {
                let q = (sel + j) % 12
                if cy.months[q].sum != 0 { return q + 1 }
            }
        }
        return sel + 1
    }

    // MARK: Aufteilung (Ring)

    public struct KBSplitSegment: Hashable, Identifiable, Sendable {
        public var key: String
        public var value: Double
        public var colorHex: String
        /// «Übrige»
        public var isOther: Bool
        public var id: String { (isOther ? "\u{1}" : "") + key }
    }

    public struct KBSplit: Hashable, Sendable {
        /// Alle Schlüssel mit Wert > 0.004, absteigend
        public var keys: [String]
        /// Ring: alle bei ≤ 5 Schlüsseln, sonst Top 4 + «Übrige»
        public var segments: [KBSplitSegment]
        /// Schlüssel hinter «Übrige»
        public var rest: [String]
        /// Summe der gezeigten Schlüssel (nie 0)
        public var total: Double
        public var values: [String: Double]

        /// Prozent eines Werts (gerundet wie Math.round).
        public func percent(_ v: Double) -> Int { Int(Format.jsRound(v / total * 100)) }
    }

    /// Farbe «Übrige».
    public static let kbOtherColor = "#9AA0A6"
    /// Farben nach Rang bei Aufteilung nach Vertragspartner.
    public static let kbPartnerPalette = ["#0E5A5E", "#8A6A1F", "#1F4E8C", "#6B4E9E", "#A93227", "#2E6A4E", "#B0562A", "#3F4A55"]

    /// Kategoriefarbe nach Name (`catColor`): Eintrag → Standardfarbe → #5F666E.
    public func kbCategoryColor(_ name: String) -> String {
        data.category(named: name)?.colorHex ?? Category.standardColors[name] ?? Category.fallbackColor
    }

    public func kbSplit(_ groups: [String: Double], dim: FilterDimension) -> KBSplit {
        let keys = groups.keys.filter { (groups[$0] ?? 0) > 0.004 }.sorted { a, b in
            let va = groups[a] ?? 0
            let vb = groups[b] ?? 0
            if va != vb { return va > vb }
            return Format.lessDE(a, b)
        }
        let sum = keys.reduce(0.0) { $0 + (groups[$1] ?? 0) }
        let top = Array(keys.prefix(keys.count > 5 ? 4 : 5))
        let rest = Array(keys.dropFirst(top.count))
        var segs: [KBSplitSegment] = []
        for (i, k) in top.enumerated() {
            let col = dim == .category ? kbCategoryColor(k) : Calc.kbPartnerPalette[i % Calc.kbPartnerPalette.count]
            segs.append(KBSplitSegment(key: k, value: groups[k] ?? 0, colorHex: col, isOther: false))
        }
        let restSum = rest.reduce(0.0) { $0 + (groups[$1] ?? 0) }
        if restSum > 0.004 {
            segs.append(KBSplitSegment(key: "Übrige", value: restSum, colorHex: Calc.kbOtherColor, isOther: true))
        }
        return KBSplit(keys: keys, segments: segs, rest: rest, total: sum == 0 ? 1 : sum, values: groups)
    }

    // MARK: Filter-Auswahl (openPick) und langes Drücken (showLpop)

    public struct KBFilterValue: Hashable, Identifiable, Sendable {
        /// Kategorie- bzw. Vertragspartner-Schlüssel oder Personenname
        public var key: String
        /// Nur bei Inhabern
        public var personID: UUID?
        public var activeCount: Int
        public var totalCount: Int
        public var id: String { personID?.uuidString ?? key }

        /// «1 aktiver Vertrag», «3 aktive Verträge» oder «nur beendete»
        public var countText: String {
            activeCount > 0 ? "\(activeCount)" + (activeCount == 1 ? " aktiver Vertrag" : " aktive Verträge") : "nur beendete"
        }
    }

    /// Werte einer Filterdimension aus allen Verträgen (auch archivierten) mit Zählern.
    /// Kategorie in Kategorien-Reihenfolge (unbekannte hinten), sonst alphabetisch (de-CH).
    public func kbFilterValues(_ dim: FilterDimension) -> [KBFilterValue] {
        var order: [String] = []
        var vals: [String: KBFilterValue] = [:]
        for c in data.contracts {
            let on = isActive(c)
            var ks: [(String, UUID?)] = []
            if dim == .holder {
                for h in c.holderIDs {
                    if let p = data.person(h), !p.name.isEmpty { ks.append((p.name, h)) }
                }
            } else {
                ks = [(statKey(c, dim), nil)]
            }
            for (k, pid) in ks where !k.isEmpty {
                let id = pid?.uuidString ?? k
                if vals[id] == nil {
                    order.append(id)
                    vals[id] = KBFilterValue(key: k, personID: pid, activeCount: 0, totalCount: 0)
                }
                vals[id]?.totalCount += 1
                if on { vals[id]?.activeCount += 1 }
            }
        }
        let list = order.compactMap { vals[$0] }
        if dim == .category {
            let names = data.categories.map { $0.name }
            return list.stableSorted { a, b in
                (names.firstIndex(of: a.key) ?? 99) < (names.firstIndex(of: b.key) ?? 99)
            }
        }
        return list.stableSorted { Format.lessDE($0.key, $1.key) }
    }

    public struct KBPopupRow: Hashable, Identifiable, Sendable {
        public var contractID: UUID
        /// Titel + « · Anteil x %» (gemeinsamer Vertrag bei Inhaber) + « · pausiert»
        public var text: String
        /// Monatskosten × Anteil (Hauptwährung)
        public var value: Double
        public var paused: Bool
        public var id: UUID { contractID }
    }

    public struct KBPopup: Hashable, Sendable {
        public var title: String
        public var rows: [KBPopupRow]
        /// Summe ohne pausierte
        public var total: Double
        /// «2 beendete Verträge nicht mitgezählt», nil ohne beendete
        public var endedText: String?
    }

    /// Inhalt des Pop-ups bei langem Drücken auf einen Filterwert.
    public func kbPopup(_ dim: FilterDimension, key: String, personID: UUID?) -> KBPopup {
        let all = data.contracts.filter { c in
            if dim == .holder, let p = personID { return c.holderIDs.contains(p) }
            return statKey(c, dim) == key
        }
        let act = all.filter { isActive($0) }.stableSorted { monthlyCost($0) > monthlyCost($1) }
        var sum = 0.0
        var rows: [KBPopupRow] = []
        for c in act {
            let off = isPaused(c)
            let f = dim == .holder ? holderShare(c, person: personID) : 1
            let v = monthlyCost(c) * f
            if !off { sum += v }
            let text = data.title(of: c) + (f < 1 ? " · " + Format.shareText(f) : "") + (off ? " · pausiert" : "")
            rows.append(KBPopupRow(contractID: c.id, text: text, value: v, paused: off))
        }
        let nOld = all.count - act.count
        return KBPopup(title: key, rows: rows, total: sum, endedText: nOld > 0 ? KBText.endedText(nOld) : nil)
    }
}

// MARK: - Budget und Einnahmen

extension Calc {
    /// Einnahmen mit Anteil > 0 für die Person, nach heutigem Betrag (Hauptwährung) absteigend.
    public func kbBudgetIncomes(person: UUID?) -> [Income] {
        data.incomes.filter { incomeShare($0, person: person) > 0 }
            .stableSorted { conv(curPrice($0), $0.currency) > conv(curPrice($1), $1.currency) }
    }

    /// Alle Einnahmen nach heutigem Betrag (Hauptwährung) absteigend (Fenster «Alle Einnahmen»).
    public func kbAllIncomes() -> [Income] {
        data.incomes.stableSorted { conv(curPrice($0), $0.currency) > conv(curPrice($1), $1.currency) }
    }

    /// Zweitzeile in «Alle Einnahmen»: «beendet», «ab 01.11.26» oder Turnus; off = blass.
    public func kbIncomeStatus(_ i: Income) -> (text: String, off: Bool) {
        if let e = i.end, e < today { return ("beendet", true) }
        if let s = i.start, s > today { return ("ab " + Format.fmtShort(s), true) }
        return (Format.incomeCycleTexts[i.cycle] ?? "monatlich", false)
    }

    public struct KBIncomeRow: Hashable, Identifiable, Sendable {
        public var incomeID: UUID
        /// Summe im Monat in Einnahmewährung
        public var amount: Double
        /// in Hauptwährung (Sortierung)
        public var value: Double
        public var id: UUID { incomeID }
    }

    /// «Einnahmen {Monat}»: Einnahmen mit mindestens einem Termin im Monat, absteigend nach Betrag.
    public func kbIncomeRows(year: Int, month: Int, person: UUID?) -> [KBIncomeRow] {
        let from = Day(year, month, 1)
        let to = Day(year, month + 1, 0)
        var out: [KBIncomeRow] = []
        for i in kbBudgetIncomes(person: person) {
            let ds = occurrences(i, from: from, to: to)
            if ds.isEmpty { continue }
            let a = ds.reduce(0.0) { $0 + priceAt(i, $1) }
            out.append(KBIncomeRow(incomeID: i.id, amount: a, value: conv(a, i.currency)))
        }
        return out.stableSorted { $0.value > $1.value }
    }

    public struct KBExpenseRow: Hashable, Identifiable, Sendable {
        public var contractID: UUID
        public var date: Day
        /// Hauptwährung × Anteil
        public var value: Double
        public var share: Double
        public var extra: ExtraPayment?
        public var id: String { contractID.uuidString + "|" + date.iso + "|" + (extra?.id.uuidString ?? "") }
    }

    /// «Ausgaben {Monat}»: jede Zahlung (Termin oder Sonderzahlung) mit Anteil > 0, absteigend nach Betrag.
    public func kbExpenseRows(year: Int, month: Int, person: UUID?) -> [KBExpenseRow] {
        let from = Day(year, month, 1)
        let to = Day(year, month + 1, 0)
        var out: [KBExpenseRow] = []
        for c in data.contracts {
            let f = holderShare(c, person: person)
            if f == 0 { continue }
            for p in payments(c, from: from, to: to) {
                out.append(KBExpenseRow(contractID: c.id, date: p.date, value: conv(p.amount, c.currency) * f, share: f, extra: p.extra))
            }
        }
        return out.stableSorted { $0.value > $1.value }
    }

    /// Zweitzeile in «Ausgaben»: Vertragspartner · «Anteil 50 %» · «Sonderzahlung · Notiz».
    public func kbExpenseSubline(_ r: KBExpenseRow) -> String {
        guard let c = data.contract(r.contractID) else { return "" }
        let parts = [data.meta(of: c), r.share < 1 ? Format.shareText(r.share) : "", r.extra.map(KBText.extraLabel) ?? ""]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Vorjahresvergleich «verfügbar» mit derselben Sperre wie in «Kosten»: entfällt, wenn eine Zahlung des Monats
    /// zu einem Vertrag ohne Vertragsbeginn gehört oder eine Einnahme (Anteil > 0) ohne Beginn im Monat einen Termin hat
    /// (beide werden rückwirkend voll gezählt; Web `bNoStart`).
    public func kbBudgetComparison(year: Int, month: Int, person: UUID?, free: Double) -> (text: String, trend: Trend)? {
        let rows = kbExpenseRows(year: year, month: month, person: person)
        if rows.contains(where: { data.contract($0.contractID)?.start == nil }) { return nil }
        let from = Day(year, month, 1)
        let to = Day(year, month + 1, 0)
        if kbBudgetIncomes(person: person).contains(where: { $0.start == nil && !occurrences($0, from: from, to: to).isEmpty }) {
            return nil
        }
        return budgetMonthComparison(year: year, month: month, person: person, free: free)
    }

    /// Satz der Leerseite «Budget» (`budgetEmpty`).
    public func kbBudgetEmptyText() -> String {
        let h = hero()
        if h.activeCount > 0 {
            return "Deine Fixkosten sind schon da: " + Format.money(h.monthlyTotal) + " " + home.rawValue + " im Monat. Es fehlt nur dein Lohn."
        }
        return "Trag deinen Lohn ein, die Fixkosten kommen aus deinen Verträgen."
    }
}
