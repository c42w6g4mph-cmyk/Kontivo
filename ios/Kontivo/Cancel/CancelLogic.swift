import SwiftUI
import UIKit
import MessageUI
import KontivoCore

/// Kündigung starten, Rückfrage «Gekündigt?» und «Als gekündigt markieren» (Web: Detail-Knöpfe, kPending, markCancelled).
extension AppModel {
    /// Startet die Kündigung je nach Kündigungsweg (Online → Link, E-Mail → Mail, Brief → Kündigungsschreiben, offen → Auswahl).
    /// Miete immer per Brief (Calc.cancVia).
    func startCancel(_ contractID: UUID, trial: Bool) {
        guard let c = data.contract(contractID) else { return }
        let calc = self.calc
        switch calc.cancVia(c) {
        case .online:
            cancelFlowOnline(c, trial: trial, calc: calc)
        case .mail:
            cancelFlowMail(c, trial: trial, calc: calc)
        case .post:
            present(.letter(contractID, trial: trial))
        case .none:
            present(.cancelChannelPick(contractID, trial: trial))
        }
    }

    /// Beim Zurückkehren in die App: Rückfrage «Gekündigt?» (setzt cancelQuestion), wenn eine Kündigung über Website/E-Mail gestartet wurde.
    func cancelReturnCheck() {
        guard let p = pendingCancel, p.leftApp else { return }
        pendingCancel = nil
        guard data.contract(p.contractID) != nil else { return }
        let q = PendingCancel(contractID: p.contractID, trial: p.trial)
        CancelWindowFlow.afterDismiss(self, wait: CancelWindowFlow.Wait.returnToApp, keepStack: false,
                                      still: { [weak self] in self?.data.contract(q.contractID) != nil }) { [weak self] in
            self?.cancelQuestion = q
        }
    }

    /// Text der Rückfrage «Gekündigt?»: ««Titel» als gekündigt markieren, läuft bis …. Der Vertrag zählt …»
    func cancelQuestionText(_ q: PendingCancel) -> String {
        guard let c = data.contract(q.contractID) else { return "" }
        let end = calc.cancelEnd(c, trial: q.trial)
        return "«" + data.title(of: c) + "» als gekündigt markieren" + (end.map { ", läuft bis " + Format.fmtD($0) } ?? "")
            + ". Der Vertrag zählt bis zum Ende weiter und wandert danach ins Archiv."
    }

    /// Antwort auf die Rückfrage. «Ja» markiert als gekündigt (mit Probeabo-Kennung, Fix M6).
    func answerCancelQuestion(_ q: PendingCancel, cancelled: Bool) {
        cancelQuestion = nil
        guard cancelled else { return }
        cancelFlowMarkCancelled(q.contractID, trial: q.trial)
    }

    // MARK: Gemeinsame Abläufe (Fristen-Tab, Rückfrage, Kündigungsweg)

    /// «Als gekündigt markieren»: speichert cancelPer/cancelledOn, schliesst die Fenster und zeigt den Toast.
    /// Pflichtvertrag: öffnet danach das Formular «Neuer Anbieter» mit dem Entwurf aus markCancelled.
    func cancelFlowMarkCancelled(_ contractID: UUID, trial: Bool) {
        var result: CancelResult?
        let day = today
        let ok = update { d in result = d.markCancelled(contractID, trial: trial, today: day) }
        guard ok, let r = result else { return }
        toast(r.toast)
        if let draft = r.replacement {
            let msg = r.replacementToast
            cancelFlowPresent(.contractForm(.newProvider(draft)), closingOthers: true) { [weak self] in
                if let msg { self?.toast(msg) }
            }
        } else {
            dismissAll()
        }
    }

    /// Fenster öffnen; mit `closingOthers` zuerst alle offenen Fenster schliessen (Ablauf in CancelWindowFlow).
    func cancelFlowPresent(_ sheet: AppSheet, closingOthers: Bool, then done: (() -> Void)? = nil) {
        if closingOthers {
            CancelWindowFlow.presentClosingOthers(self, sheet, then: done)
        } else {
            present(sheet)
            done?()
        }
    }

    /// Externen Link (Website, mailto) öffnen und optional die Rückfrage «Gekündigt?» für die Rückkehr vormerken.
    func cancelFlowOpenExternal(_ url: URL, pending: PendingCancel?) {
        if let p = pending { pendingCancel = PendingCancel(contractID: p.contractID, trial: p.trial, leftApp: false) }
        Task { @MainActor [weak self] in
            let opened = await UIApplication.shared.open(url)
            guard let self else { return }
            if opened {
                if let p = pending, self.pendingCancel?.contractID == p.contractID { self.pendingCancel?.leftApp = true }
            } else {
                if pending != nil { self.pendingCancel = nil }
                self.toast("Link konnte nicht geöffnet werden")
            }
        }
    }

    // MARK: Wege

    private func cancelFlowOnline(_ c: Contract, trial: Bool, calc: Calc) {
        guard let url = CancelLinks.web(calc.cancLink(c)) else {
            toast("Kein Link hinterlegt. Trag Website oder Kündigungslink ein.")
            ContractFormLaunch.openMoreFor = c.id
            cancelFlowPresent(.contractForm(.edit(c.id)), closingOthers: true)
            return
        }
        pendingCancel = PendingCancel(contractID: c.id, trial: trial)
        toast("Nach der Kündigung hier bestätigen")
        let id = c.id
        // kurz warten, damit der Toast noch sichtbar ist, bevor Safari öffnet
        CancelWindowFlow.afterDismiss(self, wait: 350, keepStack: false,
                                      still: { [weak self] in self?.pendingCancel?.contractID == id }) { [weak self] in
            self?.cancelFlowOpenExternal(url, pending: PendingCancel(contractID: id, trial: trial))
        }
    }

    private func cancelFlowMail(_ c: Contract, trial: Bool, calc: Calc) {
        let to = c.mail.trimmingCharacters(in: .whitespacesAndNewlines)
        if to.isEmpty {
            let id = c.id
            CancelWindowFlow.ask(self, title: "E-Mail-Adresse fehlt",
                                 message: "Trag die Kündigungsadresse des Vertragspartners beim Vertrag unter «Kontakt» ein.",
                                 ok: "Eintragen") { [weak self] in
                ContractFormLaunch.openMoreFor = id
                self?.cancelFlowPresent(.contractForm(.edit(id)), closingOthers: true)
            }
            return
        }
        let parts = Letter.parts(c, calc: calc)
        let body = Letter.directMailText(parts)
        if MFMailComposeViewController.canSendMail() {
            // kein zweites Mail-Fenster direkt übereinander (Doppeltippen)
            if case .mail = sheets.last { return }
            present(.mail(MailDraft(to: [to], subject: parts.subject, body: body, cancelContractID: c.id, cancelTrial: trial)))
        } else if let url = CancelLinks.mailto(to: to, subject: parts.subject, body: body) {
            cancelFlowOpenExternal(url, pending: PendingCancel(contractID: c.id, trial: trial))
        } else {
            toast("Mail konnte nicht geöffnet werden")
        }
    }
}

// MARK: - Links

enum CancelLinks {
    /// Nur ASCII-Zeichen ohne Sonderbedeutung bleiben unkodiert (RFC 3986 «unreserved»).
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Website-Link (mit «https://», wenn kein Schema angegeben ist). Leer oder ungültig → nil.
    static func web(_ s: String) -> URL? {
        let t = Format.normUrl(s)
        if t.isEmpty { return nil }
        if let u = URL(string: t), u.host != nil { return u }
        if let enc = t.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed), let u = URL(string: enc), u.host != nil { return u }
        return nil
    }

    /// mailto:-Link mit Betreff und Text.
    static func mailto(to: String, subject: String, body: String) -> URL? {
        let addr = to.trimmingCharacters(in: .whitespacesAndNewlines)
        var allowedAddr = unreserved
        allowedAddr.insert(charactersIn: "@+")
        let a = addr.addingPercentEncoding(withAllowedCharacters: allowedAddr) ?? ""
        let s = subject.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        let b = body.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        return URL(string: "mailto:" + a + "?subject=" + s + "&body=" + b)
    }
}

// MARK: - UIKit-Hilfe (oberstes Fenster, z.B. für das iPad-Drucken im Viewer)

@MainActor
enum CancelFlowUI {
    /// Oberstes sichtbares Fenster der App.
    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { $0.windows }
        let window = windows.first { $0.isKeyWindow } ?? windows.first
        var top = window?.rootViewController
        while let p = top?.presentedViewController, !p.isBeingDismissed { top = p }
        return top
    }
}
