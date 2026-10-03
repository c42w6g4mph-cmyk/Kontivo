import SwiftUI
import UIKit
import MessageUI
import KontivoCore

/// Mail verfassen (MFMailComposeViewController, Anhang optional). Schliesst sich nach Senden/Abbrechen selbst;
/// nach «gesendet» mit `cancelContractID` folgt die Rückfrage «Gekündigt?».
struct MailComposeView: View {
    let draft: MailDraft

    @Environment(AppModel.self) private var model

    var body: some View {
        if MFMailComposeViewController.canSendMail() {
            MailComposeRepresentable(draft: draft) { result in finish(result) }
                .interactiveDismissDisabled(true)
        } else {
            MailUnavailableView(draft: draft)
        }
    }

    private func finish(_ result: MFMailComposeResult) {
        let m = model
        let contractID = draft.cancelContractID
        let trial = draft.cancelTrial
        m.dismissTop()
        switch result {
        case .sent:
            if let id = contractID {
                // Erst nach dem Schliessen des Mail-Fensters fragen (sonst geht die Rückfrage verloren)
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 650_000_000)
                    guard m.data.contract(id) != nil else { return }
                    m.cancelQuestion = PendingCancel(contractID: id, trial: trial)
                }
            }
        case .failed:
            m.toast("Mail konnte nicht gesendet werden")
        default:
            break
        }
    }
}

private struct MailComposeRepresentable: UIViewControllerRepresentable {
    let draft: MailDraft
    let onFinish: @MainActor (MFMailComposeResult) -> Void

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        let to = draft.to.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !to.isEmpty { vc.setToRecipients(to) }
        vc.setSubject(draft.subject)
        vc.setMessageBody(draft.body, isHTML: false)
        if let a = draft.attachment {
            let name = draft.attachmentName.isEmpty ? "Anhang.pdf" : draft.attachmentName
            vc.addAttachmentData(a, mimeType: draft.attachmentType.isEmpty ? "application/pdf" : draft.attachmentType, fileName: name)
        }
        return vc
    }

    func updateUIViewController(_ uiViewController: MFMailComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onFinish: @MainActor (MFMailComposeResult) -> Void

        init(onFinish: @escaping @MainActor (MFMailComposeResult) -> Void) {
            self.onFinish = onFinish
        }

        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            let f = onFinish
            Task { @MainActor in f(result) }
        }
    }
}

/// Kein Mail-Konto eingerichtet: mailto: anbieten (ohne Anhang).
private struct MailUnavailableView: View {
    let draft: MailDraft

    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "envelope.badge")
                    .font(.system(size: 40))
                    .foregroundStyle(KColor.teal)
                Text("Auf diesem Gerät ist kein Mail-Konto eingerichtet.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(KColor.ink)
                if draft.attachment == nil {
                    Button {
                        openMailto()
                    } label: {
                        Text("In Mail öffnen").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Text("Tippe im Dokument auf «Teilen», um das PDF mit einer anderen App zu senden.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(KColor.ink2)
                }
            }
            .padding(28)
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .kPageBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { model.dismissTop() }
                }
            }
        }
    }

    private func openMailto() {
        guard let url = CancelLinks.mailto(to: draft.to.first ?? "", subject: draft.subject, body: draft.body) else { return }
        let pending = draft.cancelContractID.map { PendingCancel(contractID: $0, trial: draft.cancelTrial) }
        model.dismissTop()
        model.cancelFlowOpenExternal(url, pending: pending)
    }
}
