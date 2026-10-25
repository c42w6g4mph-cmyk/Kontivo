import SwiftUI
import KontivoCore

/// Rückfrage beim Markieren als gekündigt (Web v249 `askCancelled`): Titel «Gekündigt?», «Brief verschickt?» bzw. «Schon gekündigt»
struct CancelledAsk: Hashable {
    let contractID: UUID
    let trial: Bool
    let title: String
    /// eigener Text («Wann hast du … gekündigt? …»); nil = Standardtext
    let text: String?
}

/// Einheitliche Rückfrage mit «Gekündigt am» (Standard heute, nicht in der Zukunft) und «Läuft bis» (folgt dem Kündigungsdatum
/// über `Calc.endAsOf`, bis von Hand geändert). «Ja, gekündigt» markiert mit beiden Daten (`AppData.markCancelled(on:)`).
struct CancelledAskSheet: View {
    let ask: CancelledAsk

    @Environment(AppModel.self) private var model
    @State private var on: Day?
    @State private var per: Day?
    /// «Läuft bis» von Hand geändert: folgt «Gekündigt am» nicht mehr
    @State private var touched = false
    @State private var done = false

    var body: some View {
        NavigationStack {
            Group {
                if let c = model.data.contract(ask.contractID) {
                    form(c)
                } else {
                    Text("Dieser Vertrag existiert nicht mehr.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(ask.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Noch nicht") { model.dismissTop() }
                        .accessibilityIdentifier("cancelled.no")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ja, gekündigt") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(model.data.contract(ask.contractID) == nil)
                        .accessibilityIdentifier("cancelled.yes")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .environment(\.locale, Locale(identifier: "de_CH"))
    }

    private var today: Day { model.today }

    private func defaultEnd(_ c: Contract, from d: Day) -> Day {
        Calc.endAsOf(c, cancelledOn: d, trial: ask.trial, data: model.data) ?? d
    }

    private func form(_ c: Contract) -> some View {
        let onDay = on ?? today
        let perDay = per ?? defaultEnd(c, from: onDay)
        let text = ask.text ?? "«" + model.data.title(of: c) + "» als gekündigt markieren. Der Vertrag zählt bis zum Ende weiter und wandert danach ins Archiv."
        return Form {
            Section {
                DatePicker("Gekündigt am", selection: Binding(get: { onDay.date() }, set: { v in
                    let d = Day(date: v)
                    on = d
                    if !touched { per = defaultEnd(c, from: d) }
                }), in: ...today.date(), displayedComponents: .date)
                    .accessibilityIdentifier("cancelled.on")
                DatePicker("Läuft bis", selection: Binding(get: { perDay.date() }, set: { v in
                    per = Day(date: v)
                    touched = true
                }), displayedComponents: .date)
                    .accessibilityIdentifier("cancelled.per")
            } header: {
                Text(verbatim: text)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            } footer: {
                Text("Steht ein anderes Enddatum in der Kündigungsbestätigung, trag dieses ein.")
            }
            .listRowBackground(KColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(KColor.paper.ignoresSafeArea())
    }

    private func confirm() {
        guard !done, let c = model.data.contract(ask.contractID) else { return }
        done = true
        let onDay = on ?? today
        let perDay = per ?? defaultEnd(c, from: onDay)
        let id = ask.contractID, trial = ask.trial
        let m = model
        m.dismissTop {
            m.cancelFlowMarkCancelled(id, trial: trial, per: perDay, on: onDay)
        }
    }
}

extension AppModel {
    /// Rückfrage «Gekündigt am» / «Läuft bis» öffnen, sobald offene Fenster geschlossen sind (Web `askCancelled`).
    func presentCancelledAsk(_ contractID: UUID, trial: Bool, title: String, text: String? = nil) {
        guard data.contract(contractID) != nil else { return }
        let a = CancelledAsk(contractID: contractID, trial: trial, title: title, text: text)
        afterDismiss { [weak self] in self?.present(.cancelledAsk(a)) }
    }

    /// «Schon gekündigt»: Text mit Hinweis, dass das Vertragsende ab dem Kündigungsdatum gerechnet wird (Web v249).
    func presentAlreadyCancelled(_ contractID: UUID, trial: Bool) {
        guard let c = data.contract(contractID) else { return }
        presentCancelledAsk(contractID, trial: trial, title: "Schon gekündigt",
                            text: "Wann hast du «" + data.title(of: c) + "» gekündigt? Das Vertragsende rechnet Kontivo ab diesem Tag.")
    }
}
