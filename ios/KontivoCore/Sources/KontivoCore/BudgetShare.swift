import Foundation

/// «% der Einnahmen» im Budget: Einordnung des verbleibenden Anteils gegenüber üblichen Haushalten (Faustregeln, keine Bewertung).
/// Wie Web FQ/fqState/fqTips (index.html). Land nach Hauptwährung: CHF → Schweiz, sonst Deutschland.
/// DE: Nettolohn nach Steuern und KV → üblich bleiben 50–65 %. CH: Steuern und Krankenkasse sind Fixkosten → 35–50 %.
public enum BudgetShare {
    public enum Land: Sendable { case ch, de }
    public enum Level: Sendable, Equatable { case negative, low, edge, mid, high }

    public struct Range: Sendable, Equatable {
        public let lo: Int, hi: Int
        public let note: String
    }

    public static func land(_ home: Currency) -> Land { home == .CHF ? .ch : .de }

    public static func range(_ land: Land) -> Range {
        switch land {
        case .de: return Range(lo: 50, hi: 65, note: "Üblich in Deutschland: 50–65\u{00A0}% des Nettolohns.")
        case .ch: return Range(lo: 35, hi: 50, note: "Üblich in der Schweiz: 35–50\u{00A0}% des Nettolohns, nach Steuern und Krankenkasse.")
        }
    }

    /// Negativ (Fixkosten über Einnahmen), unter, am unteren Rand (bis 5 Punkte über der Untergrenze), im oder über dem Bereich
    public static func level(_ p: Int, _ r: Range) -> Level {
        if p < 0 { return .negative }
        if p < r.lo { return .low }
        if p > r.hi { return .high }
        return p < r.lo + 5 ? .edge : .mid
    }

    public static func headline(_ l: Level) -> (title: String, sub: String?) {
        switch l {
        case .negative: return ("Die Fixkosten übersteigen die Einnahmen.", "In diesem Monat, zum Beispiel wegen einer Jahresrechnung.")
        case .low: return ("Weniger als üblich.", "Bei höherem Einkommen oft kein Problem.")
        case .edge: return ("Im üblichen Bereich, am unteren Rand.", nil)
        case .mid: return ("Im üblichen Bereich.", nil)
        case .high: return ("Mehr als üblich.", nil)
        }
    }

    /// Jahresschnitt nur zeigen, wenn er um mind. 3 Punkte vom Monat abweicht
    public static func showAverage(month: Int, average: Int?) -> Bool {
        guard let a = average else { return false }
        return abs(a - month) >= 3
    }

    /// Tipps zeigen: unter dem Bereich, am Rand oder negativ
    public static func showsTips(_ l: Level) -> Bool { l == .negative || l == .low || l == .edge }

    /// «−12 %» bzw. «37 %» (Web: bq<0 ? "−"+(-bq) : bq)
    public static func percentText(_ p: Int) -> String { (p < 0 ? Format.minus + String(-p) : String(p)) + "\u{00A0}%" }

    /// Anteil ohne diesen Vertrag (Tipps «ohne: x %»): (verfügbar + Monatskosten) / Einnahmen, nil ohne Einnahmen.
    public static func withoutPercent(free: Double, income: Double, monthly: Double) -> Int? {
        guard income > 0.005 else { return nil }
        return Int(Format.jsRound((free + monthly) / income * 100))
    }

    /// Ansatzpunkte bei wenig Spielraum (Web fqTips): grösste beeinflussbare Fixkosten (ohne Steuern),
    /// Verträge mit Frist in 0–90 Tagen (nicht jederzeit kündbar, beobachtet, kein Pflichtvertrag, nicht gekündigt), Abos ab 2.
    public struct Tips: Sendable {
        public struct Top: Sendable { public let contractID: UUID; public let monthly: Double }
        public var top: [Top] = []
        public var soonCount = 0
        public var aboCount = 0
        public var aboMonthly = 0.0
        public var aboCategory: String?
    }

    public static func tips(_ calc: Calc, person: UUID?) -> Tips {
        let act = calc.running.filter { !calc.notStarted($0) && !calc.isTax($0) && calc.holderShare($0, person: person) > 0 }
        let val: (Contract) -> Double = { calc.monthlyCost($0) * calc.holderShare($0, person: person) }
        var t = Tips()
        t.top = act.map { Tips.Top(contractID: $0.id, monthly: val($0)) }.sorted { $0.monthly > $1.monthly }.prefix(3).map { $0 }
        t.soonCount = act.filter { c in
            if c.noWatch || c.mandatory || c.cancelPer != nil || calc.isAnytime(c) { return false }
            guard let dl = calc.noticeDeadline(c) else { return false }
            let n = calc.today.days(to: dl)
            return n >= 0 && n <= 90
        }.count
        let abos = act.filter { calc.categoryKind($0) == .media }
        if abos.count >= 2 {
            t.aboCount = abos.count
            t.aboMonthly = abos.reduce(0) { $0 + val($1) }
            t.aboCategory = calc.statKey(abos[0], .category)
        }
        return t
    }
}
