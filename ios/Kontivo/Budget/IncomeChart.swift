import SwiftUI
import KontivoCore

/// Verlauf einer Einnahme (Web v155 `priceChart(c, {inc:1})`): zeichnet den fertig berechneten `PriceChart` aus dem Kern
/// (`Calc.priceChart(_ i: Income)` bzw. `Calc.priceChart(amount:prices:start:currency:income:)` für den Formular-Entwurf).
/// Bei Einnahmen ist mehr gut: Plakette «↑ 5 % mehr» grün, «↓ 3 % weniger» orange (Farben aus dem Kern: `.up` = ungünstig).
/// Eigene kleine Hülle (statt `CTPriceChart` des Vertrags), Gestaltung wie dort: Koordinaten der Web-Grafik 320 × 132.
struct KBIncomeChart: View {
    let chart: PriceChart
    var identifier = "income.chart"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(verbatim: chart.sinceText)
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                Spacer(minLength: 8)
                Text(verbatim: chart.badgeText)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(KBIncomeChart.color(chart.badgeTone, neutral: KColor.ink2))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(KBIncomeChart.color(chart.badgeTone, neutral: KColor.ink)
                        .opacity(chart.badgeTone == .neutral ? 0.07 : 0.15)))
                    .lineLimit(1)
                    .accessibilityIdentifier(identifier + ".badge")
            }
            KBIncomeChartCanvas(chart: chart)
                .aspectRatio(KBIncomeChartCanvas.W / KBIncomeChartCanvas.H, contentMode: .fit)
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 8)
        .background(KColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: chart.accessibilityLabel + ", " + chart.badgeText))
        .accessibilityIdentifier(identifier)
    }

    /// Farbe einer Tönung: ungünstig orange, günstig grün
    static func color(_ t: PriceChartTone, neutral: Color) -> Color {
        switch t {
        case .up: return KColor.warn
        case .down: return KColor.ok
        case .neutral: return neutral
        }
    }
}

/// Zeichnung im Koordinatensystem der Web-App (320 × 132), auf die verfügbare Breite skaliert
struct KBIncomeChartCanvas: View {
    let chart: PriceChart

    static let W: CGFloat = 320
    static let H: CGFloat = 132
    static let L: CGFloat = 4
    static let R: CGFloat = 316
    static let T: CGFloat = 26
    static let B: CGFloat = 96

    /// x-Lage 0…1 → Koordinate
    private func X(_ x: Double) -> CGFloat { Self.L + (Self.R - Self.L) * CGFloat(x) }

    private func Y(_ v: Double) -> CGFloat {
        let span = chart.maxValue - chart.minValue
        guard span != 0 else { return (Self.B + Self.T) / 2 }
        return Self.B - (Self.B - Self.T) * CGFloat((v - chart.minValue) / span)
    }

    /// Text auf den Punkt zentriert, am Rand eingerückt (Web cx)
    private static func cx(_ x: CGFloat, _ txt: String, _ fs: CGFloat) -> CGFloat {
        let hw = CGFloat(txt.count) * fs * 0.29
        return max(L + hw, min(R - hw, x))
    }

    /// Linien bis heute (durchgezogen) und danach (gestrichelt) als Eckpunkte (Web pathP/pathF)
    private var lines: (past: [CGPoint], future: [CGPoint]) {
        let pts = chart.points
        guard let first = pts.first else { return ([], []) }
        let xCut = X(chart.todayX)
        var pathP: [CGPoint] = [CGPoint(x: X(first.x), y: Y(first.amount))]
        var pathF: [CGPoint] = []
        for i in pts.indices.dropFirst() {
            let x = X(pts[i].x)
            let yPrev = Y(pts[i - 1].amount)
            let y = Y(pts[i].amount)
            if !pts[i].isFuture {
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
            if let l = pathP.last { pathP.append(CGPoint(x: Self.R, y: l.y)) }
        } else if let l = pathF.last {
            pathF.append(CGPoint(x: Self.R, y: l.y))
        }
        return (pathP, pathF)
    }

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / Self.W
            let P = { (p: CGPoint) in CGPoint(x: p.x * s, y: p.y * s) }
            let ln = lines
            ZStack(alignment: .topLeading) {
                // Fläche unter der Linie bis heute
                Path { path in
                    guard let f = ln.past.first, let l = ln.past.last else { return }
                    path.move(to: P(f))
                    for q in ln.past.dropFirst() { path.addLine(to: P(q)) }
                    path.addLine(to: P(CGPoint(x: l.x, y: Self.B)))
                    path.addLine(to: P(CGPoint(x: f.x, y: Self.B)))
                    path.closeSubpath()
                }
                .fill(KColor.teal.opacity(0.12))
                // Hilfslinien von den Punkten zur Grundlinie
                ForEach(chart.points.filter { $0.index > 0 }) { p in
                    Path { path in
                        path.move(to: P(CGPoint(x: X(p.x), y: Y(p.amount) + 5)))
                        path.addLine(to: P(CGPoint(x: X(p.x), y: Self.B)))
                    }
                    .stroke(KColor.line, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                polyline(ln.past, P).stroke(KColor.teal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if !ln.future.isEmpty {
                    polyline(ln.future, P).stroke(KColor.teal.opacity(0.7),
                                                  style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                }
                ForEach(chart.points) { p in
                    let r: CGFloat = (p.isNow ? 4.5 : 3.5) * s
                    Circle()
                        .fill(p.isNow ? KColor.teal : KColor.field)
                        .overlay(Circle().strokeBorder(p.isFuture ? KColor.warn : KColor.teal, lineWidth: 2))
                        .frame(width: r * 2, height: r * 2)
                        .position(P(CGPoint(x: X(p.x), y: Y(p.amount))))
                }
                ForEach(chart.points.filter { $0.labeled }) { p in
                    labels(p, s: s, P: P)
                }
            }
        }
    }

    @ViewBuilder
    private func labels(_ p: PriceChartPoint, s: CGFloat, P: @escaping (CGPoint) -> CGPoint) -> some View {
        let x = X(p.x)
        let y = Y(p.amount)
        let fs: CGFloat = p.isNow ? 12.5 : 11
        let value = Text(verbatim: p.valueText)
            .font(.system(size: fs * s, weight: p.isNow ? .bold : .semibold))
            .foregroundStyle(p.isNow ? KColor.teal : KColor.ink2)
            .monospacedDigit()
            .fixedSize()
        if p.labelTrailing {
            // Preissenkung: Zahl links bündig rechts neben die senkrechte Linie (Web v153 dropL)
            let px = min(Self.R - CGFloat(p.valueText.count) * 11 * 0.58, x + 5)
            value
                .frame(width: 200 * s, alignment: .leading)
                .position(P(CGPoint(x: px + 100, y: y - 13)))
        } else {
            value.position(P(CGPoint(x: Self.cx(x, p.valueText, fs), y: y - 13)))
        }
        Text(verbatim: p.dateText)
            .font(.system(size: 10.5 * s))
            .foregroundStyle(KColor.ink3)
            .monospacedDigit()
            .fixedSize()
            .position(P(CGPoint(x: Self.cx(x, p.dateText, 10.5), y: Self.B + 10)))
        if let pc = p.pctText {
            Text(verbatim: pc)
                .font(.system(size: 11 * s, weight: .bold))
                .foregroundStyle(KBIncomeChart.color(p.pctTone, neutral: KColor.ink3))
                .monospacedDigit()
                .fixedSize()
                .position(P(CGPoint(x: Self.cx(x, pc, 11), y: Self.B + 25)))
        }
    }

    private func polyline(_ pts: [CGPoint], _ P: @escaping (CGPoint) -> CGPoint) -> Path {
        Path { path in
            guard let f = pts.first else { return }
            path.move(to: P(f))
            for q in pts.dropFirst() { path.addLine(to: P(q)) }
        }
    }
}
