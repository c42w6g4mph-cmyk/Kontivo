import SwiftUI
import PhotosUI
import KontivoCore

/// Vertragsformular: neu, bearbeiten, duplizieren, neuer Anbieter. Hauptseite mit «Vertrag», «Kosten», «Laufzeit & Kündigung»
/// und Unterseite «Weitere Angaben». Sichern über `saveContract` (nur Formularfelder, Status bleibt).
struct ContractFormView: View {
    let context: ContractFormContext
    @Environment(AppModel.self) private var model

    init(context: ContractFormContext) {
        self.context = context
    }

    var body: some View {
        CTFormHost(context: context, model: model)
    }
}

private struct CTFormHost: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let context: ContractFormContext
    @State private var form: CTFormState
    @State private var showMore = false
    @State private var askDiscard = false

    init(context: ContractFormContext, model: AppModel) {
        self.context = context
        _form = State(initialValue: CTFormState(context: context, data: model.data, today: model.today))
    }

    var body: some View {
        NavigationStack {
            CTFormMainPage(form: form, showMore: $showMore)
                .navigationTitle(form.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { cancel() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sichern") { save() }
                            .fontWeight(.semibold)
                    }
                }
                .navigationDestination(isPresented: $showMore) {
                    CTFormMorePage(form: form)
                        .navigationTitle("Weitere Angaben")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Sichern") { save() }
                                    .fontWeight(.semibold)
                            }
                        }
                }
        }
        .environment(\.locale, Locale(identifier: "de_CH"))
        .confirmationDialog("Änderungen verwerfen?", isPresented: $askDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) {
                form.closed = true
                dismiss()
            }
            Button("Weiter bearbeiten", role: .cancel) {}
        }
        .sheet(isPresented: $form.showCategoryPicker) {
            CTCategoryPickSheet(selected: $form.categoryID)
                .environment(model)
        }
        .sheet(isPresented: $form.showCatalog) {
            CTCatalogSheet { t in
                form.applyTemplate(t, keepName: false, onlyEmpty: false, data: model.data)
                model.toast("Vorlage übernommen — bitte prüfen")
            }
            .environment(model)
        }
        .sheet(isPresented: $form.showLogoSearch) {
            LogoSearchSheet(name: form.logoSearchName, currency: form.currency, web: form.web.ctTrimmed) { png, bg in
                form.setLogo(png, background: bg, model: model)
                form.showLogoSearch = false
            }
            .environment(model)
        }
        .sheet(item: $form.cropItem) { item in
            ImageCropSheet(image: item.image, title: "Logo zuschneiden") { png, bg in
                form.setLogo(png, background: bg, model: model)
                form.cropItem = nil
            }
            .environment(model)
        }
        .onChange(of: form.logoPhoto) { _, item in
            guard let item else { return }
            loadLogoPhoto(item)
        }
        .onAppear {
            if case .edit(let id) = context, ContractFormLaunch.openMoreFor == id {
                ContractFormLaunch.openMoreFor = nil
                showMore = true
            }
        }
        .onDisappear { form.closed = true }
    }

    private func cancel() {
        if form.isDirty {
            askDiscard = true
        } else {
            form.closed = true
            dismiss()
        }
    }

    private func save() {
        let existing = form.isExisting
        if form.save(model: model) {
            form.closed = true
            dismiss()
            model.toast(existing ? "Aktualisiert" : "Vertrag angelegt")
        }
    }

    private func loadLogoPhoto(_ item: PhotosPickerItem) {
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            form.logoPhoto = nil
            if let d = data, let img = UIImage(data: d) {
                form.cropItem = CTImageItem(image: img)
            } else {
                model.toast("Bild konnte nicht gelesen werden")
            }
        }
    }
}

// MARK: - Hauptseite

private struct CTFormMainPage: View {
    @Bindable var form: CTFormState
    @Binding var showMore: Bool

    var body: some View {
        GeometryReader { geo in
            Form {
                CTFormContractSection(form: form)
                CTFormCostSection(form: form)
                CTFormTermSection(form: form)
                Section {
                    CTFormMoreRow(form: form, showMore: $showMore)
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.horizontal, max(0, (geo.size.width - KMetric.maxContent) / 2), for: .scrollContent)
        }
        .kPageBackground()
        .modifier(CTKeyboardDone())
    }
}

/// Knopf «Fertig» über der Tastatur (Zifferntastaturen haben keine Eingabetaste)
struct CTKeyboardDone: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}

/// Feld mit Beschriftung darüber (wie .field der Web-App)
struct CTField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default
    var capitalization: TextInputAutocapitalization = .sentences
    var autocorrect = true
    var limit: Int? = nil
    /// Kennung für UI-Tests
    var identifier: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
            TextField(placeholder, text: $text)
                .accessibilityIdentifier(identifier)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(!autocorrect)
                .foregroundStyle(KColor.ink)
                .onChange(of: text) { _, v in
                    if let l = limit, v.count > l { text = String(v.prefix(l)) }
                }
        }
        .padding(.vertical, 2)
    }
}

// MARK: Abschnitt «Vertrag»

private struct CTFormContractSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        Section {
            CTFormLogoRows(form: form)
            CTField(title: "Bezeichnung", placeholder: "z.B. Handy-Abo", text: $form.label, identifier: "form.label")
            CTFormPartnerBlock(form: form)
            categoryRow
            if model.data.persons.count >= 2 {
                holdersRow
            }
        } header: {
            Text("Vertrag")
        }
        .listRowBackground(KColor.surface)
    }

    private var categoryRow: some View {
        let cat = model.data.category(form.categoryID)
        return Button {
            form.showCategoryPicker = true
        } label: {
            HStack(spacing: 10) {
                Text("Kategorie").foregroundStyle(KColor.ink)
                Spacer(minLength: 8)
                if let c = cat {
                    MarkView(category: c, size: 26)
                    Text(c.name).foregroundStyle(KColor.ink).lineLimit(1)
                } else {
                    Text("Kategorie wählen").foregroundStyle(KColor.ink3)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Kategorie, " + (cat?.name ?? "Kategorie wählen"))
        .accessibilityIdentifier("form.category")
    }

    private var holdersRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inhaber — mehrere möglich")
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
            CTFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(model.data.persons) { p in
                    Chip(title: p.name, isOn: form.holderIDs.contains(p.id)) {
                        form.toggleHolder(p.id, persons: model.data.persons)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: Logo und Farbe

private struct CTFormLogoRows: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Bindable var form: CTFormState

    var body: some View {
        let data = model.data
        let logo = form.effectiveLogo(data)
        let symbol = KIcon.symbol(for: data.category(form.categoryID))
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { form.logoOpen.toggle() }
        } label: {
            HStack(spacing: 12) {
                MarkView(logoID: logo?.id, logoBg: logo?.bg, colorHex: form.markColor(data), symbol: symbol, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Logo").foregroundStyle(KColor.ink)
                    Text("Logo & Farbe").font(.footnote).foregroundStyle(KColor.ink2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
                    .rotationEffect(.degrees(form.logoOpen ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Logo und Farbe ändern")
        if form.logoOpen {
            Button {
                if form.logoSearchName.isEmpty {
                    model.toast("Zuerst den Firmennamen eintragen")
                } else {
                    form.showLogoSearch = true
                }
            } label: {
                Label("Logo suchen", systemImage: "magnifyingglass")
            }
            PhotosPicker(selection: $form.logoPhoto, matching: .images) {
                Label("Bild wählen", systemImage: "photo")
            }
            Button {
                pasteLogo()
            } label: {
                Label("Einfügen", systemImage: "doc.on.clipboard")
            }
            Button {
                googleSearch()
            } label: {
                Label("Google", systemImage: "globe")
            }
            if form.googleHint {
                (Text("So geht’s: ").bold() + Text("In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen."))
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
            }
            if logo != nil {
                Button(role: .destructive) {
                    form.removeLogo()
                } label: {
                    Label("Bild entfernen", systemImage: "trash")
                }
            }
            swatches
        }
    }

    private var swatches: some View {
        let data = model.data
        let catColor = data.category(form.categoryID)?.colorHex ?? KCategory.fallbackColor
        return VStack(alignment: .leading, spacing: 10) {
            Text("Farbe, wenn kein Bild")
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
            CTFlowLayout(spacing: 10, lineSpacing: 10) {
                swatch(hex: catColor, selected: (form.colorHex ?? "").isEmpty, label: "A", a11y: "Farbe der Kategorie") {
                    form.colorHex = nil
                }
                ForEach(KCategory.palette, id: \.self) { col in
                    swatch(hex: col, selected: (form.colorHex ?? "").uppercased() == col.uppercased(), label: nil, a11y: "Farbe " + col) {
                        form.colorHex = col
                    }
                }
            }
            if !form.partnerName.ctTrimmed.isEmpty {
                Text("Gilt für alle Verträge dieses Vertragspartners.")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink3)
            }
        }
        .padding(.vertical, 4)
    }

    /// «Einfügen»: Bild aus der Zwischenablage oder Bild-Link → Zuschneiden (pasteLogo)
    private func pasteLogo() {
        form.googleHint = false
        let pb = UIPasteboard.general
        if let img = pb.image {
            form.cropItem = CTImageItem(image: img)
            return
        }
        if let s = pb.string?.ctTrimmed, let u = URL(string: s), let scheme = u.scheme?.lowercased(),
           scheme == "http" || scheme == "https", u.host != nil {
            model.toast("Lade Bild…")
            let f = form
            let m = model
            Task {
                if let img = await CTLogoFetch.image(u) {
                    if !f.closed { f.cropItem = CTImageItem(image: img) }
                } else {
                    m.toast("Bild-Link konnte nicht geladen werden")
                }
            }
            return
        }
        model.toast("Kein Bild in der Zwischenablage. In Google Bild lange drücken → «Kopieren».")
    }

    /// «Google»: Bildersuche «<Name> logo» im Browser öffnen
    private func googleSearch() {
        let n = form.logoSearchName
        if n.isEmpty {
            model.toast("Zuerst den Firmennamen eintragen")
            return
        }
        form.googleHint = true
        if let u = URL(string: "https://www.google.com/search?tbm=isch&q=" + CTWebPartners.enc(n + " logo")) {
            openURL(u)
        }
    }

    private func swatch(hex: String, selected: Bool, label: String?, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color(hex: hex))
                if let l = label {
                    Text(l).font(.caption.weight(.bold)).foregroundStyle(.white)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().strokeBorder(selected ? KColor.ink : Color.clear, lineWidth: 2).padding(-3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Abschnitt «Kosten»

private struct CTFormCostSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        Section {
            LabeledContent(form.prices.isEmpty ? "Betrag" : "Anfangspreis") {
                TextField("59.90", text: $form.amountText)
                    .accessibilityIdentifier("form.amount")
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .foregroundStyle(KColor.ink)
            }
            Picker("Währung", selection: $form.currency) {
                ForEach(Currency.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
            Picker("Turnus", selection: $form.cycle) {
                ForEach(cycleOptions, id: \.self) { m in
                    Text(Format.cycleTextOrMonthly(m)).tag(m)
                }
            }
            .onChange(of: form.cycle) { _, _ in
                if let t = form.cycleChanged() { model.toast(t) }
            }
            DatePicker("Nächste Zahlung am", selection: $form.due.ctDate, displayedComponents: .date)
        } header: {
            Text("Kosten")
        }
        .listRowBackground(KColor.surface)
    }

    private var cycleOptions: [Int] {
        Format.cycleOptions.contains(form.cycle) ? Format.cycleOptions : Format.cycleOptions + [form.cycle]
    }
}

// MARK: Abschnitt «Laufzeit & Kündigung»

private struct CTFormTermSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState

    var body: some View {
        let today = model.today
        Section {
            Picker("Laufzeit", selection: $form.termFixed) {
                Text("Jederzeit kündbar").tag(false)
                Text("Feste Laufzeit").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            CTOptionalDateRow(title: "Vertragsbeginn", day: $form.start, fallback: today)
            if form.termFixed {
                CTOptionalDateRow(title: "Vertragsende", day: $form.end, fallback: today.addingMonths(12))
            }
            LabeledContent("Kündigungsfrist") {
                HStack(spacing: 6) {
                    TextField("–", text: $form.noticeText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 56)
                    Picker("Einheit", selection: $form.noticeUnit) {
                        Text("Monate").tag(NoticeUnit.months)
                        Text("Wochen").tag(NoticeUnit.weeks)
                        Text("Tage").tag(NoticeUnit.days)
                        Text(". im Monat").tag(NoticeUnit.dayOfMonth)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if form.termFixed {
                Picker("Verlängert sich um", selection: $form.renewMonths) {
                    Text("— nicht automatisch").tag(0)
                    Text("1 Monat").tag(1)
                    ForEach([3, 6, 12, 24], id: \.self) { m in
                        Text("\(m) Monate").tag(m)
                    }
                    if ![0, 1, 3, 6, 12, 24].contains(form.renewMonths) {
                        Text("\(form.renewMonths) Monate").tag(form.renewMonths)
                    }
                }
            } else {
                Picker("Kündbar per", selection: $form.cancelTerm) {
                    Text("jederzeit").tag(CancelTerm.anytime)
                    Text("Ende Periode").tag(CancelTerm.period)
                    Text("Monatsende").tag(CancelTerm.monthEnd)
                    Text("Quartalsende").tag(CancelTerm.quarterEnd)
                    Text("Halbjahresende").tag(CancelTerm.halfYearEnd)
                    Text("Jahresende").tag(CancelTerm.yearEnd)
                    Text("Ende Vertragsjahr").tag(CancelTerm.contractYear)
                }
            }
        } header: {
            Text("Laufzeit & Kündigung")
        } footer: {
            let hint = form.termHint(model.data, today: today)
            if !hint.isEmpty {
                Text(hint)
            }
        }
        .listRowBackground(KColor.surface)
    }
}

// MARK: Zeile «Weitere Angaben»

private struct CTFormMoreRow: View {
    @Bindable var form: CTFormState
    @Binding var showMore: Bool

    var body: some View {
        let summary = form.moreSummary
        Button {
            showMore = true
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weitere Angaben")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KColor.ink)
                    Text(summary ?? "Preisänderungen, Sonderzahlungen, Kundennummer, Kontakt, Dateien …")
                        .font(.footnote)
                        .foregroundStyle(summary == nil ? KColor.ink2 : KColor.teal)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
    }
}
