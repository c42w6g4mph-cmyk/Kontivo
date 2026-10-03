import SwiftUI
import KontivoCore

/// Fenster «Alle Einnahmen»: nach heutigem Betrag absteigend; Tippen öffnet das Formular.
struct IncomesAllView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let calc = model.calc
        let list = calc.kbAllIncomes()
        NavigationStack {
            List {
                if !list.isEmpty {
                    Section {
                        ForEach(list) { i in
                            row(i, calc: calc)
                        }
                    }
                }
                Section {
                    Button {
                        model.present(.incomeForm(nil))
                    } label: {
                        Label("Einnahme erfassen", systemImage: "plus")
                            .font(.body.weight(.semibold))
                    }
                    .listRowBackground(KColor.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper)
            .navigationTitle("Alle Einnahmen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { CloseButton() }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.present(.incomeForm(nil))
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Einnahme erfassen")
                }
            }
        }
    }

    private func row(_ i: Income, calc: Calc) -> some View {
        let st = calc.kbIncomeStatus(i)
        return Button {
            model.present(.incomeForm(i.id))
        } label: {
            HStack(spacing: 11) {
                MarkView(income: i, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: i.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                    Text(verbatim: st.text)
                        .font(.caption)
                        .foregroundStyle(KColor.ink3)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: Format.money(calc.curPrice(i)))
                        .font(.body.weight(.semibold).monospacedDigit())
                        .foregroundStyle(KColor.ink)
                    if i.currency != calc.home {
                        Text(verbatim: i.currency.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(KColor.ink3)
                    }
                }
            }
            .opacity(st.off ? 0.5 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(KColor.surface)
        .accessibilityElement(children: .combine)
    }
}
