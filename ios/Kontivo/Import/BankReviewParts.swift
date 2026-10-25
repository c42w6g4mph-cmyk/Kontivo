import SwiftUI
import KontivoCore

// MARK: - Bausteine der Vorschlagsliste (Web `.bkr`, `.bkq`, `.bkpay`, `.bkdup`, `.bkhero`, Stand v330)

/// Zeilenhöhen der Web-App in SwiftUI (SF Pro: natürliche Zeilenhöhe ≈ 1.193 × Schriftgrösse)
enum BankType {
    /// Zusätzlicher Zeilenabstand für CSS `line-height`
    static func extra(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat { Swift.max(0, lineHeight - size * 1.193) }
    /// Halber Durchschuss oben/unten (erste/letzte Zeile)
    static func halfLeading(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat { extra(size, lineHeight) / 2 }
}

/// Fläche aus Farbe mit Anteil über `--surface` (CSS `color-mix(in srgb, farbe p%, var(--surface))`)
struct BankMix: View {
    let color: Color
    let p: Double
    var radius: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(KColor.surface)
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(color.opacity(p))
        }
    }
}

/// Haken (Web `M5 12.5l4.5 4.5L19 7.5` bzw. CSS-Winkel): in den Rahmen eingepasst
struct BankCheckGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.5))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.32, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// Auswahl als Haken-Abzeichen unten rechts am Logo (Web v327 `.bkr > .bkck`): 22 pt mit 2.5 pt Rand in `--surface`;
/// aus = Ring 1.6 pt ink3, an = Messing mit Haken. `known` = schon erfasst (`.bkok`, Messing 30 %, nicht antippbar).
struct BankBadge: View {
    let on: Bool
    var known = false

    var body: some View {
        ZStack {
            Circle().fill(KColor.surface)
            if known {
                Circle().fill(KColor.brass.opacity(0.30)).padding(2.5)
                BankCheckGlyph().stroke(KColor.teal, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 8, height: 6)
            } else if on {
                Circle().fill(KColor.brassFab).padding(2.5)
                BankCheckGlyph().stroke(KColor.onBrass, style: StrokeStyle(lineWidth: 2, lineCap: .butt, lineJoin: .miter))
                    .frame(width: 8, height: 6)
            } else {
                Circle().strokeBorder(KColor.ink3, lineWidth: 1.6).padding(2.5)
            }
        }
        .frame(width: 22, height: 22)
    }
}

/// Logo mit Abzeichen: Kachel 36 pt, Abzeichen 20 pt nach rechts/unten versetzt (Web left 34 / top 31 bei Kachel 14 / 11).
/// Mit `toggle` ist die ganze Kachel die Trefferfläche für die Auswahl (Web `::before` über das Logo).
struct BankMarkBadge<M: View>: View {
    let mark: M
    var on = true
    var dim = false
    var badge = true
    var known = false
    var label = ""
    var toggle: (() -> Void)?

    var body: some View {
        let content = ZStack(alignment: .topLeading) {
            mark.opacity(dim ? 0.45 : 1)
            if badge || known {
                BankBadge(on: on, known: known).offset(x: 20, y: 20)
            }
        }
        .frame(width: 42, height: 42, alignment: .topLeading)
        .padding(.trailing, -6)
        .padding(.bottom, -6)
        if let t = toggle {
            Button(action: t) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(label)
                .accessibilityAddTraits(on ? [.isSelected] : [])
                .accessibilityValue(on ? "ausgewählt" : "nicht ausgewählt")
        } else {
            content.accessibilityHidden(true)
        }
    }
}

/// Plaketten unter der Zeile (Web `.bkq`): 11 pt, 4/7 Innenabstand, Radius 20; Anzahl antippen klappt die Zahlungen auf
struct BankChipsRow: View {
    let chips: [BankChip]
    let expanded: Bool
    let id: String
    let onPay: () -> Void

    var body: some View {
        BankFlow(spacing: 5) {
            ForEach(chips, id: \.self) { c in
                if c.kind == .payments {
                    Button(action: onPay) {
                        HStack(spacing: 3) {
                            Text(c.text)
                            Path { p in
                                p.move(to: CGPoint(x: 7, y: 10))
                                p.addLine(to: CGPoint(x: 12, y: 15))
                                p.addLine(to: CGPoint(x: 17, y: 10))
                            }
                            .applying(CGAffineTransform(scaleX: 11 / 24, y: 11 / 24))
                            .stroke(style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                            .frame(width: 11, height: 11)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                        }
                        .modifier(BankChipStyle(fg: expanded ? KColor.paper : KColor.ink2, bg: AnyView(Capsule().fill(expanded ? KColor.ink : KColor.sunken))))
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(expanded ? "aufgeklappt" : "zugeklappt")
                    .accessibilityIdentifier("bankPay-" + id)
                } else if c.kind == .price {
                    Text(c.text).modifier(BankChipStyle(fg: KColor.teal, bg: AnyView(BankMix(color: KColor.brass, p: 0.18, radius: 20))))
                } else {
                    Text(c.text).modifier(BankChipStyle(fg: KColor.ink2, bg: AnyView(Capsule().fill(KColor.sunken))))
                }
            }
        }
    }
}

struct BankChipStyle: ViewModifier {
    let fg: Color
    let bg: AnyView

    func body(content: Content) -> some View {
        content
            .font(.system(size: 11))
            .foregroundStyle(fg)
            .lineLimit(1)
            // Web line-height 1 + 4/4 Innenabstand = 19 hoch
            .frame(height: 19)
            .padding(.horizontal, 7)
            .background(bg.clipShape(Capsule()))
    }
}

/// Aufgeklappte Zahlungen (Web `.bkpay`): neueste zuerst, 12 sichtbar, «Alle n anzeigen»; neuer Preis Messing, einmalig/gratis grau
struct BankPayList: View {
    let rows: [BankPayRow]
    let currency: String
    let all: Bool
    let onAll: () -> Void

    var body: some View {
        let n = all ? rows.count : Swift.min(12, rows.count)
        VStack(spacing: 0) {
            ForEach(0..<n, id: \.self) { j in
                let r = rows[j]
                if j > 0 { Rectangle().fill(KColor.line).frame(height: 1) }
                HStack(spacing: 8) {
                    Text(r.label).foregroundStyle(KColor.ink2)
                    Spacer(minLength: 0)
                    Text(r.value(currency))
                        .fontWeight(r.changed ? .semibold : .medium)
                        .foregroundStyle(r.amount == nil ? KColor.ink3 : r.changed ? KColor.teal : r.odd ? KColor.ink3 : KColor.ink)
                }
                .font(.system(size: 13).monospacedDigit())
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
            if rows.count > n {
                Rectangle().fill(KColor.line).frame(height: 1)
                Button(action: onAll) {
                    Text("Alle \(rows.count) anzeigen")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(KColor.teal)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 7)
                        .padding(.bottom, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
    }
}

/// Rückfrage als Box unter der Zeile (Web v327 `.bkdup`): Titel, Erklärung, zwei Knöpfe
struct BankAskBox: View {
    let title: String
    let text: String
    let yes: String
    let no: String
    /// gewählte Antwort: true = erster Knopf, false = zweiter, nil = offen
    let answer: Bool?
    var id = ""
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(BankType.extra(13.5, 18.225))
                .foregroundStyle(KColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                button(yes, on: answer == true, action: onYes).accessibilityIdentifier("bankAskYes-" + id)
                button(no, on: answer == false, action: onNo).accessibilityIdentifier("bankAskNo-" + id)
            }
            .padding(.top, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
    }

    private func button(_ t: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(on ? KColor.onBrass : KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? KColor.brassFab : KColor.surface))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// «Ja, übernehmen» / «Nein» (`.bkyn button`): Fläche sunken, 14.5 pt halbfett, Radius 11; gewählt = Messing
struct BankYesNo: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(on ? KColor.onBrass : KColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? KColor.brassFab : KColor.sunken))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Schnellwahl `.bkchips button`: 13.5 pt, 7/12 Innenabstand, Rand line, Radius 20; gewählt = Messing
struct BankTermChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(on ? KColor.onBrass : KColor.ink)
                .kLineHeight(13.5, 19.575)
                // Innenabstand 7/12 plus Rand 1 → 35.6 hoch wie Web
                .padding(.vertical, 8)
                .padding(.horizontal, 13)
                .background(Capsule().fill(on ? KColor.brassFab : KColor.surface))
                .overlay(Capsule().strokeBorder(on ? KColor.brassFab : KColor.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Umbrechende Reihe (CSS `flex-wrap`)
struct BankFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = Swift.max(rowH, sz.height)
            w = Swift.max(w, x - spacing)
        }
        return CGSize(width: proposal.width ?? w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = Swift.max(rowH, sz.height)
        }
    }
}
