import SwiftUI
import KontivoCore

// Karten des Vertragsformulars nach «Kosten» (Web v145, früher Unterseite «Weitere Angaben»):
// Sonderzahlungen · Zuordnung (Kategorie, Personen + Aufteilung, Kundennummer, Vertragsnummer nach `contrLbl`) ·
// Kontakt (Adresse «hinzufügen»/Felder/Einfügen, Website, Telefon, E-Mail) · Notiz.

// MARK: - Sonderzahlungen (Web #xList, #xForm)

struct CTFormExtrasSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        let today = model.today
        CTSection {
            // Web v318: Sonderzahlung per Wischen nach links löschen (statt ×)
            ForEach(Array(form.extras.enumerated()), id: \.element.id) { i, x in
                CTSwipeDelete(identifier: "form.extraRow.\(i)", onDelete: { form.extras.removeAll { $0.id == x.id } }) {
                    extraRow(x, today: today)
                }
            }
            if form.extraOpen {
                Picker("Art", selection: $form.extraCredit) {
                    Text("Zahlung").tag(false)
                    Text("Gutschrift").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .id(ContractFormField.extras)
                CTFormDateRow(title: "Datum", day: form.extraDate, fallback: today, identifier: "form.extraDate") { form.extraDate = $0 }
                    .ctMiss(form, .extraDate)
                    .id(ContractFormField.extraDate)
                HStack(spacing: 12) {
                    CTRowLabel("Betrag")
                    TextField("", text: $form.extraAmountText, prompt: Text(ContractFormRules.placeholder).foregroundColor(KColor.ink3))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .foregroundStyle(KColor.teal)
                        .focused(focus, equals: .extraAmount)
                        .accessibilityLabel("Betrag der Sonderzahlung")
                        .accessibilityIdentifier("form.extraAmount")
                }
                .ctMiss(form, .extraAmount)
                .id(ContractFormField.extraAmount)
                HStack(spacing: 12) {
                    CTRowLabel("Bezeichnung")
                    TextField("", text: $form.extraNote, prompt: Text(ContractFormRules.placeholder).foregroundColor(KColor.ink3))
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(KColor.teal)
                        .accessibilityLabel("Bezeichnung der Sonderzahlung")
                        .onChange(of: form.extraNote) { _, v in
                            if v.count > 60 { form.extraNote = String(v.prefix(60)) }
                        }
                }
                VStack(alignment: .leading, spacing: 8) {
                    CTFormOKButton(title: "Sonderzahlung hinzufügen", identifier: "form.extraAdd") {
                        withAnimation(.easeInOut(duration: 0.2)) { model.toast(form.addExtra()) }
                    }
                    Text("Zum Beispiel Nebenkostenabrechnung oder Aktivierungsgebühr. Zählt in «Kosten» und «Budget» im jeweiligen Monat, nicht in den monatlichen Fixkosten.")
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                }
                .padding(.vertical, 2)
            } else {
                CTFormAddRow(title: "Sonderzahlung", identifier: "form.extraOpen") {
                    withAnimation(.easeInOut(duration: 0.2)) { form.extraOpen = true }
                }
            }
        } header: {
            Text("Sonderzahlungen")
        }
        .listRowBackground(KColor.surface)
    }

    /// Zeile (Web .fpr): Bezeichnung bzw. «Sonderzahlung»/«Gutschrift», Plaketten, Datum klein; Betrag (Löschen per Wischen)
    private func extraRow(_ x: ExtraPayment, today: Day) -> some View {
        let cr = x.amount < 0
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(x.note.isEmpty ? (cr ? "Gutschrift" : "Sonderzahlung") : x.note)
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                    if cr && !x.note.isEmpty { CTMiniTag(text: "Gutschrift", tone: KColor.ok) }
                    if x.date > today { CTMiniTag(text: "geplant", tone: KColor.warn) }
                }
                Text(Format.fmtD(x.date))
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
            }
            Spacer(minLength: 8)
            Text(verbatim: (cr ? Format.minus : "") + Format.money(abs(x.amount), form.currency))
                .font(.body.monospacedDigit())
                .foregroundStyle(cr ? KColor.ok : KColor.teal)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 47)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Zuordnung (Web #fsAssign)

struct CTFormAssignSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding
    @State private var showTaxInfo = false

    var body: some View {
        let data = model.data
        CTSection {
            categoryRow
            if data.persons.count >= 2 {
                // Web `.frow.fcol` 12 0, Abstand 8; `.chips` Abstand 6, `.chips .chip` = `Chip` (36.3 hoch)
                VStack(alignment: .leading, spacing: 8) {
                    CTRowLabel("Personen")
                    CTFlowLayout(spacing: 6, lineSpacing: 6) {
                        ForEach(data.persons) { p in
                            Chip(title: p.name, isOn: form.holderIDs.contains(p.id)) {
                                form.toggleHolder(p.id, persons: model.data.persons)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
                if form.holderIDs.count >= 2 { CTFormSplitRows(form: form) }
            }
            CTFormTextRow(title: "Kundennummer", text: $form.customerNo, identifier: "form.customerNo", field: .customerNo, focus: focus)
            CTFormTextRow(title: form.contractNumberLabel(data), text: $form.contractNo, identifier: "form.contractNo", field: .contractNo, focus: focus)
        } header: {
            Text("Zuordnung")
        }
        .listRowBackground(KColor.surface)
    }

    private var categoryRow: some View {
        let cat = model.data.category(form.categoryID)
        return HStack(spacing: 6) {
            Button {
                form.showCategoryPicker = true
            } label: {
                HStack(spacing: 10) {
                    CTRowLabel("Kategorie")
                    Spacer(minLength: 8)
                    // Web `.cfi` 28 (Radius 8), `.cfn` 16 px
                    if let c = cat {
                        MarkView(category: c, size: 28)
                        Text(c.name).font(.system(size: 16)).foregroundStyle(KColor.teal).lineLimit(1)
                    } else {
                        Text("wählen").font(.system(size: 16)).foregroundStyle(KColor.ink3)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Kategorie, " + (cat?.name ?? "wählen"))
            .accessibilityIdentifier("form.category")
            if cat?.kind == .taxes {
                Button { showTaxInfo = true } label: {
                    Image(systemName: "info.circle").font(.body).foregroundStyle(KColor.ink2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Info: nicht kündbar")
            }
        }
        .id(ContractFormField.category)
        .alert("Nicht kündbar", isPresented: $showTaxInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(ContractFormRules.taxInfo)
        }
    }
}

// MARK: - Kontakt (Web #fsContact)

struct CTFormContactSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        // Website und Adresse gehören zum Vertragspartner (Datenmodell mit IDs): ohne Vertragspartner nicht speicherbar
        let noPartner = form.partnerName.ctTrimmed.isEmpty
        CTSection {
            if form.addressVisible {
                addressRows(noPartner: noPartner)
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { form.showAddress() }
                } label: {
                    HStack {
                        CTRowLabel("Adresse")
                        Spacer(minLength: 8)
                        Text(ContractFormRules.placeholder).font(.system(size: 16)).foregroundStyle(KColor.ink3)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Adresse hinzufügen")
                .accessibilityIdentifier("form.addressAdd")
                .id(ContractFormField.address)
            }
            CTFormTextRow(title: "Website", text: $form.web, keyboard: .URL, contentType: .URL, identifier: "form.web", field: .web, focus: focus)
                .disabled(noPartner)
                .opacity(noPartner ? 0.5 : 1)
            CTFormTextRow(title: "Telefon", text: $form.tel, keyboard: .phonePad, contentType: .telephoneNumber, identifier: "form.tel",
                          field: .tel, focus: focus)
            CTFormTextRow(title: "E-Mail", text: $form.mail, keyboard: .emailAddress, contentType: .emailAddress, identifier: "form.mail",
                          field: .mail, focus: focus)
        } header: {
            Text("Kontakt")
        } footer: {
            Text("Die Adresse braucht es für die Kündigung per Brief. Sie gilt für alle Verträge dieses Vertragspartners."
                 + (noPartner ? " Adresse und Website: zuerst den Vertragspartner eintragen." : ""))
        }
        .listRowBackground(KColor.surface)
    }

    /// Adressfelder wie auf der Vertragspartner-Seite (Web #fAddrW): Firma, Zusatz, Strasse, PLZ | Ort, Land; «Einfügen» verteilt
    /// eine kopierte Adresse auf die Felder (v86)
    @ViewBuilder
    private func addressRows(noPartner: Bool) -> some View {
        HStack {
            CTRowLabel("Adresse")
            Spacer()
            PasteButton(payloadType: String.self) { items in
                guard let t = items.first else { return }
                Task { @MainActor in
                    if form.pasteAddress(t) { model.toast("Adresse eingefügt, bitte prüfen") } else { model.toast("Keine Adresse in der Zwischenablage") }
                }
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.capsule)
            .controlSize(.mini)
            .disabled(noPartner)
        }
        Group {
            TextField(noPartner ? "Firma (optional)" : "Firma (optional, sonst " + form.partnerName.ctTrimmed + ")", text: $form.address.company)
                .textContentType(.organizationName)
                .focused(focus, equals: .address)
                .id(ContractFormField.address)
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
        .foregroundStyle(KColor.ink)
        .disabled(noPartner)
        .opacity(noPartner ? 0.5 : 1)
    }
}

// MARK: - Notiz

struct CTFormNoteSection: View {
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        CTSection {
            // Web `.fnotef`: 16 px (Zeile 23.2), 12 0, 84 hoch
            TextField("Zugangsweg, Ansprechpartner, Besonderheiten", text: $form.note, axis: .vertical)
                .font(.system(size: 16))
                .lineSpacing(23.2 - 16 * 1.193)
                .lineLimit(3...10)
                .frame(minHeight: 60, alignment: .top)
                .padding(.vertical, 12)
                .foregroundStyle(KColor.ink)
                .focused(focus, equals: .note)
                .accessibilityLabel("Notiz")
                .accessibilityIdentifier("form.note")
                .id(ContractFormField.note)
        } header: {
            Text("Notiz")
        }
        .listRowBackground(KColor.surface)
    }
}
