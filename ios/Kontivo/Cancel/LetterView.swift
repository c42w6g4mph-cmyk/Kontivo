import SwiftUI
import UIKit
import KontivoCore

/// Kündigungsschreiben: Unterzeichnende wählen, Empfänger, Betreff und Text bearbeiten, Unterschriften, PDF erstellen.
/// Web v143–v160: KVG-Hinweis, «Fehlt noch» nur ohne Kunden- und Vertragsnummer, Beschriftung nach `contractNumberLabel`,
/// nach dem PDF beim Schliessen «Brief verschickt?». Native Zusätze: «Per Mail senden», «Drucken» (Viewer: «Teilen»).
struct LetterView: View {
    let contractID: UUID
    let trial: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var ready = false
    @State private var signers: [UUID] = []
    @State private var toText = ""
    @State private var subject = ""
    @State private var bodyText = ""
    /// Zuletzt automatisch gesetzter Text (Wechsel der Unterzeichnenden ersetzt nur unveränderten Text)
    @State private var autoBody = ""
    @State private var custNo = ""
    @State private var contrNo = ""
    /// «Fehlt noch — wird beim Vertrag gespeichert»: nur wenn Kunden- UND Vertragsnummer fehlen (Web v156)
    @State private var showMissing = false
    /// Zeitpunkt des letzten PDFs: beim Schliessen «Brief verschickt?» (Web `closeLetter`)
    @State private var madeAt: Date?
    @State private var addrStatus = ""
    @State private var searching = false
    @State private var sheet: LetterSheet?
    @State private var ask: LetterAsk?
    @State private var scrollToWho = 0
    @FocusState private var focus: LetterField?

    var body: some View {
        NavigationStack {
            Group {
                if let c = model.data.contract(contractID) {
                    LetterFormHost(scrollToWho: scrollToWho) { form(c) }
                } else {
                    Text("Dieser Vertrag existiert nicht mehr.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .kPageBackground()
                }
            }
            // Web `.shbar`: «Schliessen» | «Kündigung» | «PDF»
            .ctSheetBar("Kündigung") {
                CTBarCancelButton(title: "Schliessen") { dismiss() }
            } trailing: {
                CTBarConfirmButton(title: "PDF") { createPDF() }
                    .accessibilityLabel("PDF erstellen")
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focus = nil }
                }
            }
        }
        .onAppear(perform: setup)
        .onDisappear(perform: askSentIfClosed)
        .sheet(item: $sheet) { s in sheetContent(s) }
        .alert(ask?.title ?? "", isPresented: askShown, presenting: ask) { a in
            Button("Trotzdem erstellen") { continueAfter(a) }
            Button("Abbrechen", role: .cancel) {}
        } message: { a in
            Text(a.message)
        }
    }

    private var askShown: Binding<Bool> {
        Binding(get: { ask != nil }, set: { if !$0 { ask = nil } })
    }

    // MARK: Formular (Web `#sheetLetter`: Beschriftung 12.5 Tinte 2, Felder auf `--field`, Radius 10, 11/12, 16 px, 12 Abstand)

    @ViewBuilder private func form(_ c: Contract) -> some View {
        let calc = model.calc
        let parts = Letter.parts(c, signers: signers, calc: calc)
        let rent = calc.isRent(c)
        whoSection(parts)
        recipientSection(c)
        if Letter.showsKvgHint(c, data: model.data) {
            Text(Letter.kvgHint)
                .font(.system(size: 13))
                .foregroundStyle(KColor.ink2)
                .ctLines(13, 18.2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
                .accessibilityIdentifier("letter.kvg")
        }
        if showMissing { missingSection(c) }
        LetterLabeled(label: "Betreff") {
            TextField("", text: $subject)
                .font(.system(size: 16))
                .frame(minHeight: LetterMetric.line + 0.8)
                .focused($focus, equals: .subject)
                .letterBox()
                .accessibilityLabel("Betreff")
        }
        LetterLabeled(label: "Text") {
            // Web `textarea.lt`: 260 hoch (11/12 Innenabstand), 16 px, Zeile 23.2
            TextEditor(text: $bodyText)
                .font(.system(size: 16))
                .lineSpacing(LetterMetric.lineGap)
                .frame(minHeight: 238 - LetterMetric.lineGap / 2 + 16)
                .scrollContentBackground(.hidden)
                .focused($focus, equals: .body)
                .padding(.top, LetterMetric.lineGap / 2)
                .padding(.horizontal, -5).padding(.vertical, -8)
                .letterBox()
                .accessibilityLabel("Text")
        }
        signatureSection(rent: rent)
        Text(Letter.hints(c, parts: parts, calc: calc).joined(separator: " "))
            .font(.system(size: 12.5))
            .foregroundStyle(KColor.ink2)
            .ctLines(12.5, 19.375)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
        // Nativ zusätzlich (README «Bewusst anders»): direkt verschicken bzw. drucken (PDF ohne Vorschau)
        HStack(spacing: 8) {
            LetterSmallButton(title: "Per Mail senden") { createPDF(.mail) }
                .accessibilityIdentifier("letter.mail")
            LetterSmallButton(title: "Drucken") { createPDF(.print) }
                .accessibilityIdentifier("letter.print")
        }
        .padding(.top, 14)
    }

    // «Wer kündigt?» und Absenderzeile
    @ViewBuilder private func whoSection(_ parts: LetterParts) -> some View {
        let persons = model.data.persons
        if persons.count >= 2 {
            VStack(alignment: .leading, spacing: 6) {
                Text("Wer kündigt?")
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                    .ctLine(18.125)
                LetterChipFlow(spacing: 6).callAsFunction {
                    if persons.count == 2 {
                        ForEach(persons) { p in
                            LetterChip(title: p.name, isOn: signers.count == 1 && signers.first == p.id) { setSigners([p.id]) }
                        }
                        LetterChip(title: "Beide", isOn: signers.count == 2) { setSigners(persons.map { $0.id }) }
                    } else {
                        ForEach(persons) { p in
                            LetterChip(title: p.name, isOn: signers.contains(p.id)) { toggleSigner(p.id, persons: persons) }
                        }
                    }
                }
            }
            .padding(.bottom, 6)
            .id(LetterAnchor.who)
        }
        LetterSenderLine(parts: parts, missing: Letter.signersMissingAddress(signers, data: model.data)) { pid in
            model.present(.manage(.sender(pid)))
        }
        // Web: `.note` 4 oben fällt mit Chips (0 0 6) bzw. Kopfleiste (4) zusammen
        .padding(.bottom, 12)
        .id(persons.count >= 2 ? LetterAnchor.sender : LetterAnchor.who)
    }

    @ViewBuilder private func recipientSection(_ c: Contract) -> some View {
        LetterLabeled(label: "Empfänger") {
            ZStack(alignment: .topLeading) {
                if toText.isEmpty {
                    Text("Firma AG\nStrasse Nr.\nPLZ Ort")
                        .font(.system(size: 16))
                        .lineSpacing(LetterMetric.lineGap)
                        .padding(.top, LetterMetric.lineGap / 2)
                        .foregroundStyle(KColor.ink3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Web `#ltTo`: 92 hoch (11/12, 3 Zeilen à 23.2), 16 px
                TextEditor(text: $toText)
                    .font(.system(size: 16))
                    .lineSpacing(LetterMetric.lineGap)
                    .frame(minHeight: 3 * LetterMetric.line - LetterMetric.lineGap / 2 + 16)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .to)
                    .padding(.top, LetterMetric.lineGap / 2)
                    .padding(.horizontal, -5).padding(.vertical, -8)
                    .accessibilityLabel("Empfänger")
            }
            .letterBox()
            HStack(spacing: 10) {
                Button {
                    searchAddress(c)
                } label: {
                    Text("Adresse suchen")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(KColor.teal)
                        .ctLine(18.125)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(searching)
                if searching { ProgressView().controlSize(.small) }
                if !addrStatus.isEmpty {
                    Text(addrStatus)
                        .font(.system(size: 12.5))
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
        }
    }

    /// Nummern direkt nachtragen (beide fehlen); Vertragsnummer beschriftet wie im Formular («Policennummer», «Rufnummer» …)
    private func missingSection(_ c: Contract) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fehlt noch — wird beim Vertrag gespeichert")
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .ctLine(18.125)
            HStack(alignment: .top, spacing: 11) {
                if c.customerNo.isEmpty {
                    LetterLabeled(label: "Kundennummer") {
                        TextField("", text: $custNo)
                            .font(.system(size: 16))
                            .frame(minHeight: LetterMetric.line + 0.8)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .customer)
                            .letterBox()
                            .accessibilityLabel("Kundennummer")
                            .accessibilityIdentifier("letter.custNo")
                    }
                }
                if c.contractNo.isEmpty {
                    let l = Letter.contractNumberLabel(c, data: model.data)
                    LetterLabeled(label: l) {
                        TextField("", text: $contrNo)
                            .font(.system(size: 16))
                            .frame(minHeight: LetterMetric.line + 0.8)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .contract)
                            .letterBox()
                            .accessibilityLabel(l)
                            .accessibilityIdentifier("letter.contrNo")
                    }
                }
            }
        }
    }

    @ViewBuilder private func signatureSection(rent: Bool) -> some View {
        Text("Unterschrift")
            .font(.system(size: 12.5))
            .foregroundStyle(KColor.ink2)
            .ctLine(18.125)
            .padding(.bottom, 6)
        if rent {
            Text(Letter.rentSignatureNote(signerCount: signers.count))
                .font(.system(size: 13))
                .foregroundStyle(KColor.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.warn.opacity(0.12)))
        } else if signers.isEmpty {
            Text("Zuerst oben wählen, wer kündigt.")
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
        } else {
            ForEach(signers, id: \.self) { pid in
                LetterSignatureRow(name: model.data.senderName(pid),
                                   signature: model.data.person(pid)?.signatureJPEG.flatMap { UIImage(data: $0) },
                                   onDraw: { sheet = .pad(pid) },
                                   onSuggest: { openSuggestions(pid) },
                                   onRemove: {
                                       model.update { $0.setSignature(pid, nil) }
                                       model.toast("Unterschrift entfernt")
                                   })
                    .padding(.bottom, 12)
            }
            // Web `.note` 6 oben fällt mit 12 unter der Unterschrift zusammen
            Text("Jede Person unterschreibt selbst.")
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .ctLines(12.5, 19.375)
        }
    }

    // MARK: Fenster

    @ViewBuilder private func sheetContent(_ s: LetterSheet) -> some View {
        switch s {
        case .address(let list):
            AddressPickSheet(candidates: list) { cand in pickAddress(cand) }
                .environment(model)
        case .pad(let pid):
            SignaturePadSheet(title: "Unterschrift") { jpeg in
                model.update { $0.setSignature(pid, jpeg) }
            }
            .environment(model)
        case .suggest(let pid, let first, let last):
            SignatureSuggestionsSheet(first: first, last: last) { jpeg in
                model.update { $0.setSignature(pid, jpeg) }
            }
            .environment(model)
        }
    }

    // MARK: Abläufe

    private func setup() {
        guard !ready, let c = model.data.contract(contractID) else { return }
        ready = true
        let s = Letter.defaultSigners(c, data: model.data)
        let p = Letter.parts(c, signers: s, calc: model.calc)
        signers = s
        toText = p.to.joined(separator: "\n")
        subject = p.subject
        autoBody = p.bodyText
        bodyText = p.bodyText
        showMissing = Letter.showsMissingNumbers(c)
        addrStatus = p.to.count <= 1 ? "Keine Adresse hinterlegt" : ""
    }

    /// Wechsel der Unterzeichnenden: Text nur neu setzen, wenn er nicht von Hand geändert wurde.
    private func setSigners(_ a: [UUID]) {
        signers = a
        guard let c = model.data.contract(contractID) else { return }
        let nb = Letter.parts(c, signers: a, calc: model.calc).bodyText
        if bodyText == autoBody {
            bodyText = nb
            autoBody = nb
        }
    }

    /// Ab 3 Personen: Person umschalten, Reihenfolge wie in der Personenliste.
    private func toggleSigner(_ id: UUID, persons: [Person]) {
        var a = signers
        if let i = a.firstIndex(of: id) { a.remove(at: i) } else { a.append(id) }
        setSigners(persons.map { $0.id }.filter { a.contains($0) })
    }

    private func openSuggestions(_ pid: UUID) {
        let s = model.data.resolvedSender(pid)
        var first = s.first
        var last = s.last
        if first.isEmpty && last.isEmpty {
            let words = (model.data.person(pid)?.name ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
            first = words.first ?? ""
            last = words.dropFirst().joined(separator: " ")
        }
        if first.isEmpty && last.isEmpty {
            model.toast("Zuerst den Namen beim Absender erfassen")
            return
        }
        sheet = .suggest(pid, first, last)
    }

    private func searchAddress(_ c: Contract) {
        let partner = model.data.partner(c.partnerID)
        let pn = (partner?.name ?? "").trimmingCharacters(in: .whitespaces)
        let name = pn.isEmpty ? c.label : pn
        let domain = Format.domain(of: partner?.web ?? "")
        let currency = c.currency
        addrStatus = "Suche …"
        searching = true
        Task { @MainActor in
            let found = await AddressSearch.find(name: name, domain: domain, currency: currency)
            searching = false
            if found.isEmpty {
                addrStatus = "Keine Adresse gefunden — bitte von der Website oder Rechnung übernehmen."
            } else {
                addrStatus = ""
                sheet = .address(found)
            }
        }
    }

    /// Gewählte Adresse ins Empfängerfeld und beim Vertragspartner speichern.
    private func pickAddress(_ cand: AddressCandidate) {
        toText = cand.lines.joined(separator: "\n")
        addrStatus = ""
        if let c = model.data.contract(contractID) { saveRecipient(cand.lines, contract: c) }
        model.toast("Adresse eingesetzt — bitte prüfen")
    }

    /// Empfängeradresse beim Vertragspartner merken (ohne die Namenszeile und ohne die automatisch angehängte Länderzeile,
    /// Web C25 `base.cLine`); leer ändert nichts.
    private func saveRecipient(_ to: [String], contract c: Contract, countryLine: String = "") {
        guard let pid = c.partnerID, let p = model.data.partner(pid) else { return }
        let text = Letter.addressToSave(to, partnerName: p.name, countryLine: countryLine)
        guard !text.isEmpty, text != p.address.text else { return }
        let addr = WebImport.addrSplit(text, partnerName: p.name)
        model.update { $0.setPartnerAddress(pid, addr) }
    }

    /// «PDF erstellen» (Reihenfolge der Prüfungen wie in der Web-App); `intent`: danach Vorschau, Mail oder Drucken.
    private func createPDF(_ intent: LetterIntent = .view) {
        guard let c = model.data.contract(contractID) else { return }
        // Doppeltippen: läuft schon eine Rückfrage oder liegt der Viewer schon darüber, nichts tun
        guard ask == nil, CancelWindowFlow.isTop(model, .letter(contractID, trial: trial)) else { return }
        focus = nil
        if signers.isEmpty {
            model.toast("Bitte wählen, wer kündigt")
            scrollToWho += 1
            return
        }
        let calc = model.calc
        let base = Letter.parts(c, signers: signers, calc: calc)
        let to = toText.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var subj = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if subj.isEmpty { subj = base.subject }
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if to.isEmpty {
            model.toast("Empfänger fehlt")
            focus = .to
            return
        }
        if text.isEmpty {
            model.toast("Der Text ist leer")
            return
        }
        saveRecipient(to, contract: c, countryLine: base.countryLine)
        // Referenzzeilen aus dem Text lösen; nachgetragene Nummern speichern und als Referenz einsetzen
        let split = Letter.splitReferences(text)
        var refs = split.references
        let nC = custNo.trimmingCharacters(in: .whitespacesAndNewlines)
        let nV = contrNo.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nC.isEmpty || !nV.isEmpty {
            let id = contractID
            model.update { d in
                guard let i = d.contractIndex(id) else { return }
                if !nC.isEmpty && d.contracts[i].customerNo.isEmpty { d.contracts[i].customerNo = nC }
                if !nV.isEmpty && d.contracts[i].contractNo.isEmpty { d.contracts[i].contractNo = nV }
            }
            let numLabels = Letter.referenceLabels.filter { $0 != "Kundennummer" }
            let nLabel = Letter.contractNumberLabel(model.data.contract(id) ?? c, data: model.data)
            if !nC.isEmpty && !refs.contains(where: { $0.hasPrefix("Kundennummer: ") }) { refs.append("Kundennummer: " + nC) }
            if !nV.isEmpty && !refs.contains(where: { r in numLabels.contains { r.hasPrefix($0 + ": ") } }) { refs.append(nLabel + ": " + nV) }
            // Nachgetragene Nummern als Referenzzeilen in den Text übernehmen (gilt auch für weitere PDFs), «Fehlt noch» ausblenden
            let wasAuto = bodyText == autoBody
            bodyText = refs.joined(separator: "\n") + "\n\n" + split.body
            if wasAuto { autoBody = bodyText }
            custNo = ""
            contrNo = ""
            showMissing = model.data.contract(id).map { Letter.showsMissingNumbers($0) } ?? false
        }
        let rent = calc.isRent(c)
        let data = model.data
        let sigs: [Data?] = rent ? [] : signers.map { data.person($0)?.signatureJPEG }
        let input = LetterPDFInput(sender: base.sender, to: to, city: base.city, date: model.today, subject: subj,
                                   references: refs, body: split.body, names: base.names, signatures: sigs,
                                   country: base.country, windowRight: data.settings.letterWindowRight)
        let info = LetterDocumentInfo(subject: subj,
                                      mailText: Letter.mailText(references: refs, body: split.body, names: base.names, sender: base.sender),
                                      names: base.names,
                                      recipient: c.mail.trimmingCharacters(in: .whitespacesAndNewlines),
                                      isRent: rent)
        let missing = Letter.signersMissingAddress(signers, data: data).map { data.person($0)?.name ?? "" }
        let job = LetterJob(input: input, toCount: to.count, missingNames: missing, info: info,
                            fileName: Letter.pdfFileName(c, data: data, today: model.today),
                            title: Letter.viewerTitle(c, data: data), intent: intent)
        proceed(job, from: 0)
    }

    /// Rückfragen nacheinander: Empfänger ohne Adresse, Anschrift zu lang, dann Absender unvollständig.
    private func proceed(_ job: LetterJob, from stage: Int) {
        if stage <= 0 && job.toCount <= 1 {
            ask = LetterAsk(stage: 0, job: job, title: "Ohne Empfängeradresse?",
                            message: "Im Anschriftfeld steht nur der Name. Für den Postversand fehlt die Adresse.")
            return
        }
        if stage <= 1 && job.toCount > 6 {
            ask = LetterAsk(stage: 1, job: job, title: "Anschrift zu lang",
                            message: "Die Anschrift hat \(job.toCount) Zeilen. Ins Fenster eines Kuverts passen höchstens 6, sonst überdeckt sie Datum oder Betreff.")
            return
        }
        if stage <= 2 && !job.missingNames.isEmpty {
            ask = LetterAsk(stage: 2, job: job, title: "Absender unvollständig", message: Letter.missingSenderText(job.missingNames))
            return
        }
        finish(job)
    }

    private func continueAfter(_ a: LetterAsk) {
        let next = a.stage + 1
        let job = a.job
        let me = AppSheet.letter(contractID, trial: trial)
        // Erst weiter, wenn die Rückfrage geschlossen ist (und nur, wenn der Brief noch zuoberst liegt)
        CancelWindowFlow.afterDismiss(model, wait: 350, still: { [model] in CancelWindowFlow.isTop(model, me) }) {
            proceed(job, from: next)
        }
    }

    private func finish(_ job: LetterJob) {
        // Doppeltippen auf «PDF»: nur öffnen, solange der Brief zuoberst liegt
        let me = AppSheet.letter(contractID, trial: trial)
        guard CancelWindowFlow.isTop(model, me) else { return }
        let pdf = LetterPDF.render(job.input)
        guard !pdf.isEmpty else {
            model.toast("PDF konnte nicht erstellt werden")
            return
        }
        madeAt = Date()
        switch job.intent {
        case .view:
            let ref = DocumentRef(data: pdf, type: "application/pdf", title: job.title, fileName: job.fileName,
                                  letterContractID: contractID, letterTrial: trial)
            LetterDocumentStore.put(ref.id, job.info)
            CancelWindowFlow.present(model, .document(ref), over: me)
        case .mail:
            LetterActions.sendMail(model, pdf: pdf, fileName: job.fileName, info: job.info,
                                   contractID: contractID, trial: trial, over: me)
        case .print:
            LetterActions.printPDF(model, data: pdf, jobName: LetterActions.pdfName(job.fileName))
        }
    }
}

// MARK: - Nach dem Schliessen

extension LetterView {
    /// Nach dem PDF beim Schliessen fragen «Brief verschickt?» (Web `closeLetter`, Kern `cancelledQuestion(letter: true)`);
    /// nicht, solange das Schreiben noch offen ist (z.B. Viewer darüber) und nicht, wenn seit dem PDF schon gefragt wurde.
    fileprivate func askSentIfClosed() {
        guard let made = madeAt else { return }
        let me = AppSheet.letter(contractID, trial: trial)
        if model.sheets.contains(where: { $0.id == me.id }) { return }
        madeAt = nil
        let id = contractID
        if CancelQuestionLog.asked(id, since: made) { return }
        let m = model
        let t = trial
        CancelWindowFlow.afterDismiss(m, wait: 250, keepStack: false, still: { m.data.contract(id) != nil }) {
            m.askCancelled(id, trial: t, letter: true)
        }
    }
}

// MARK: - Hilfstypen

private enum LetterField: Hashable {
    case to, customer, contract, subject, body
}

private enum LetterAnchor: Hashable {
    case who, sender
}

private enum LetterSheet: Identifiable {
    case address([AddressCandidate])
    case pad(UUID)
    case suggest(UUID, String, String)

    var id: String {
        switch self {
        case .address: return "address"
        case .pad(let p): return "pad-\(p)"
        case .suggest(let p, _, _): return "suggest-\(p)"
        }
    }
}

private struct LetterJob {
    var input: LetterPDFInput
    var toCount: Int
    var missingNames: [String]
    var info: LetterDocumentInfo
    var fileName: String
    var title: String
    var intent: LetterIntent = .view
}

/// Was nach «PDF erstellen» passiert: Vorschau (mit allen Aktionen), direkt Mail mit Anhang oder direkt Drucken.
private enum LetterIntent {
    case view, mail, print
}

private struct LetterAsk {
    var stage: Int
    var job: LetterJob
    var title: String
    var message: String
}

/// Formular mit Sprung zu «Wer kündigt?»
private struct LetterFormHost<Content: View>: View {
    let scrollToWho: Int
    @ViewBuilder var content: Content

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                // Web: Inhalt 4 unter der Kopfleiste (`.shbar` margin-bottom 4)
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 17)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                    .frame(maxWidth: KMetric.maxContent)
                    .frame(maxWidth: .infinity)
            }
                .background(KColor.paper.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: scrollToWho) { _, _ in
                    withAnimation { proxy.scrollTo(LetterAnchor.who, anchor: .top) }
                }
        }
    }
}

/// «Absender: …» bzw. «Wer kündigt? Bitte oben wählen.»; fehlt eine Adresse: «Adresse fehlt: X ergänzen» (orange, antippbar).
private struct LetterSenderLine: View {
    let parts: LetterParts
    let missing: [UUID]
    let onOpen: (UUID) -> Void

    @Environment(AppModel.self) private var model

    var body: some View {
        let line = Letter.senderLine(parts)
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Text(line.bold).fontWeight(.bold))\(line.text)")
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .ctLines(12.5, 19.375)
                .fixedSize(horizontal: false, vertical: true)
            if !parts.signers.isEmpty && !missing.isEmpty {
                LetterChipFlow(spacing: 6).callAsFunction {
                    Text("Adresse fehlt:")
                        .font(.footnote)
                        .foregroundStyle(KColor.warn)
                    ForEach(Array(missing.enumerated()), id: \.element) { item in
                        Button {
                            onOpen(item.element)
                        } label: {
                            Text((model.data.person(item.element)?.name ?? "") + " ergänzen" + (item.offset < missing.count - 1 ? "," : ""))
                                .font(.footnote.weight(.semibold))
                                .underline()
                                .foregroundStyle(KColor.warn)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

/// Unterschrift einer Person: Name, weisse Box (72 pt) mit Bild oder «Keine Unterschrift · Linie bleibt frei», Knöpfe.
private struct LetterSignatureRow: View {
    let name: String
    let signature: UIImage?
    let onDraw: () -> Void
    let onSuggest: () -> Void
    let onRemove: () -> Void

    /// Web: Name 13/600 Tinte 2 (2 Rand, 5 darunter), Fläche weiss 72 hoch, Radius 12, Rand 1 `--line`; Knöpfe nebeneinander
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KColor.ink2)
                .ctLine(18.85)
                .padding(.horizontal, 2)
                .padding(.bottom, 5)
            GeometryReader { geo in
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                    if let img = signature {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: geo.size.width * 0.9, maxHeight: 60)
                            .accessibilityLabel("Unterschrift " + name)
                    } else {
                        Text("Keine Unterschrift · Linie bleibt frei")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
            }
            .frame(height: 72)
            HStack(spacing: 8) {
                LetterSmallButton(title: "Zeichnen", action: onDraw)
                LetterSmallButton(title: "Vorschläge", action: onSuggest)
                if signature != nil {
                    LetterSmallButton(title: "Entfernen", destructive: true, action: onRemove)
                }
            }
            .padding(.top, 6)
        }
    }
}

/// Feld mit Beschriftung darüber (Web `.field`: label 12.5 Tinte 2, Abstand 5, 12 darunter)
private struct LetterLabeled<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
                .ctLine(18.125)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 12)
    }
}

/// Masse der Eingabefelder (Web `.field input/textarea` 16 px, Zeile 23.2)
private enum LetterMetric {
    static let line: CGFloat = 23.2
    /// Zeilenabstand zusätzlich zur natürlichen SF-Zeilenhöhe (16 × 1.193)
    static let lineGap: CGFloat = 23.2 - 16 * 1.193
}

private extension View {
    /// Eingabefläche (Web `.field input/textarea`: `--field`, Radius 10, 11/12)
    func letterBox() -> some View {
        padding(.vertical, 11).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
    }
}

/// Chip «Wer kündigt?» (Web `.chips button`: 14 px, 7/12, gewählt Tinte/Papier, sonst Rand `--line`)
private struct LetterChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                .lineLimit(1)
                .ctLine(20.3)
                .padding(.horizontal, 13).padding(.vertical, 8)
                .foregroundStyle(isOn ? KColor.paper : KColor.ink2)
                .background(Capsule().fill(isOn ? KColor.ink : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? KColor.ink : KColor.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Kleiner Knopf (Web `#ltSigs button`: Fläche, Rand 1 `--line`, Radius 10, 13/600, 8/4)
private struct LetterSmallButton: View {
    let title: String
    var destructive = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(destructive ? KColor.alert : KColor.ink)
                .lineLimit(1)
                .ctLine(18.85)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8).padding(.horizontal, 4)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// Einfacher Fliesssatz für Chips (bricht in die nächste Zeile um).
private struct LetterChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowH: CGFloat = 0
        var width: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            let w = min(sz.width, maxW)
            if x > 0 && x + w > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += w + spacing
            rowH = max(rowH, sz.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: maxW.isFinite ? maxW : width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            let w = min(sz.width, bounds.width)
            if x > bounds.minX && x + w > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: sz.height))
            x += w + spacing
            rowH = max(rowH, sz.height)
        }
    }
}
