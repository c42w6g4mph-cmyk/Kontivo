import SwiftUI
import UIKit
import MessageUI
import KontivoCore

/// Kündigungsschreiben direkt verschicken oder drucken (aus dem Brief und aus dem PDF-Viewer):
/// - Mail mit PDF-Anhang (MFMailComposeViewController); ohne Mail-Konto Teilen-Menü mit dem PDF
/// - Drucken (UIPrintInteractionController) mit dem PDF
/// Nach dem Senden bzw. Teilen folgt (ausser bei Miete) die Rückfrage «Gekündigt?».
@MainActor
enum LetterActions {
    /// «Per Mail senden»: Mail-Fenster über `over`; ohne Mail-Konto das Teilen-Menü.
    static func sendMail(_ model: AppModel, pdf: Data, fileName: String, info: LetterDocumentInfo,
                         contractID: UUID?, trial: Bool, over: AppSheet) {
        let name = pdfName(fileName)
        let ask = info.isRent ? nil : contractID
        guard MFMailComposeViewController.canSendMail() else {
            model.toast("Kein Mail-Konto eingerichtet – PDF mit einer anderen App senden")
            share(model, pdf: pdf, fileName: name, askContractID: ask, trial: trial)
            return
        }
        let draft = MailDraft(to: info.recipient.isEmpty ? [] : [info.recipient],
                              subject: info.subject,
                              body: info.attachmentMailBody,
                              attachment: pdf,
                              attachmentName: name,
                              attachmentType: "application/pdf",
                              cancelContractID: ask,
                              cancelTrial: trial)
        // Doppeltippen: nur öffnen, solange `over` zuoberst liegt
        CancelWindowFlow.present(model, .mail(draft), over: over)
    }

    /// Teilen-Menü mit der Datei (z.B. andere Mail-App, Dateien, AirDrop). Nach erfolgreichem Teilen optional «Gekündigt?».
    static func share(_ model: AppModel, pdf: Data, fileName: String, askContractID: UUID?, trial: Bool) {
        guard let url = DocShareFile.write(pdf, name: fileName), let top = CancelFlowUI.topViewController() else {
            model.toast("Teilen fehlgeschlagen")
            return
        }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.completionWithItemsHandler = { _, completed, _, _ in
            Task { @MainActor in
                DocShareFile.remove(url)
                guard completed, let id = askContractID, model.data.contract(id) != nil else { return }
                // kurz warten, bis das Teilen-Menü weg ist
                try? await Task.sleep(nanoseconds: 450_000_000)
                model.cancelQuestion = PendingCancel(contractID: id, trial: trial)
            }
        }
        if let pop = vc.popoverPresentationController, let v = top.view {
            pop.sourceView = v
            pop.sourceRect = CGRect(x: v.bounds.midX, y: v.bounds.maxY - 90, width: 1, height: 1)
            pop.permittedArrowDirections = [.down]
        }
        top.present(vc, animated: true)
    }

    /// «Drucken»: Druckdialog des Systems mit der Datei. false = nicht druckbar (Toast gezeigt).
    @discardableResult
    static func printPDF(_ model: AppModel, data: Data, jobName: String, photo: Bool = false) -> Bool {
        guard UIPrintInteractionController.canPrint(data) else {
            model.toast("Drucken ist für diese Datei nicht möglich")
            return false
        }
        let pic = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = photo ? .photo : .general
        info.jobName = jobName
        pic.printInfo = info
        pic.printingItem = data
        if UIDevice.current.userInterfaceIdiom == .pad, let top = CancelFlowUI.topViewController(), let v = top.view {
            // iPad: Druckdialog als Popover über der Aktionsleiste
            let rect = CGRect(x: v.bounds.midX - 1, y: v.bounds.maxY - 90, width: 2, height: 2)
            _ = pic.present(from: rect, in: v, animated: true, completionHandler: nil)
        } else {
            _ = pic.present(animated: true, completionHandler: nil)
        }
        return true
    }

    /// Dateiname mit «.pdf».
    static func pdfName(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { n = "Kuendigung" }
        n = n.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
        return DocShareFile.hasExtension(n) ? n : n + ".pdf"
    }
}
