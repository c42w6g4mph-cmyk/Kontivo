import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import KontivoCore

/// Unterseite «Weitere Angaben»: Preisänderungen, Sonderzahlungen, Fristen, Kundendaten, Kontakt & Notiz, Adresse, Dokumente.
struct CTFormMorePage: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    init(form: CTFormState) {
        self.form = form
    }

    var body: some View {
        GeometryReader { geo in
            Form {
                CTMorePrices(form: form)
                CTMoreExtras(form: form)
                CTMoreDeadlines(form: form)
                CTMoreCustomer(form: form)
                CTMoreContact(form: form)
                CTMoreAddress(form: form)
                CTMoreDocuments(form: form)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.horizontal, max(0, (geo.size.width - KMetric.maxContent) / 2), for: .scrollContent)
        }
        .kPageBackground()
        .fileImporter(isPresented: $form.showFileImporter, allowedContentTypes: [.pdf, .png, .jpeg, .webP, .heic, .image]) { result in
            importFile(result)
        }
        .onChange(of: form.docPhoto) { _, item in
            guard let item else { return }
            loadDocPhoto(item)
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else {
            if case .failure = result { model.toast("Upload fehlgeschlagen") }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            model.toast("Upload fehlgeschlagen")
            return
        }
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)?.preferredMIMEType ?? CTMoreDocuments.guessType(ext)
        form.attach(data, name: url.lastPathComponent, type: type, model: model)
    }

    private func loadDocPhoto(_ item: PhotosPickerItem) {
        let today = model.today
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            form.docPhoto = nil
            guard let d = data, let img = UIImage(data: d), let jpg = img.jpegData(compressionQuality: 0.85) else {
                model.toast("Upload fehlgeschlagen")
                return
            }
            form.attach(jpg, name: "Foto " + Format.fmtShort(today) + ".jpg", type: "image/jpeg", model: model)
        }
    }
}

/// Abschnittskopf mit Zähler rechts («2 Änderungen»)
private struct CTMoreHeader: View {
    let title: String
    var count: String = ""
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if !count.isEmpty {
                Text(count).textCase(nil)
            }
        }
    }
}

// MARK: Preisänderungen

private struct CTMorePrices: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        let today = model.today
        let ps = form.sortedPrices
        let n = ps.count
        Section {
            if !ps.isEmpty {
                priceRows(ps, today: today)
            }
            CTOptionalDateRow(title: "Gültig ab", day: $form.priceFrom, fallback: today)
            LabeledContent("Neuer Betrag") {
                TextField("74.90", text: $form.priceAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            Button("Preisänderung hinzufügen") {
                model.toast(form.addPrice())
            }
            .fontWeight(.semibold)
        } header: {
            CTMoreHeader(title: "Preisänderungen", count: n > 0 ? "\(n)" + (n == 1 ? " Änderung" : " Änderungen") : "")
        } footer: {
            Text("Der Betrag unter «Kosten» ist der Anfangspreis. Jede Änderung gilt ab ihrem Datum.")
        }
        .listRowBackground(KColor.surface)
    }

    @ViewBuilder
    private func priceRows(_ ps: [PriceChange], today: Day) -> some View {
        let ni = ps.lastIndex { $0.from <= today } ?? -1
        let cur = form.currency.rawValue
        let base = CTNumber.parse(form.amountText)
        CTPriceRow(label: "Anfangspreis", amount: (base.map { Format.money($0) } ?? "—") + " " + cur,
                   tag: ni < 0 ? .current : nil, isCurrent: ni < 0, hPad: 0)
        ForEach(Array(ps.enumerated()), id: \.offset) { i, p in
            CTPriceRow(label: "ab " + Format.fmtD(p.from), amount: Format.money(p.amount) + " " + cur,
                       tag: i == ni ? .current : (p.from > today ? .planned : nil), isCurrent: i == ni,
                       onDelete: { form.removePrice(p.from) }, hPad: 0)
        }
    }
}

// MARK: Sonderzahlungen

private struct CTMoreExtras: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        let today = model.today
        let n = form.extras.count
        Section {
            CTExtrasList(extras: form.extras, currency: form.currency.rawValue, today: today, onDelete: { x in
                form.extras.removeAll { $0.id == x.id }
            }, framed: false)
            Picker("Art", selection: $form.extraCredit) {
                Text("Zahlung").tag(false)
                Text("Gutschrift").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            CTOptionalDateRow(title: "Datum", day: $form.extraDate, fallback: today)
            LabeledContent("Betrag") {
                TextField("120.00", text: $form.extraAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            CTField(title: "Bezeichnung (optional)", placeholder: "z.B. Nebenkostenabrechnung", text: $form.extraNote, limit: 60)
            Button("Sonderzahlung hinzufügen") {
                model.toast(form.addExtra())
            }
            .fontWeight(.semibold)
        } header: {
            CTMoreHeader(title: "Sonderzahlungen", count: n > 0 ? "\(n) erfasst" : "")
        } footer: {
            Text("Zum Beispiel Nebenkostenabrechnung oder Aktivierungsgebühr. Zählt in «Kosten» und «Budget» im jeweiligen Monat, nicht in den monatlichen Fixkosten.")
        }
        .listRowBackground(KColor.surface)
    }
}

// MARK: Fristen

private struct CTMoreDeadlines: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        let today = model.today
        Section {
            Picker("In «Fristen» anzeigen", selection: $form.watch) {
                Text("Ja").tag(CTFormState.Watch.yes)
                Text("Nein – Pflichtvertrag").tag(CTFormState.Watch.mandatory)
                Text("Nein – z.B. Miete").tag(CTFormState.Watch.noWatch)
            }
            Picker("Kündigungsweg", selection: $form.cancelChannel) {
                Text("—").tag(CancelChannel?.none)
                ForEach(CancelChannel.allCases, id: \.self) { ch in
                    Text(ch.webText).tag(CancelChannel?.some(ch))
                }
            }
            CTOptionalDateRow(title: "Probeabo endet", day: $form.trial, fallback: today.addingMonths(1))
            if form.cancelChannel == .online {
                CTField(title: "Kündigungslink", placeholder: "netflix.com/cancelplan", text: $form.cancelURL,
                        keyboard: .URL, capitalization: .never, autocorrect: false)
            }
            Toggle("Mietvertrag", isOn: rentBinding)
        } header: {
            Text("Fristen")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pflichtvertrag: nur Wechsel möglich, z.B. Grundversicherung.")
                if form.cancelChannel == .online {
                    Text("Seite im Kundenkonto, auf der du kündigst. Leer: die Website des Vertragspartners wird geöffnet.")
                }
                Text("Miete braucht immer einen Brief mit Unterschrift.")
            }
        }
        .listRowBackground(KColor.surface)
    }

    private var rentBinding: Binding<Bool> {
        Binding(
            get: {
                if let r = form.isRent { return r }
                let kind = model.data.category(form.categoryID)?.kind
                return Letter.isRentHeuristic(label: form.label, partner: form.partnerName, kind: kind)
            },
            set: { form.isRent = $0 }
        )
    }
}

// MARK: Kundendaten

private struct CTMoreCustomer: View {
    @Bindable var form: CTFormState

    static let payMethods = ["Lastschrift (LSV/SEPA)", "eBill", "Kreditkarte", "QR-Rechnung", "Dauerauftrag", "TWINT", "PayPal", "Sonstiges"]

    var body: some View {
        Section {
            CTField(title: "Kundennummer", placeholder: "", text: $form.customerNo, capitalization: .never, autocorrect: false)
            CTField(title: "Vertragsnummer", placeholder: "", text: $form.contractNo, capitalization: .never, autocorrect: false)
            Picker("Zahlungsart", selection: $form.payMethod) {
                Text("—").tag("")
                ForEach(options, id: \.self) { m in
                    Text(m).tag(m)
                }
            }
            CTField(title: "Belastet über", placeholder: "z.B. Visa …4417", text: $form.payAccount, autocorrect: false)
        } header: {
            Text("Kundendaten")
        }
        .listRowBackground(KColor.surface)
    }

    private var options: [String] {
        let m = form.payMethod
        return (m.isEmpty || CTMoreCustomer.payMethods.contains(m)) ? CTMoreCustomer.payMethods : CTMoreCustomer.payMethods + [m]
    }
}

// MARK: Kontakt & Notiz

private struct CTMoreContact: View {
    @Bindable var form: CTFormState

    var body: some View {
        let noPartner = form.partnerName.ctTrimmed.isEmpty
        Section {
            CTField(title: "Website oder Kundenportal", placeholder: "swisscom.ch/login", text: $form.web,
                    keyboard: .URL, capitalization: .never, autocorrect: false)
                .disabled(noPartner)
                .opacity(noPartner ? 0.5 : 1)
            CTField(title: "Telefon", placeholder: "", text: $form.tel, keyboard: .phonePad, capitalization: .never, autocorrect: false)
            CTField(title: "E-Mail", placeholder: "", text: $form.mail, keyboard: .emailAddress, capitalization: .never, autocorrect: false)
            VStack(alignment: .leading, spacing: 3) {
                Text("Notiz")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                TextField("Zugangsweg, Ansprechpartner, Besonderheiten", text: $form.note, axis: .vertical)
                    .lineLimit(3...10)
                    .foregroundStyle(KColor.ink)
            }
            .padding(.vertical, 2)
        } header: {
            Text("Kontakt & Notiz")
        } footer: {
            if noPartner {
                Text("Website: Zuerst den Vertragspartner eintragen.")
            }
        }
        .listRowBackground(KColor.surface)
    }
}

// MARK: Adresse des Vertragspartners

private struct CTMoreAddress: View {
    @Bindable var form: CTFormState

    var body: some View {
        let noPartner = form.partnerName.ctTrimmed.isEmpty
        Section {
            Group {
                TextField("Firma, z.B. Sunrise GmbH", text: $form.address.company)
                    .textContentType(.organizationName)
                TextField("Zusatz, z.B. Kundendienst oder Postfach", text: $form.address.extra)
                TextField("Strasse und Nr.", text: $form.address.street)
                    .textContentType(.fullStreetAddress)
                HStack(spacing: 10) {
                    TextField("PLZ", text: $form.address.zip)
                        .keyboardType(.numbersAndPunctuation)
                        .textContentType(.postalCode)
                        .frame(maxWidth: 90)
                    Divider()
                    TextField("Ort", text: $form.address.city)
                        .textContentType(.addressCity)
                }
                TextField("Land (optional)", text: $form.address.country)
                    .textContentType(.countryName)
            }
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .disabled(noPartner)
            .opacity(noPartner ? 0.5 : 1)
        } header: {
            Text("Adresse des Vertragspartners")
        } footer: {
            Text(noPartner ? "Zuerst den Vertragspartner eintragen."
                 : "Für die Kündigung per Brief. Gilt für alle Verträge dieses Vertragspartners.")
        }
        .listRowBackground(KColor.surface)
    }
}

// MARK: Dokumente

private struct CTMoreDocuments: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        let n = form.documents.count
        Section {
            ForEach(form.documents) { d in
                HStack(spacing: 10) {
                    Button {
                        model.present(.document(DocumentRef(fileID: d.id, type: d.type, title: d.name, fileName: d.name)))
                    } label: {
                        Label {
                            Text(d.name).foregroundStyle(KColor.ink).lineLimit(1)
                        } icon: {
                            Image(systemName: CTText.isPDF(d) ? "doc.richtext" : "photo")
                                .foregroundStyle(KColor.teal)
                        }
                    }
                    .buttonStyle(.borderless)
                    Spacer(minLength: 8)
                    Button {
                        form.documents.removeAll { $0.id == d.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(KColor.ink3)
                            .imageScale(.large)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Entfernen")
                }
            }
            Button {
                form.showFileImporter = true
            } label: {
                Label("Datei anhängen — PDF oder Bild", systemImage: "paperclip")
            }
            PhotosPicker(selection: $form.docPhoto, matching: .images) {
                Label("Foto anhängen", systemImage: "photo.on.rectangle")
            }
        } header: {
            CTMoreHeader(title: "Dokumente", count: n > 0 ? "\(n)" + (n == 1 ? " Datei" : " Dateien") : "")
        }
        .listRowBackground(KColor.surface)
    }

    /// Typ aus der Endung (guessType)
    static func guessType(_ ext: String) -> String {
        switch ext {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return "application/octet-stream"
        }
    }
}
