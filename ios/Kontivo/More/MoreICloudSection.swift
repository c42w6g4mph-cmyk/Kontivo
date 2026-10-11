import SwiftUI
import KontivoCore

/// «Mehr → Daten»: Schalter «iCloud-Sync» mit Zustand und kurzer Erklärung (iOS-typisch wie bei anderen Apps).
/// Build ohne iCloud-Berechtigung: im Release nichts, im Debug-Build eine graue Zeile.
struct MoreICloudSection: View {
    @Environment(AppModel.self) private var model
    @State private var askOff = false
    @State private var askDelete = false
    @State private var askAccount = false

    var body: some View {
        if model.sync.buildEnabled {
            section(model.sync)
        } else {
            #if DEBUG
            Text(SyncTexts.buildOff)
                .font(.caption)
                .foregroundStyle(KColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 10)
                .accessibilityIdentifier("more.icloud.unavailable")
            #endif
        }
    }

    private func section(_ sync: SyncController) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(get: { sync.isOn }, set: { on in
                if on { sync.turnOn() } else { askOff = true }
            })) {
                HStack(spacing: 12) {
                    MoreManageIcon(symbol: "icloud.fill", color: KColor.teal)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(SyncTexts.title)
                            .font(.body)
                            .foregroundStyle(KColor.ink)
                        Text(SyncTexts.status(sync.status, lastSync: sync.lastSync))
                            .font(.caption)
                            .foregroundStyle(tone(sync.status))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .tint(KColor.teal)
            .disabled(!sync.canToggle)
            .accessibilityIdentifier("more.icloud")

            if sync.status == .accountChanged {
                Button(SyncTexts.accountButton) { askAccount = true }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(KColor.teal)
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.leading, 42)
                    .accessibilityIdentifier("more.icloud.account")
            }

            Text(SyncTexts.explanation)
                .font(.caption)
                .foregroundStyle(KColor.ink2)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            MoreLine()
                .padding(.top, 12)
                .padding(.bottom, 12)
        }
        .confirmationDialog(SyncTexts.offTitle, isPresented: $askOff, titleVisibility: .visible) {
            Button(SyncTexts.offButton) {
                Task { await sync.turnOff(deleteFromICloud: false) }
            }
            Button(SyncTexts.offDeleteButton, role: .destructive) {
                // Eigene Rückfrage, sobald diese geschlossen ist
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    askDelete = true
                }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(SyncTexts.offMessage)
        }
        .alert(SyncTexts.deleteTitle, isPresented: $askDelete) {
            Button(SyncTexts.deleteButton, role: .destructive) {
                Task { await sync.turnOff(deleteFromICloud: true) }
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(SyncTexts.deleteMessage)
        }
        .alert(SyncTexts.accountTitle, isPresented: $askAccount) {
            Button(SyncTexts.accountOK) { sync.adoptCurrentAccount() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(SyncTexts.accountMessage)
        }
    }

    private func tone(_ s: SyncStatus) -> Color {
        switch s {
        case .quotaFull, .accountChanged, .deletedElsewhere, .failed: return KColor.warn
        default: return KColor.ink3
        }
    }
}
