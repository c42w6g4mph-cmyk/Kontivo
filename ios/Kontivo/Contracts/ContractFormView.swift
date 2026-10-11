import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import KontivoCore

/// Vertragsformular: neu, bearbeiten, duplizieren, neuer Vertragspartner. Seit Web v145 eine Seite «wie die Ansicht»:
/// Kopf (Logo mit Stift, Bezeichnung, Vertragspartner mit Katalog, Dokumente), Kacheln «pro Monat | pro Jahr», Karten
/// Kosten · Sonderzahlungen · Laufzeit & Kündigung · Zuordnung · Kontakt · Notiz. Keine Unterseite «Weitere Angaben» mehr.
/// Sichern über `saveContract` (nur Formularfelder, Status bleibt). Sprung zu einem Feld von aussen: `ContractFormGo`.
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
    @State private var askDiscard = false

    init(context: ContractFormContext, model: AppModel) {
        self.context = context
        _form = State(initialValue: CTFormState(context: context, data: model.data, today: model.today))
    }

    var body: some View {
        NavigationStack {
            CTFormPage(form: form)
                .navigationTitle(form.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Abbrechen") { cancel() }
                    }
                    // Titel verkleinert sich statt abgeschnitten zu werden («Neuer Vertragspartner» neben breiten Knöpfen)
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
        }
        .environment(\.locale, Locale(identifier: "de_CH"))
        // Abbrechen mit Änderungen fragt (Web v143 `ask`, Texte aus dem Kern); Alert statt Aktionsblatt, damit
        // «Weiter bearbeiten» auch als Popover (iOS 26) sichtbar bleibt
        .alert(ContractFormRules.discardTitle, isPresented: $askDiscard) {
            Button(ContractFormRules.discardOK, role: .destructive) {
                form.closed = true
                dismiss()
            }
            Button(ContractFormRules.discardKeep, role: .cancel) {}
        } message: {
            Text(ContractFormRules.discardText)
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
        // Dokumente (Knopf rechts im Kopf): Datei oder Foto direkt in den Entwurf
        .fileImporter(isPresented: $form.showFileImporter, allowedContentTypes: [.pdf, .png, .jpeg, .webP, .heic, .image]) { result in
            CTFormDocs.importFile(result, form: form, model: model)
        }
        .onChange(of: form.docPhoto) { _, item in
            guard let item else { return }
            CTFormDocs.loadPhoto(item, form: form, model: model)
        }
        .onAppear {
            // Sprung von aussen (Web `openForm(c); formGo(id)`), nach dem Einblenden des Fensters
            if case .edit(let id) = context, let f = ContractFormGo.take(for: id, data: model.data) {
                let fm = form
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    fm.goTo = f
                }
            }
        }
        .onDisappear {
            form.closed = true
            form.searchTask?.cancel()
        }
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

// MARK: - Seite

/// Eine Seite im Stil der Vertragsansicht: Karten (Inset-Grouped) mit Zeilen «Beschriftung links, Wert rechts».
private struct CTFormPage: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    @FocusState private var focus: ContractFormField?

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                Form {
                    CTFormHeadSections(form: form, focus: $focus)
                    CTFormCostSection(form: form, focus: $focus)
                    CTFormExtrasSection(form: form, focus: $focus)
                    CTFormTermSection(form: form, focus: $focus)
                    CTFormAssignSection(form: form, focus: $focus)
                    CTFormContactSection(form: form, focus: $focus)
                    CTFormNoteSection(form: form, focus: $focus)
                }
                .listSectionSpacing(.compact)
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.horizontal, max(KMetric.gutter, (geo.size.width - KMetric.maxContent) / 2), for: .scrollContent)
                .onChange(of: form.goTo) { _, f in
                    guard let f else { return }
                    go(f, proxy)
                }
            }
        }
        .kPageBackground()
        .kKeyboardDone()
    }

    /// Web `formGo(id)`: Unterbereich öffnen, zur Zeile scrollen, Textfeld fokussieren
    private func go(_ f0: ContractFormField, _ proxy: ScrollViewProxy) {
        form.goTo = nil
        var f = f0
        switch f0 {
        case .prices: form.priceOpen = true
        case .extras: form.extraOpen = true
        case .address: form.addressShown = true
        case .cancelURL: if form.cancelChannel != .online { f = .web }
        case .cancelMail: if form.cancelChannel != .email { f = .mail }
        default: break
        }
        if f != f0 && f == .web && form.partnerName.ctTrimmed.isEmpty { f = .partner }
        let target = f
        // Vertragspartner liegt im Kopf (Zeile mit der Bezeichnung)
        let row: ContractFormField = f == .partner ? .label : f
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(row, anchor: .center) }
            if target.isText {
                try? await Task.sleep(nanoseconds: 300_000_000)
                focus = target
            }
        }
    }
}

// MARK: - Kopf (Web .fhead, #pSug, #dupHint, Panels, #fSugg, #fKz)

private struct CTFormHeadSections: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        let data = model.data
        Section {
            CTFormHead(form: form, focus: focus)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .id(ContractFormField.label)
        }
        CTFormPartnerSuggestions(form: form, focus: focus)
        if let hint = form.duplicateHint(data, today: model.today) {
            Section {
                Label {
                    Text(hint)
                } icon: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.footnote)
                .foregroundStyle(KColor.warn)
                .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("form.dupHint")
            }
        }
        if form.docsOpen {
            Section {
                CTFormDocsPanel(form: form)
            }
            .listRowBackground(KColor.surface)
        }
        if form.logoOpen {
            CTFormLogoPanel(form: form)
        }
        let kz = form.keyTiles(calc: model.calc)
        let sug = form.suggest
        let hasSug: Bool = { if case .none = sug { return false }; return true }()
        if hasSug || kz != nil {
            Section {
                if hasSug {
                    CTTemplateRow(form: form)
                        .listRowInsets(EdgeInsets(top: 2, leading: 4, bottom: 2, trailing: 4))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                if let k = kz {
                    CTFormKeyTiles(month: k.month, year: k.year, currency: form.currency.rawValue)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 2, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
    }
}

/// Logo (76 pt) mit Stift, Bezeichnung gross, Vertragspartner mit Katalog-Knopf, rechts Dokumente-Knopf
private struct CTFormHead: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        let data = model.data
        let logo = form.effectiveLogo(data)
        HStack(alignment: .center, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    form.logoOpen.toggle()
                    if form.logoOpen { form.docsOpen = false }
                }
            } label: {
                MarkView(logoID: logo?.id, logoBg: logo?.bg, colorHex: form.markColor(data),
                         symbol: KIcon.symbol(for: data.category(form.categoryID)), size: 76)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(KColor.surface)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(KColor.teal))
                            .overlay(Circle().strokeBorder(KColor.paper, lineWidth: 2))
                            .offset(x: 5, y: 5)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 76 * 0.25 + 3, style: .continuous)
                            .strokeBorder(form.logoOpen ? KColor.teal : Color.clear, lineWidth: 2)
                            .padding(-3)
                    )
                    .padding(.trailing, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Logo und Farbe ändern")
            .accessibilityAddTraits(form.logoOpen ? .isSelected : [])
            .accessibilityIdentifier("form.logo")
            VStack(alignment: .leading, spacing: 8) {
                TextField("Bezeichnung", text: $form.label)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(KColor.ink)
                    .focused(focus, equals: .label)
                    .submitLabel(.next)
                    .onSubmit { focus.wrappedValue = .partner }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
                    .accessibilityLabel("Bezeichnung")
                    .accessibilityIdentifier("form.label")
                    .onChange(of: form.label) { _, _ in form.sugActive = true }
                CTFormPartnerField(form: form, focus: focus)
            }
            CTFormDocsButton(form: form)
        }
    }
}

/// Runder Dokumente-Knopf rechts im Kopf (Web .ddoc #fDocsChip): «Anhängen» bzw. «n Dateien», gefüllt mit Dokumenten
private struct CTFormDocsButton: View {
    @Bindable var form: CTFormState

    var body: some View {
        let n = form.documents.count
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                form.docsOpen.toggle()
                if form.docsOpen { form.logoOpen = false }
            }
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(n > 0 ? KColor.teal : KColor.teal.opacity(0.13))
                    Image(systemName: "paperclip")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(n > 0 ? KColor.surface : KColor.teal)
                }
                .frame(width: 44, height: 44)
                Text(n > 0 ? Format.count(n, "Datei", "Dateien") : "Anhängen")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KColor.teal)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(minWidth: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(n > 0 ? Format.count(n, "Dokument", "Dokumente") : "Dokument anhängen")
        .accessibilityAddTraits(form.docsOpen ? .isSelected : [])
        .accessibilityIdentifier("form.docsChip")
    }
}

// MARK: Logo und Farbe (Panel unter dem Kopf, Web #oLogo)

private struct CTFormLogoPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Bindable var form: CTFormState

    var body: some View {
        let logo = form.effectiveLogo(model.data)
        Section {
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
        } header: {
            Text("Logo & Farbe")
        }
        .listRowBackground(KColor.surface)
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

// MARK: - Karte «Kosten» (Web #fsCost)

private struct CTFormCostSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    var body: some View {
        let calc = model.calc
        let today = model.today
        Section {
            if let chart = form.priceChart(calc: calc) {
                CTPriceChart(chart: chart, identifier: "form.priceChart", framed: false)
                    .listRowInsets(EdgeInsets(top: 6, leading: 14, bottom: 4, trailing: 14))
            }
            amountRow
            priceRows(today: today)
            if form.priceOpen {
                priceForm(today: today)
            } else {
                CTFormAddRow(title: "Preisänderung", identifier: "form.priceOpen") {
                    withAnimation(.easeInOut(duration: 0.2)) { form.openPriceForm() }
                }
            }
            Picker(selection: Binding(get: { form.cycle }, set: { v in
                if let t = form.setCycle(v, today: model.today) { model.toast(t) }
            })) {
                ForEach(cycleOptions, id: \.self) { m in
                    Text(Format.cycleTextOrMonthly(m)).tag(m)
                }
            } label: {
                CTRowLabel("Zahlungsrhythmus")
            }
            .pickerStyle(.menu)
            .tint(KColor.teal)
            .accessibilityIdentifier("form.cycle")
            dueRow
            if form.dueOpen {
                CTDueGrid(day: form.due.day, month: form.due.month, cycle: form.cycle,
                          onDay: { d in withAnimation(.easeInOut(duration: 0.2)) { form.pickDueDay(d, today: model.today) } },
                          onMonth: { m in form.pickDueMonth(m, today: model.today) })
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("form.dueGrid")
            }
            payRows
        } header: {
            Text("Kosten")
        } footer: {
            // Zahlungsregel live, gleich formuliert wie im Detail (Web #fPayHint)
            let h = form.payHint(calc: calc)
            if !h.isEmpty {
                Text(h).accessibilityIdentifier("form.payHint")
            }
        }
        .listRowBackground(KColor.surface)
    }

    private var cycleOptions: [Int] {
        Format.cycleOptions.contains(form.cycle) ? Format.cycleOptions : Format.cycleOptions + [form.cycle]
    }

    /// Betrag (bzw. Anfangspreis) und Währung in einer Zeile (Web #fAmt + #fCur)
    private var amountRow: some View {
        HStack(spacing: 8) {
            CTRowLabel(form.prices.isEmpty ? "Betrag" : "Anfangspreis")
                .layoutPriority(1)
            TextField(CTNumber.placeholder(form.currency), text: $form.amountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(KColor.teal)
                .focused(focus, equals: .amount)
                .accessibilityLabel(form.prices.isEmpty ? "Betrag" : "Anfangspreis")
                .accessibilityIdentifier("form.amount")
            Menu {
                Picker("Währung", selection: $form.currency) {
                    ForEach(Currency.allCases, id: \.self) { c in
                        Text(c.rawValue).tag(c)
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(form.currency.rawValue)
                        .font(.body.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(KColor.teal)
                .fixedSize()
            }
            .accessibilityLabel("Währung, " + form.currency.rawValue)
            .accessibilityIdentifier("form.currency")
        }
        .id(ContractFormField.amount)
    }

    /// Preisliste (Web #pList .fpr): «ab TT.MM.JJ», Plakette aktuell/geplant, Betrag, Veränderung in %, × entfernt,
    /// Antippen lädt die Zeile zum Ändern
    @ViewBuilder
    private func priceRows(today: Day) -> some View {
        let ps = form.sortedPrices
        let nowIdx = ps.lastIndex { $0.from <= today } ?? -1
        let base = CTNumber.parse(form.amountText) ?? 0
        ForEach(Array(ps.enumerated()), id: \.offset) { i, p in
            let prev = i == 0 ? base : ps[i - 1].amount
            HStack(spacing: 8) {
                Button {
                    model.toast(form.editPrice(p))
                } label: {
                    HStack(spacing: 6) {
                        Text("ab " + Format.fmtShort(p.from))
                            .foregroundStyle(KColor.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                        if i == nowIdx {
                            CTMiniTag(text: "aktuell")
                        } else if p.from > today {
                            CTMiniTag(text: "geplant", tone: KColor.warn)
                        }
                        Spacer(minLength: 6)
                        Text(verbatim: p.amount != 0 ? Format.money(p.amount, form.currency) : "gratis")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(KColor.teal)
                            .lineLimit(1)
                        if prev != 0 {
                            let pc = (p.amount - prev) / prev * 100
                            CTPctPill(text: Format.pctText(pc), tone: pc > 0.05 ? 1 : (pc < -0.05 ? -1 : 0))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("form.priceRow.\(i)")
                Button {
                    form.removePrice(p.from)
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preisänderung entfernen")
            }
        }
    }

    /// Unterbereich «Preisänderung» (Web #pForm): Gültig ab, Neuer Betrag, hinzufügen / Abbrechen
    @ViewBuilder
    private func priceForm(today: Day) -> some View {
        CTFormDateRow(title: "Gültig ab", day: form.priceFrom, fallback: today, identifier: "form.priceFrom") { form.priceFrom = $0 }
            .id(ContractFormField.prices)
        HStack(spacing: 12) {
            CTRowLabel("Neuer Betrag")
            TextField(Format.numberStyle(form.currency) == .de ? "74,90" : "74.90", text: $form.priceAmountText)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .foregroundStyle(KColor.teal)
                .accessibilityLabel("Neuer Betrag")
                .accessibilityIdentifier("form.priceAmount")
        }
        HStack(spacing: 12) {
            CTFormOKButton(title: "Preisänderung hinzufügen", identifier: "form.priceAdd") { add(force: false) }
            Button("Abbrechen") {
                withAnimation(.easeInOut(duration: 0.2)) { form.cancelPriceForm() }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(KColor.ink2)
            .accessibilityIdentifier("form.priceCancel")
        }
        .padding(.vertical, 2)
    }

    /// Vormerken; «Preis bleibt gleich» fragt nicht blockierend nach («Trotzdem hinzufügen»)
    private func add(force: Bool) {
        switch form.addPrice(force: force) {
        case .toast(let t, let long, _):
            model.toast(t, seconds: long ? 4 : 2.4)
        case .confirmSame(let title, let message):
            let f = form
            let m = model
            model.ask(title: title, message: message, ok: "Trotzdem hinzufügen") {
                if case .toast(let t, let long, _) = f.addPrice(force: true) { m.toast(t, seconds: long ? 4 : 2.4) }
            }
        }
    }

    /// «Zahlung am» als Zeile (Web #fDueBtn): «27. im Monat», «27. Jan, Apr, Jul, Okt», «27. Juni»
    private var dueRow: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { form.dueOpen.toggle() }
        } label: {
            HStack(spacing: 8) {
                CTRowLabel("Zahlung am")
                Spacer(minLength: 8)
                Text(form.dueText)
                    .foregroundStyle(KColor.teal)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
                    .rotationEffect(.degrees(form.dueOpen ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zahlung am")
        .accessibilityValue(form.dueText)
        .accessibilityAddTraits(form.dueOpen ? .isSelected : [])
        .accessibilityIdentifier("form.dueBtn")
    }

    static let payMethods = ["Lastschrift (LSV/SEPA)", "eBill", "Kreditkarte", "QR-Rechnung", "Dauerauftrag", "TWINT", "PayPal", "Sonstiges"]

    /// «Zahlung via» (Zahlungsart) und darunter «über …» (Belastet über), nur mit Zahlungsart oder Wert (Web #fPayM/#fPayA)
    @ViewBuilder
    private var payRows: some View {
        let m = form.payMethod
        let options = (m.isEmpty || CTFormCostSection.payMethods.contains(m)) ? CTFormCostSection.payMethods : CTFormCostSection.payMethods + [m]
        Picker(selection: $form.payMethod) {
            Text("wählen").tag("")
            ForEach(options, id: \.self) { o in
                Text(o).tag(o)
            }
        } label: {
            CTRowLabel("Zahlung via")
        }
        .pickerStyle(.menu)
        .tint(m.isEmpty ? KColor.ink3 : KColor.teal)
        .accessibilityIdentifier("form.payMethod")
        if !m.isEmpty || !form.payAccount.ctTrimmed.isEmpty || focus.wrappedValue == .payAccount {
            TextField("über, z.B. Visa …4417", text: $form.payAccount)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
                .foregroundStyle(KColor.teal)
                .focused(focus, equals: .payAccount)
                .accessibilityLabel("Belastet über")
                .accessibilityIdentifier("form.payAccount")
                .id(ContractFormField.payAccount)
                .listRowSeparator(.hidden, edges: .top)
        }
    }
}

// MARK: - Aufteilung

/// Aufteilung bei gemeinsamen Verträgen (Web v82–v84): «Gleich aufgeteilt» oder «Individuell» mit Beträgen pro Zahlung
/// (auf den Rappen, zum aktuellen Preis), Prozent darunter. 2 Personen: Namen oben, Regler (50-Rappen-Schritte, nach rechts = mehr
/// für die rechte Person), darunter beide Felder; das andere passt sich an. Ab 3: nur Felder nebeneinander, letzter = Rest.
struct CTFormSplitRows: View {
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
                                .accessibilityValue(Format.money(form.splitAmount(holders[1].id, total: total), form.currency) + " " + form.currency.rawValue)
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
                                    Text(verbatim: Format.money(form.splitAmount(p.id, total: total), form.currency))
                                        .font(.body.weight(.semibold).monospacedDigit())
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                        .padding(.horizontal, 10).padding(.vertical, 9)
                                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                                } else {
                                    TextField(Format.amountInput(0, form.currency), text: amountBinding(p.id, total: total))
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
                    Text(verbatim: total > 0 ? "Total " + Format.money(total, form.currency) + " " + form.currency.rawValue + " pro Zahlung" : "Zuerst den Betrag unter «Kosten» eintragen.")
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
        return Format.number(r, maxFractionDigits: 1) + "\u{00A0}%"
    }

    /// Während der Eingabe bleibt der getippte Text stehen; sonst der formatierte Betrag.
    private func amountBinding(_ id: UUID, total: Double) -> Binding<String> {
        Binding(
            get: { focused == id ? (texts[id] ?? Format.amountInput(form.splitAmount(id, total: total), form.currency)) : Format.amountInput(form.splitAmount(id, total: total), form.currency) },
            set: { v in
                texts[id] = v
                form.setSplitAmount(id, CTNumber.parse(v) ?? 0, total: total)
            }
        )
    }
}
