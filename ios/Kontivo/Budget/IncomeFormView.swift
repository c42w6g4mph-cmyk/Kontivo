import SwiftUI
import PhotosUI
import UIKit
import KontivoCore

/// Einnahme erfassen (incomeID nil) oder bearbeiten.
struct IncomeFormView: View {
    @Environment(AppModel.self) private var model
    let incomeID: UUID?

    var body: some View {
        if let sug = BankFormBridge.shared.income(incomeID) {
            // Bereich import: Vorschlag aus dem Kontoauszug (Web `openIncome` mit `fBank`)
            KBIncomeForm(initial: sug, isNew: true, bankSuggestion: true)
        } else {
            let existing = model.data.income(incomeID)
            KBIncomeForm(initial: existing ?? KBIncomeForm.newDraft(model), isNew: existing == nil)
        }
    }
}

/// Bild für «Logo zuschneiden»
struct KBCropImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Formular der Einnahme im Stil des Vertragsformulars (Web v154/v155/v159, `openIncome`): Kopf mit Logo, Bezeichnung und
/// Quelle, Kacheln «pro Monat | pro Jahr», Karte «Betrag» mit Verlauf, Änderungsliste (Prozent, Antippen lädt die Änderung,
/// «Abbrechen» stellt sie wieder her), Zahlungsrhythmus und «Zahlung am» als Tag im Tagesraster (Monatsreihe ab Rhythmus
/// 2 Monate, einmalig = Datum), «Zeitraum», «Zuordnung» (Art, Empfänger), «Notiz». Entwurf als Kopie, gesichert wird erst
/// mit «Sichern».
struct KBIncomeForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: Income
    @State private var original: Income
    @State private var amountText: String
    @State private var originalAmountText: String
    @State private var isNew: Bool
    /// Unterformular «Änderung, z.B. Lohnerhöhung» offen
    @State private var subOpen = false
    @State private var priceFrom: Day?
    @State private var priceAmountText = ""
    /// Zum Bearbeiten angetippte Änderung (Web `iPBak`): «Abbrechen» stellt sie wieder her
    @State private var priceBak: PriceChange?
    /// Tagesraster «Zahlung am» offen
    @State private var dueOpen = false
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

    /// Zahlungsrhythmus wie in der Web-App (einmalig zuletzt)
    static let cycleOrder = [1, 2, 3, 6, 12, 24, 0]

    /// Bereich import: Vorschlag aus dem Kontoauszug – Titel «Vorschlag», «Sichern» geht zurück in die Vorschlagsliste
    private let bankSuggestion: Bool

    init(initial: Income, isNew: Bool, bankSuggestion: Bool = false) {
        self.bankSuggestion = bankSuggestion
        let at = isNew && !bankSuggestion ? "" : Format.amountInput(initial.amount, initial.currency)
        _draft = State(initialValue: initial)
        _original = State(initialValue: initial)
        _amountText = State(initialValue: at)
        _originalAmountText = State(initialValue: at)
        _isNew = State(initialValue: isNew)
    }

    /// Vorbelegung: Art Lohn, Hauptwährung, monatlich, Zahlung heute, erste Person als Empfänger
    static func newDraft(_ model: AppModel) -> Income {
        Income(kind: .lohn, amount: 0, currency: model.data.settings.homeCurrency, cycle: 1,
               due: model.today, holderID: model.data.persons.first?.id)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                Form {
                    headSection
                    if showLogo { logoSection }
                    tilesSection
                    amountSection
                    periodSection
                    assignmentSection
                    noteSection
                    if !isNew { deleteSection }
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.interactively)
                .contentMargins(.horizontal, max(KMetric.gutter, (geo.size.width - KMetric.maxContent) / 2), for: .scrollContent)
            }
            .kPageBackground()
            .kKeyboardDone()
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
            .onChange(of: draft.cycle) { _, _ in dueOpen = false }
        }
    }

    /// Web v154: «Neue Einnahme» bzw. «Bearbeiten»
    private var formTitle: String { bankSuggestion ? "Vorschlag" : (isNew ? "Neue Einnahme" : "Bearbeiten") }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Abbrechen") { cancel() }
                .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Verwerfen", role: .destructive) { close() }
                    Button("Weiter bearbeiten", role: .cancel) {}
                } message: {
                    Text("Deine Eingaben in diesem Formular gehen verloren.")
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Sichern") { save() }
                .fontWeight(.semibold)
        }
    }

    // MARK: Kopf (Logo, Bezeichnung, Quelle)

    private var headSection: some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showLogo.toggle() }
                } label: {
                    MarkView(income: draft, size: 76)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Circle().fill(KColor.tealFill))
                                .overlay(Circle().strokeBorder(KColor.surface, lineWidth: 2))
                                .offset(x: 5, y: 5)
                        }
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Logo ändern")
                .accessibilityIdentifier("income.logo")
                VStack(spacing: 8) {
                    TextField("", text: $draft.label, prompt: Text("Bezeichnung, z.B. Lohn"))
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .foregroundStyle(KColor.ink)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(KColor.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .accessibilityLabel("Bezeichnung")
                        .accessibilityIdentifier("income.label")
                    TextField("", text: $draft.name, prompt: Text("Quelle, z.B. Arbeitgeber AG"))
                        .foregroundStyle(KColor.ink2)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(KColor.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .accessibilityLabel("Quelle")
                        .accessibilityIdentifier("income.name")
                }
            }
            .padding(.top, 4)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
    }

    private var logoSection: some View {
        Section {
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
        } header: {
            Text("Logo")
        } footer: {
            Text("Ohne Bild: Symbol der Art")
        }
        .listRowBackground(KColor.surface)
    }

    // MARK: Kacheln «pro Monat | pro Jahr» (Web iPaintKz)

    /// Entwurf mit eingetipptem Betrag (Web `iDraftPC`)
    private var draftForCalc: Income {
        var t = draft
        t.amount = Format.parseAmount(amountText) ?? 0
        return t
    }

    @ViewBuilder
    private var tilesSection: some View {
        let d = draftForCalc
        if d.amount > 0 || !d.prices.isEmpty {
            let cp = model.calc.curPrice(d)
            let cu = d.currency
            Section {
                HStack(spacing: 8) {
                    if d.cycle != 0 {
                        tile("pro Monat", Format.money(cp / Double(d.cycle), cu), cu)
                        tile("pro Jahr", Format.money0(cp / Double(d.cycle) * 12, cu), cu)
                    } else {
                        tile("einmalig", Format.money(cp, cu), cu)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("income.tiles")
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    private func tile(_ label: String, _ value: String, _ cu: Currency) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label)
                .font(.caption)
                .foregroundStyle(KColor.ink2)
            (Text(verbatim: value).font(.system(size: 22, weight: .bold))
                + Text(verbatim: " " + cu.rawValue).font(.footnote.weight(.medium)).foregroundStyle(KColor.ink2))
                .foregroundStyle(KColor.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Betrag (Verlauf, Betrag, Änderungen, Rhythmus, Zahlung am)

    private var amountLabel: String { draft.prices.isEmpty ? "Betrag netto" : "Anfangsbetrag netto" }

    /// Platzhalter nach Hauptwährung (Web `amtPh`)
    private var amountPlaceholder: String { Format.numberStyle() == .de ? "6500,00" : "6500.00" }

    private var amountSection: some View {
        let d = draftForCalc
        let chart = model.calc.priceChart(amount: d.amount, prices: d.prices, start: d.start, currency: d.currency, income: true)
        return Section {
            if let ch = chart {
                KBIncomeChart(chart: ch, identifier: "income.form.chart")
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            }
            amountRow
            priceRows
            if subOpen {
                priceSubForm
            } else {
                Button {
                    priceFrom = nil
                    priceAmountText = ""
                    subOpen = true
                } label: {
                    Label("Änderung, z.B. Lohnerhöhung", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(KColor.teal)
                }
                .buttonStyle(.borderless)
                .accessibilityIdentifier("income.addChange")
            }
            Picker("Zahlungsrhythmus", selection: $draft.cycle) {
                ForEach(KBIncomeForm.cycleOrder, id: \.self) { m in
                    Text(verbatim: Format.incomeCycleTexts[m] ?? "").tag(m)
                }
            }
            .pickerStyle(.menu)
            .accessibilityIdentifier("income.cycle")
            dueRows
        } header: {
            Text("Betrag")
        } footer: {
            Text("Netto eintragen, also was auf dem Konto ankommt. Einen 13. Monatslohn oder Bonus am besten als eigene jährliche Einnahme erfassen.")
        }
        .listRowBackground(KColor.surface)
    }

    private var amountRow: some View {
        HStack(spacing: 8) {
            Text(verbatim: amountLabel)
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            TextField("", text: $amountText, prompt: Text(verbatim: amountPlaceholder))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .foregroundStyle(KColor.teal)
                .frame(minWidth: 80)
                .accessibilityLabel(Text(verbatim: amountLabel))
                .accessibilityIdentifier("income.amount")
            Menu {
                Picker("Währung", selection: $draft.currency) {
                    ForEach(Currency.allCases, id: \.self) { c in
                        Text(verbatim: c.rawValue).tag(c)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 3) {
                    Text(verbatim: draft.currency.rawValue)
                        .foregroundStyle(KColor.teal)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                }
            }
            .accessibilityLabel("Währung")
            .accessibilityValue(Text(verbatim: draft.currency.rawValue))
            .accessibilityIdentifier("income.currency")
        }
    }

    /// Änderungsliste (Web `iPaintPrices`): «ab 01.01.26» mit Plakette aktuell/geplant, Betrag, Veränderung in %
    /// (bei Einnahmen ist mehr gut: grün), × entfernt, Antippen lädt die Änderung ins Unterformular.
    @ViewBuilder
    private var priceRows: some View {
        let today = model.today
        let sorted = draft.prices.sorted { $0.from < $1.from }
        let ni = sorted.lastIndex(where: { $0.from <= today }) ?? -1
        let base = Format.parseAmount(amountText) ?? 0
        ForEach(Array(sorted.enumerated()), id: \.element.from) { i, p in
            let prev = i == 0 ? base : sorted[i - 1].amount
            priceRow(p, tag: i == ni ? "aktuell" : (p.from > today ? "geplant" : nil), planned: p.from > today, prev: prev)
        }
    }

    private func priceRow(_ p: PriceChange, tag: String?, planned: Bool, prev: Double) -> some View {
        let pc: Double? = prev != 0 ? (p.amount - prev) / prev * 100 : nil
        return HStack(spacing: 8) {
            Button {
                editPrice(p)
            } label: {
                HStack(spacing: 6) {
                    Text(verbatim: "ab " + Format.fmtShort(p.from))
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                    if let t = tag {
                        Text(verbatim: t)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(planned ? KColor.warn : Color.white)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(planned ? KColor.warn.opacity(0.15) : KColor.teal))
                    }
                    Spacer(minLength: 6)
                    Text(verbatim: Format.money(p.amount, draft.currency))
                        .font(.body.weight(.medium).monospacedDigit())
                        .foregroundStyle(KColor.teal)
                        .lineLimit(1)
                    if let v = pc {
                        let tone: PriceChartTone = v > 0.05 ? .down : (v < -0.05 ? .up : .neutral)
                        Text(verbatim: Format.pctText(v))
                            .font(.caption.weight(.bold))
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .foregroundStyle(KBIncomeChart.color(tone, neutral: KColor.ink2))
                            .background(Capsule().fill(KBIncomeChart.color(tone, neutral: KColor.ink).opacity(tone == .neutral ? 0.07 : 0.15)))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Antippen zum Ändern")
            .accessibilityIdentifier("income.price." + p.from.iso)
            Button {
                removePrice(p.from)
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(KColor.ink3)
                    .padding(.vertical, 6)
                    .padding(.leading, 4)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Änderung entfernen")
        }
    }

    /// Unterformular «Gültig ab» / «Neuer Betrag» / «Änderung hinzufügen» / «Abbrechen»
    @ViewBuilder
    private var priceSubForm: some View {
        KBOptionalDateRow(title: "Gültig ab", date: $priceFrom, defaultDate: model.today)
            .accessibilityIdentifier("income.priceFrom")
        HStack {
            Text("Neuer Betrag").foregroundStyle(KColor.ink)
            Spacer(minLength: 8)
            TextField("", text: $priceAmountText, prompt: Text(verbatim: "–"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .foregroundStyle(KColor.teal)
                .accessibilityLabel("Neuer Betrag")
                .accessibilityIdentifier("income.priceAmount")
        }
        VStack(spacing: 2) {
            Button {
                _ = addPrice()
            } label: {
                Text("Änderung hinzufügen")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("income.priceAdd")
            Button {
                cancelSub()
            } label: {
                Text("Abbrechen")
                    .font(.body)
                    .foregroundStyle(KColor.ink2)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("income.priceCancel")
        }
        .padding(.vertical, 4)
    }

    /// «Zahlung am» als Tag im Monat (Tagesraster, Monatsreihe ab 2 Monaten); einmalig ein Datum (Web `iPaintDue`)
    @ViewBuilder
    private var dueRows: some View {
        if draft.cycle == 0 {
            DatePicker("Datum", selection: dueBinding, displayedComponents: .date)
                .accessibilityIdentifier("income.dueDate")
        } else {
            let txt = ContractFormRules.dueText(draft.due, cycle: draft.cycle)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { dueOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Zahlung am").foregroundStyle(KColor.ink)
                    Spacer(minLength: 8)
                    Text(verbatim: txt)
                        .foregroundStyle(KColor.teal)
                        .multilineTextAlignment(.trailing)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                        .rotationEffect(.degrees(dueOpen ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Zahlung am")
            .accessibilityValue(Text(verbatim: txt))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("income.due")
            if dueOpen {
                let v = draft.due ?? model.today
                KBDueGrid(day: v.day, month: v.month, cycle: draft.cycle, idPrefix: "income.due") { d in
                    pickDue(day: d, month: nil)
                } onMonth: { m in
                    pickDue(day: nil, month: m)
                }
            }
        }
    }

    private var dueBinding: Binding<Date> {
        Binding(get: { (draft.due ?? model.today).date() },
                set: { draft.due = Day(date: $0) })
    }

    /// Tag antippen übernimmt und klappt zu, Monat antippen übernimmt und bleibt offen (Web v159, `iDueFrom`)
    private func pickDue(day: Int?, month: Int?) {
        let v = draft.due ?? model.today
        draft.due = ContractFormRules.incomeDueFrom(day: day ?? v.day, month: month ?? v.month, cycle: draft.cycle, today: model.today)
        if day != nil {
            withAnimation(.easeInOut(duration: 0.2)) { dueOpen = false }
        }
    }

    // MARK: Zeitraum, Zuordnung, Notiz, Löschen

    private var periodSection: some View {
        Section {
            KBOptionalDateRow(title: "Ab", date: $draft.start, defaultDate: model.today)
            KBOptionalDateRow(title: "Bis", date: $draft.end, defaultDate: model.today)
        } header: {
            Text("Zeitraum")
        }
        .listRowBackground(KColor.surface)
    }

    private var assignmentSection: some View {
        Section {
            Menu {
                Picker("Art", selection: $draft.kind) {
                    ForEach(IncomeKind.allCases, id: \.self) { k in
                        Label(k.displayName, systemImage: KIcon.symbol(forKey: k.icon)).tag(k)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 10) {
                    Text("Art").foregroundStyle(KColor.ink)
                    Spacer(minLength: 8)
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(hex: draft.kind.colorHex))
                        .frame(width: 26, height: 26)
                        .overlay(Image(systemName: KIcon.symbol(forKey: draft.kind.icon))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white))
                        .accessibilityHidden(true)
                    Text(verbatim: draft.kind.displayName)
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(KColor.ink3)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Art")
            .accessibilityValue(Text(verbatim: draft.kind.displayName))
            .accessibilityIdentifier("income.kind")
            if !model.data.persons.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Empfänger – genau eine Person")
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                    KBChipFlow(spacing: 8) {
                        ForEach(model.data.persons) { p in
                            Chip(title: p.name, isOn: draft.holderID == p.id) { draft.holderID = p.id }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Zuordnung")
        }
        .listRowBackground(KColor.surface)
    }

    private var noteSection: some View {
        Section {
            TextField("", text: $draft.note, axis: .vertical)
                .lineLimit(3...8)
                .accessibilityLabel("Notiz")
                .accessibilityIdentifier("income.note")
        } header: {
            Text("Notiz")
        }
        .listRowBackground(KColor.surface)
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Text("Einnahme löschen")
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("income.delete")
        }
        .listRowBackground(KColor.surface)
    }

    // MARK: Aktionen

    private var logoName: String {
        let n = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? draft.label.trimmingCharacters(in: .whitespacesAndNewlines) : n
    }

    private var deleteName: String { original.label.isEmpty ? original.name : original.label }

    private var subTyped: Bool {
        priceFrom != nil || !priceAmountText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isDirty: Bool {
        draft != original || amountText != originalAmountText || (subOpen && subTyped)
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
        // eingetippte, nicht hinzugefügte Änderung übernehmen (Web v143); misslingt das, bleibt das Formular offen.
        // Bewusst strenger als Web `iSave` (dort wird eine halb ausgefüllte Änderung still verworfen): nichts geht verloren.
        if subOpen && subTyped && !addPrice() { return }
        let hasTitle = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasTitle else {
            model.toast("Bezeichnung fehlt")
            return
        }
        guard let a = Format.parseAmount(amountText), a >= 0 else {
            model.toast("Betrag prüfen")
            return
        }
        var d = draft
        d.amount = a
        if bankSuggestion {
            BankFormBridge.shared.incomeDone(d)
            close()
            return
        }
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

    /// Löschen schliesst auch die Einnahme-Ansicht darunter (Web `closeSheets`)
    private func delete() {
        guard !closed else { return }
        closed = true
        let id = draft.id
        model.update { data in data.deleteIncome(id) }
        let n = model.sheets.count
        if n >= 2, model.sheets[n - 2] == .incomeDetail(id) {
            model.dismiss(level: n - 2)
        } else {
            model.dismissTop()
        }
        model.toast("Gelöscht")
    }

    /// «Änderung hinzufügen» (Web `iPAdd`): gleiches Datum ersetzt; true = übernommen
    @discardableResult
    private func addPrice() -> Bool {
        guard let f = priceFrom else {
            model.toast("Datum fehlt")
            return false
        }
        guard let a = Format.parseAmount(priceAmountText), a >= 0 else {
            model.toast("Betrag prüfen")
            return false
        }
        draft.prices.removeAll { $0.from == f }
        draft.prices.append(PriceChange(from: f, amount: Format.round2(a)))
        draft.prices.sort { $0.from < $1.from }
        priceBak = nil
        priceFrom = nil
        priceAmountText = ""
        subOpen = false
        return true
    }

    /// «Abbrechen» im Unterformular: angetippte Änderung zurück in die Liste
    private func cancelSub() {
        restoreBak()
        priceFrom = nil
        priceAmountText = ""
        subOpen = false
    }

    private func restoreBak() {
        if let b = priceBak {
            if !draft.prices.contains(where: { $0.from == b.from }) {
                draft.prices.append(b)
                draft.prices.sort { $0.from < $1.from }
            }
            priceBak = nil
        }
    }

    /// Änderung antippen: aus der Liste nehmen und ins Unterformular laden (Web data-ipedit)
    private func editPrice(_ p: PriceChange) {
        restoreBak()
        draft.prices.removeAll { $0.from == p.from }
        priceBak = p
        priceFrom = p.from
        priceAmountText = Format.amountInput(p.amount, draft.currency)
        subOpen = true
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

// MARK: - Tagesraster «Zahlung am» (Web v159 `dgHtml`)

/// 7 Spalten mit den Tagen 1–31 (gewählter Tag als Kreis), bei Rhythmus ≥ 2 Monate darüber die 12 Monate mit markierter
/// Reihe (z.B. Jan/Apr/Jul/Okt). Regeln: `ContractFormRules.dueGridMonths`, `dueGridShowsMonths`.
struct KBDueGrid: View {
    let day: Int
    let month: Int
    let cycle: Int
    var idPrefix = "due"
    let onDay: (Int) -> Void
    let onMonth: (Int) -> Void

    var body: some View {
        VStack(spacing: 10) {
            if ContractFormRules.dueGridShowsMonths(cycle: cycle) {
                let on = ContractFormRules.dueGridMonths(month: month, cycle: cycle)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                    ForEach(1...12, id: \.self) { m in
                        let sel = on.contains(m)
                        Button {
                            onMonth(m)
                        } label: {
                            Text(verbatim: Format.monthShort[m - 1])
                                .font(.subheadline.weight(sel ? .semibold : .regular))
                                .foregroundStyle(sel ? Color.white : KColor.ink)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(sel ? KColor.tealFill : KColor.field))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(Text(verbatim: Format.monthNames[m - 1]))
                        .accessibilityAddTraits(sel ? .isSelected : [])
                        .accessibilityIdentifier(idPrefix + ".month.\(m)")
                    }
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(1...31, id: \.self) { n in
                    let sel = n == day
                    Button {
                        onDay(n)
                    } label: {
                        Text(verbatim: String(n))
                            .font(.body.weight(sel ? .semibold : .regular).monospacedDigit())
                            .foregroundStyle(sel ? Color.white : KColor.ink)
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(sel ? KColor.tealFill : Color.clear))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text(verbatim: String(n) + "."))
                    .accessibilityAddTraits(sel ? .isSelected : [])
                    .accessibilityIdentifier(idPrefix + ".day.\(n)")
                }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Chips mit Zeilenumbruch

/// Einfache Fliess-Anordnung für Chips (Empfänger)
struct KBChipFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
            w = max(w, x - spacing)
        }
        return CGSize(width: proposal.width ?? w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
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
