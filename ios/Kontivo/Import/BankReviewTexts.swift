import SwiftUI
import KontivoCore

/// Texte, Plaketten und Lohn-Nachfrage der Vorschlagsliste (Web bkTitle, bkSub, bkPer, bkChips, bkIncDev)
extension BankReview {
    // MARK: Texte (Web bkTitle, bkSub, bkPer)

    func title(_ it: Item) -> String {
        let l = it.ed.label
        return !l.isEmpty && Partners.lnorm(l) != Partners.lnorm(it.ed.name) ? l : it.ed.name
    }

    /// Zweite Zeile: Vertragspartner (falls oben die Bezeichnung steht), sonst die Kategorie (Web `bkSub`)
    func sub(_ it: Item, _ d: AppData) -> String {
        let e = it.ed
        return !e.label.isEmpty && Partners.lnorm(e.label) != Partners.lnorm(e.name) ? e.name : categoryName(it, d)
    }

    func incTitle(_ it: IncItem) -> String { it.ed.label.isEmpty ? it.ed.name : it.ed.label }

    func incSub(_ it: IncItem) -> String {
        let e = it.ed
        return !e.label.isEmpty && Partners.lnorm(e.label) != Partners.lnorm(e.name) ? e.name : e.kind.displayName
    }

    static let periods: [Int: String] = [1: "pro Monat", 2: "alle 2 Monate", 3: "pro Quartal", 6: "pro Halbjahr", 12: "pro Jahr", 24: "alle 2 Jahre"]
    static func per(_ c: Int) -> String { periods[c] ?? "alle \(c) Monate" }

    /// «05.09.2026» (Web `bkDay` = `fmtDot`)
    static func day(_ d: Day) -> String { BankImport.dot(d) }

    /// Plaketten und Zahlungsliste (Kern `BankReviewRules`)
    func chips(_ it: Item) -> [BankChip] {
        let s = it.s
        return BankImport.chips(dates: s.dates, amounts: s.amounts, count: s.count, last: s.last, lowConfidence: s.confidence == .low,
                                change: s.change, varies: s.varies, cycle: s.cycle, currency: s.currency, amount: it.ed.amount, income: false)
    }

    func chips(_ it: IncItem) -> [BankChip] {
        let s = it.s
        return BankImport.chips(dates: s.dates, amounts: s.amounts, count: s.count, last: s.last, lowConfidence: s.confidence == .low,
                                change: nil, varies: s.varies, cycle: s.cycle, currency: s.currency, amount: it.ed.amount, income: true)
    }

    /// Letzte Gutschrift weicht ab (Web `bkIncDev`)
    func deviation(_ it: IncItem) -> BankIncomeDeviation? {
        BankImport.incomeDeviation(dates: it.s.dates, amounts: it.s.amounts, amount: it.ed.amount, cycle: it.ed.cycle, edited: it.over != nil)
    }

    /// Betrag in der Zeile: bei «Neuer Lohn» die letzte Gutschrift
    func incAmount(_ it: IncItem) -> Double {
        if it.nl, let v = deviation(it) { return v.amount }
        return it.ed.amount
    }

    /// Lohn-Wörter in Bezeichnung, Name oder Art (Web: «als dein Lohn bisher», «Neuer Lohn»)
    static let rxWage = BRXLite("lohn|gehalt|salär|salaer")
    func isWage(_ it: IncItem) -> Bool {
        Self.rxWage.test(Partners.lnorm(it.ed.label + " " + it.ed.name + " " + it.ed.kind.displayName))
    }
}

/// Kleiner Regex-Test ohne Kern-Interna (BRX ist intern im Kern)
struct BRXLite: @unchecked Sendable {
    let re: NSRegularExpression?
    init(_ p: String) { re = try? NSRegularExpression(pattern: p) }
    func test(_ s: String) -> Bool {
        re?.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }
}
