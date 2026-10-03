import SwiftUI
import KontivoCore

/// Hauptwährung als Kacheln mit Fahne und Kürzel (wie `curPickHtml` der Web-App): EUR und CHF gross,
/// «Weitere Währungen» klappt USD, GBP und TRY auf. Wird in «Mehr» und in der Einführung verwendet.
struct MoreCurrencyPicker: View {
    let selection: Currency
    @Binding var expanded: Bool
    let onPick: (Currency) -> Void

    static let main: [Currency] = [.EUR, .CHF]
    static let more: [Currency] = [.USD, .GBP, .TRY]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(Self.main, id: \.self) { c in
                    MoreCurrencyTile(currency: c, isOn: c == selection, big: true) { onPick(c) }
                }
            }
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack {
                    Text("Weitere Währungen")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KColor.teal)
                .padding(.horizontal, 2).padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(expanded ? "aufgeklappt" : "zugeklappt")
            if expanded {
                HStack(spacing: 8) {
                    ForEach(Self.more, id: \.self) { c in
                        MoreCurrencyTile(currency: c, isOn: c == selection, big: false) { onPick(c) }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Hauptwährung")
    }
}

/// Eine Währungskachel: Fahne, Kürzel fett, gewählt mit Haken.
struct MoreCurrencyTile: View {
    let currency: Currency
    let isOn: Bool
    let big: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: big ? 10 : 7) {
                MoreFlagView(currency: currency)
                    .frame(width: big ? 30 : 24, height: big ? 20 : 16)
                    .clipShape(RoundedRectangle(cornerRadius: big ? 4 : 3, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: big ? 4 : 3, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                Text(currency.rawValue)
                    .font(big ? .body.weight(.bold) : .subheadline.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, big ? 12 : 9)
            .padding(.vertical, big ? 11 : 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(KColor.teal.opacity(0.08)) : AnyShapeStyle(KColor.field))
            )
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous).fill(isOn ? KColor.surface : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isOn ? KColor.teal : Color.clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topTrailing) {
                if isOn {
                    ZStack {
                        Circle().fill(KColor.teal)
                        Image(systemName: "checkmark")
                            .font(.system(size: big ? 9 : 8, weight: .heavy))
                            .foregroundStyle(.white)
                    }
                    .frame(width: big ? 18 : 15, height: big ? 18 : 15)
                    .padding(big ? 7 : 5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(currency.rawValue) (\(currency.displayName))")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Fahnen als kleine Zeichnungen (Seitenverhältnis 3:2, wie die SVG der Web-App): Schweiz, EU, USA, Grossbritannien, Türkei.
struct MoreFlagView: View {
    let currency: Currency

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / 30
            let sy = size.height / 20
            ctx.scaleBy(x: sx, y: sy)
            switch currency {
            case .CHF: MoreFlagView.drawCH(&ctx)
            case .EUR: MoreFlagView.drawEU(&ctx)
            case .USD: MoreFlagView.drawUS(&ctx)
            case .GBP: MoreFlagView.drawUK(&ctx)
            case .TRY: MoreFlagView.drawTR(&ctx)
            }
        }
        .accessibilityHidden(true)
    }

    private static func rgb(_ v: UInt32) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    private static let full = Path(CGRect(x: 0, y: 0, width: 30, height: 20))

    private static func dot(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
    }

    private static func drawCH(_ ctx: inout GraphicsContext) {
        ctx.fill(full, with: .color(rgb(0xDA291C)))
        var p = Path()
        p.move(to: CGPoint(x: 13, y: 4))
        p.addLine(to: CGPoint(x: 17, y: 4))
        p.addLine(to: CGPoint(x: 17, y: 8))
        p.addLine(to: CGPoint(x: 21, y: 8))
        p.addLine(to: CGPoint(x: 21, y: 12))
        p.addLine(to: CGPoint(x: 17, y: 12))
        p.addLine(to: CGPoint(x: 17, y: 16))
        p.addLine(to: CGPoint(x: 13, y: 16))
        p.addLine(to: CGPoint(x: 13, y: 12))
        p.addLine(to: CGPoint(x: 9, y: 12))
        p.addLine(to: CGPoint(x: 9, y: 8))
        p.addLine(to: CGPoint(x: 13, y: 8))
        p.closeSubpath()
        ctx.fill(p, with: .color(.white))
    }

    private static func drawEU(_ ctx: inout GraphicsContext) {
        ctx.fill(full, with: .color(rgb(0x003399)))
        var stars = Path()
        for i in 0..<12 {
            let a = Double(i) * .pi / 6
            let x = 15 + 6 * sin(a)
            let y = 10 - 6 * cos(a)
            stars.addPath(dot(CGFloat(x), CGFloat(y), 1.05))
        }
        ctx.fill(stars, with: .color(rgb(0xFFCC00)))
    }

    private static func drawUS(_ ctx: inout GraphicsContext) {
        ctx.fill(full, with: .color(.white))
        var stripes = Path()
        for k in 0..<7 {
            stripes.addRect(CGRect(x: 0, y: CGFloat(k) * 3.077, width: 30, height: 1.538))
        }
        ctx.fill(stripes, with: .color(rgb(0xB22234)))
        ctx.fill(Path(CGRect(x: 0, y: 0, width: 13, height: 10.77)), with: .color(rgb(0x3C3B6E)))
        var stars = Path()
        let rowsY: [CGFloat] = [1.4, 3.3, 5.2, 7.1, 9.0]
        for (r, y) in rowsY.enumerated() {
            let xs: [CGFloat] = r % 2 == 0 ? [1.6, 3.8, 6.0, 8.2, 10.4, 12.6] : [2.7, 4.9, 7.1, 9.3, 11.5]
            for x in xs { stars.addPath(dot(x, y, 0.55)) }
        }
        ctx.fill(stars, with: .color(.white))
    }

    private static func drawUK(_ ctx: inout GraphicsContext) {
        ctx.fill(full, with: .color(rgb(0x012169)))
        var diag = Path()
        diag.move(to: CGPoint(x: 0, y: 0)); diag.addLine(to: CGPoint(x: 30, y: 20))
        diag.move(to: CGPoint(x: 30, y: 0)); diag.addLine(to: CGPoint(x: 0, y: 20))
        var cross = Path()
        cross.move(to: CGPoint(x: 15, y: 0)); cross.addLine(to: CGPoint(x: 15, y: 20))
        cross.move(to: CGPoint(x: 0, y: 10)); cross.addLine(to: CGPoint(x: 30, y: 10))
        var inner = ctx
        inner.clip(to: full)
        inner.stroke(diag, with: .color(.white), lineWidth: 4)
        inner.stroke(diag, with: .color(rgb(0xC8102E)), lineWidth: 1.5)
        inner.stroke(cross, with: .color(.white), lineWidth: 6)
        inner.stroke(cross, with: .color(rgb(0xC8102E)), lineWidth: 3.4)
    }

    private static func drawTR(_ ctx: inout GraphicsContext) {
        ctx.fill(full, with: .color(rgb(0xE30A17)))
        ctx.fill(dot(11.5, 10, 5), with: .color(.white))
        ctx.fill(dot(12.8, 10, 4), with: .color(rgb(0xE30A17)))
        var star = Path()
        star.move(to: CGPoint(x: 17.3, y: 10))
        star.addLine(to: CGPoint(x: 21.2, y: 8.7))
        star.addLine(to: CGPoint(x: 18.8, y: 12))
        star.addLine(to: CGPoint(x: 18.8, y: 8))
        star.addLine(to: CGPoint(x: 21.2, y: 11.3))
        star.closeSubpath()
        ctx.fill(star, with: .color(.white))
    }
}

/// Kleines Schweizer Kreuz (quadratisch) für «Made with ❤️ in …»
struct MoreSwissMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 32
            ctx.scaleBy(x: s, y: s)
            ctx.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: 32, height: 32), cornerRadius: 3), with: .color(Color(red: 0xDA / 255, green: 0x29 / 255, blue: 0x1C / 255)))
            var p = Path()
            p.move(to: CGPoint(x: 13, y: 6))
            p.addLine(to: CGPoint(x: 19, y: 6))
            p.addLine(to: CGPoint(x: 19, y: 13))
            p.addLine(to: CGPoint(x: 26, y: 13))
            p.addLine(to: CGPoint(x: 26, y: 19))
            p.addLine(to: CGPoint(x: 19, y: 19))
            p.addLine(to: CGPoint(x: 19, y: 26))
            p.addLine(to: CGPoint(x: 13, y: 26))
            p.addLine(to: CGPoint(x: 13, y: 19))
            p.addLine(to: CGPoint(x: 6, y: 19))
            p.addLine(to: CGPoint(x: 6, y: 13))
            p.addLine(to: CGPoint(x: 13, y: 13))
            p.closeSubpath()
            ctx.fill(p, with: .color(.white))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Schweiz")
    }
}
