import Foundation
import KontivoCore

// Kleine Rechenhilfen des Bereichs «Verträge», die der Bereich core in KontivoCore nachzieht.
// TODO(Integrator): sobald `Calc.payRule`, die Preisverlauf-Zusammenfassung und `Completeness` im Kern sind,
// die Aufrufe hier auf den Kern umstellen und diese Datei löschen.

enum CTLocalCalc {
    /// Zahlungsregel (Web `payRule`): «monatlich am 27.», «monatlich am Monatsende», «jährlich am 1. Januar».
    /// TODO(core): durch `Calc.payRule` ersetzen.
    static func payRule(due: Day?, cycle: Int) -> String {
        guard let a = due else { return "" }
        let m = cycle > 0 ? cycle : 1
        let cy = Format.cycleTextOrMonthly(m)
        if m >= 12 { return cy + " am \(a.day). " + Format.monthNames[a.month - 1] }
        return cy + (a.day >= 31 ? " am Monatsende" : " am \(a.day).")
    }

    /// Prozent wie Web `pctTxt`: «+12 %», «−0.5 %», «±0 %» (unter 1 % mit einer Nachkommastelle).
    static func pctText(_ p: Double) -> String {
        let a = abs(p)
        let sign = p > 0 ? "+" : (p < 0 ? Format.minus : "±")
        let num = (a > 0 && a < 1) ? Format.number(a, maxFractionDigits: 1) : String(Int(Format.jsRound(a)))
        return sign + num + " %"
    }

    /// Summe aller Zahlungen von Vertragsbeginn bis heute in Vertragswährung (Web `paidSoFar` im Detail); nil ohne Beginn.
    static func paidSoFar(_ c: Contract, calc: Calc) -> Double? {
        guard let s0 = c.start, s0 < calc.today else { return nil }
        let sum = calc.payments(c, from: s0, to: calc.today).reduce(0.0) { $0 + $1.amount }
        return sum > 0.005 ? sum : nil
    }
}

/// Fehlende Angaben eines Vertrags für den Hinweis im Detail (Web `vkNeeds(id).per[id]`).
/// TODO(core): durch `Completeness` aus KontivoCore ersetzen (dort inkl. `settings.logoSkip`, das hier noch fehlt).
enum CTCompletenessLocal {
    enum Need: String { case logo, term, snd }

    static func needs(_ c: Contract, data: AppData, calc: Calc, hasFile: (String) -> Bool) -> [Need] {
        guard calc.isActive(c), c.cancelPer == nil else { return [] }
        var r: [Need] = []
        if let p = data.partner(c.partnerID), !p.name.isEmpty {
            let has = data.partners.contains { $0.id == p.id && ($0.logoID.map { !$0.isEmpty && hasFile($0) } ?? false) }
            if !has { r.append(.logo) }
        }
        if termNeed(c, data: data, calc: calc) { r.append(.term) }
        if !calc.isFixed(c) && calc.cancVia(c) != .online {
            let missing = c.holderIDs.contains { h in
                let s = data.resolvedSender(h)
                return !((!s.first.isEmpty || !s.last.isEmpty) && !s.street.isEmpty && !s.city.isEmpty)
            }
            if missing { r.append(.snd) }
        }
        return r
    }

    /// Web `vkTermNeed`
    static func termNeed(_ c: Contract, data: AppData, calc: Calc) -> Bool {
        if c.cancelPer != nil || c.noWatch || c.mandatory || calc.isFixed(c) { return false }
        if data.settings.qualityIgnored.contains("c:" + c.id.uuidString + ":notice") { return false }
        if c.end != nil && c.renewMonths == 0 { return false }
        let anyNotice = c.end == nil && c.cancelTerm == .anytime && c.notice > 0
        if calc.noticeDeadline(c) == nil { return !anyNotice }
        let longTerm: Set<CancelTerm> = [.yearEnd, .contractYear, .quarterEnd, .halfYearEnd]
        return c.notice == 0 && (c.end != nil || longTerm.contains(c.cancelTerm))
    }

    /// Text des Hinweises (Web `vkHintHtml`)
    static func hint(_ r: [Need]) -> (title: String, sub: String) {
        let names: [Need: String] = [.logo: "Logo", .term: "Kündigungsfrist", .snd: "Absender-Adresse"]
        let why = r.contains(.term) ? "dann erinnert Kontivo rechtzeitig"
            : (r.contains(.snd) ? "dann ist die Kündigung startklar" : "dann sieht der Vertrag komplett aus")
        let title = r.count == 1 ? "1 Angabe fehlt noch" : "\(r.count) Angaben fehlen noch"
        return (title, r.compactMap { names[$0] }.joined(separator: " · ") + " – " + why)
    }
}
