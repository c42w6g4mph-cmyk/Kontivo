import SwiftUI
import UIKit

// MARK: - CSS-Masse der Web-App (Bereich onb: Einführung und Fristen)
//
// CSS-px = iOS-pt. Die Web-App setzt Zeilenhöhen (`line-height`) fest; SwiftUI-Text hat die natürliche Zeilenhöhe der Schrift.
// `onbLine` gleicht das aus: Zeilenabstand = Zeilenhöhe − natürliche Höhe, die Hälfte davon oben und unten (wie der Browser).

enum OnbCSS {
    /// Natürliche Zeilenhöhe der Systemschrift (SF Pro, SF Pro Rounded, New York)
    static func natural(_ size: CGFloat, _ weight: UIFont.Weight = .regular, _ design: UIFontDescriptor.SystemDesign = .default) -> CGFloat {
        var f = UIFont.systemFont(ofSize: size, weight: weight)
        if design != .default, let d = f.fontDescriptor.withDesign(design) { f = UIFont(descriptor: d, size: size) }
        return f.lineHeight
    }

    /// Breite des Bildschirms in CSS-`vw` (1 % der Breite) bzw. Höhe in `vh` (1 % der Höhe inkl. Sicherheitsabstände)
    static func clamp(_ lo: CGFloat, _ v: CGFloat, _ hi: CGFloat) -> CGFloat { min(hi, max(lo, v)) }
}

extension View {
    /// CSS `line-height` (px) für Text der Grösse `size`: mehrzeilig über den Zeilenabstand, oben/unten die halbe Differenz.
    /// Bei kleinerer Zeilenhöhe als die Schrift (Titel mit 1.1) wird der Rahmen entsprechend kleiner (Text ragt über).
    func onbLine(_ size: CGFloat, _ lh: CGFloat, _ weight: UIFont.Weight = .regular,
                 _ design: UIFontDescriptor.SystemDesign = .default) -> some View {
        let extra = lh - OnbCSS.natural(size, weight, design)
        return self.lineSpacing(max(0, extra)).padding(.vertical, extra / 2)
    }
}

// MARK: - Farben, die die Web-App mit `color-mix` berechnet (Werte aus getComputedStyle, hell / dunkel)

enum OnbColor {
    static func dyn(_ light: (CGFloat, CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat, CGFloat)) -> Color {
        Color(UIColor { tc in
            let v = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: v.0, green: v.1, blue: v.2, alpha: v.3)
        })
    }

    /// `#onb .obsafe`: color-mix(ok 9 %, surface)
    static let safeFill = dyn((0.926235, 0.947412, 0.937529, 1), (0.236824, 0.263686, 0.264196, 1))
    /// `#onb .obauto`: color-mix(teal 9 %, surface)
    static let autoFill = dyn((0.957294, 0.946353, 0.920941, 1), (0.262588, 0.256627, 0.252902, 1))
    /// `#onb .obsr em`: color-mix(brass 16 %, transparent)
    static let soonFill = dyn((0.658824, 0.517647, 0.215686, 0.16), (0.776471, 0.670588, 0.470588, 0.16))
    /// `#onb .obbar span.on`, Fortschritt: teal 13 % bzw. ink 13 %
    static let tealSoft = dyn((0.52549, 0.403922, 0.121569, 0.13), (0.776471, 0.670588, 0.470588, 0.13))
    static let inkSoft = dyn((0.0705882, 0.0745098, 0.0784314, 0.13), (0.909804, 0.901961, 0.886275, 0.13))
    /// `.esart` (Leerseite): color-mix(teal 12 %, surface)
    static let heroTile = dyn((0.943059, 0.928471, 0.894588, 1), (0.279529, 0.270274, 0.260078, 1))
    /// `.eprev.illu .epacts span`: color-mix(sunken 70 %, surface)
    static let previewButton = dyn((0.953333, 0.953333, 0.947843, 1), (0.241961, 0.245882, 0.261569, 1))
}

// MARK: - Symbole der Web-App (Inline-SVG, viewBox 24×24, Strich mit runden Enden)

/// SVG-Pfad (Befehle M L H V A Z, absolut und relativ) plus Kreise und abgerundete Rechtecke, skaliert auf den Rahmen.
struct OnbSVGShape: Shape {
    var d: [String] = []
    /// (cx, cy, r)
    var circles: [[CGFloat]] = []
    /// (x, y, w, h, rx)
    var rects: [[CGFloat]] = []
    var viewBox: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var p = Path()
        for s in d { OnbSVGShape.append(s, to: &p) }
        for c in circles where c.count == 3 {
            p.addEllipse(in: CGRect(x: c[0] - c[2], y: c[1] - c[2], width: 2 * c[2], height: 2 * c[2]))
        }
        for r in rects where r.count == 5 {
            p.addRoundedRect(in: CGRect(x: r[0], y: r[1], width: r[2], height: r[3]), cornerSize: CGSize(width: r[4], height: r[4]))
        }
        let s = min(rect.width, rect.height) / viewBox
        let t = CGAffineTransform(scaleX: s, y: s)
            .concatenating(CGAffineTransform(translationX: rect.minX + (rect.width - viewBox * s) / 2,
                                             y: rect.minY + (rect.height - viewBox * s) / 2))
        return p.applying(t)
    }

    // MARK: Parser

    private enum Tok { case cmd(Character), num(CGFloat) }

    private static func tokens(_ s: String) -> [Tok] {
        var out: [Tok] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isLetter && c != "e" && c != "E" {
                out.append(.cmd(c)); i += 1; continue
            }
            if c == "-" || c == "+" || c == "." || c.isNumber {
                var j = i
                var str = ""
                if chars[j] == "-" || chars[j] == "+" { str.append(chars[j]); j += 1 }
                var dot = false
                while j < chars.count {
                    let ch = chars[j]
                    if ch.isNumber { str.append(ch); j += 1 }
                    else if ch == "." && !dot { dot = true; str.append(ch); j += 1 }
                    else if (ch == "e" || ch == "E") && j + 1 < chars.count {
                        str.append(ch); j += 1
                        if chars[j] == "-" || chars[j] == "+" { str.append(chars[j]); j += 1 }
                    } else { break }
                }
                if let v = Double(str) { out.append(.num(CGFloat(v))) }
                i = max(j, i + 1)
                continue
            }
            i += 1
        }
        return out
    }

    static func append(_ s: String, to p: inout Path) {
        let toks = tokens(s)
        var i = 0
        var cmd: Character = "M"
        var cur = CGPoint.zero
        var start = CGPoint.zero
        func num() -> CGFloat? {
            guard i < toks.count, case .num(let v) = toks[i] else { return nil }
            i += 1
            return v
        }
        while i < toks.count {
            if case .cmd(let c) = toks[i] { cmd = c; i += 1 }
            let rel = cmd.isLowercase
            switch cmd.uppercased() {
            case "M":
                guard let x = num(), let y = num() else { return }
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                start = cur
                p.move(to: cur)
                cmd = rel ? "l" : "L" // weitere Paare = Linien
            case "L":
                guard let x = num(), let y = num() else { return }
                cur = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                p.addLine(to: cur)
            case "H":
                guard let x = num() else { return }
                cur.x = rel ? cur.x + x : x
                p.addLine(to: cur)
            case "V":
                guard let y = num() else { return }
                cur.y = rel ? cur.y + y : y
                p.addLine(to: cur)
            case "A":
                guard let rx = num(), let ry = num(), let _ = num(), let la = num(), let sw = num(),
                      let x = num(), let y = num() else { return }
                let end = rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
                arc(&p, from: cur, to: end, r: (rx + ry) / 2, large: la != 0, sweep: sw != 0)
                cur = end
            case "Z":
                p.closeSubpath()
                cur = start
            default:
                i += 1
            }
        }
    }

    /// Kreisbogen (SVG-Endpunktform, rx = ry, ohne Drehung) als kubische Bézierkurven
    private static func arc(_ p: inout Path, from p0: CGPoint, to p1: CGPoint, r rIn: CGFloat, large: Bool, sweep: Bool) {
        var r = abs(rIn)
        guard r > 0, p0 != p1 else { p.addLine(to: p1); return }
        let x1 = (p0.x - p1.x) / 2, y1 = (p0.y - p1.y) / 2
        let lam = (x1 * x1 + y1 * y1) / (r * r)
        if lam > 1 { r *= sqrt(lam) }
        let sign: CGFloat = large != sweep ? 1 : -1
        let num = max(0, r * r * r * r - r * r * y1 * y1 - r * r * x1 * x1)
        let den = r * r * y1 * y1 + r * r * x1 * x1
        let coef = sign * sqrt(num / den)
        let cxp = coef * y1, cyp = -coef * x1
        let cx = cxp + (p0.x + p1.x) / 2, cy = cyp + (p0.y + p1.y) / 2
        let t1 = atan2((y1 - cyp) / r, (x1 - cxp) / r)
        let t2 = atan2((-y1 - cyp) / r, (-x1 - cxp) / r)
        var dt = t2 - t1
        if !sweep && dt > 0 { dt -= 2 * .pi }
        if sweep && dt < 0 { dt += 2 * .pi }
        let n = max(1, Int(ceil(abs(dt) / (.pi / 2) - 0.0001)))
        let seg = dt / CGFloat(n)
        let k = 4 / 3 * tan(seg / 4)
        var a = t1
        for _ in 0..<n {
            let b = a + seg
            let pa = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
            let pb = CGPoint(x: cx + r * cos(b), y: cy + r * sin(b))
            let c1 = CGPoint(x: pa.x - k * r * sin(a), y: pa.y + k * r * cos(a))
            let c2 = CGPoint(x: pb.x + k * r * sin(b), y: pb.y - k * r * cos(b))
            if a == t1 && p.currentPoint == nil { p.move(to: pa) }
            p.addCurve(to: pb, control1: c1, control2: c2)
            a = b
        }
    }
}

/// Symbole der Einführung und der Fristen (Pfade 1:1 aus index.html v224)
enum OnbGlyph {
    case list, stat, budget, term, more, sparkle, bank, pdf, photo, lock, check, heroCheck

    var shape: OnbSVGShape {
        switch self {
        case .list: return OnbSVGShape(d: ["M7 3h7l5 5v13H7z", "M14 3v5h5", "M10 13h6M10 17h5"])
        case .stat: return OnbSVGShape(d: ["M5 20v-8M10 20V5M15 20v-6M20 20V9"])
        case .budget: return OnbSVGShape(d: ["M3 10h18", "M15.5 14.5h2.5"], rects: [[3, 6, 18, 13, 3]])
        case .term: return OnbSVGShape(d: ["M12 8.5v4l2.8 1.8", "M9.5 2.8h5"], circles: [[12, 12.5, 8]])
        case .more: return OnbSVGShape(circles: [[5, 12, 1.9], [12, 12, 1.9], [19, 12, 1.9]])
        case .sparkle: return OnbSVGShape(d: ["M12 3l1.8 4.6L18.5 9l-4.7 1.6L12 15l-1.8-4.4L5.5 9l4.7-1.4z"])
        case .bank: return OnbSVGShape(d: ["M3 10l9-6 9 6M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 20h18"])
        case .pdf: return OnbSVGShape(d: ["M6 3h9l4 4v14H6z", "M15 3v4h4", "M9 13h6M9 17h4"])
        case .photo: return OnbSVGShape(d: ["M4 8h3l1.6-2.4h6.8L17 8h3v11H4z"], circles: [[12, 13.2, 3.4]])
        case .lock: return OnbSVGShape(d: ["M8 10.5V8a4 4 0 0 1 8 0v2.5"], rects: [[5, 10.5, 14, 10, 2]])
        case .check: return OnbSVGShape(d: ["M5 12.5l4.5 4.5L19 7.5"])
        case .heroCheck: return OnbSVGShape(d: ["m5 12.5 4.2 4.2L19 7"])
        }
    }

    /// Gefüllt statt Strich (Punkte von «Mehr»)
    var filled: Bool { self == .more }
}

/// Symbol in Grösse `size` (CSS width/height) mit Strichstärke `stroke` in viewBox-Einheiten (CSS stroke-width)
struct OnbIcon: View {
    let glyph: OnbGlyph
    var size: CGFloat
    var stroke: CGFloat = 2

    var body: some View {
        Group {
            if glyph.filled {
                glyph.shape.fill(style: FillStyle())
            } else {
                glyph.shape.stroke(style: StrokeStyle(lineWidth: stroke * size / 24, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// CSS-Chevron aus zwei Rahmenlinien (8×8, rechts/unten 1.6 px, gedreht): `.tfx i`, `.tfold i`, `.obmorebtn i`
struct OnbChevron: View {
    /// Drehung in Grad wie im CSS (45 = nach unten, −45 = nach rechts, −135 = nach oben)
    var degrees: Double
    var box: CGFloat = 8
    var line: CGFloat = 1.6
    var color: Color = KColor.ink3

    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: box - line / 2, y: 0))
            p.addLine(to: CGPoint(x: box - line / 2, y: box - line / 2))
            p.addLine(to: CGPoint(x: 0, y: box - line / 2))
        }
        .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .butt, lineJoin: .miter))
        .frame(width: box, height: box)
        .rotationEffect(.degrees(degrees))
        .accessibilityHidden(true)
    }
}
