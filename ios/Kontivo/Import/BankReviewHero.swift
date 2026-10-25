import SwiftUI
import KontivoCore

/// Kopfkarte (Web v323 `.bkhero`): überlappende Logos bzw. Kategorie-Symbole, «n Verträge erkannt», Kategorien als Satz
struct BankHeroCard: View {
    let hero: BankReview.Hero
    let income: Bool

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: -9) {
                if hero.marks.isEmpty && hero.more == 0 {
                    more("✓")
                }
                ForEach(hero.marks) { m in
                    MarkView(logoID: m.logo?.id, logoBg: m.logo?.bg, colorHex: m.colorHex, symbol: m.symbol, size: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.surface))
                        .padding(-3)
                }
                if hero.more > 0 { more("+\(hero.more)") }
            }
            .padding(.trailing, 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(hero.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !hero.sub.isEmpty || !hero.em.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        if !hero.sub.isEmpty { Text(hero.sub).foregroundStyle(KColor.ink2) }
                        if !hero.em.isEmpty { Text(hero.em).foregroundStyle(KColor.teal) }
                    }
                    .font(.system(size: 13))
                    .lineSpacing(BankType.extra(13, 17.55))
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KColor.surface)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [(income ? Color(red: 0x5F / 255, green: 0xB4 / 255, blue: 0x87 / 255) : KColor.brass)
                                            .opacity(income ? 0.26 : 0.20), .clear],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        )
        .padding(.top, 2)
        .padding(.bottom, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bankHero")
    }

    private func more(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(KColor.ink2)
            .frame(width: 38, height: 38)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.sunken))
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.surface))
            .padding(-3)
    }
}

/// Segment `.hseg` (in «Zuordnen an»): Fläche sunken mit Ring, Knopf 13.5 pt; gewählt = ink mit paper
struct BankSegment: View {
    let options: [(UUID, String)]
    let selected: UUID?
    let action: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { j in
                let o = options[j]
                let on = o.0 == selected
                Button { action(o.0) } label: {
                    Text(o.1)
                        .font(.system(size: 13.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? KColor.paper : KColor.ink2)
                        .kLineHeight(13.5, 19.575)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(on ? KColor.ink : Color.clear)
                                .shadow(color: on ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
    }
}
