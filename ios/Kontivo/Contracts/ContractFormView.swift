import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
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
                    // Titel verkleinert sich statt abgeschnitten zu werden («Vertrag bearbe…» neben breiten Knöpfen)
                    ToolbarItem(placement: .principal) {
                        Text(form.title)
                            .font(.headline)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .accessibilityAddTraits(.isHeader)
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
        } message: {
            Text("Deine Eingaben in diesem Formular gehen verloren.")
        }
        .sheet(isPresented: $form.showCategoryPicker) {
            CTCategoryPickSheet(selected: $form.categoryID)
                .environment(model)
        }
        .sheet(isPresented: $form.showCatalog) {
            CTCatalogSheet { t in
                CTTplLogo.apply(t, form: form, model: model)
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
        // Steuern & Gebühren erzwingen «Nicht kündbar» (Web paintCats)
        .onChange(of: form.categoryID) { _, _ in form.categoryChanged(model.data) }
        // Dokumente (Chip neben dem Logo): Datei oder Foto direkt in den Entwurf
        .fileImporter(isPresented: $form.showFileImporter, allowedContentTypes: [.pdf, .png, .jpeg, .webP, .heic, .image]) { result in
            CTFormDocs.importFile(result, form: form, model: model)
        }
        .onChange(of: form.docPhoto) { _, item in
            guard let item else { return }
            CTFormDocs.loadPhoto(item, form: form, model: model)
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
                CTFormTermSection(form: form, showMore: $showMore)
                Section {
                    CTFormMoreRow(form: form, showMore: $showMore)
                }
                .listRowBackground(KColor.surface)
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .contentMargins(.horizontal, max(KMetric.gutter, (geo.size.width - KMetric.maxContent) / 2), for: .scrollContent)
        }
        .kPageBackground()
        .kKeyboardDone()
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
                if form.holderIDs.count >= 2 { CTFormSplitRows(form: form) }
            }
        } header: {
            Text("Vertrag")
        }
        .listRowBackground(KColor.surface)
    }

    @State private var showTaxInfo = false

    /// Text des Infoknopfs hinter «Steuern & Gebühren» (Web TAX_INFO, v88)
    static let taxInfo = "Steuern und Gebühren (z.B. Serafe, Rundfunkbeitrag, Motorfahrzeugsteuer) gelten als nicht kündbar: keine Fristen, kein Kündigen, nicht unter «Fristen». Andere nicht kündbare Verträge: unter «Laufzeit & Kündigung» die Kachel «Nicht kündbar» wählen."

    private var categoryRow: some View {
        let cat = model.data.category(form.categoryID)
        return HStack(spacing: 6) {
            categoryButton(cat)
            if cat?.kind == .taxes {
                Button { showTaxInfo = true } label: {
                    Image(systemName: "info.circle").font(.body).foregroundStyle(KColor.ink2)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Info: nicht kündbar")
            }
        }
        .alert("Nicht kündbar", isPresented: $showTaxInfo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(CTFormContractSection.taxInfo)
        }
    }

    private func categoryButton(_ cat: KontivoCore.Category?) -> some View {
        Button {
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
        .buttonStyle(.borderless)
        .accessibilityLabel("Kategorie, " + (cat?.name ?? "Kategorie wählen"))
        .accessibilityIdentifier("form.category")
    }

    private var holdersRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Personen — mehrere möglich")
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

/// Aufteilung bei gemeinsamen Verträgen (Web v82–v84): «Gleich aufgeteilt» oder «Individuell» mit Beträgen pro Zahlung
/// (auf den Rappen, zum aktuellen Preis), Prozent darunter. 2 Inhaber: Namen oben, Regler (50-Rappen-Schritte, nach rechts = mehr
/// für die rechte Person), darunter beide Felder; das andere passt sich an. Ab 3: nur Felder nebeneinander, letzter = Rest.
private struct CTFormSplitRows: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    @State private var texts: [UUID: String] = [:]
    @FocusState private var focused: UUID?

    var body: some View {
        let holders = form.holderIDs.compactMap { model.data.person($0) }
        let total = form.splitTotal(today: model.today)
        VStack(alignment: .leading, spacing: 8) {
            Picker("Aufteilung", selection: Binding(get: { form.splitIndividual }, set: { form.setSplitIndividual($0) })) {
                Text("Gleich aufgeteilt").tag(false)
                Text("Individuell").tag(true)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("form.split")
            if form.splitIndividual {
                VStack(alignment: .leading, spacing: 8) {
                    if holders.count == 2 {
                        HStack {
                            Text(holders[0].name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(holders[1].name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        }
                        .foregroundStyle(KColor.ink)
                        if total > 0 {
                            Slider(value: Binding(get: { form.splitAmount(holders[1].id, total: total) },
                                                  set: { v in focused = nil; texts = [:]; form.setSplitAmount(holders[1].id, min(v, total), total: total) }),
                                   in: 0...(total * 2).rounded(.up) / 2, step: 0.5)
                                .tint(KColor.ink3)
                                .accessibilityLabel("Aufteilung, Betrag " + holders[1].name)
                                .accessibilityValue(Format.money(form.splitAmount(holders[1].id, total: total)) + " " + form.currency.rawValue)
                        }
                    }
                    let cols = holders.count == 3 ? 3 : 2
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: cols), alignment: .leading, spacing: 10) {
                        ForEach(Array(holders.enumerated()), id: \.element.id) { i, p in
                            let rest = holders.count > 2 && i == holders.count - 1
                            VStack(alignment: holders.count == 2 && i == 1 ? .trailing : .leading, spacing: 5) {
                                if holders.count > 2 {
                                    Text(p.name).font(.footnote.weight(.semibold)).foregroundStyle(KColor.ink).lineLimit(1)
                                }
                                if rest {
                                    Text(verbatim: Format.money(form.splitAmount(p.id, total: total)))
                                        .font(.body.weight(.semibold).monospacedDigit())
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(.horizontal, 10).padding(.vertical, 9)
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                } else {
                                    TextField("0.00", text: amountBinding(p.id, total: total))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                        .focused($focused, equals: p.id)
                                        .padding(.horizontal, 10).padding(.vertical, 9)
                                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.surface))
                                        .accessibilityLabel("Betrag " + p.name)
                                        .disabled(total <= 0)
                                }
                                Text(verbatim: pct(form.splitPercent(p.id)) + (rest ? " · Rest" : ""))
                                    .font(.caption.monospacedDigit()).foregroundStyle(KColor.ink2)
                            }
                        }
                    }
                    Text(verbatim: total > 0 ? "Total " + Format.money(total) + " " + form.currency.rawValue + " pro Zahlung" : "Zuerst den Betrag unter «Kosten» eintragen.")
                        .font(.caption).foregroundStyle(KColor.ink2)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(KColor.field, in: RoundedRectangle(cornerRadius: 12))
                .onChange(of: focused) { old, _ in if let o = old { texts[o] = nil } }
            }
        }
        .padding(.vertical, 4)
    }

    private func pct(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return (r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)) + "\u{00A0}%"
    }

    /// Während der Eingabe bleibt der getippte Text stehen; sonst der formatierte Betrag.
    private func amountBinding(_ id: UUID, total: Double) -> Binding<String> {
        Binding(
            get: { focused == id ? (texts[id] ?? String(format: "%.2f", form.splitAmount(id, total: total))) : String(format: "%.2f", form.splitAmount(id, total: total)) },
            set: { v in
                texts[id] = v
                form.setSplitAmount(id, CTNumber.parse(v) ?? 0, total: total)
            }
        )
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
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    form.logoOpen.toggle()
                    if form.logoOpen { form.docsOpen = false }
                }
            } label: {
                HStack(spacing: 12) {
                    MarkView(logoID: logo?.id, logoBg: logo?.bg, colorHex: form.markColor(data), symbol: symbol, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Logo").foregroundStyle(KColor.ink)
                        Text("Logo & Farbe").font(.footnote).foregroundStyle(KColor.ink2)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                        .rotationEffect(.degrees(form.logoOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Logo und Farbe ändern")
            Spacer(minLength: 8)
            CTFormDocsChip(form: form)
        }
        if form.docsOpen {
            CTFormDocsPanel(form: form)
        }
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
            // Das Logo hängt am Vertragspartner (die Farbe darunter nur an diesem Vertrag) – Hinweis daher direkt bei den Bild-Knöpfen
            if !form.partnerName.ctTrimmed.isEmpty {
                Text("Gilt für alle Verträge dieses Vertragspartners.")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink3)
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
            Picker("Zahlungsrhythmus", selection: $form.cycle) {
                ForEach(cycleOptions, id: \.self) { m in
                    Text(Format.cycleTextOrMonthly(m)).tag(m)
                }
            }
            .onChange(of: form.cycle) { _, _ in
                if let t = form.cycleChanged() { model.toast(t) }
            }
            DatePicker("Zahlung am", selection: $form.due.ctDate, displayedComponents: .date)
                .accessibilityIdentifier("form.due")
        } header: {
            Text("Kosten")
        } footer: {
            // Zahlungsregel live, gleich formuliert wie im Detail (Web #fPayHint)
            let h = form.payHint(model.data, today: model.today)
            if !h.isEmpty {
                Text(h).accessibilityIdentifier("form.payHint")
            }
        }
        .listRowBackground(KColor.surface)
    }

    private var cycleOptions: [Int] {
        Format.cycleOptions.contains(form.cycle) ? Format.cycleOptions : Format.cycleOptions + [form.cycle]
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
                    Text(summary ?? "Preisänderungen, Sonderzahlungen, Kundennummer, Kontakt …")
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
        .accessibilityIdentifier("form.more")
    }
}
