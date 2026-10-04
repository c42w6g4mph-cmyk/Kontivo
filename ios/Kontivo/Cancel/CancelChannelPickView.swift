import SwiftUI
import KontivoCore

/// Auswahl des Kündigungswegs («Wie kündigst du «Titel»?»). Speichert den Weg beim Vertrag und startet danach
/// die passende Aktion (Link, Mail, Brief).
struct CancelChannelPickView: View {
    let contractID: UUID
    let trial: Bool

    @Environment(AppModel.self) private var model
    /// Weg gewählt (gegen Doppeltippen)
    @State private var picked = false

    private struct Option: Identifiable {
        let channel: CancelChannel
        let title: String
        let detail: String
        var id: String { channel.rawValue }
    }

    private let options: [Option] = [
        Option(channel: .online, title: "Online", detail: "Kundenkonto, Kündigungsbutton"),
        Option(channel: .email, title: "Per E-Mail", detail: "Mail mit fertigem Text"),
        Option(channel: .letter, title: "Per Brief", detail: "PDF mit Unterschrift"),
    ]

    var body: some View {
        let c = model.data.contract(contractID)
        let title = c.map { model.data.title(of: $0) } ?? "Ohne Namen"
        NavigationStack {
            List {
                Section {
                    ForEach(options) { o in
                        Button { pick(o.channel) } label: { row(o, current: c?.cancelChannel) }
                            .accessibilityLabel(o.title + ", " + o.detail)
                    }
                } header: {
                    Text("Wie kündigst du «\(title)»?")
                        .font(.headline)
                        .foregroundStyle(KColor.ink)
                        .textCase(nil)
                        .padding(.bottom, 4)
                } footer: {
                    Text("Wird beim Vertrag gespeichert. Miete braucht immer einen Brief mit Unterschrift.")
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper.ignoresSafeArea())
            .navigationTitle("Kündigungsweg")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { CancelWindowFlow.dismiss(model, ifTop: .cancelChannelPick(contractID, trial: trial)) }
                }
            }
        }
    }

    private func row(_ o: Option, current: CancelChannel?) -> some View {
        HStack(spacing: 12) {
            Text(o.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(KColor.ink)
            Spacer(minLength: 8)
            Text(o.detail)
                .font(.subheadline)
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.trailing)
            if current == o.channel {
                Image(systemName: "checkmark").foregroundStyle(KColor.teal).fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
    }

    private func pick(_ ch: CancelChannel) {
        // Doppeltippen: nur einmal auslösen und nur dieses Fenster schliessen
        guard !picked else { return }
        let m = model
        let me = AppSheet.cancelChannelPick(contractID, trial: trial)
        guard CancelWindowFlow.isTop(m, me) else { return }
        picked = true
        let id = contractID
        let t = trial
        m.update { $0.setCancelChannel(id, ch) }
        CancelWindowFlow.dismiss(m, ifTop: me)
        // Nach dem Schliessen dieses Fensters die passende Aktion auslösen
        CancelWindowFlow.afterDismiss(m, still: { m.data.contract(id) != nil }) {
            m.startCancel(id, trial: t)
        }
    }
}
