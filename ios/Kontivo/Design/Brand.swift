import SwiftUI

// Marke Kontivo (Web v168–v174, brand/): Logo-K mit Trennfuge, App-Icon «K im Zeitring», Wortmarke «Kontivo»
// mit O als Kreisdiagramm (1/3 Messing ab 12 Uhr) und «ntivo» in Inter Display Bold (Glyphen als Vektorpfade, deckungsgleich
// mit brand/kontivo-wortmarke-*.svg). Koordinaten 1:1 aus den SVGs der Web-App.

/// Logo-K mit Trennfuge im Koordinatenraum der Web-SVG (viewBox 339.5 292 357.5 440).
/// Stamm = Polygon ohne den 144 breiten Streifen um den Winkel, Arme = Winkel mit Strichbreite 80, oben/unten gekappt.
enum KLogoK {
    static let viewBox = CGRect(x: 339.5, y: 292, width: 357.5, height: 440)

    static func stem(_ p: inout Path, _ t: (CGFloat, CGFloat) -> CGPoint) {
        let pts: [(CGFloat, CGFloat)] = [(339.78, 292), (393.78, 292), (439.78, 349.5), (439.78, 433.27), (376.796, 512),
                                         (439.78, 590.73), (439.78, 732), (339.78, 732)]
        p.move(to: t(pts[0].0, pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: t(q.0, q.1)) }
        p.closeSubpath()
    }

    static func arms(_ p: inout Path, _ t: (CGFloat, CGFloat) -> CGPoint) {
        let pts: [(CGFloat, CGFloat)] = [(417.776, 512), (593.776, 292), (696.224, 292), (520.224, 512), (696.224, 732), (593.776, 732)]
        p.move(to: t(pts[0].0, pts[0].1))
        for q in pts.dropFirst() { p.addLine(to: t(q.0, q.1)) }
        p.closeSubpath()
    }
}

/// Logo-K als Form (füllt das Rechteck im Seitenverhältnis 357.5 : 440)
struct KLogoKShape: Shape {
    func path(in rect: CGRect) -> Path {
        let vb = KLogoK.viewBox
        let s = min(rect.width / vb.width, rect.height / vb.height)
        let t: (CGFloat, CGFloat) -> CGPoint = { x, y in CGPoint(x: rect.minX + (x - vb.minX) * s, y: rect.minY + (y - vb.minY) * s) }
        var p = Path()
        KLogoK.stem(&p, t)
        KLogoK.arms(&p, t)
        return p
    }
}

/// App-Symbol als Vektor (brand/kontivo-icon.svg, v174 Variante B): Schwarz #111113, Ring #ECEAE6, 1/3 Messing #C6AB78, K 88 %.
/// `segmentAngle`: Drehung des Messing-Segments (Splash), `cornerRadius` relativ (Web rx 228/1024).
struct KAppLogo: View {
    var size: CGFloat = 96
    var segmentAngle: Angle = .zero
    var rounded = true

    var body: some View {
        let s = size / 1024
        ZStack {
            Rectangle().fill(Color(hex: "#111113"))
            Circle()
                .stroke(Color(hex: "#ECEAE6"), lineWidth: 64 * s)
                .frame(width: 764 * s, height: 764 * s)
            KArc(start: .degrees(-90), end: .degrees(30))
                .stroke(Color(hex: "#C6AB78"), style: StrokeStyle(lineWidth: 64 * s, lineCap: .butt))
                .frame(width: 764 * s, height: 764 * s)
                .rotationEffect(segmentAngle)
            KAppLogoK()
                .fill(Color(hex: "#ECEAE6"))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: rounded ? size * 228 / 1024 : 0, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// K des App-Symbols: translate(512 512) scale(0.88) translate(-516.4 -512) im 1024er Raster
private struct KAppLogoK: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 1024
        let t: (CGFloat, CGFloat) -> CGPoint = { x, y in
            CGPoint(x: rect.minX + (512 + 0.88 * (x - 516.4)) * s, y: rect.minY + (512 + 0.88 * (y - 512)) * s)
        }
        var p = Path()
        KLogoK.stem(&p, t)
        KLogoK.arms(&p, t)
        return p
    }
}

/// Kreisbogen im Uhrzeigersinn (Winkel wie SVG: 0° = 3 Uhr, −90° = 12 Uhr)
struct KArc: Shape {
    var start: Angle
    var end: Angle
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                 startAngle: start, endAngle: end, clockwise: false)
        return p
    }
}

/// Wortmarke «Kontivo» (Web `.bfwm`/`.splWm`, v171): Grösse = Schriftgrad in pt (1 em). Box 3.4009 × 0.76 em, Grundlinie bei 0.73 em.
/// `part(i)` liefert für die Einblend-Animation des Intros je Teil (0 = K, 1 = O, 2… = n t i v o) Deckkraft und Versatz.
struct KWordmark: View {
    var size: CGFloat
    /// Fortschritt je Teil (0…1, darf überschwingen); nil = statisch
    var progress: ((Int) -> Double)? = nil
    /// Anteil des gezeichneten Messing-Segments (Intro: 0 → 1)
    var brass: Double = 1

    static let width: CGFloat = 3400.9
    static let height: CGFloat = 760
    /// Grundlinie ab Oberkante (Einheit 1/1000 em)
    static let baseline: CGFloat = 730

    var body: some View {
        let s = size / 1000
        ZStack(alignment: .topLeading) {
            ForEach(0..<7, id: \.self) { i in
                let p = progress?(i) ?? 1
                Group {
                    if i == 1 {
                        ZStack {
                            KWordmarkShape(part: 1).fill(KColor.ink)
                            KWordmarkBrass(amount: brass).fill(KColor.brass)
                        }
                    } else {
                        KWordmarkShape(part: i).fill(KColor.ink, style: FillStyle(eoFill: i >= 2))
                    }
                }
                .opacity(min(1, max(0, p)))
                .offset(y: 10 * (1 - p))
            }
        }
        .frame(width: KWordmark.width * s, height: KWordmark.height * s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kontivo")
    }
}

/// Teil der Wortmarke als Fläche im 1000er-em-Raster (Ursprung links oben der Box)
struct KWordmarkShape: Shape {
    let part: Int

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch part {
        case 0:
            // K: Logo-K auf 0.72 em Höhe (585 × 720), oben 10
            let k: CGFloat = 720 / 440
            KLogoK.stem(&p) { x, y in CGPoint(x: (x - 339.5) * k, y: 10 + (y - 292) * k) }
            KLogoK.arms(&p) { x, y in CGPoint(x: (x - 339.5) * k, y: 10 + (y - 292) * k) }
        case 1:
            // O: Kreis Mitte (830, 450), r 212.8, Strich 123.2; dunkler Teil von 4 Uhr bis 12 Uhr
            var a = Path()
            a.addArc(center: CGPoint(x: 830, y: 450), radius: 212.8, startAngle: .degrees(30), endAngle: .degrees(270), clockwise: false)
            p = a.strokedPath(StrokeStyle(lineWidth: 123.2, lineCap: .butt))
        case 2: KWordmarkGlyphs.glyphN(&p)
        case 3: KWordmarkGlyphs.glyphT(&p)
        case 4: KWordmarkGlyphs.glyphI(&p)
        case 5: KWordmarkGlyphs.glyphV(&p)
        default: KWordmarkGlyphs.glyphO(&p)
        }
        return p.applying(CGAffineTransform(scaleX: rect.width / KWordmark.width, y: rect.height / KWordmark.height))
    }
}

/// Messing-Drittel des O (12 Uhr → 4 Uhr), `amount` = gezeichneter Anteil
struct KWordmarkBrass: Shape {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func path(in rect: CGRect) -> Path {
        guard amount > 0 else { return Path() }
        var a = Path()
        a.addArc(center: CGPoint(x: 830, y: 450), radius: 212.8, startAngle: .degrees(-90),
                 endAngle: .degrees(-90 + 120 * min(1, amount)), clockwise: false)
        return a.strokedPath(StrokeStyle(lineWidth: 123.2, lineCap: .butt))
            .applying(CGAffineTransform(scaleX: rect.width / KWordmark.width, y: rect.height / KWordmark.height))
    }
}

/// Glyphen «ntivo» (Inter Display Bold, OFL) aus brand/kontivo-wortmarke-hell.svg, umgerechnet mit ios/design-tools/wordmark_glyphs.py
enum KWordmarkGlyphs {
    /// «n»
    static func glyphN(_ p: inout Path) {
        p.move(to: CGPoint(x: 1319.82, y: 443.38))
        p.addCurve(to: CGPoint(x: 1420.90, y: 327.66), control1: CGPoint(x: 1319.82, y: 363.30), control2: CGPoint(x: 1361.33, y: 327.66))
        p.addCurve(to: CGPoint(x: 1515.62, y: 433.61), control1: CGPoint(x: 1480.96, y: 327.66), control2: CGPoint(x: 1515.62, y: 364.28))
        p.addLine(to: CGPoint(x: 1515.62, y: 730.00))
        p.addLine(to: CGPoint(x: 1659.18, y: 730.00))
        p.addLine(to: CGPoint(x: 1659.18, y: 407.25))
        p.addCurve(to: CGPoint(x: 1478.51, y: 203.63), control1: CGPoint(x: 1659.18, y: 276.88), control2: CGPoint(x: 1588.38, y: 203.63))
        p.addCurve(to: CGPoint(x: 1317.38, y: 295.43), control1: CGPoint(x: 1404.30, y: 203.63), control2: CGPoint(x: 1352.05, y: 236.84))
        p.addLine(to: CGPoint(x: 1317.38, y: 214.38))
        p.addLine(to: CGPoint(x: 1175.78, y: 214.38))
        p.addLine(to: CGPoint(x: 1175.78, y: 730.00))
        p.addLine(to: CGPoint(x: 1319.82, y: 730.00))
        p.closeSubpath()
    }
    /// «t»
    static func glyphT(_ p: inout Path) {
        p.move(to: CGPoint(x: 2047.61, y: 214.38))
        p.addLine(to: CGPoint(x: 1942.14, y: 214.38))
        p.addLine(to: CGPoint(x: 1942.14, y: 73.75))
        p.addLine(to: CGPoint(x: 1798.10, y: 73.75))
        p.addLine(to: CGPoint(x: 1798.10, y: 214.38))
        p.addLine(to: CGPoint(x: 1709.23, y: 214.38))
        p.addLine(to: CGPoint(x: 1709.23, y: 327.17))
        p.addLine(to: CGPoint(x: 1798.10, y: 327.17))
        p.addLine(to: CGPoint(x: 1798.10, y: 593.28))
        p.addCurve(to: CGPoint(x: 1963.62, y: 730.00), control1: CGPoint(x: 1798.10, y: 687.03), control2: CGPoint(x: 1850.34, y: 730.00))
        p.addLine(to: CGPoint(x: 2047.61, y: 730.00))
        p.addLine(to: CGPoint(x: 2047.61, y: 617.21))
        p.addLine(to: CGPoint(x: 1992.43, y: 617.21))
        p.addCurve(to: CGPoint(x: 1942.14, y: 570.82), control1: CGPoint(x: 1953.37, y: 617.21), control2: CGPoint(x: 1942.14, y: 605.98))
        p.addLine(to: CGPoint(x: 1942.14, y: 327.17))
        p.addLine(to: CGPoint(x: 2047.61, y: 327.17))
        p.closeSubpath()
    }
    /// «i»
    static func glyphI(_ p: inout Path) {
        p.move(to: CGPoint(x: 2109.87, y: 730.00))
        p.addLine(to: CGPoint(x: 2253.91, y: 730.00))
        p.addLine(to: CGPoint(x: 2253.91, y: 214.38))
        p.addLine(to: CGPoint(x: 2109.87, y: 214.38))
        p.closeSubpath()
        p.move(to: CGPoint(x: 2181.65, y: 149.44))
        p.addCurve(to: CGPoint(x: 2263.68, y: 72.78), control1: CGPoint(x: 2229.01, y: 149.44), control2: CGPoint(x: 2263.68, y: 116.72))
        p.addCurve(to: CGPoint(x: 2181.65, y: -3.88), control1: CGPoint(x: 2263.68, y: 28.83), control2: CGPoint(x: 2229.01, y: -3.88))
        p.addCurve(to: CGPoint(x: 2099.62, y: 72.78), control1: CGPoint(x: 2134.29, y: -3.88), control2: CGPoint(x: 2099.62, y: 28.83))
        p.addCurve(to: CGPoint(x: 2181.65, y: 149.44), control1: CGPoint(x: 2099.62, y: 116.72), control2: CGPoint(x: 2134.29, y: 149.44))
        p.closeSubpath()
    }
    /// «v»
    static func glyphV(_ p: inout Path) {
        p.move(to: CGPoint(x: 2491.48, y: 730.00))
        p.addLine(to: CGPoint(x: 2651.63, y: 730.00))
        p.addLine(to: CGPoint(x: 2843.04, y: 214.38))
        p.addLine(to: CGPoint(x: 2693.62, y: 214.38))
        p.addLine(to: CGPoint(x: 2609.64, y: 469.26))
        p.addCurve(to: CGPoint(x: 2573.51, y: 591.33), control1: CGPoint(x: 2597.43, y: 509.79), control2: CGPoint(x: 2585.23, y: 550.80))
        p.addCurve(to: CGPoint(x: 2536.40, y: 469.26), control1: CGPoint(x: 2561.79, y: 550.80), control2: CGPoint(x: 2549.58, y: 509.79))
        p.addLine(to: CGPoint(x: 2451.44, y: 214.38))
        p.addLine(to: CGPoint(x: 2300.56, y: 214.38))
        p.closeSubpath()
    }
    /// «o»
    static func glyphO(_ p: inout Path) {
        p.move(to: CGPoint(x: 3110.38, y: 741.72))
        p.addCurve(to: CGPoint(x: 3372.58, y: 472.68), control1: CGPoint(x: 3267.12, y: 741.72), control2: CGPoint(x: 3372.58, y: 634.30))
        p.addCurve(to: CGPoint(x: 3110.38, y: 202.66), control1: CGPoint(x: 3372.58, y: 311.06), control2: CGPoint(x: 3267.12, y: 202.66))
        p.addCurve(to: CGPoint(x: 2848.66, y: 472.68), control1: CGPoint(x: 2954.13, y: 202.66), control2: CGPoint(x: 2848.66, y: 311.06))
        p.addCurve(to: CGPoint(x: 3110.38, y: 741.72), control1: CGPoint(x: 2848.66, y: 634.30), control2: CGPoint(x: 2954.13, y: 741.72))
        p.closeSubpath()
        p.move(to: CGPoint(x: 3110.38, y: 625.02))
        p.addCurve(to: CGPoint(x: 2993.68, y: 472.68), control1: CGPoint(x: 3040.55, y: 625.02), control2: CGPoint(x: 2993.68, y: 568.38))
        p.addCurve(to: CGPoint(x: 3110.38, y: 319.36), control1: CGPoint(x: 2993.68, y: 376.49), control2: CGPoint(x: 3041.04, y: 319.36))
        p.addCurve(to: CGPoint(x: 3227.57, y: 472.68), control1: CGPoint(x: 3180.20, y: 319.36), control2: CGPoint(x: 3227.57, y: 376.49))
        p.addCurve(to: CGPoint(x: 3110.38, y: 625.02), control1: CGPoint(x: 3227.57, y: 568.38), control2: CGPoint(x: 3180.69, y: 625.02))
        p.closeSubpath()
    }
}
