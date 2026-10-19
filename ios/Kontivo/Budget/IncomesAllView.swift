import SwiftUI
import KontivoCore

/// Fenster «Alle Einnahmen» (Web `openIncAll` im Auswahlblatt): Titel 22 px, «×», Liste auf Feldfarbe nach heutigem Betrag
/// absteigend (beendete/künftige blass), «Einnahme erfassen», «Schliessen». Tippen öffnet die Einnahme-Ansicht (Web v155).
struct IncomesAllView: View {
    @Environment(AppModel.self) private var model
    /// Höhe des Inhalts (für die Blatthöhe wie im Web)
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        let calc = model.calc
        let list = calc.kbAllIncomes()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Web `h2#pickTitle`: 22 px Semibold, Zeilenhöhe 31.9, rechts 44 frei für «×»
                Text("Alle Einnahmen")
                    .font(KFont.title(22))
                    .tracking(-0.264)
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .frame(height: 31.9)
                    .padding(.trailing, 44)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("incomes.title")
                if !list.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { k, i in
                            if k > 0 { KBRowDivider() }
                            row(i, calc: calc)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: KBM.listRadius, style: .continuous).fill(KColor.field))
                    .clipShape(RoundedRectangle(cornerRadius: KBM.listRadius, style: .continuous))
                    .padding(.top, 12)
                    .padding(.bottom, 6)
                }
                Button {
                    model.present(.incomeForm(nil))
                } label: {
                    Text("Einnahme erfassen")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10 + KBM.pad(19.575, 13.5))
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 12)
                .accessibilityIdentifier("incomes.add")
                Button {
                    model.dismissTop()
                } label: {
                    Text("Schliessen")
                        .font(.system(size: 14))
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14 + KBM.pad(20.3, 14))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 13)
            }
            .padding(.horizontal, KBM.side)
            .padding(.top, 32)
            .padding(.bottom, 18)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .overlay(alignment: .topTrailing) {
            // Web `.pickx`: 36 pt Kreis versenkt, 16 pt unter der Blattkante, 12 pt vom Rand
            KBRoundButton(edge: .clear, fill: KColor.sunken, action: { model.dismissTop() }) {
                Text(verbatim: "×").font(.system(size: 20))
            }
            .accessibilityLabel("Schliessen")
            .padding(.top, 16)
            .padding(.trailing, 12)
        }
        .background(KColor.paper.ignoresSafeArea())
        // Web: Blatt so hoch wie der Inhalt (+ unterer Sicherheitsabstand), höchstens ganz offen
        .presentationDetents([.height(contentHeight > 0 ? contentHeight + 34 : 545), .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ i: Income, calc: Calc) -> some View {
        let st = calc.kbIncomeStatus(i)
        return Button {
            model.present(.incomeDetail(i.id))
        } label: {
            KBIncomeRowLabel(income: i, title: i.title, sub: st.text, amount: Format.money(calc.curPrice(i), i.currency),
                             currency: i.currency != calc.home ? i.currency.rawValue : nil, subMuted: true)
                .opacity(st.off ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
