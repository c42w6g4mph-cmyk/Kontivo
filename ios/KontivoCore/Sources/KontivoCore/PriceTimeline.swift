import Foundation

// MARK: - Preisverlauf im Formular als Zeitstrahl (Web v314–v320: priceRowsHtml, tlPaint, bindPriceList, newRowBind)

/// Eine Stufe des Zeitstrahls (Preisänderung), Reihenfolge neueste zuerst.
public struct PriceTimelineRow: Hashable, Sendable, Identifiable {
    public var from: Day
    public var amount: Double
    /// Heute gültiger Preis (fett, Punkt in Messing)
    public var isCurrent: Bool
    /// Geplante Änderung (nach heute, Punkt gestrichelt)
    public var isFuture: Bool
    /// «aktuell», «geplant» oder ""
    public var status: String
    /// Veränderung zum vorherigen Betrag («+10 %»), nil ohne vorherigen Betrag
    public var pctText: String?
    /// Farbe der Prozentangabe: bei Verträgen teurer = up (rot), bei Einnahmen mehr = down (grün)
    public var pctTone: PriceChartTone
    /// «ab 01.03.27»
    public var dateText: String
    /// Unterzeile «aktuell · +10 %» (für Bedienungshilfen)
    public var subText: String { ([status] + (pctText.map { [$0] } ?? [])).filter { !$0.isEmpty }.joined(separator: " · ") }

    public var id: Day { from }
}

/// Aufbau des Betragsbereichs (gleich mit und ohne Preisänderungen, Web v319): Zeile «Währung», «+ Preisänderung»,
/// Stufen neueste zuerst, Startzeile zuletzt.
public struct PriceTimeline: Hashable, Sendable {
    /// Zeitstrahl sichtbar (ab 1 Preisänderung): Punkte und Linie
    public var on: Bool
    public var rows: [PriceTimelineRow]
    /// Startzeile: «Betrag» bzw. «Betrag netto»; mit Änderungen «ab 01.01.24» bzw. «Anfangspreis»/«Anfangsbetrag»
    public var startLabel: String
    /// Unterzeile der Startzeile («Anfangspreis»), nur mit Vertragsbeginn
    public var startSub: String
    /// Startzeile ist der heute gültige Betrag (alle Änderungen erst geplant)
    public var startIsCurrent: Bool
}

public enum PriceTimelineRules {
    /// Zeitstrahl aus Entwurf (Web `tlPaint` + `priceRowsHtml`). `base` = eingetippter Betrag (Anfangspreis), `income` = Einnahme.
    public static func make(prices: [PriceChange], base: Double, start: Day?, today: Day, income: Bool) -> PriceTimeline {
        let ps = Calc.sortedPrices(prices)
        var ni = -1
        for (i, p) in ps.enumerated() where p.from <= today { ni = i }
        var rows: [PriceTimelineRow] = []
        var prev = base.isFinite ? base : 0
        for (i, p) in ps.enumerated() {
            let fut = p.from > today
            let pc = prev != 0 ? (p.amount - prev) / prev * 100 : 0
            var tone = PriceChartTone.neutral
            if pc > 0.05 { tone = income ? .down : .up } else if pc < -0.05 { tone = income ? .up : .down }
            rows.append(PriceTimelineRow(from: p.from, amount: p.amount, isCurrent: i == ni, isFuture: fut,
                                         status: i == ni ? "aktuell" : (fut ? "geplant" : ""),
                                         pctText: prev != 0 ? Format.pctText(pc) : nil, pctTone: tone,
                                         dateText: "ab " + Format.fmtShort(p.from)))
            prev = p.amount
        }
        let on = !ps.isEmpty
        let first = income ? "Anfangsbetrag" : "Anfangspreis"
        let label: String
        if on {
            label = start.map { "ab " + Format.fmtShort($0) } ?? first
        } else {
            label = income ? "Betrag netto" : "Betrag"
        }
        return PriceTimeline(on: on, rows: rows.reversed(), startLabel: label, startSub: on && start != nil ? first : "",
                             startIsCurrent: on && ni < 0)
    }

    /// Ergebnis einer Änderung direkt in der Zeile
    public enum RowEdit: Equatable, Sendable {
        /// übernehmen (gerundeter Betrag bzw. neues Datum)
        case amount(Double)
        case date(Day)
        /// unverändert lassen
        case keep
        /// Meldung zeigen, Zeile zurücksetzen
        case reject(String)
    }

    /// Betrag einer Stufe geändert (Web `bindPriceList` change .pai)
    public static func editAmount(_ text: String) -> RowEdit {
        let t = text.trimmingCharacters(in: .whitespaces)
        guard let a = Format.parseAmount(t), a >= 0 else {
            return .reject(t.isEmpty ? "Betrag fehlt – zum Entfernen × tippen" : "Betrag prüfen")
        }
        return .amount(Format.round2(a))
    }

    /// Datum einer Stufe geändert (Web `bindPriceList` change .pdi): nach dem Beginn, nicht doppelt
    public static func editDate(_ new: Day, old: Day, start: Day?, prices: [PriceChange]) -> RowEdit {
        if new == old { return .keep }
        if let s = start, new <= s { return .reject("Datum muss nach dem Beginn liegen") }
        if prices.contains(where: { $0.from == new }) { return .reject("Am " + Format.fmtD(new) + " gibt es schon eine Änderung") }
        return .date(new)
    }

    /// Stufe mit Datum `old` auf neuen Betrag/neues Datum setzen
    public static func apply(_ e: RowEdit, to old: Day, in prices: [PriceChange]) -> [PriceChange] {
        var ps = prices
        guard let i = ps.firstIndex(where: { $0.from == old }) else { return ps }
        switch e {
        case .amount(let a): ps[i].amount = a
        case .date(let d): ps[i].from = d
        case .keep, .reject: break
        }
        return ps
    }
}
