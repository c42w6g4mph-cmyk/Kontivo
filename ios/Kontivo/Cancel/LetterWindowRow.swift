import SwiftUI
import KontivoCore

/// «Kuvert-Fenster Links | Rechts» (Web v229 `.ltwin`, `settings.ltWin`): Lage der Anschrift im PDF; gilt für alle Briefe.
struct LetterWindowRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let right = model.data.settings.letterWindowRight
        HStack(spacing: 10) {
            Text("Kuvert-Fenster")
                .font(.system(size: 13))
                .foregroundStyle(KColor.ink2)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                button("Links", on: !right) { set(false) }
                button("Rechts", on: right) { set(true) }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
            .frame(minWidth: 170)
            .fixedSize()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kuvert-Fenster")
            .accessibilityIdentifier("letter.window")
        }
        .padding(.top, 8)
    }

    private func set(_ r: Bool) {
        _ = model.update { $0.settings.letterWindowRight = r }
        model.toast(r ? "Adresse rechts (Schweizer Kuvert mit Fenster rechts)" : "Adresse links (DIN-Kuvert, Fenster links)")
    }

    private func button(_ t: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: t)
                .font(.system(size: 13, weight: on ? .semibold : .medium))
                .foregroundStyle(on ? KColor.ink : KColor.ink2)
                .frame(minWidth: 77)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? KColor.surface : .clear)
                    .shadow(color: .black.opacity(on ? 0.08 : 0), radius: 1, y: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
