import SwiftUI
import KontivoCore

/// Preisverlauf als Stufen-Diagramm (Web `priceChart`, v99–v160), nur bei mind. 1 Preisänderung. Reine Ansicht (nicht antippbar).
/// Rechnung im Kern (`Calc.priceChart`, auch für den Formular-Entwurf `Calc.priceChart(amount:prices:start:currency:income:)`),
/// hier nur das Zeichnen: oben «seit …» und Plakette (heute zum Anfang), an jedem beschrifteten Punkt Preis darüber, Datum und
/// Prozent zum vorherigen Preis darunter; Preissenkung rechts neben der senkrechten Linie (v153).
struct CTPriceChart: View {
    @Environment(AppModel.self) private var model
    private let contract: Contract?
    private let given: PriceChart?
    private let identifier: String
    /// Eigene Fläche (Detail); im Formular sitzt das Diagramm direkt in der Karte (Web `.fcard .pchart` transparent)
    private let framed: Bool

    /// Verlauf eines gespeicherten Vertrags (Detail, Vertragspartner)
    init(contract: Contract, today: Day, identifier: String = "detail.priceChart", framed: Bool = true) {
        self.contract = contract
        given = nil
        self.identifier = identifier
        self.framed = framed
    }

    /// Fertig gerechneter Verlauf (Formular-Entwurf)
    init(chart: PriceChart, identifier: String = "form.priceChart", framed: Bool = false) {
        contract = nil
        given = chart
        self.identifier = identifier
        self.framed = framed
    }

    var body: some View {
        if let m = given ?? contract.flatMap({ model.calc.priceChart($0) }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    // Web `.pchead`: 12.5 px Tinte 2 (Zeile 18.125); `.pbadge` 14/650 (Zeile 20.3), 4/10, neutral in Tinte
                    Text(verbatim: m.sinceText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(KColor.ink2)
                        .ctLine(18.125)
                    Spacer(minLength: 8)
                    Text(verbatim: m.badgeText)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(tone(m.badgeTone, neutral: KColor.ink))
                        .ctLine(20.3)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Capsule().fill(tone(m.badgeTone, neutral: KColor.ink).opacity(m.badgeTone == .neutral ? 0.07 : 0.15)))
                        .lineLimit(1)
                        .accessibilityIdentifier("chart.badge")
                }
                CTPriceChartCanvas(chart: m)
                    .aspectRatio(CTPriceChartCanvas.W / CTPriceChartCanvas.H, contentMode: .fit)
            }
            .padding(.horizontal, framed ? 12 : 0).padding(.top, framed ? 12 : 4).padding(.bottom, framed ? 8 : 0)
            .background(framed ? KColor.field : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: m.accessibilityLabel + ", " + m.badgeText))
            .accessibilityIdentifier(identifier)
        }
    }

    private func tone(_ t: PriceChartTone, neutral: Color) -> Color {
        switch t {
        case .up: return KColor.warn
        case .down: return KColor.ok
        case .neutral: return neutral
        }
    }
}

/// Zeichnung im Koordinatensystem der Web-App (SVG 320 × 132, Rand 4, oben 26, Grundlinie 96), auf die Breite skaliert
struct CTPriceChartCanvas: View {
    let chart: PriceChart

    static let W: CGFloat = 320
    static let H: CGFloat = 132
    static let L: CGFloat = 4
    static let R: CGFloat = 316
    static let T: CGFloat = 26
    static let B: CGFloat = 96

    private func X(_ x: Double) -> CGFloat { CTPriceChartCanvas.L + (CTPriceChartCanvas.R - CTPriceChartCanvas.L) * CGFloat(x) }

    private func Y(_ v: Double) -> CGFloat {
        let span = chart.maxValue - chart.minValue
        let f = span != 0 ? (v - chart.minValue) / span : 0.5
        return CTPriceChartCanvas.B - (CTPriceChartCanvas.B - CTPriceChartCanvas.T) * CGFloat(f)
    }

    /// Text auf den Punkt zentriert, am Rand eingerückt (Web `cx`)
    private static func cx(_ x: CGFloat, _ txt: String, _ fs: CGFloat) -> CGFloat {
        let hw = CGFloat(txt.count) * fs * 0.29
        return max(L + hw, min(R - hw, x))
    }

    /// Linie bis heute (durchgezogen) und danach (gestrichelt), als Eckpunkte (Web pathP/pathF)
    private var lines: (past: [CGPoint], future: [CGPoint]) {
        let pts = chart.points
        guard let p0 = pts.first else { return ([], []) }
        let xCut = X(chart.todayX)
        var past: [CGPoint] = [CGPoint(x: X(p0.x), y: Y(p0.amount))]
        var fut: [CGPoint] = []
        for i in pts.indices.dropFirst() {
            let x = X(pts[i].x), yPrev = Y(pts[i - 1].amount), y = Y(pts[i].amount)
            if !pts[i].isFuture {
                past.append(CGPoint(x: x, y: yPrev))
                past.append(CGPoint(x: x, y: y))
            } else {
                if fut.isEmpty {
                    past.append(CGPoint(x: xCut, y: yPrev))
                    fut.append(CGPoint(x: xCut, y: yPrev))
                }
                fut.append(CGPoint(x: x, y: yPrev))
                fut.append(CGPoint(x: x, y: y))
            }
        }
        if fut.isEmpty {
            if let l = past.last { past.append(CGPoint(x: CTPriceChartCanvas.R, y: l.y)) }
        } else if let l = fut.last {
            fut.append(CGPoint(x: CTPriceChartCanvas.R, y: l.y))
        }
        return (past, fut)
    }

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / CTPriceChartCanvas.W
            let P = { (p: CGPoint) in CGPoint(x: p.x * s, y: p.y * s) }
            let ln = lines
            let pts = chart.points
            ZStack(alignment: .topLeading) {
                // Fläche unter der Linie bis heute
                Path { path in
                    guard let f = ln.past.first, let l = ln.past.last else { return }
                    path.move(to: P(f))
                    for q in ln.past.dropFirst() { path.addLine(to: P(q)) }
                    path.addLine(to: P(CGPoint(x: l.x, y: CTPriceChartCanvas.B)))
                    path.addLine(to: P(CGPoint(x: f.x, y: CTPriceChartCanvas.B)))
                    path.closeSubpath()
                }
                .fill(KColor.teal.opacity(0.12))
                // Hilfslinien von den Punkten zur Grundlinie
                ForEach(pts.filter { $0.index > 0 }) { p in
                    Path { path in
                        path.move(to: P(CGPoint(x: X(p.x), y: Y(p.amount) + 5)))
                        path.addLine(to: P(CGPoint(x: X(p.x), y: CTPriceChartCanvas.B)))
                    }
                    .stroke(KColor.line, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                polyline(ln.past, P).stroke(KColor.teal, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if !ln.future.isEmpty {
                    polyline(ln.future, P).stroke(KColor.teal.opacity(0.7), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [4, 4]))
                }
                ForEach(pts) { p in
                    let r: CGFloat = (p.isNow ? 4.5 : 3.5) * s
                    Circle()
                        .fill(p.isNow ? KColor.teal : KColor.field)
                        .overlay(Circle().strokeBorder(p.isFuture ? KColor.warn : KColor.teal, lineWidth: 2))
                        .frame(width: r * 2, height: r * 2)
                        .position(P(CGPoint(x: X(p.x), y: Y(p.amount))))
                }
                ForEach(pts.filter { $0.labeled }) { p in
                    let x = X(p.x), y = Y(p.amount)
                    let fs: CGFloat = p.isNow ? 12.5 : 11
                    // Preissenkung: Zahl links bündig rechts neben die senkrechte Linie (Web v153 `dropL`)
                    let vx = p.labelTrailing
                        ? min(CTPriceChartCanvas.R - CGFloat(p.valueText.count) * 11 * 0.58, x + 5) + CGFloat(p.valueText.count) * fs * 0.29
                        : CTPriceChartCanvas.cx(x, p.valueText, fs)
                    Text(verbatim: p.valueText)
                        .font(.system(size: fs * s, weight: p.isNow ? .bold : .semibold))
                        .foregroundStyle(p.isNow ? KColor.teal : KColor.ink2)
                        .monospacedDigit()
                        .fixedSize()
                        .position(P(CGPoint(x: vx, y: y - 13)))
                    Text(verbatim: p.dateText)
                        .font(.system(size: 10.5 * s))
                        .foregroundStyle(KColor.ink3)
                        .monospacedDigit()
                        .fixedSize()
                        .position(P(CGPoint(x: CTPriceChartCanvas.cx(x, p.dateText, 10.5), y: CTPriceChartCanvas.B + 10)))
                    if let pc = p.pctText {
                        Text(verbatim: pc)
                            .font(.system(size: 11 * s, weight: .bold))
                            .foregroundStyle(p.pctTone == .up ? KColor.warn : (p.pctTone == .down ? KColor.ok : KColor.ink3))
                            .monospacedDigit()
                            .fixedSize()
                            .position(P(CGPoint(x: CTPriceChartCanvas.cx(x, pc, 11), y: CTPriceChartCanvas.B + 25)))
                    }
                }
            }
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
