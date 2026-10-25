import SwiftUI
import KontivoCore

// MARK: - Ladeanzeige (Web `bkLoad`)

struct BankLoadingView: View {
    let step: Int
    let nTx: Int?
    let logoDone: Int
    let logoTotal: Int
    let safe: String

    private var steps: [String] {
        var l = ["Kontoauszug lesen", "Fixkosten und Einnahmen suchen", "Mit deinen Einträgen abgleichen", "Logos suchen"]
        if logoTotal > 0 { l[3] = "Logos suchen (\(logoDone) von \(logoTotal))" }
        if let n = nTx { l[0] = n == 1 ? "1 Buchung gelesen" : "\(n) Buchungen gelesen" }
        return l
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                BankSpinLogo()
                    .padding(.bottom, 22)
                Text("Kontivo sucht Fixkosten und Einnahmen")
                    .font(.system(size: 21, weight: .bold))
                    .tracking(-0.21)
                    .foregroundStyle(KColor.ink)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 6)
                    .accessibilityAddTraits(.isHeader)
                Text("Das dauert nur einen Moment.")
                    .font(.system(size: 15))
                    .lineSpacing(15 * 0.4 - 3)
                    .foregroundStyle(KColor.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 22)
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(steps.indices, id: \.self) { i in
                        stepRow(i, steps[i])
                    }
                }
                .frame(maxWidth: 300, alignment: .leading)
                BankSafeNote(text: safe)
                    .padding(.top, 26)
            }
            .padding(.top, 34)
            .padding(.horizontal, 8)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 17)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bankLoading")
    }

    /// `.bksteps li`: Kreis 22 pt (Rand 2 pt), erledigt = Messing mit Haken, laufend = drehender Ring, Text 16 pt
    private func stepRow(_ i: Int, _ text: String) -> some View {
        let done = i < step, now = i == step
        return HStack(spacing: 12) {
            ZStack {
                if done {
                    Circle().fill(KColor.brass)
                    Text("✓").font(.system(size: 13)).foregroundStyle(KColor.onBrass)
                } else if now {
                    BankSpinner(size: 22, line: 2)
                } else {
                    Circle().strokeBorder(KColor.line, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
            Text(text)
                .font(.system(size: 16, weight: now ? .semibold : .regular))
                .foregroundStyle(done || now ? KColor.ink : KColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(done ? "erledigt" : (now ? "läuft" : ""))
    }
}

/// Drehender Ring (Web `.bksteps .now i`, `.bkload2 i`): Rand in Akzent 25 %, oben voller Akzent, 0.8 s je Umdrehung
struct BankSpinner: View {
    var size: CGFloat
    var line: CGFloat
    var period: Double = 0.8
    var top: Color = KColor.teal
    var track: Color = KColor.teal.opacity(0.25)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let p = reduceMotion ? 2.4 : period
            let a = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: p) / p * 360
            ZStack {
                Circle().strokeBorder(track, lineWidth: line)
                // border-top eines Kreises = Viertelbogen oben
                Circle()
                    .inset(by: line / 2)
                    .trim(from: 0.625, to: 0.875)
                    .stroke(top, lineWidth: line)
            }
            .rotationEffect(.degrees(a))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Intro-Logo (Web `#splash .splLogo`, `BK_LOGO`): schwarze Kachel, heller Ring, Messing-Segment dreht sich um das K (1.4 s),
/// 84 pt, Radius 20, Schatten 0 10 26 rgba(0,0,0,.22)
struct BankSpinLogo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { ctx in
            let p = reduceMotion ? 4.0 : 1.4
            let a = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: p) / p * 360
            Canvas { g, size in
                Self.draw(g, size: size, angle: a)
            }
        }
        .frame(width: 84, height: 84)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 13, y: 10)
        .accessibilityHidden(true)
    }

    static let light = Color(red: 0xEC / 255, green: 0xEA / 255, blue: 0xE6 / 255)
    static let dark = Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x13 / 255)
    static let brass = Color(red: 0xC6 / 255, green: 0xAB / 255, blue: 0x78 / 255)

    /// SVG viewBox 0 0 1024 1024
    static func draw(_ g: GraphicsContext, size: CGSize, angle: Double) {
        let k = size.width / 1024
        var c = g
        c.scaleBy(x: k, y: k)
        c.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 1024, height: 1024), cornerRadius: 228), with: .color(dark))
        let ctr = CGPoint(x: 512, y: 512)
        c.stroke(Path(ellipseIn: CGRect(x: 512 - 382, y: 512 - 382, width: 764, height: 764)), with: .color(light), lineWidth: 64)
        // Segment: von oben (−90°) im Uhrzeigersinn bis 30°, dreht sich um die Mitte
        var seg = Path()
        seg.addArc(center: ctr, radius: 382, startAngle: .degrees(-90 + angle), endAngle: .degrees(30 + angle), clockwise: false)
        c.stroke(seg, with: .color(brass), style: StrokeStyle(lineWidth: 64, lineCap: .butt))
        // K: translate(512 512) scale(0.88) translate(-516.4 -512)
        var kc = c
        kc.translateBy(x: 512, y: 512)
        kc.scaleBy(x: 0.88, y: 0.88)
        kc.translateBy(x: -516.4, y: -512)
        var stem = Path()
        stem.addLines([CGPoint(x: 339.78, y: 292), CGPoint(x: 393.78, y: 292), CGPoint(x: 439.78, y: 349.5), CGPoint(x: 439.78, y: 732), CGPoint(x: 339.78, y: 732)])
        stem.closeSubpath()
        kc.fill(stem, with: .color(light))
        var arm = Path()
        arm.move(to: CGPoint(x: 693, y: 792))
        arm.addLine(to: CGPoint(x: 469, y: 512))
        arm.addLine(to: CGPoint(x: 693, y: 232))
        kc.clip(to: Path(CGRect(x: 0, y: 292, width: 1024, height: 440)))
        kc.stroke(arm, with: .color(dark), style: StrokeStyle(lineWidth: 144, lineCap: .butt, lineJoin: .miter))
        kc.stroke(arm, with: .color(light), style: StrokeStyle(lineWidth: 80, lineCap: .butt, lineJoin: .miter))
    }
}

/// Grüne Box «Bleibt auf deinem Gerät.» (Web v201 `.safenote`, gleich wie in der Einführung): Schloss 22 pt in Grün,
/// Text 13 pt (Zeilenhöhe 1.4), Fläche Grün 9 % über surface, Radius 16, höchstens 360 pt breit
struct BankSafeNote: View {
    let text: String
    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            Canvas { g, size in
                let k = size.width / 24
                var c = g
                c.scaleBy(x: k, y: k)
                let style = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                c.stroke(Path(roundedRect: CGRect(x: 5, y: 10.5, width: 14, height: 10), cornerRadius: 2), with: .color(KColor.ok), style: style)
                var arc = Path()
                arc.move(to: CGPoint(x: 8, y: 10.5))
                arc.addLine(to: CGPoint(x: 8, y: 8))
                arc.addArc(center: CGPoint(x: 12, y: 8), radius: 4, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
                arc.addLine(to: CGPoint(x: 16, y: 10.5))
                c.stroke(arc, with: .color(KColor.ok), style: style)
            }
            .frame(width: 22, height: 22)
            .accessibilityHidden(true)
            (Text("Bleibt auf deinem Gerät.").fontWeight(.semibold).foregroundColor(KColor.ok) + Text(" " + text).foregroundColor(KColor.ink2))
                .font(.system(size: 13))
                .lineSpacing(13 * 0.4 - 2.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: 360)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface)
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.ok.opacity(0.09))
            }
        )
        .accessibilityElement(children: .combine)
    }
}
