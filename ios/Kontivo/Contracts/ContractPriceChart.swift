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

    /// Stufen mit abgerundeten Ecken (Web v321 Variante A): waagrecht bis kurz vor den Wechsel, Bogen, senkrecht, Bogen
    private func steps(_ path: inout Path, _ a: Int, _ b: Int, _ P: (CGPoint) -> CGPoint) {
        let pts = chart.points
        guard a <= b else { return }
        for i in a...b {
            let x = X(pts[i].x), y0 = Y(pts[i - 1].amount), y1 = Y(pts[i].amount)
            let rr = Swift.min(7, Swift.abs(y1 - y0) / 2, (x - X(pts[i - 1].x)) / 2)
            let dy: CGFloat = y1 > y0 ? rr : -rr
            if rr < 0.5 {
                path.addLine(to: P(CGPoint(x: x, y: y0)))
                path.addLine(to: P(CGPoint(x: x, y: y1)))
            } else {
                path.addLine(to: P(CGPoint(x: x - rr, y: y0)))
                path.addQuadCurve(to: P(CGPoint(x: x, y: y0 + dy)), control: P(CGPoint(x: x, y: y0)))
                path.addLine(to: P(CGPoint(x: x, y: y1 - dy)))
                path.addQuadCurve(to: P(CGPoint(x: x + rr, y: y1)), control: P(CGPoint(x: x, y: y1)))
            }
        }
    }

    /// Linie bis heute (pathP) bzw. danach (pathF, gepunktet); `area` = Fläche unter der Linie bis heute
    private func paths(_ P: (CGPoint) -> CGPoint) -> (past: Path, future: Path?, area: Path) {
        let pts = chart.points
        let ni = chart.nowIndex
        let last = pts.count - 1
        let xt = X(chart.todayX)
        let x0 = X(pts.first?.x ?? 0)
        var past = Path()
        past.move(to: P(CGPoint(x: x0, y: Y(pts.first?.amount ?? 0))))
        if ni >= 1 { steps(&past, 1, ni, P) }
        let pastEnd = CGPoint(x: ni < last ? xt : CTPriceChartCanvas.R, y: Y(pts[ni].amount))
        past.addLine(to: P(pastEnd))
        var area = past
        area.addLine(to: P(CGPoint(x: pastEnd.x, y: CTPriceChartCanvas.B)))
        area.addLine(to: P(CGPoint(x: x0, y: CTPriceChartCanvas.B)))
        area.closeSubpath()
        var fut: Path?
        if ni < last {
            var f = Path()
            f.move(to: P(CGPoint(x: xt, y: Y(pts[ni].amount))))
            steps(&f, ni + 1, last, P)
            f.addLine(to: P(CGPoint(x: CTPriceChartCanvas.R, y: Y(pts[last].amount))))
            fut = f
        }
        return (past, fut, area)
    }

    /// Text an einem Punkt: mittig (am Rand eingerückt), rechtsbündig (`end`, Ende bei x + 4) bzw. linksbündig (`start`, ab x − 4);
    /// Preissenkung mit Zahl rechts neben der Linie (`trailing`, ab x + 5). `y` = Grundlinie wie im SVG.
    @ViewBuilder
    private func label(_ t: String, x: CGFloat, y: CGFloat, fs: CGFloat, anchor: PriceChartAnchor, trailing: Bool = false, s: CGFloat,
                       weight: Font.Weight, color: Color) -> some View {
        let w = CGFloat(t.count) * fs * 0.58
        let text = Text(verbatim: t).font(.system(size: fs * s, weight: weight)).foregroundStyle(color).monospacedDigit().fixedSize()
        let cy = (y - fs * 0.35) * s
        if trailing {
            text.frame(width: 0, alignment: .leading).position(x: Swift.min(CTPriceChartCanvas.R - w, x + 5) * s, y: cy)
        } else {
            switch anchor {
            case .end:
                text.frame(width: 0, alignment: .trailing).position(x: Swift.max(CTPriceChartCanvas.L + w, x + 4) * s, y: cy)
            case .start:
                text.frame(width: 0, alignment: .leading).position(x: Swift.min(CTPriceChartCanvas.R - w, x - 4) * s, y: cy)
            case .middle:
                text.position(x: CTPriceChartCanvas.cx(x, t, fs) * s, y: cy)
            }
        }
    }

    var body: some View {
        GeometryReader { g in
            let s = g.size.width / CTPriceChartCanvas.W
            let P = { (p: CGPoint) in CGPoint(x: p.x * s, y: p.y * s) }
            let pp = paths(P)
            let pts = chart.points
            let ni = chart.nowIndex
            ZStack(alignment: .topLeading) {
                // Verlaufsfläche unter der Linie bis heute (Web .pg0 34 % → .pg1 4 %)
                pp.area.fill(LinearGradient(colors: [KColor.teal.opacity(0.34), KColor.teal.opacity(0.04)],
                                            startPoint: UnitPoint(x: 0.5, y: CTPriceChartCanvas.T / CTPriceChartCanvas.H),
                                            endPoint: UnitPoint(x: 0.5, y: CTPriceChartCanvas.B / CTPriceChartCanvas.H)))
                pp.past.stroke(KColor.teal, style: StrokeStyle(lineWidth: 2.2 * s, lineCap: .round, lineJoin: .round))
                if let f = pp.future {
                    f.stroke(KColor.teal.opacity(0.8), style: StrokeStyle(lineWidth: 2 * s, lineCap: .round, lineJoin: .round, dash: [1 * s, 5 * s]))
                }
                // Hilfslinie «heute», nur wenn noch Änderungen geplant sind
                if ni < pts.count - 1 {
                    Path { path in
                        path.move(to: P(CGPoint(x: X(chart.todayX), y: CTPriceChartCanvas.T - 8)))
                        path.addLine(to: P(CGPoint(x: X(chart.todayX), y: CTPriceChartCanvas.B)))
                    }
                    .stroke(KColor.ink3.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
                ForEach(pts.filter { $0.labeled }) { p in
                    let x = X(p.x), y = Y(p.amount)
                    let fs: CGFloat = p.isNow ? 12.5 : 11
                    label(p.valueText, x: x, y: y - 10, fs: fs, anchor: p.anchor, trailing: p.labelTrailing, s: s,
                          weight: p.isNow ? .bold : .semibold, color: p.isNow ? KColor.teal : KColor.ink2)
                    label(p.dateText, x: x, y: CTPriceChartCanvas.B + 14, fs: 10.5, anchor: p.anchor, s: s, weight: .regular, color: KColor.ink3)
                    if let pc = p.pctText {
                        label(pc, x: x, y: CTPriceChartCanvas.B + 29, fs: 11, anchor: p.anchor, s: s, weight: .bold,
                              color: p.pctTone == .up ? KColor.warn : (p.pctTone == .down ? KColor.ok : KColor.ink3))
                    }
                }
                ForEach(pts) { p in
                    let c = P(CGPoint(x: X(p.x), y: Y(p.amount)))
                    if p.isNow {
                        Circle().fill(KColor.teal.opacity(0.18)).frame(width: 17 * s, height: 17 * s).position(c)
                    }
                    let r: CGFloat = (p.isNow ? 4.5 : 3.3) * s
                    Circle()
                        .fill(p.isNow ? KColor.teal : KColor.field)
                        .overlay(Circle().strokeBorder(p.isFuture ? KColor.warn : KColor.teal, lineWidth: 2))
                        .frame(width: r * 2, height: r * 2)
                        .position(c)
                }
            }
        }
    }
}
