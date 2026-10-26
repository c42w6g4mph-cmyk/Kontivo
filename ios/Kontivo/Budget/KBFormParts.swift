import SwiftUI
import PhotosUI
import UIKit
import KontivoCore

// MARK: - Bausteine des Formulars (Web `.fsec`, `.fcard`, `.frow`)

/// Abschnittstitel (Web `h3.fsec`: 13 px Semibold Tinte 2, Abstand 22 oben, 8 unten)
struct KBFormSection: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(KColor.ink2)
            .frame(minHeight: 18.85)
            .padding(.horizontal, 2)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Weisse Karte (Web `.fcard`: Rundung 16, Innenrand 13)
struct KBFormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: KBM.cardRadius, style: .continuous).fill(KColor.surface))
    }
}

/// Zeile (Web `.frow`): Bezeichnung 15 px Tinte 2 links, Wert rechts, mind. 48 pt; `miss` = kurze Markierung (v219)
struct KBFormRow<Value: View>: View {
    let label: String
    var miss = false
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: label)
                .font(.system(size: 15))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            value
        }
        // Web `.frow`: 4 + Feld 39.2 + 4 (mit Linie 48.2)
        .padding(.vertical, 4)
        .frame(minHeight: 47.2)
        .background(KBMissFlash(on: miss))
    }
}

/// Markierung einer Zeile mit fehlender Angabe (Web v219 `.frow.miss::before`): Warnfarbe 16 % als abgerundete Fläche bis an den
/// Kartenrand (−8 pt), 3 pt oben/unten; bleibt 40 % der Zeit sichtbar und blendet in 1.8 s aus.
struct KBMissFlash: View {
    let on: Bool
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(KColor.alert.opacity(0.16))
            .padding(.vertical, 3)
            .padding(.horizontal, -8)
            .opacity(opacity)
            .onChange(of: on) { _, v in
                guard v else { return }
                opacity = 1
                withAnimation(.easeOut(duration: 1.08).delay(0.72)) { opacity = 0 }
            }
            .allowsHitTesting(false)
    }
}

/// Roter Rahmen um ein Kopffeld (Web v219 `.fht.miss`: 2 px, blendet aus)
struct KBMissRing: View {
    let on: Bool
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(KColor.alert, lineWidth: 2)
            .padding(-1)
            .opacity(opacity)
            .onChange(of: on) { _, v in
                guard v else { return }
                opacity = 1
                withAnimation(.easeOut(duration: 1.08).delay(0.72)) { opacity = 0 }
            }
            .allowsHitTesting(false)
    }
}

/// Wert einer Auswahl (Web `select`: 16 px Medium Akzent, Winkel rechts)
struct KBSelectValue: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KColor.teal)
                .lineLimit(1)
            KBChevronDown(expanded: false, color: KColor.ink2)
                .scaleEffect(0.9)
                .padding(.trailing, -6)
        }
        .padding(.vertical, 8)
    }
}

/// Chip «Empfänger» (Web `.chips button`): gewählt Tinte mit Papierschrift, sonst Rand
struct KBInkChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? KColor.paper : KColor.ink2)
                .lineLimit(1)
                .padding(.horizontal, 13)
                // Web: Rand 1 + Innenabstand 7/12 + Zeile 20.3 (Höhe 36.3)
                .padding(.vertical, 8 + KBM.pad(20.3, 14))
                .background(Capsule().fill(isOn ? KColor.ink : .clear))
                .overlay(Capsule().strokeBorder(isOn ? KColor.ink : KColor.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Knopf der Logo-Auswahl (Web `.lbtn`)
struct KBLogoButtonLabel: View {
    let title: String
    var destructive = false

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(destructive ? KColor.alert : KColor.ink)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
            .contentShape(Rectangle())
    }
}

/// Vorschaubild eines Internet-Treffers (Commons-Logo bzw. Website-Symbol) auf weisser Kachel 34 pt
struct KBWebThumb: View {
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white)
            .frame(width: 34, height: 34)
            .overlay {
                if let url {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
    }
}

/// Stift (Web `.ledit svg`: M4 20h4L19 9l-4-4L4 16z)
struct KBPencilGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 4 * s, y: 20 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 20 * s))
        p.addLine(to: CGPoint(x: 19 * s, y: 9 * s))
        p.addLine(to: CGPoint(x: 15 * s, y: 5 * s))
        p.addLine(to: CGPoint(x: 4 * s, y: 16 * s))
        p.closeSubpath()
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

/// Plus (Web `M12 5v14M5 12h14`)
struct KBPlusGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 12 * s, y: 5 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
        p.move(to: CGPoint(x: 5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

// MARK: - Tagesraster «Zahlung am» (Web v159 `dgHtml`)

/// 7 Spalten mit den Tagen 1–31 (gewählter Tag als Kreis), bei Rhythmus ≥ 2 Monate darüber die 12 Monate mit markierter
/// Reihe (z.B. Jan/Apr/Jul/Okt). Regeln: `ContractFormRules.dueGridMonths`, `dueGridShowsMonths`.
struct KBDueGrid: View {
    let day: Int
    let month: Int
    let cycle: Int
    var idPrefix = "due"
    let onDay: (Int) -> Void
    let onMonth: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if ContractFormRules.dueGridShowsMonths(cycle: cycle) {
                let on = ContractFormRules.dueGridMonths(month: month, cycle: cycle)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(1...12, id: \.self) { m in
                        let sel = on.contains(m)
                        Button {
                            onMonth(m)
                        } label: {
                            Text(verbatim: Format.monthShort[m - 1])
                                .font(.subheadline.weight(sel ? .semibold : .regular))
                                .foregroundStyle(sel ? Color.white : KColor.ink)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(sel ? KColor.tealFill : KColor.field))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: Format.monthNames[m - 1]))
                        .accessibilityAddTraits(sel ? .isSelected : [])
                        .accessibilityIdentifier(idPrefix + ".month.\(m)")
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(1...31, id: \.self) { n in
                    let sel = n == day
                    Button {
                        onDay(n)
                    } label: {
                        Text(verbatim: String(n))
                            .font(.body.weight(sel ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(sel ? Color.white : KColor.ink)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(sel ? KColor.tealFill : Color.clear))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(verbatim: String(n) + "."))
                    .accessibilityAddTraits(sel ? .isSelected : [])
                    .accessibilityIdentifier(idPrefix + ".day.\(n)")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Chips mit Zeilenumbruch

/// Einfache Fliess-Anordnung (Empfänger-Chips, Budget-Zeile «verfügbar nach Fixkosten · …»); Zeilen senkrecht zentriert.
struct KBChipFlow: Layout {
    var spacing: CGFloat = 8
    /// Abstand zwischen Zeilen (nil = `spacing`)
    var lineSpacing: CGFloat? = nil

    private func rows(_ maxW: CGFloat, _ subviews: Subviews) -> [[(Int, CGSize)]] {
        var out: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                out.append([])
                x = 0
            }
            out[out.count - 1].append((i, sz))
            x += sz.width + spacing
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let rs = rows(maxW, subviews)
        let ls = lineSpacing ?? spacing
        var h: CGFloat = 0, w: CGFloat = 0
        for (k, r) in rs.enumerated() {
            h += (r.map { $0.1.height }.max() ?? 0) + (k > 0 ? ls : 0)
            w = max(w, r.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, r.count - 1)))
        }
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rs = rows(bounds.width, subviews)
        let ls = lineSpacing ?? spacing
        var y = bounds.minY
        for r in rs {
            let rh = r.map { $0.1.height }.max() ?? 0
            var x = bounds.minX
            for (i, sz) in r {
                subviews[i].place(at: CGPoint(x: x, y: y + (rh - sz.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += rh + ls
        }
    }
}

/// Datum, das leer sein darf: «Datum wählen» bzw. DatePicker mit «×»
struct KBOptionalDateRow: View {
    let title: String
    @Binding var date: Day?
    var defaultDate: Day

    var body: some View {
        if let d = date {
            HStack(spacing: 8) {
                DatePicker(title,
                           selection: Binding(get: { d.date() }, set: { date = Day(date: $0) }),
                           displayedComponents: .date)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KColor.ink3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: title + ": Datum entfernen"))
            }
        } else {
            Button {
                date = defaultDate
            } label: {
                HStack {
                    Text(verbatim: title)
                        .foregroundStyle(KColor.ink)
                    Spacer()
                    Text("Datum wählen")
                        .foregroundStyle(KColor.teal)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
