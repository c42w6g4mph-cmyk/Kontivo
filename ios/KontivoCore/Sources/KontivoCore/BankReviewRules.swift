import Foundation

// MARK: - Kontoauszug: Regeln der Vorschlagsliste (Web bkChips, bkPayList, bkIncDev, bkIncPrices, agoTxt, fmtDot)
// Nur Rechnung und Texte; die Darstellung liegt in Kontivo/Import.

/// Plakette unter einem Vorschlag (Web `.bkq i`, Variante Q)
public struct BankChip: Equatable, Hashable, Sendable {
    public enum Kind: Sendable {
        /// «12 Zahlungen» – antippen klappt die Zahlungen auf
        case payments
        /// Preisänderung im Auszug (Messing)
        case price
        case plain
    }

    public var text: String
    public var kind: Kind
}

/// Zeile der aufgeklappten Zahlungsliste (Web `bkPayList`): Betrag nil = ausgelassener Monat («gratis»)
public struct BankPayRow: Equatable, Hashable, Sendable {
    public var date: Day
    public var amount: Double?
    /// erste Zahlung einer neuen Preisstufe («neuer Preis»)
    public var changed: Bool
    /// liegt bei keiner Stufe («einmalig»)
    public var odd: Bool
}

/// Letzte Gutschrift weicht vom erkannten Betrag ab (Web `bkIncDev`)
public struct BankIncomeDeviation: Equatable, Sendable {
    public var date: Day
    public var amount: Double
    /// Differenz zum erkannten Betrag (positiv = mehr)
    public var diff: Double
}

extension BankImport {
    /// «05.09.2026» (Web `fmtDot`/`bkDay`, Datum TT.MM.JJJJ)
    public static func dot(_ d: Day) -> String {
        Day.pad(d.day, 2) + "." + Day.pad(d.month, 2) + "." + String(d.year)
    }

    /// Preisverlauf eines Vorschlags: Kosten nach Stufen, Einnahmen nach Lohnstufen (Web `bankPriceHist(s, inc)`)
    static func history(dates: [Day], amounts: [Double], cycle: Int, income: Bool) -> PriceHistory? {
        income ? incomeHistory(dates: dates, amounts: amounts) : priceHistory(dates: dates, amounts: amounts, cycle: cycle)
    }

    /// Plaketten unter einem Vorschlag (Web `bkChips`): Anzahl Zahlungen (bzw. «einmal am …»), Preisänderung im Auszug,
    /// Anzahl Änderungen, «Betrag schwankt», gratis Monate. `amount` = gewählter Betrag (Liste).
    public static func chips(dates: [Day], amounts: [Double], count n: Int, last: Day, lowConfidence: Bool, change: BankPriceChange?,
                             varies: Bool, cycle: Int, currency: String, amount: Double, income: Bool) -> [BankChip] {
        var c: [BankChip] = []
        if lowConfidence && n == 1 {
            c.append(BankChip(text: "einmal am " + dot(last), kind: .plain))
        } else {
            c.append(BankChip(text: n == 1 ? "1 Zahlung" : "\(n) Zahlungen", kind: .payments))
        }
        let ph = history(dates: dates, amounts: amounts, cycle: cycle, income: income)
        var lc: (prev: Double, amount: Double, from: Day)? = nil
        if let h = ph, let lastChg = h.changes.last {
            lc = (h.changes.count > 1 ? h.changes[h.changes.count - 2].amount : h.base, h.current, lastChg.from)
        } else if !income, let ch = change {
            lc = (ch.prev, ch.amount, ch.from)
        }
        let cur = Currency(rawValue: currency)
        if let l = lc, l.prev > 0, Swift.abs(amount - l.amount) < 0.005 {
            let pc = (l.amount / l.prev - 1) * 100
            if Swift.abs(pc) >= 100 {
                c.append(BankChip(text: "vorher " + Format.money(l.prev, cur) + " · ab " + dot(l.from), kind: .price))
            } else {
                let t = String(format: "%.1f", Swift.abs(pc)).replacingOccurrences(of: ".", with: ",")
                c.append(BankChip(text: (pc > 0 ? "+" : "−") + t + " % ab " + dot(l.from), kind: .price))
            }
            if let h = ph, h.changes.count > 1 {
                c.append(BankChip(text: "\(h.changes.count)" + (income ? " Änderungen" : " Preisänderungen"), kind: .plain))
            }
        } else if varies && ph == nil {
            c.append(BankChip(text: "Betrag schwankt", kind: .plain))
        }
        if let h = ph, !h.free.isEmpty {
            c.append(BankChip(text: h.free.count == 1 ? "1 Monat gratis" : "\(h.free.count) Monate gratis", kind: .plain))
        }
        return c
    }

    /// Zahlungen eines Vorschlags, neueste zuerst, mit ausgelassenen (gratis) Monaten (Web `bkPayList`)
    public static func payRows(dates: [Day], amounts: [Double], cycle: Int, income: Bool) -> [BankPayRow] {
        var D: [(Day, Double?)] = dates.indices.reversed().map { (dates[$0], $0 < amounts.count ? amounts[$0] : nil) }
        let ph = history(dates: dates, amounts: amounts, cycle: cycle, income: income)
        var chg = Set<Day>()
        if let h = ph {
            for p in h.changes { chg.insert(p.from) }
            for d in h.free { D.append((d, nil)) }
            D = BU.sorted(D) { x, y in x.0 < y.0 ? 1 : -1 }
        }
        let tol = income ? 0.01 : 0.005
        return D.map { x in
            guard let a = x.1 else { return BankPayRow(date: x.0, amount: nil, changed: false, odd: false) }
            let odd = ph.map { h in
                !h.levels.contains { l in Swift.abs(l - a) <= Swift.max(0.01, l * tol) || Swift.abs(l - a) <= l * 0.01 }
            } ?? false
            return BankPayRow(date: x.0, amount: a, changed: ph != nil && chg.contains(x.0), odd: odd)
        }
    }

    /// Letzte Gutschrift weicht mehr als 2 % vom erkannten Betrag ab (Lohn 7'285.30, am 23.10. kamen 8'221.90): nachfragen
    /// statt still ignorieren (Web v327 `bkIncDev`). Nur monatlich und ohne Formular-Änderung (`edited`).
    public static func incomeDeviation(dates: [Day], amounts: [Double], amount: Double, cycle: Int, edited: Bool) -> BankIncomeDeviation? {
        let n = dates.count
        if edited || n == 0 || cycle != 1 || !(amount > 0) || amounts.count < n { return nil }
        let a = amounts[n - 1]
        if !(a > 0) || Swift.abs(a - amount) / amount <= 0.02 { return nil }
        return BankIncomeDeviation(date: dates[n - 1], amount: a, diff: BU.r2(a - amount))
    }

    /// Einnahme aus dem Auszug mit «Neuer Lohn» (Web v327 `bkIncPrices`): Stufen vor der abweichenden Zahlung, ab dann deren Betrag
    public static func incomePrices(_ s: BankIncomeSuggestion, amount a: Double, newLevel v: BankIncomeDeviation?) -> (amount: Double, prices: [PriceChange]) {
        var r = incomePrices(s, amount: a)
        if let v = v { r.prices = r.prices.filter { $0.from < v.date } + [PriceChange(from: v.date, amount: v.amount)] }
        return r
    }
}

extension BankImportInfo {
    /// «heute», «gestern», «vor 5 Tagen», «vor 3 Wochen», «vor 2 Monaten» (Web `agoTxt`)
    public func agoText(today: Day) -> String {
        let n = at.days(to: today)
        if n <= 0 { return "heute" }
        if n == 1 { return "gestern" }
        if n < 14 { return "vor \(n) Tagen" }
        if n < 60 { return "vor \(Int(BU.round(Double(n) / 7))) Wochen" }
        let m = Int(BU.round(Double(n) / 30.44))
        return m < 2 ? "vor 1 Monat" : "vor \(m) Monaten"
    }

    /// Zeile «Kontoauszug einlesen» in Mehr → Daten (Web `paintBkRow`): Zeitraum und «vor … eingelesen · n Dateien»
    public var rangeText: String { BankImport.dot(from) + " – " + BankImport.dot(to) }

    public func agoLine(today: Day) -> String {
        agoText(today: today) + " eingelesen" + (files > 1 ? " · \(files) Dateien" : "")
    }
}

extension BankPayRow {
    /// Links: «01.01.2026 · neuer Preis», «… · einmalig», «… · keine Zahlung»
    public var label: String {
        BankImport.dot(date) + (amount == nil ? " · keine Zahlung" : (changed ? " · neuer Preis" : "") + (odd ? " · einmalig" : ""))
    }

    /// Rechts: Betrag bzw. «gratis»
    public func value(_ currency: String) -> String {
        amount.map { Format.money($0, Currency(rawValue: currency)) } ?? "gratis"
    }
}
