import SwiftUI
import KontivoCore

/// Fenster «Alle Einnahmen» (Web `openIncAll` im Auswahlblatt): Titel 22 px, «×», Liste auf Feldfarbe nach heutigem Betrag
/// absteigend (beendete/künftige blass), «Einnahme erfassen», «Schliessen». Tippen öffnet die Einnahme-Ansicht (Web v155).
struct IncomesAllView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let calc = model.calc
        let list = calc.kbAllIncomes()
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text("Alle Einnahmen")
                        .font(KFont.title(22))
                        .tracking(-0.264)
                        .foregroundStyle(KColor.ink)
                        .padding(.top, 2)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("incomes.title")
                    Spacer(minLength: 12)
                    KBRoundButton(edge: .clear, fill: KColor.sunken, action: { model.dismissTop() }) {
                        Text(verbatim: "×").font(.system(size: 20))
                    }
                    .accessibilityLabel("Schliessen")
                    .padding(.top, -16)
                    .padding(.trailing, -12)
                }
                .padding(.bottom, 3)
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
                        .padding(.vertical, 13 + KBM.pad(20.3, 14))
                        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 9)
            }
            .padding(.horizontal, KBM.side)
            .padding(.top, 30)
            .padding(.bottom, 18)
        }
        .background(KColor.paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
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
