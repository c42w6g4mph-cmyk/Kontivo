import SwiftUI
import PhotosUI
import UIKit
import KontivoCore

/// Einnahme erfassen (incomeID nil) oder bearbeiten.
struct IncomeFormView: View {
    @Environment(AppModel.self) private var model
    let incomeID: UUID?

    var body: some View {
        let existing = model.data.income(incomeID)
        KBIncomeForm(initial: existing ?? KBIncomeForm.newDraft(model), isNew: existing == nil)
    }
}

/// Bild für «Logo zuschneiden»
struct KBCropImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Formular der Einnahme (Entwurf als Kopie, gesichert wird erst mit «Sichern»).
struct KBIncomeForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: Income
    @State private var original: Income
    @State private var amountText: String
    @State private var originalAmountText: String
    @State private var isNew: Bool
    /// Neue Änderung (z.B. Lohnerhöhung)
    @State private var priceFrom: Day?
    @State private var priceAmountText = ""
    @State private var showLogo = false
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var photoItem: PhotosPickerItem?
    /// Fenster wird geschlossen (Doppeltippen auf «Sichern»/«Löschen» schliesst sonst das Fenster darunter)
    @State private var closed = false
    @State private var cropImage: KBCropImage?
    @State private var showLogoSearch = false
    /// Hinweis nach «Google»
    @State private var webHint = false
    /// Zurück aus Google: an «Einfügen» erinnern
    @State private var webWait = false

    /// Turnus-Auswahl wie in der Web-App (einmalig zuletzt)
    static let cycleOrder = [1, 2, 3, 6, 12, 24, 0]

    init(initial: Income, isNew: Bool) {
        let at = isNew ? "" : Format.fixed2(initial.amount)
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
        _amountText = State(initialValue: at)
        _originalAmountText = State(initialValue: at)
        _isNew = State(initialValue: isNew)
    }

    /// Vorbelegung: Art Lohn, Hauptwährung, monatlich, Zahltag heute, erster Inhaber als Empfänger
    static func newDraft(_ model: AppModel) -> Income {
        Income(kind: .lohn, amount: 0, currency: model.data.settings.homeCurrency, cycle: 1,
               due: model.today, holderID: model.data.persons.first?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                amountSection
                changesSection
                periodSection
                recipientSection
                noteSection
                if !isNew {
                    deleteSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(KColor.paper)
            .navigationTitle(formTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .alert("Einnahme löschen?", isPresented: $confirmDelete) {
                Button("Löschen", role: .destructive) { delete() }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(verbatim: "«" + deleteName + "» wird endgültig gelöscht.")
            }
            .sheet(item: $cropImage) { ci in
                ImageCropSheet(image: ci.image, title: "Logo zuschneiden") { data, bg in
                    applyLogo(data, bg)
                    cropImage = nil
                }
                .environment(model)
            }
            .sheet(isPresented: $showLogoSearch) {
                LogoSearchSheet(name: logoName, currency: draft.currency, web: "") { data, bg in
                    applyLogo(data, bg)
                    showLogoSearch = false
                }
                .environment(model)
            }
            .onChange(of: photoItem) { _, item in loadPhoto(item) }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active && webWait {
                    webWait = false
                    model.toast("Bild kopiert? Jetzt «Einfügen» tippen")
                }
            }
        }
    }

    private var formTitle: String { isNew ? "Neue Einnahme" : "Einnahme bearbeiten" }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { cancel() }
                .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Verwerfen", role: .destructive) { close() }
                    Button("Weiter bearbeiten", role: .cancel) {}
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Sichern") { save() }
                .fontWeight(.semibold)
        }
    }

    // MARK: Grunddaten

    private var basicsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $showLogo) {
                logoPanel
            } label: {
                HStack(spacing: 12) {
                    MarkView(income: draft, size: 40)
                    Text("Logo").foregroundStyle(KColor.ink)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Logo ändern")
            }
            LabeledContent("Bezeichnung") {
                TextField("", text: $draft.label, prompt: Text("z.B. Lohn"))
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("income.label")
            }
            LabeledContent("Quelle") {
                TextField("", text: $draft.name, prompt: Text("z.B. Arbeitgeber AG"))
                    .multilineTextAlignment(.trailing)
                    .autocorrectionDisabled()
            }
            Picker("Art", selection: $draft.kind) {
                ForEach(IncomeKind.allCases, id: \.self) { k in
                    Label {
                        Text(verbatim: k.displayName)
                    } icon: {
                        Image(systemName: KIcon.symbol(forKey: k.icon))
                            .foregroundStyle(Color(hex: k.colorHex))
                    }
                    .tag(k)
                }
            }
            .pickerStyle(.navigationLink)
        } header: {
            Text("Grunddaten")
        }
    }

    @ViewBuilder
    private var logoPanel: some View {
        Button {
            autoFind()
        } label: {
            Label("Logo automatisch finden", systemImage: "magnifyingglass")
        }
        Button {
            pasteLogo()
        } label: {
            Label("Einfügen", systemImage: "doc.on.clipboard")
        }
        PhotosPicker(selection: $photoItem, matching: .images) {
            Label("Hochladen", systemImage: "photo")
        }
        Button {
            googleSearch()
        } label: {
            Label("Google", systemImage: "globe")
        }
        if webHint {
            (Text("So geht’s: ").bold()
             + Text("In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen."))
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
        }
        if draft.logoID != nil {
            Button(role: .destructive) {
                draft.logoID = nil
                draft.logoBg = nil
            } label: {
                Label("Logo entfernen", systemImage: "trash")
            }
        }
        Text("Ohne Bild: Symbol der Art")
            .font(.footnote)
            .foregroundStyle(KColor.ink3)
    }

    // MARK: Betrag

    private var amountLabel: String { draft.prices.isEmpty ? "Betrag netto" : "Anfangsbetrag netto" }

    private var amountSection: some View {
        Section {
            LabeledContent(amountLabel) {
                TextField("", text: $amountText, prompt: Text(verbatim: "6500.00"))
                    .accessibilityIdentifier("income.amount")
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
            }
            Picker("Währung", selection: $draft.currency) {
                ForEach(Currency.allCases, id: \.self) { c in
                    Text(verbatim: c.rawValue).tag(c)
                }
            }
            Picker("Turnus", selection: $draft.cycle) {
                ForEach(KBIncomeForm.cycleOrder, id: \.self) { m in
                    Text(verbatim: Format.incomeCycleTexts[m] ?? "").tag(m)
                }
            }
            DatePicker("Zahltag", selection: dueBinding, displayedComponents: .date)
        } header: {
            Text("Betrag")
        } footer: {
            Text("Netto eintragen, also was auf dem Konto ankommt. Einen 13. Monatslohn oder Bonus am besten als eigene jährliche Einnahme erfassen.")
        }
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { (draft.due ?? model.today).date() },
                set: { draft.due = Day(date: $0) })
    }

    // MARK: Änderungen (Preisliste)

    private var changesSection: some View {
        let today = model.today
        let sorted = draft.prices.sorted { $0.from < $1.from }
        let ni = sorted.lastIndex(where: { $0.from <= today }) ?? -1
        return Section {
            if !sorted.isEmpty {
                priceRow(title: "Anfangsbetrag", tag: ni < 0 ? "aktuell" : nil, planned: false,
                         amount: Format.parseNum(amountText), onDelete: nil)
                ForEach(Array(sorted.enumerated()), id: \.offset) { i, p in
                    priceRow(title: "ab " + Format.fmtD(p.from),
                             tag: i == ni ? "aktuell" : (p.from > today ? "geplant" : nil),
                             planned: p.from > today,
                             amount: p.amount,
                             onDelete: { removePrice(p.from) })
                }
            }
            KBOptionalDateRow(title: "Gültig ab", date: $priceFrom, defaultDate: today)
            LabeledContent("Neuer Betrag") {
                TextField("", text: $priceAmountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.body.monospacedDigit())
            }
            Button("Änderung hinzufügen") { addPrice() }
        } header: {
            Text("Änderungen, z.B. Lohnerhöhung")
        }
    }

    private func priceRow(title: String, tag: String?, planned: Bool, amount: Double?, onDelete: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: title)
                .foregroundStyle(KColor.ink)
            if let t = tag {
                Text(verbatim: t)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(planned ? KColor.warn : KColor.teal)
                    .background(Capsule().fill((planned ? KColor.warn : KColor.teal).opacity(0.12)))
            }
            Spacer(minLength: 8)
            Text(verbatim: (amount.map { Format.money($0) } ?? "—") + " " + draft.currency.rawValue)
                .font(.body.monospacedDigit())
                .foregroundStyle(KColor.ink2)
            if let del = onDelete {
                Button(action: del) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KColor.ink3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Entfernen")
            }
        }
    }

    // MARK: Zeitraum, Empfänger, Notiz, Löschen

    private var periodSection: some View {
        Section {
            KBOptionalDateRow(title: "Ab", date: $draft.start, defaultDate: model.today)
            KBOptionalDateRow(title: "Bis", date: $draft.end, defaultDate: model.today)
        } header: {
            Text("Zeitraum")
        }
    }

    private var recipientSection: some View {
        Section {
            Picker("Empfänger", selection: $draft.holderID) {
                ForEach(model.data.persons) { p in
                    Text(verbatim: p.name).tag(UUID?.some(p.id))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Empfänger — genau eine Person")
        }
    }

    private var noteSection: some View {
        Section {
            TextField("Notiz", text: $draft.note, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Notiz")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text("Einnahme löschen")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Aktionen

    private var logoName: String {
        let n = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? draft.label.trimmingCharacters(in: .whitespacesAndNewlines) : n
    }

    private var deleteName: String { original.label.isEmpty ? original.name : original.label }

    private var isDirty: Bool {
        draft != original || amountText != originalAmountText || priceFrom != nil
            || !priceAmountText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func cancel() {
        if isDirty {
            confirmDiscard = true
        } else {
            close()
        }
    }

    /// Fenster genau einmal schliessen.
    private func close() {
        guard !closed else { return }
        closed = true
        model.dismissTop()
    }

    private func save() {
        guard !closed else { return }
        let hasTitle = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasTitle else {
            model.toast("Bezeichnung fehlt")
            return
        }
        guard let a = Format.parseNum(amountText), a >= 0 else {
            model.toast("Betrag prüfen")
            return
        }
        var d = draft
        d.amount = a
        let today = model.today
        let wasNew = isNew
        let ok = model.update { data in
            _ = try data.saveIncome(d, today: today)
        }
        if ok {
            close()
            model.toast(wasNew ? "Einnahme erfasst" : "Aktualisiert")
        }
    }

    private func delete() {
        guard !closed else { return }
        let id = draft.id
        model.update { data in data.deleteIncome(id) }
        close()
        model.toast("Gelöscht")
    }

    private func addPrice() {
        guard let f = priceFrom else {
            model.toast("Datum fehlt")
            return
        }
        guard let a = Format.parseNum(priceAmountText), a >= 0 else {
            model.toast("Betrag prüfen")
            return
        }
        draft.prices.removeAll { $0.from == f }
        draft.prices.append(PriceChange(from: f, amount: Format.round2(a)))
        draft.prices.sort { $0.from < $1.from }
        priceFrom = nil
        priceAmountText = ""
    }

    private func removePrice(_ from: Day) {
        draft.prices.removeAll { $0.from == from }
    }

    // MARK: Logo

    private func applyLogo(_ data: Data, _ bg: String) {
        guard let id = model.storeFile(data, type: "image/png") else { return }
        draft.logoID = id
        draft.logoBg = bg
    }

    private func autoFind() {
        if logoName.isEmpty {
            model.toast("Zuerst den Namen eintragen")
            return
        }
        webHint = false
        showLogoSearch = true
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task { @MainActor in
            let data = try? await item.loadTransferable(type: Data.self)
            photoItem = nil
            if let d = data, let img = UIImage(data: d) {
                cropImage = KBCropImage(image: img)
            } else {
                model.toast("Bild konnte nicht geladen werden")
            }
        }
    }

    /// Bild (oder Bild-Link) aus der Zwischenablage → Zuschneiden
    private func pasteLogo() {
        webWait = false
        webHint = false
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image {
            cropImage = KBCropImage(image: img)
            return
        }
        if pb.hasURLs, let u = pb.url, ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            loadImage(from: u)
            return
        }
        if pb.hasStrings, let s = pb.string?.trimmingCharacters(in: .whitespacesAndNewlines),
           s.range(of: #"^https?://\S+$"#, options: .regularExpression) != nil, let u = URL(string: s) {
            loadImage(from: u)
            return
        }
        model.toast("Kein Bild in der Zwischenablage. In Google Bild lange drücken → «Kopieren».")
    }

    private func loadImage(from url: URL) {
        model.toast("Lade Bild…")
        Task { @MainActor in
            var img: UIImage?
            if let result = try? await URLSession.shared.data(from: url) {
                img = UIImage(data: result.0)
            }
            if let img {
                cropImage = KBCropImage(image: img)
            } else {
                model.toast("Bild-Link konnte nicht geladen werden")
            }
        }
    }

    /// Google-Bildersuche öffnen; danach Bild kopieren und «Einfügen» tippen
    private func googleSearch() {
        let n = logoName
        if n.isEmpty {
            model.toast("Zuerst den Firmennamen eintragen")
            return
        }
        var comps = URLComponents(string: "https://www.google.com/search")
        comps?.queryItems = [URLQueryItem(name: "tbm", value: "isch"), URLQueryItem(name: "q", value: n + " logo")]
        guard let url = comps?.url else { return }
        webHint = true
        webWait = true
        openURL(url)
    }
}

/// Datum, das leer sein darf: «Datum wählen» bzw. DatePicker mit «×»
struct KBOptionalDateRow: View {
    let title: String
    @Binding var date: Day?
    var defaultDate: Day

    var body: some View {
        if let d = date {
            HStack(spacing: 8) {
                DatePicker(title,
                           selection: Binding(get: { d.date() }, set: { date = Day(date: $0) }),
                           displayedComponents: .date)
                Button {
                    date = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(KColor.ink3)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text(verbatim: title + ": Datum entfernen"))
            }
        } else {
            Button {
                date = defaultDate
            } label: {
                HStack {
                    Text(verbatim: title)
                        .foregroundStyle(KColor.ink)
                    Spacer()
                    Text("Datum wählen")
                        .foregroundStyle(KColor.teal)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
