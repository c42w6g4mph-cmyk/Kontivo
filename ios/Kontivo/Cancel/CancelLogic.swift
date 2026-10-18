import SwiftUI
import UIKit
import MessageUI
import KontivoCore

/// Kündigung starten, Rückfragen «Gekündigt?» / «Brief verschickt?» und «Als gekündigt markieren»
/// (Web: Detail-Knöpfe, kPending, closeLetter, markCancelled). Texte aus dem Kern (`Calc.cancelledQuestion`, `Letter.mailChecks`).
extension AppModel {
    /// Startet die Kündigung je nach Kündigungsweg (Online → Link, E-Mail → Prüfungen und Mail, Brief → Kündigungsschreiben,
    /// offen → Auswahl). Miete immer per Brief (Calc.cancVia). `trial`: Kündigung gilt fürs laufende Probeabo.
    func startCancel(_ contractID: UUID, trial: Bool) {
        guard let c = data.contract(contractID) else { return }
        let calc = self.calc
        switch calc.cancVia(c) {
        case .online:
            cancelFlowOnline(c, trial: trial, calc: calc)
        case .mail:
            cancelFlowMail(c, trial: trial)
        case .post:
            present(.letter(contractID, trial: trial))
        case .tel:
            cancelFlowPhone(c, trial: trial)
        case .none:
            present(.cancelChannelPick(contractID, trial: trial))
        }
    }

    /// Beim Zurückkehren in die App: Rückfrage «Gekündigt?», wenn eine Kündigung über Website/E-Mail gestartet wurde (Web kPending).
    func cancelReturnCheck() {
        guard let p = pendingCancel, p.leftApp else { return }
        pendingCancel = nil
        guard data.contract(p.contractID) != nil else { return }
        let id = p.contractID
        let trial = p.trial
        CancelWindowFlow.afterDismiss(self, wait: CancelWindowFlow.Wait.returnToApp, keepStack: false,
                                      still: { [weak self] in self?.data.contract(id) != nil }) { [weak self] in
            self?.askCancelled(id, trial: trial, letter: false)
        }
    }

    /// Rückfrage nach der Kündigung (Web v143): «Gekündigt?» (Online/E-Mail, «Ja, gekündigt» / «Abbrechen») bzw.
    /// «Brief verschickt?» (nach dem Kündigungsschreiben, «Ja, gekündigt» / «Noch nicht»). Entfällt, wenn schon gekündigt.
    func askCancelled(_ contractID: UUID, trial: Bool, letter: Bool) {
        guard let c = data.contract(contractID), let q = calc.cancelledQuestion(c, trial: trial, letter: letter) else { return }
        CancelQuestionLog.note(contractID)
        ask(title: q.title, message: q.text, ok: q.ok, cancel: q.no, action: { [weak self] in
            self?.cancelFlowMarkCancelled(contractID, trial: trial)
        })
    }

    /// Text der alten Rückfrage `cancelQuestion` (RootView, Übergang): wie «Gekündigt?» aus dem Kern.
    func cancelQuestionText(_ q: PendingCancel) -> String {
        guard let c = data.contract(q.contractID) else { return "" }
        return calc.cancelledQuestion(c, trial: q.trial, letter: false)?.text ?? ""
    }

    /// Antwort auf die alte Rückfrage `cancelQuestion` (RootView, Übergang). «Ja» markiert als gekündigt.
    func answerCancelQuestion(_ q: PendingCancel, cancelled: Bool) {
        cancelQuestion = nil
        guard cancelled else { return }
        cancelFlowMarkCancelled(q.contractID, trial: q.trial)
    }

    // MARK: Gemeinsame Abläufe (Detail, Fristen-Tab, Rückfrage, Kündigungsweg)

    /// «Als gekündigt markieren» (Web `markCancelled(id, trial, per)`): speichert cancelPer/cancelledOn, schliesst die Fenster und
    /// zeigt den Toast («Gekündigt — läuft bis …», «Endet heute – danach im Archiv», «Beendet – steht jetzt im Archiv»).
    /// `per`: «Läuft bis» aus «Schon gekündigt …» (sonst Termin bzw. letzter Gratistag).
    /// «Nur Anbieter wechseln»: öffnet danach das Formular «Neuer Vertragspartner» mit dem Entwurf aus markCancelled.
    func cancelFlowMarkCancelled(_ contractID: UUID, trial: Bool, per: Day? = nil) {
        var result: CancelResult?
        let day = today
        let ok = update { d in result = d.markCancelled(contractID, trial: trial, per: per, today: day) }
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
            ContractFormLaunch.edit(self, c.id, focus: c.cancelChannel == .online ? .cancelURL : .web)
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

    /// Kündigung per Telefon (Web v210 `ktel`, z.B. Sunrise, Salt): ohne Nummer «Telefonnummer fehlt» → Formular «Telefon»;
    /// sonst Kundendienst anrufen, danach beim Zurückkehren «Gekündigt?» bestätigen.
    private func cancelFlowPhone(_ c: Contract, trial: Bool) {
        let tn = String(c.tel.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) || $0 == "+" })
        let id = c.id
        guard !tn.isEmpty, let url = URL(string: "tel:" + tn) else {
            CancelWindowFlow.ask(self, title: "Telefonnummer fehlt",
                                 message: "Trag die Nummer des Kundendiensts beim Vertrag unter «Kontakt» ein.",
                                 ok: "Eintragen") { [weak self] in
                guard let self else { return }
                ContractFormLaunch.edit(self, id, focus: .tel)
            }
            return
        }
        pendingCancel = PendingCancel(contractID: id, trial: trial)
        toast("Nach dem Anruf hier bestätigen")
        CancelWindowFlow.afterDismiss(self, wait: 350, keepStack: false,
                                      still: { [weak self] in self?.pendingCancel?.contractID == id }) { [weak self] in
            self?.cancelFlowOpenExternal(url, pending: PendingCancel(contractID: id, trial: trial))
        }
    }

    /// «Per E-Mail kündigen» (Web `kmail`): ohne Adresse «E-Mail-Adresse fehlt» → Formular; sonst die Prüfungen nacheinander
    /// (`Letter.mailChecks`: «Wer kündigt?», «Absender unvollständig», «Kundennummer fehlt»), dann die Mail.
    private func cancelFlowMail(_ c: Contract, trial: Bool) {
        let to = c.mail.trimmingCharacters(in: .whitespacesAndNewlines)
        if to.isEmpty {
            let id = c.id
            let field: ContractFormFocus = c.cancelChannel == .email ? .cancelMail : .mail
            CancelWindowFlow.ask(self, title: "E-Mail-Adresse fehlt",
                                 message: "Trag die Kündigungsadresse des Vertragspartners beim Vertrag unter «Kontakt» ein.",
                                 ok: "Eintragen") { [weak self] in
                guard let self else { return }
                ContractFormLaunch.edit(self, id, focus: field)
            }
            return
        }
        cancelFlowMailCheck(c.id, trial: trial, step: 0)
    }

    /// Prüfung Nr. `step` vor dem Mailversand; «Trotzdem senden»/«Ohne senden» geht zur nächsten, danach die Mail.
    private func cancelFlowMailCheck(_ id: UUID, trial: Bool, step: Int) {
        guard let c = data.contract(id) else { return }
        let checks = Letter.mailChecks(c, data: data)
        guard step < checks.count else {
            cancelFlowSendMail(c, trial: trial)
            return
        }
        let check = checks[step]
        let t = Letter.mailCheckTexts(check, data: data)
        ask(title: t.title, message: t.text, ok: t.ok, cancel: t.no, onCancel: { [weak self] in
            guard let self else { return }
            // erst weiter, wenn die Rückfrage geschlossen ist
            CancelWindowFlow.afterDismiss(self, wait: 350, keepStack: false,
                                          still: { [weak self] in self?.data.contract(id) != nil }) { [weak self] in
                self?.cancelFlowMailCheck(id, trial: trial, step: step + 1)
            }
        }, action: { [weak self] in
            guard let self else { return }
            switch check {
            case .noSigner:
                // Web: Formular ohne Sprungziel (Personen stehen unter «Zuordnung»)
                ContractFormLaunch.edit(self, id, focus: nil)
            case .senderIncomplete(let ids):
                if let p = ids.first { self.cancelFlowPresent(.manage(.sender(p)), closingOthers: true) }
            case .numberMissing:
                ContractFormLaunch.edit(self, id, focus: .customerNo)
            }
        })
    }

    /// Mail mit dem Kündigungstext (Referenzen, Text, Namen und Absenderzeilen, Web v143).
    private func cancelFlowSendMail(_ c: Contract, trial: Bool) {
        let to = c.mail.trimmingCharacters(in: .whitespacesAndNewlines)
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

/// Wann zuletzt nach der Kündigung gefragt wurde (je Vertrag): Das Kündigungsschreiben fragt beim Schliessen nur dann
/// «Brief verschickt?», wenn seit dem PDF noch keine Rückfrage kam (z.B. nach «Per Mail senden» schon «Brief verschickt?»).
@MainActor
enum CancelQuestionLog {
    private static var last: [UUID: Date] = [:]

    static func note(_ id: UUID) { last[id] = Date() }

    static func asked(_ id: UUID, since d: Date) -> Bool {
        (last[id] ?? .distantPast) >= d
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
