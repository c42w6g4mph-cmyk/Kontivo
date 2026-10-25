import SwiftUI
import KontivoCore

// MARK: - «Fair geteilt?» (Web .fgcard): Balken = Anteil an den Fixkosten, Strich = Anteil an den Einnahmen

struct KBFairShareView: View {
    @Environment(AppModel.self) private var model
    let rows: [Calc.FairRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            KBGroupHeader(title: Calc.fairTitle, amount: Calc.fairSubtitle)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.personID) { idx, r in
                    if idx > 0 { KBRowDivider() }
                    HStack(spacing: 12) {
                        KBFairAvatar(person: model.data.person(r.personID))
                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: r.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(KColor.ink)
                                .lineLimit(1)
                                .frame(height: 21.75)
                            Text(verbatim: r.subline)
                                .font(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(KColor.ink3)
                                .lineLimit(1)
                                .frame(height: 18.1)
                            // Web `.fgbar`: 8 hoch, 6 oben; Strich 3 × 16 ragt oben und unten 4 heraus (ohne Platz zu belegen)
                            GeometryReader { g in
                                let w = g.size.width
                                ZStack(alignment: .leading) {
                                    Capsule().fill(KColor.line).frame(height: 8)
                                    Capsule().fill(KColor.teal.opacity(0.45)).frame(width: w * CGFloat(r.fixedPercent) / 100, height: 8)
                                }
                                .frame(height: 8)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(KColor.ink).frame(width: 3, height: 16)
                                        .offset(x: w * CGFloat(r.incomePercent) / 100 - 1.5)
                                }
                            }
                            .frame(height: 8)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
                Text(verbatim: Calc.fairHint)
                    .font(.system(size: 12.5))
                    .kLineHeight(12.5, 18.125)
                    .foregroundStyle(KColor.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .kbSurface(KBM.listRadius)
        }
        // Web `.grp` padding-bottom 2
        .padding(.bottom, 2)
        .accessibilityIdentifier("budget.fair")
    }
}

/// Personenbild in «Fair geteilt?» (Web `avHtml`/`.mdav`): 38 pt Kreis Messing mit weisser Initiale 15 px Bold, sonst Foto
struct KBFairAvatar: View {
    @Environment(AppModel.self) private var model
    let person: Person?

    var body: some View {
        ZStack {
            if let img = model.image(person?.avatarID) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Circle().fill(KColor.tealFill)
                Text(verbatim: String((person?.name ?? "?").prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}
