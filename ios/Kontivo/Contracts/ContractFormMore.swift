import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import KontivoCore

/// Unterseite «Weitere Angaben»: Preisänderungen, Sonderzahlungen, Erinnerung und Wechsel, Kundendaten,
/// Adresse des Vertragspartners, Kontakt & Notiz (Dokumente seit Web 6e77e47 als Chip auf der Hauptseite).
struct CTFormMorePage: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    @FocusState private var addressFocused: Bool

    init(form: CTFormState) {
        self.form = form
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                Form {
                    CTMorePrices(form: form)
                    CTMoreExtras(form: form)
                    CTMoreReminder(form: form)
                    CTMoreCustomer(form: form)
                    CTMoreAddress(form: form, focused: $addressFocused)
                    CTMoreContact(form: form)
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.horizontal, max(KMetric.gutter, (geo.size.width - KMetric.maxContent) / 2), for: .scrollContent)
                .onAppear { scrollToAddress(proxy) }
                .onChange(of: form.focusAddress) { _, on in if on { scrollToAddress(proxy) } }
            }
        }
        .kPageBackground()
        .kKeyboardDone()
    }

    static let addressAnchor = "ct.more.address"

    /// «Erfassen/Ändern» beim Kündigungsweg Brief: zur Adresse scrollen und das erste Feld fokussieren
    private func scrollToAddress(_ proxy: ScrollViewProxy) {
        guard form.focusAddress else { return }
        form.focusAddress = false
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            withAnimation { proxy.scrollTo(CTFormMorePage.addressAnchor, anchor: .center) }
            if !form.partnerName.ctTrimmed.isEmpty { addressFocused = true }
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
                    .accessibilityIdentifier("form.priceAmount")
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            Button("Preisänderung hinzufügen") {
                add(force: false)
            }
            .fontWeight(.semibold)
            .accessibilityIdentifier("form.priceAdd")
        } header: {
            CTMoreHeader(title: "Preisänderungen", count: n > 0 ? "\(n)" + (n == 1 ? " Änderung" : " Änderungen") : "")
        } footer: {
            Text("Der Betrag unter «Kosten» ist der Anfangspreis. Jede Änderung gilt ab ihrem Datum.")
        }
        .listRowBackground(KColor.surface)
    }

    /// Vormerken; «Preis bleibt gleich» fragt nicht blockierend nach («Trotzdem hinzufügen»)
    private func add(force: Bool) {
        switch form.addPrice(force: force) {
        case .toast(let t, let long):
            model.toast(t, seconds: long ? 4 : 2.4)
        case .confirmSame(let title, let message):
            let f = form
            let m = model
            model.ask(title: title, message: message, ok: "Trotzdem hinzufügen") {
                if case .toast(let t, let long) = f.addPrice(force: true) { m.toast(t, seconds: long ? 4 : 2.4) }
            }
        }
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

// MARK: Erinnerung und Wechsel

private struct CTMoreReminder: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        Section {
            Toggle(isOn: $form.mandatory) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pflichtvertrag")
                    Text("Wechseln statt kündigen, z.B. Krankenkasse. Nach der Kündigung neuen Anbieter erfassen.")
                        .font(.footnote).foregroundStyle(KColor.ink2)
                }
            }
            .accessibilityIdentifier("form.mandatory")
            Toggle(isOn: $form.noWatch) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nicht an Frist erinnern")
                    Text("Erscheint nicht unter «Fristen», z.B. Miete.")
                        .font(.footnote).foregroundStyle(KColor.ink2)
                }
            }
            .accessibilityIdentifier("form.noWatch")
            // Nativ zusätzlich: Mietvertrag (Brief mit Unterschrift); ohne Wahl gilt die Erkennung aus Bezeichnung/Kategorie
            Toggle("Mietvertrag", isOn: rentBinding)
        } header: {
            Text("Erinnerung und Wechsel")
        } footer: {
            Text("Miete braucht immer einen Brief mit Unterschrift.")
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
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focused: FocusState<Bool>.Binding

    var body: some View {
        let noPartner = form.partnerName.ctTrimmed.isEmpty
        Section {
            Group {
                TextField(form.partnerName.ctTrimmed.isEmpty ? "Firma (optional)" : "Firma (optional, sonst " + form.partnerName.ctTrimmed + ")", text: $form.address.company)
                    .textContentType(.organizationName)
                    .focused(focused)
                    .id(CTFormMorePage.addressAnchor)
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
            HStack {
                Text("Adresse des Vertragspartners")
                Spacer()
                // Einfügen: Adresse aus Rechnung, Website oder Karten auf die Felder verteilen (Web v86)
                PasteButton(payloadType: String.self) { items in
                    guard let t = items.first else { return }
                    Task { @MainActor in
                        if !form.pasteAddress(t) { model.toast("Keine Adresse in der Zwischenablage") } else { model.toast("Adresse eingefügt, bitte prüfen") }
                    }
                }
                .labelStyle(.titleOnly)
                .buttonBorderShape(.capsule)
                .controlSize(.mini)
                .disabled(noPartner)
            }
        } footer: {
            Text(noPartner ? "Zuerst den Vertragspartner eintragen."
                 : "Für die Kündigung per Brief. Gilt für alle Verträge dieses Vertragspartners.")
        }
        .listRowBackground(KColor.surface)
    }
}
