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

    /// Web `openCancViaPick`: Online · Per E-Mail · Per Brief · Per Telefon (v210). Aus `CancelChannel.allCases`, damit «Telefon»
    /// erscheint, sobald der Kern den Weg kennt (TODO core-API).
    private let options: [Option] = CancelChannel.allCases.compactMap { ch in
        let t: [String: (String, String)] = [
            "Online / Kundenkonto": ("Online", "Kundenkonto, Kündigungsbutton"),
            "E-Mail": ("Per E-Mail", "Mail mit fertigem Text"),
            "Brief": ("Per Brief", "PDF mit Unterschrift"),
            "Telefon": ("Per Telefon", "Kundendienst anrufen"),
        ]
        guard let v = t[ch.webText] else { return nil }
        return Option(channel: ch, title: v.0, detail: v.1)
    }

    var body: some View {
        let c = model.data.contract(contractID)
        let title = c.map { model.data.title(of: $0) } ?? "Ohne Namen"
        // Web `openCancViaPick`: Auswahlblatt mit Titel «Wie kündigst du «…»?», Zeilen `.pick` und Hinweis
        CTPickSheet(title: "Wie kündigst du «\(title)»?") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(options) { o in
                    CTPickRow(title: o.title, detail: o.detail) { pick(o.channel) }
                        .accessibilityLabel(o.title + ", " + o.detail)
                }
                Text("Wird beim Vertrag gespeichert. Miete braucht immer einen Brief mit Unterschrift.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                    .ctLines(12.5, 19.375)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4).padding(.horizontal, 2)
            }
        }
        .presentationDetents([.medium, .large])
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
