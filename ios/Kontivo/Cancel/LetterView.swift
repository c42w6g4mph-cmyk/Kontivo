import SwiftUI
import UIKit
import KontivoCore

/// Kündigungsschreiben: Unterzeichnende wählen, Empfänger, Betreff und Text bearbeiten, Unterschriften, PDF erstellen.
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
    @State private var missCust = false
    @State private var missContr = false
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
            .navigationTitle("Kündigung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schliessen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("PDF") { createPDF() }
                        .fontWeight(.semibold)
                        .accessibilityLabel("PDF erstellen")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { focus = nil }
                }
            }
        }
        .onAppear(perform: setup)
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

    // MARK: Formular

    @ViewBuilder private func form(_ c: Contract) -> some View {
        let calc = model.calc
        let parts = Letter.parts(c, signers: signers, calc: calc)
        let rent = calc.isRent(c)
        whoSection(parts)
        recipientSection(c)
        if missCust || missContr { missingSection }
        Section {
            TextField("Betreff", text: $subject)
                .focused($focus, equals: .subject)
        } header: {
            Text("Betreff").textCase(nil)
        }
        .listRowBackground(KColor.surface)
        Section {
            TextEditor(text: $bodyText)
                .font(.callout)
                .lineSpacing(3)
                .frame(minHeight: 260)
                .scrollContentBackground(.hidden)
                .focused($focus, equals: .body)
                .accessibilityLabel("Text")
        } header: {
            Text("Text").textCase(nil)
        }
        .listRowBackground(KColor.surface)
        signatureSection(rent: rent)
        Section {
            Text(Letter.hints(c, parts: parts, calc: calc).joined(separator: " "))
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
        Section {
            Button {
                createPDF()
            } label: {
                Label("PDF erstellen", systemImage: "doc.richtext")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    // «Wer kündigt?» und Absenderzeile
    @ViewBuilder private func whoSection(_ parts: LetterParts) -> some View {
        let persons = model.data.persons
        Section {
            if persons.count >= 2 {
                LetterChipFlow(spacing: 8).callAsFunction {
                    if persons.count == 2 {
                        ForEach(persons) { p in
                            Chip(title: p.name, isOn: signers.count == 1 && signers.first == p.id) { setSigners([p.id]) }
                        }
                        Chip(title: "Beide", isOn: signers.count == 2) { setSigners(persons.map { $0.id }) }
                    } else {
                        ForEach(persons) { p in
                            Chip(title: p.name, isOn: signers.contains(p.id)) { toggleSigner(p.id, persons: persons) }
                        }
                    }
                }
                .padding(.vertical, 4)
                .id(LetterAnchor.who)
            }
            LetterSenderLine(parts: parts, missing: Letter.signersMissingAddress(signers, data: model.data)) { pid in
                model.present(.manage(.sender(pid)))
            }
            .id(persons.count >= 2 ? LetterAnchor.sender : LetterAnchor.who)
        } header: {
            if persons.count >= 2 { Text("Wer kündigt?").textCase(nil) }
        }
        .listRowBackground(KColor.surface)
    }

    @ViewBuilder private func recipientSection(_ c: Contract) -> some View {
        Section {
            ZStack(alignment: .topLeading) {
                if toText.isEmpty {
                    Text("Firma AG\nStrasse Nr.\nPLZ Ort")
                        .foregroundStyle(KColor.ink3)
                        .padding(.top, 8)
                        .padding(.leading, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $toText)
                    .frame(minHeight: 92)
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.words)
                    .focused($focus, equals: .to)
                    .accessibilityLabel("Empfänger")
            }
            HStack(spacing: 10) {
                Button {
                    searchAddress(c)
                } label: {
                    Label("Adresse suchen", systemImage: "magnifyingglass")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(searching)
                if searching { ProgressView().controlSize(.small) }
                if !addrStatus.isEmpty {
                    Text(addrStatus)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } header: {
            Text("Empfänger").textCase(nil)
        }
        .listRowBackground(KColor.surface)
    }

    private var missingSection: some View {
        Section {
            if missCust {
                TextField("Kundennummer", text: $custNo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .customer)
            }
            if missContr {
                TextField("Vertragsnummer", text: $contrNo)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .contract)
            }
        } header: {
            Text("Fehlt noch — wird beim Vertrag gespeichert").textCase(nil)
        }
        .listRowBackground(KColor.surface)
    }

    @ViewBuilder private func signatureSection(rent: Bool) -> some View {
        Section {
            if rent {
                Text(Letter.rentSignatureNote(signerCount: signers.count))
                    .font(.footnote)
                    .foregroundStyle(KColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
                    .listRowBackground(KColor.warn.opacity(0.12))
            } else if signers.isEmpty {
                Text("Zuerst oben wählen, wer kündigt.")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                    .listRowBackground(KColor.surface)
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
                    .listRowBackground(KColor.surface)
                }
            }
        } header: {
            Text("Unterschrift").textCase(nil)
        } footer: {
            if !rent && !signers.isEmpty { Text("Jede Person unterschreibt selbst.") }
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
        missCust = c.customerNo.isEmpty
        missContr = c.contractNo.isEmpty
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

    /// Empfängeradresse beim Vertragspartner merken (ohne die Namenszeile); leer ändert nichts.
    private func saveRecipient(_ to: [String], contract c: Contract) {
        guard let pid = c.partnerID, let p = model.data.partner(pid) else { return }
        let pn = p.name.trimmingCharacters(in: .whitespaces).lowercased()
        let rest = (to.first?.lowercased() == pn) ? Array(to.dropFirst()) : to
        let text = rest.joined(separator: "\n")
        guard !text.isEmpty, text != p.address.text else { return }
        let addr = WebImport.addrSplit(text, partnerName: p.name)
        model.update { $0.setPartnerAddress(pid, addr) }
    }

    /// «PDF erstellen» (Reihenfolge der Prüfungen wie in der Web-App).
    private func createPDF() {
        guard let c = model.data.contract(contractID) else { return }
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
        saveRecipient(to, contract: c)
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
            if !nC.isEmpty && !refs.contains(where: { $0.hasPrefix("Kundennummer: ") }) { refs.append("Kundennummer: " + nC) }
            if !nV.isEmpty && !refs.contains(where: { $0.hasPrefix("Vertragsnummer: ") }) { refs.append("Vertragsnummer: " + nV) }
        }
        let rent = calc.isRent(c)
        let data = model.data
        let sigs: [Data?] = rent ? [] : signers.map { data.person($0)?.signatureJPEG }
        let input = LetterPDFInput(sender: base.sender, to: to, city: base.city, date: model.today, subject: subj,
                                   references: refs, body: split.body, names: base.names, signatures: sigs)
        let info = LetterDocumentInfo(subject: subj,
                                      mailText: Letter.mailText(references: refs, body: split.body, names: base.names, sender: base.sender),
                                      names: base.names,
                                      recipient: c.mail.trimmingCharacters(in: .whitespacesAndNewlines),
                                      isRent: rent)
        let missing = Letter.signersMissingAddress(signers, data: data).map { data.person($0)?.name ?? "" }
        let job = LetterJob(input: input, toCount: to.count, missingNames: missing, info: info,
                            fileName: Letter.pdfFileName(c, data: data, today: model.today),
                            title: Letter.viewerTitle(c, data: data))
        proceed(job, from: 0)
    }

    /// Rückfragen nacheinander: Empfänger ohne Adresse, dann Absender unvollständig.
    private func proceed(_ job: LetterJob, from stage: Int) {
        if stage <= 0 && job.toCount <= 1 {
            ask = LetterAsk(stage: 0, job: job, title: "Ohne Empfängeradresse?",
                            message: "Im Anschriftfeld steht nur der Name. Für den Postversand fehlt die Adresse.")
            return
        }
        if stage <= 1 && !job.missingNames.isEmpty {
            ask = LetterAsk(stage: 1, job: job, title: "Absender unvollständig", message: Letter.missingSenderText(job.missingNames))
            return
        }
        finish(job)
    }

    private func continueAfter(_ a: LetterAsk) {
        let next = a.stage + 1
        let job = a.job
        // Erst weiter, wenn die Rückfrage geschlossen ist
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            proceed(job, from: next)
        }
    }

    private func finish(_ job: LetterJob) {
        let pdf = LetterPDF.render(job.input)
        guard !pdf.isEmpty else {
            model.toast("PDF konnte nicht erstellt werden")
            return
        }
        let ref = DocumentRef(data: pdf, type: "application/pdf", title: job.title, fileName: job.fileName,
                              letterContractID: contractID, letterTrial: trial)
        LetterDocumentStore.put(ref.id, job.info)
        model.present(.document(ref))
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
            Form { content }
                .scrollContentBackground(.hidden)
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
            Text("\(Text(line.bold).fontWeight(.semibold).foregroundStyle(KColor.ink))\(line.text)")
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
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
        .padding(.vertical, 2)
    }
}

/// Unterschrift einer Person: Name, weisse Box (72 pt) mit Bild oder «Keine Unterschrift · Linie bleibt frei», Knöpfe.
private struct LetterSignatureRow: View {
    let name: String
    let signature: UIImage?
    let onDraw: () -> Void
    let onSuggest: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KColor.ink)
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
                            .font(.footnote)
                            .foregroundStyle(Color(white: 0.45))
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
            }
            .frame(height: 72)
            HStack(spacing: 8) {
                Button("Zeichnen", action: onDraw)
                Button("Vorschläge", action: onSuggest)
                if signature != nil {
                    Button("Entfernen", role: .destructive, action: onRemove)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 6)
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
