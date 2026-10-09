import SwiftUI
import KontivoCore

/// Preisverlauf als Stufen-Diagramm (Web priceChart, v99–v131), nur bei mind. 1 Preisänderung. Reine Ansicht (nicht antippbar).
/// Oben «seit …» und Plakette (heute zum Anfang). An jedem Punkt Preis darüber, Datum und Prozent zum vorherigen Preis darunter,
/// alle Beschriftungen auf den Punkt zentriert (am Rand eingerückt); Preis 0 = «gratis», nach einer Gratis-Phase keine Prozentangabe.
struct CTPriceChart: View {
    let contract: Contract
    let today: Day

    var body: some View {
        // TODO(core): Zusammenfassung (seit/Plakette) aus dem Kern übernehmen, sobald vorhanden
        if let m = CTPriceChartModel(contract: contract, today: today) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text(verbatim: m.since)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                    Spacer(minLength: 8)
                    Text(verbatim: m.badge)
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(tone(m.badgeTone, neutral: KColor.ink2))
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(tone(m.badgeTone, neutral: KColor.ink).opacity(m.badgeTone == 0 ? 0.07 : 0.15)))
                        .lineLimit(1)
                        .accessibilityIdentifier("chart.badge")
                }
                CTPriceChartCanvas(m: m)
                    .aspectRatio(CTPriceChartModel.W / CTPriceChartModel.H, contentMode: .fit)
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
            .background(KColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: m.accessibility))
            .accessibilityIdentifier("detail.priceChart")
        }
    }

    private func tone(_ t: Int, neutral: Color) -> Color {
        t > 0 ? KColor.warn : (t < 0 ? KColor.ok : neutral)
    }
}

/// Zeichnung im Koordinatensystem der Web-App (320 × 132), auf die verfügbare Breite skaliert
private struct CTPriceChartCanvas: View {
    let m: CTPriceChartModel

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / CTPriceChartModel.W
            let P = { (p: CGPoint) in CGPoint(x: p.x * s, y: p.y * s) }
            ZStack(alignment: .topLeading) {
                // Fläche unter der Linie bis heute
                Path { path in
                    guard let f = m.area.first else { return }
                    path.move(to: P(f))
                    for q in m.area.dropFirst() { path.addLine(to: P(q)) }
                    path.closeSubpath()
                }
                .fill(KColor.teal.opacity(0.12))
                // Hilfslinien von den Punkten zur Grundlinie
                ForEach(m.points.filter { $0.index > 0 }) { p in
                    Path { path in
                        path.move(to: P(CGPoint(x: p.x, y: p.y + 5)))
                        path.addLine(to: P(CGPoint(x: p.x, y: CTPriceChartModel.B)))
                    }
                    .stroke(KColor.line, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                line(m.past, P).stroke(KColor.teal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if !m.future.isEmpty {
                    line(m.future, P).stroke(KColor.teal.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                }
                ForEach(m.points) { p in
                    let r: CGFloat = (p.now ? 4.5 : 3.5) * s
                    Circle()
                        .fill(p.now ? KColor.teal : KColor.field)
                        .overlay(Circle().strokeBorder(p.future ? KColor.warn : KColor.teal, lineWidth: 2))
                        .frame(width: r * 2, height: r * 2)
                        .position(P(CGPoint(x: p.x, y: p.y)))
                }
                ForEach(m.points.filter { $0.label }) { p in
                    Text(verbatim: p.priceText)
                        .font(.system(size: (p.now ? 12.5 : 11) * s, weight: p.now ? .bold : .semibold))
                        .foregroundStyle(p.now ? KColor.teal : KColor.ink2)
                        .monospacedDigit()
                        .fixedSize()
                        .position(P(CGPoint(x: CTPriceChartModel.cx(p.x, p.priceText, p.now ? 12.5 : 11), y: p.y - 13)))
                    Text(verbatim: p.dateText)
                        .font(.system(size: 10.5 * s))
                        .foregroundStyle(KColor.ink3)
                        .monospacedDigit()
                        .fixedSize()
                        .position(P(CGPoint(x: CTPriceChartModel.cx(p.x, p.dateText, 10.5), y: CTPriceChartModel.B + 10)))
                    if let pc = p.pctText {
                        Text(verbatim: pc)
                            .font(.system(size: 11 * s, weight: .bold))
                            .foregroundStyle(p.pctTone > 0 ? KColor.warn : (p.pctTone < 0 ? KColor.ok : KColor.ink3))
                            .monospacedDigit()
                            .fixedSize()
                            .position(P(CGPoint(x: CTPriceChartModel.cx(p.x, pc, 11), y: CTPriceChartModel.B + 25)))
                    }
                }
            }
        }
    }

    private func line(_ pts: [CGPoint], _ P: @escaping (CGPoint) -> CGPoint) -> Path {
        Path { path in
            guard let f = pts.first else { return }
            path.move(to: P(f))
            for q in pts.dropFirst() { path.addLine(to: P(q)) }
        }
    }
}

/// Rechenteil des Diagramms (wie Web priceChart), unabhängig von der Breite (Koordinaten 320 × 132)
struct CTPriceChartModel {
    static let W: CGFloat = 320
    static let H: CGFloat = 132
    static let L: CGFloat = 4
    static let R: CGFloat = 316
    static let T: CGFloat = 26
    static let B: CGFloat = 96

    struct Point: Identifiable {
        let index: Int
        let day: Day
        let amount: Double
        let x: CGFloat
        let y: CGFloat
        let future: Bool
        let now: Bool
        let label: Bool
        let priceText: String
        let dateText: String
        let pctText: String?
        /// 1 teurer, −1 günstiger, 0 gleich
        let pctTone: Int
        var id: Int { index }
    }

    var points: [Point] = []
    /// Linie bis heute (durchgezogen) und danach (gestrichelt), als Eckpunkte
    var past: [CGPoint] = []
    var future: [CGPoint] = []
    var area: [CGPoint] = []
    var since: String
    var badge: String
    /// 1 teurer, −1 günstiger, 0 neutral
    var badgeTone: Int
    var accessibility: String

    /// Text auf den Punkt zentriert, am Rand eingerückt (Web cx)
    static func cx(_ x: CGFloat, _ txt: String, _ fs: CGFloat) -> CGFloat {
        let hw = CGFloat(txt.count) * fs * 0.29
        return max(L + hw, min(R - hw, x))
    }

    init?(contract c: Contract, today t: Day) {
        let ps = c.prices.filter { $0.amount.isFinite }.ctStableSorted { $0.from < $1.from }
        guard let first = ps.first, let lastP = ps.last else { return nil }
        let base = c.amount.isFinite ? c.amount : 0
        // Start: Vertragsbeginn vor der ersten Stufe, sonst erste Stufe − max(180 Tage, 25 % der Spanne)
        var st: Day
        var hasSt = false
        if let s = c.start, s < first.from {
            st = s
            hasSt = true
        } else {
            let span = max(180, Int((Double(first.from.days(to: lastP.from)) * 0.25).rounded(.down)))
            st = first.from.addingDays(-span)
        }
        let maxTL = t > lastP.from ? t : lastP.from
        let extra = max(45.0, Double(st.days(to: maxTL)) * 0.1)
        let total = max(1.0, Double(st.days(to: maxTL)) + extra)
        func X(_ d: Day) -> CGFloat { CTPriceChartModel.L + (CTPriceChartModel.R - CTPriceChartModel.L) * CGFloat(Double(st.days(to: d)) / total) }
        let xEnd = CTPriceChartModel.R

        var pts: [(d: Day, a: Double)] = [(st, base)]
        for p in ps { pts.append((p.from, p.amount)) }
        let vals = pts.map { $0.a }
        var mn = vals.min() ?? 0
        var mx = vals.max() ?? 1
        if mx == mn { mx += 1; mn -= 1 }
        let pad = (mx - mn) * 0.08
        mn -= pad
        mx += pad
        func Y(_ v: Double) -> CGFloat {
            CTPriceChartModel.B - (CTPriceChartModel.B - CTPriceChartModel.T) * CGFloat((v - mn) / (mx - mn))
        }
        var ni = 0
        for (i, p) in pts.enumerated() where p.d <= t { ni = i }

        // Linien (Web pathP/pathF)
        let xCut = min(X(t), xEnd)
        var pathP: [CGPoint] = [CGPoint(x: X(st), y: Y(pts[0].a))]
        var pathF: [CGPoint] = []
        for i in 1..<pts.count {
            let x = X(pts[i].d)
            let yPrev = Y(pts[i - 1].a)
            let y = Y(pts[i].a)
            if pts[i].d <= t {
                pathP.append(CGPoint(x: x, y: yPrev))
                pathP.append(CGPoint(x: x, y: y))
            } else {
                if pathF.isEmpty {
                    pathP.append(CGPoint(x: xCut, y: yPrev))
                    pathF.append(CGPoint(x: xCut, y: yPrev))
                }
                pathF.append(CGPoint(x: x, y: yPrev))
                pathF.append(CGPoint(x: x, y: y))
            }
        }
        if pathF.isEmpty {
            if let l = pathP.last { pathP.append(CGPoint(x: xEnd, y: l.y)) }
        } else if let l = pathF.last {
            pathF.append(CGPoint(x: xEnd, y: l.y))
        }
        past = pathP
        future = pathF
        if let l = pathP.last {
            area = pathP + [CGPoint(x: l.x, y: CTPriceChartModel.B), CGPoint(x: X(st), y: CTPriceChartModel.B)]
        }

        // Beschriftung: von hinten nach vorn, nur mit genug Abstand zum nächsten beschrifteten Punkt
        var show = Set<Int>()
        var lastX: CGFloat = 1e9
        for k in stride(from: pts.count - 1, through: 0, by: -1) {
            let xk = X(pts[k].d)
            if lastX - xk >= 66 {
                show.insert(k)
                lastX = xk
            }
        }
        var out: [Point] = []
        for (i, p) in pts.enumerated() {
            let pv = p.a != 0 ? Format.money(p.a) : "gratis"
            let dt = i > 0 ? Format.fmtShort(p.d) : (hasSt ? Format.fmtShort(p.d) : "Anfang")
            var pc: String?
            var tone = 0
            if i > 0 && pts[i - 1].a != 0 {
                let v = (p.a - pts[i - 1].a) / pts[i - 1].a * 100
                pc = CTLocalCalc.pctText(v)
                tone = v > 0 ? 1 : (v < 0 ? -1 : 0)
            }
            out.append(Point(index: i, day: p.d, amount: p.a, x: X(p.d), y: Y(p.a), future: p.d > t, now: i == ni,
                             label: show.contains(i), priceText: pv, dateText: dt, pctText: pc, pctTone: tone))
        }
        points = out

        // Kopf: «seit …» und Plakette heute zum Anfang (auch «unverändert», wenn zwischendurch geändert)
        let planned = ni == 0
        let cur = pts[ni].a
        let pct = base != 0 ? (cur - base) / base * 100 : 0
        since = hasSt ? "seit " + Format.fmtShort(st) : "seit Anfang"
        if planned {
            badge = "geplant ab " + Format.fmtShort(pts[1].d)
            badgeTone = 0
        } else if base == 0 && cur > 0 {
            badge = "vorher gratis"
            badgeTone = 1
        } else if abs(pct) < 0.05 {
            badge = "unverändert"
            badgeTone = 0
        } else {
            var txt = CTLocalCalc.pctText(abs(pct))
            if txt.hasPrefix("+") || txt.hasPrefix("±") { txt.removeFirst() }
            badge = (pct > 0 ? "↑ " : "↓ ") + txt + (pct > 0 ? " teurer" : " günstiger")
            badgeTone = pct > 0 ? 1 : -1
        }
        accessibility = "Preisverlauf von " + Format.money(base) + " auf " + Format.money(lastP.amount) + " " + c.currency.rawValue
            + ", " + badge
    }
}
