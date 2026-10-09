import Foundation

// MARK: - Preisverlauf (Web `priceChart`, v99–v131)

/// Farbe einer Beschriftung bzw. der Plakette im Preisverlauf.
public enum PriceChartTone: String, Hashable, Sendable {
    case neutral, up, down
}

/// Ein Punkt des Preisverlaufs (Index 0 = Anfangspreis).
public struct PriceChartPoint: Hashable, Sendable, Identifiable {
    public var index: Int
    public var date: Day
    public var amount: Double
    /// Lage auf der x-Achse 0…1 (wie die SVG-Koordinaten der Web-App, gleiche Zeitspanne)
    public var x: Double
    /// Heute gültiger Preis (grösserer Punkt)
    public var isNow: Bool
    /// Geplante Änderung (nach heute, gestrichelt)
    public var isFuture: Bool
    /// Beschriftungen zeigen (von hinten nach vorn, nur mit genug Abstand zum nächsten beschrifteten Punkt)
    public var labeled: Bool
    /// «59.90» bzw. «59,90» (EUR); Preis 0 → «gratis»
    public var valueText: String
    /// «01.03.27»; beim Anfangspreis ohne Vertragsbeginn «Anfang»
    public var dateText: String
    /// Veränderung zum vorherigen Preis («+5 %»); nil beim Anfangspreis und nach einer Gratis-Phase
    public var pctText: String?
    public var pctTone: PriceChartTone

    public var id: Int { index }
}

/// Fertig berechneter Preisverlauf für das Diagramm im Vertragsdetail (Swift Charts zeichnet nur noch).
public struct PriceChart: Hashable, Sendable {
    public var points: [PriceChartPoint]
    /// Beginn der x-Achse (Vertragsbeginn bzw. erste Änderung − max(180 Tage, 25 % der Spanne))
    public var start: Day
    /// Ende der x-Achse (heute bzw. letzte Änderung + max(45 Tage, 10 %))
    public var end: Day
    /// Heute als x-Lage 0…1 (Linie bis hier durchgezogen, danach gestrichelt), höchstens 1
    public var todayX: Double
    /// Index des heute gültigen Preises
    public var nowIndex: Int
    /// y-Achse mit 8 % Rand
    public var minValue: Double
    public var maxValue: Double
    /// Kopf links: «seit 01.03.24» bzw. «seit Anfang»
    public var sinceText: String
    /// Plakette: «geplant ab 01.03.27», «vorher gratis», «unverändert», «↑ 5 % teurer», «↓ 3 % günstiger»
    public var badgeText: String
    public var badgeTone: PriceChartTone
    /// «Preisverlauf von 59.90 auf 64.90 CHF»
    public var accessibilityLabel: String
}

extension Calc {
    /// Breite der Web-Grafik (viewBox 320, Rand 4) für die Abstandsregel der Beschriftungen (66 Einheiten).
    static let priceChartWidth = 312.0
    static let priceChartLabelGap = 66.0

    /// Preisverlauf eines Vertrags (nur mit mindestens einer Preisänderung), 1:1 wie Web `priceChart`:
    /// Preise nach echtem Datum, Plakette = heute gegenüber dem Anfang (Entscheid: auch «unverändert», wenn zwischendurch geändert),
    /// Preis 0 als «gratis», nach einer Gratis-Phase keine Prozentangabe.
    public func priceChart(_ c: Contract) -> PriceChart? {
        let ps = pricesOf(c)
        guard let firstP = ps.first, let lastP = ps.last else { return nil }
        let t = today
        let base0 = c.amount.isFinite ? c.amount : 0
        // Zeit in Tagen ab der ersten Änderung (Bruchteile wie die Millisekunden der Web-App)
        let first = firstP.from, last = lastP.from
        func dn(_ d: Day) -> Double { Double(first.days(to: d)) }
        let lastN = dn(last)
        var hasSt = false
        let stN: Double
        let stDay: Day
        if let s = c.start, s < first {
            hasSt = true
            stN = dn(s)
            stDay = s
        } else {
            let span = Swift.max(180, lastN * 0.25)
            stN = -span
            stDay = first.addingDays(-Int(span.rounded(.up)))
        }
        let tN = dn(t)
        let mxN = Swift.max(tN, lastN)
        let endN = mxN + Swift.max(45, (mxN - stN) * 0.1)
        let endDay = first.addingDays(Int(endN.rounded(.down)))
        let range = endN - stN
        func X(_ n: Double) -> Double { range > 0 ? (n - stN) / range : 0 }

        // Werte: Anfangspreis + Stufen
        var raw: [(d: Day, n: Double, a: Double)] = [(stDay, stN, base0)]
        for p in ps { raw.append((p.from, dn(p.from), p.amount)) }
        var ni = 0
        for (i, p) in raw.enumerated() where p.n <= tN { ni = i }
        var mn = raw.map { $0.a }.min() ?? 0
        var mx = raw.map { $0.a }.max() ?? 0
        if mx == mn { mx += 1; mn -= 1 }
        let pad = (mx - mn) * 0.08
        mn -= pad
        mx += pad

        // Beschriftung: von hinten nach vorn, nur mit genug Abstand
        var show = Set<Int>()
        var lastX = 1e9
        for k in stride(from: raw.count - 1, through: 0, by: -1) {
            let xk = X(raw[k].n) * Calc.priceChartWidth
            if lastX - xk >= Calc.priceChartLabelGap {
                show.insert(k)
                lastX = xk
            }
        }
        var points: [PriceChartPoint] = []
        for (i, p) in raw.enumerated() {
            var pct: String? = nil
            var tone = PriceChartTone.neutral
            if i > 0 && raw[i - 1].a != 0 {
                let pc = (p.a - raw[i - 1].a) / raw[i - 1].a * 100
                pct = Format.pctText(pc)
                tone = pc > 0 ? .up : (pc < 0 ? .down : .neutral)
            }
            points.append(PriceChartPoint(index: i, date: p.d, amount: p.a, x: X(p.n), isNow: i == ni, isFuture: p.n > tN,
                                          labeled: show.contains(i),
                                          valueText: p.a != 0 ? Format.money(p.a, c.currency) : "gratis",
                                          dateText: i > 0 || hasSt ? Format.fmtShort(p.d) : "Anfang",
                                          pctText: pct, pctTone: tone))
        }

        let planned = ni == 0
        let cur = raw[ni].a, base = raw[0].a
        let pct = base != 0 ? (cur - base) / base * 100 : 0
        var badge: String
        var bTone = PriceChartTone.neutral
        if planned {
            badge = "geplant ab " + Format.fmtShort(raw[1].d)
        } else if base == 0 && cur > 0 {
            badge = "vorher gratis"
            bTone = .up
        } else if Swift.abs(pct) < 0.05 {
            badge = "unverändert"
        } else {
            var p = Format.pctText(Swift.abs(pct))
            if p.hasPrefix("+") || p.hasPrefix("±") { p.removeFirst() }
            badge = (pct > 0 ? "↑ " : "↓ ") + p + (pct > 0 ? " teurer" : " günstiger")
            bTone = pct > 0 ? .up : .down
        }
        return PriceChart(points: points, start: stDay, end: endDay, todayX: Swift.min(1, X(Swift.min(tN, endN))), nowIndex: ni,
                          minValue: mn, maxValue: mx,
                          sinceText: hasSt ? "seit " + Format.fmtShort(stDay) : "seit Anfang",
                          badgeText: badge, badgeTone: bTone,
                          accessibilityLabel: "Preisverlauf von " + Format.money(base, c.currency) + " auf "
                            + Format.money(raw[raw.count - 1].a, c.currency) + " " + c.currency.rawValue)
    }
}
