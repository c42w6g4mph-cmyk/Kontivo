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

/// Felder des Formulars (Sprungziele bei fehlenden Angaben, Web v218 `goMiss`)
enum KBIncomeField: Hashable {
    case label, name, amount, priceFrom, priceAmount
}

/// Formular der Einnahme 1:1 wie Web v224 (`#sheetInc`): weisse Kopfleiste «Abbrechen | Titel | Sichern», Kopf mit Logo (76 pt),
/// Bezeichnung (21 px) und Quelle mit Trefferliste (eigene Quellen, Internet, Logo-Übernahme, v222), Kacheln «pro Monat | pro Jahr»,
/// Karte «Betrag» mit Verlauf, Änderungen und Plakette «+ Änderung» unter dem Betrag (v222), Zahlungsrhythmus, «Zahlung am»
/// (Tagesraster), «Zeitraum», «Zuordnung», «Notiz». Platzhalter «hinzufügen» (v216/v217); beim Sichern mit fehlender Angabe
/// Meldung «… fehlt», Sprung ins Feld und kurze Markierung der Zeile (v218/v219). Entwurf als Kopie, gesichert wird mit «Sichern».
struct KBIncomeForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var draft: Income
    @State private var original: Income
    @State private var amountText: String
    @State private var originalAmountText: String
    @State private var isNew: Bool
    /// Unterformular «Änderung» offen
    @State private var subOpen = false
    @State private var priceFrom: Day?
    @State private var priceAmountText = ""
    /// Zum Bearbeiten angetippte Änderung (Web `iPBak`): «Abbrechen» stellt sie wieder her
    @State private var priceBak: PriceChange?
    /// Tagesraster «Zahlung am» offen
    @State private var dueOpen = false
    /// Offene Datumsauswahl (Ab, Bis, Gültig ab, Datum bei einmalig)
    @State private var dateOpen: String?
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
    /// Fehlende Angabe: markierte Zeile (Web `.miss`, 1.8 s)
    @State private var miss: String?
    @State private var missTick = 0
    @FocusState private var focus: KBIncomeField?
    /// Trefferliste unter «Quelle» (Web v222 `iSug`)
    @State private var sugWeb: [WebPartnerHit] = []
    @State private var sugLoading = false
    @State private var sugSelected: String
    @State private var sugHidden = true
    @State private var sugTask: Task<Void, Never>?

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
        _sugSelected = State(initialValue: initial.name)
    }

    /// Vorbelegung: Art Lohn, Hauptwährung, monatlich, Zahlung heute, erste Person als Empfänger
    static func newDraft(_ model: AppModel) -> Income {
        Income(kind: .lohn, amount: 0, currency: model.data.settings.homeCurrency, cycle: 1,
               due: model.today, holderID: model.data.persons.first?.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headSection
                        if !sugHidden { suggestions.padding(.top, 8) }
                        if showLogo { logoSection.padding(.top, 8) }
                        tilesSection
                        KBFormSection("Betrag")
                        amountCard
                        Text("Netto eintragen, also was auf dem Konto ankommt. Einen 13. Monatslohn oder Bonus am besten als eigene jährliche Einnahme erfassen.")
                            .font(.system(size: 12.5))
                            .kLineHeight(12.5, 19.375)
                            .foregroundStyle(KColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                            .padding(.top, 8)
                        KBFormSection("Zeitraum")
                        KBFormCard {
                            dateRow("Ab", key: "start", date: $draft.start)
                            KBRowDivider()
                            dateRow("Bis", key: "end", date: $draft.end)
                        }
                        KBFormSection("Zuordnung")
                        assignmentCard
                        KBFormSection("Notiz")
                        KBFormCard {
                            TextField("", text: $draft.note, axis: .vertical)
                                .font(.system(size: 16))
                                .lineLimit(3...8)
                                .frame(minHeight: 60, alignment: .topLeading)
                                .padding(.vertical, 12)
                                .accessibilityLabel("Notiz")
                                .accessibilityIdentifier("income.note")
                        }
                        if !isNew {
                            Button {
                                confirmDelete = true
                            } label: {
                                Text("Einnahme löschen")
                                    .font(.system(size: 14))
                                    .foregroundStyle(KColor.alert)
                                    .frame(maxWidth: .infinity)
                                    .padding(13)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 14 + 9)
                            .accessibilityIdentifier("income.delete")
                        }
                    }
                    .padding(.horizontal, KBM.side)
                    .padding(.top, 8)
                    .padding(.bottom, 18)
                    .frame(maxWidth: KMetric.maxContent)
                    .frame(maxWidth: .infinity)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: missTick) { _, _ in
                    if let m = miss { withAnimation(.easeInOut) { proxy.scrollTo(m, anchor: .center) } }
                }
            }
        }
        .background(KColor.paper.ignoresSafeArea())
        .kKeyboardDone()
        .alert("Einnahme löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(verbatim: "«" + deleteName + "» wird endgültig gelöscht.")
        }
        .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { close() }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Deine Eingaben in diesem Formular gehen verloren.")
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
        .onChange(of: draft.name) { _, n in
            if !sugSelected.isEmpty && n.trimmingCharacters(in: .whitespaces) != sugSelected { sugSelected = "" }
            scheduleSuggestions()
        }
        .onChange(of: focus) { _, f in
            if f == .name { scheduleSuggestions() } else if f != nil { hideSuggestions() }
        }
        .onDisappear { sugTask?.cancel() }
    }

    /// Web v154: «Neue Einnahme» bzw. «Bearbeiten»
    private var formTitle: String { bankSuggestion ? "Vorschlag" : (isNew ? "Neue Einnahme" : "Bearbeiten") }

    /// Web `.shbar`: weisse Leiste mit Linie unten; «Abbrechen» 16 px Tinte 2, Titel 18 px Semibold, «Sichern» 16 px Bold Akzent
    private var headerBar: some View {
        ZStack {
            Text(verbatim: formTitle)
                .font(KFont.title(18))
                .tracking(-0.216)
                .foregroundStyle(KColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("income.form.title")
            HStack {
                Button("Abbrechen") { cancel() }
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink2)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("income.cancel")
                Spacer()
                Button("Sichern") { save() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KColor.teal)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("income.save")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KBM.side)
        .padding(.top, 6 + 14)
        .padding(.bottom, 10)
        .background(KColor.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    // MARK: Kopf (Logo, Bezeichnung, Quelle)

    private var headSection: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showLogo.toggle() }
            } label: {
                // Web: Vorschau ohne Logo neutral grau (Inline-Farbe ohne `--c` → Pastell in #5F666E)
                MarkView(logoID: draft.logoID, logoBg: draft.logoBg, colorHex: "#5F666E",
                         symbol: KIcon.symbol(forKey: draft.kind.icon), size: 76)
                    .overlay(alignment: .bottomTrailing) {
                        // Web `.ledit`: 26 pt Kreis Messing mit weissem Rand, Stift
                        KBPencilGlyph()
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                            .frame(width: 12, height: 12)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(KColor.tealFill))
                            .overlay(Circle().strokeBorder(KColor.surface, lineWidth: 2))
                            .offset(x: 5, y: 5)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Logo ändern")
            .accessibilityIdentifier("income.logo")
            VStack(spacing: 6) {
                TextField("", text: $draft.label, prompt: Text("Bezeichnung, z.B. Lohn").foregroundColor(KColor.ink3))
                    .font(KFont.title(21))
                    .tracking(-0.252)
                    .foregroundStyle(KColor.ink)
                    .focused($focus, equals: .label)
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(KColor.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(KBMissRing(on: miss == "label"))
                    .id("label")
                    .accessibilityLabel("Bezeichnung")
                    .accessibilityIdentifier("income.label")
                TextField("", text: $draft.name, prompt: Text("Quelle, z.B. Arbeitgeber AG").foregroundColor(KColor.ink3))
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink2)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .name)
                    .padding(.horizontal, 10)
                    .frame(height: 38)
                    .background(KColor.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityLabel("Quelle")
                    .accessibilityIdentifier("income.name")
            }
        }
        // Web `.fhead` margin 8 0 4 (die 8 oben fallen mit dem Abstand unter der Kopfzeile zusammen)
        .padding(.bottom, 4)
    }

    // MARK: Trefferliste «Quelle» (Web v222)

    /// Eigene Quellen (bis 3, Name enthält die Eingabe), ohne die gleiche Quelle doppelt
    private var ownSources: [Income] {
        let q = draft.name.trimmingCharacters(in: .whitespaces).lowercased()
        var seen = Set<String>()
        var out: [Income] = []
        for i in model.data.incomes where i.id != draft.id {
            let n = i.name.trimmingCharacters(in: .whitespaces)
            let k = n.lowercased()
            if n.isEmpty || seen.contains(k) || !k.contains(q) { continue }
            seen.insert(k)
            out.append(i)
            if out.count == 3 { break }
        }
        return out
    }

    private func hideSuggestions() {
        sugTask?.cancel()
        sugHidden = true
        sugWeb = []
        sugLoading = false
    }

    private func scheduleSuggestions() {
        sugTask?.cancel()
        let q = draft.name.trimmingCharacters(in: .whitespaces)
        guard focus == .name, q.count >= 2, q != sugSelected else { hideSuggestions(); return }
        sugWeb = []
        sugLoading = q.count >= 3
        sugHidden = ownSources.isEmpty && !sugLoading
        sugTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            let hits = model.uiTestMode ? [] : await CTWebPartners.search(q)
            if Task.isCancelled { return }
            let own = Set(ownSources.map { $0.name.lowercased() })
            sugWeb = hits.filter { !own.contains($0.name.lowercased()) }
            sugLoading = false
            sugHidden = ownSources.isEmpty && sugWeb.isEmpty
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 0) {
            let own = ownSources
            if !own.isEmpty {
                sugHead("Deine Quellen")
                ForEach(own) { i in
                    Button { pickOwn(i) } label: {
                        sugRow(mark: AnyView(MarkView(income: i, size: 34)), title: i.name,
                               sub: i.label.isEmpty ? i.kind.displayName : i.label)
                    }
                    .buttonStyle(.plain)
                }
            }
            if !sugWeb.isEmpty {
                sugHead("Aus dem Internet")
                ForEach(sugWeb, id: \.self) { w in
                    Button { pickWeb(w) } label: {
                        sugRow(mark: AnyView(KBWebThumb(url: CTWebPartners.thumbURL(w))), title: w.name,
                               sub: w.dom + (w.desc.isEmpty ? "" : " · " + w.desc))
                    }
                    .buttonStyle(.plain)
                }
            } else if sugLoading {
                Text("Suche …")
                    .font(.system(size: 13))
                    .foregroundStyle(KColor.ink3)
                    .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
    }

    private func sugHead(_ t: String) -> some View {
        Text(verbatim: t)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(KColor.ink3)
            .padding(.top, 8)
            .padding(.bottom, 2)
    }

    private func sugRow(mark: AnyView, title: String, sub: String) -> some View {
        HStack(spacing: 12) {
            mark
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                Text(verbatim: sub)
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    /// Eigene Quelle übernehmen: Name und (falls noch keins) Logo
    private func pickOwn(_ i: Income) {
        sugSelected = i.name
        draft.name = i.name
        if let l = i.logoID, draft.logoID == nil || model.image(draft.logoID) == nil {
            draft.logoID = l
            draft.logoBg = i.logoBg ?? "#FFFFFF"
        }
        hideSuggestions()
    }

    /// Internet-Treffer übernehmen; Logo laden (Commons, sonst Website-Symbol), nur wenn noch keins gesetzt ist
    private func pickWeb(_ w: WebPartnerHit) {
        sugSelected = w.name
        draft.name = w.name
        hideSuggestions()
        if draft.logoID != nil && model.image(draft.logoID) != nil {
            model.toast("Übernommen")
            return
        }
        model.toast("Lade Logo …")
        let before = draft.id
        Task { @MainActor in
            let r = await CTLogoFetch.logo(file: w.file, domain: w.dom)
            guard !closed, draft.id == before, draft.name.trimmingCharacters(in: .whitespaces) == w.name.trimmingCharacters(in: .whitespaces) else { return }
            if let r, draft.logoID == nil || model.image(draft.logoID) == nil, let id = model.storeFile(r.png, type: "image/png") {
                draft.logoID = id
                draft.logoBg = r.bg
                model.toast("Übernommen: Logo")
            } else {
                model.toast("Kein Logo gefunden – unter «Logo» selbst wählen")
            }
        }
    }

    // MARK: Logo

    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { autoFind() } label: {
                Text("Logo automatisch finden")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.tealFill))
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                logoButton("Einfügen") { pasteLogo() }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    KBLogoButtonLabel(title: "Hochladen")
                }
                .buttonStyle(.plain)
                logoButton("Google") { googleSearch() }
            }
            if webHint {
                (Text("So geht’s: ").bold()
                 + Text("In Google das passende Bild lange drücken → «Kopieren». Dann zurück in die App und «Einfügen» tippen."))
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
            }
            if draft.logoID != nil {
                Button {
                    draft.logoID = nil
                    draft.logoBg = nil
                } label: {
                    KBLogoButtonLabel(title: "Logo entfernen", destructive: true)
                }
                .buttonStyle(.plain)
            }
            Text("Ohne Bild: Symbol der Art")
                .font(.system(size: 12))
                .foregroundStyle(KColor.ink3)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: KBM.cardRadius, style: .continuous).fill(KColor.surface))
    }

    private func logoButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { KBLogoButtonLabel(title: t) }
            .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                if d.cycle != 0 {
                    tile("pro Monat", Format.money(cp / Double(d.cycle), cu), cu)
                    tile("pro Jahr", Format.money0(cp / Double(d.cycle) * 12, cu), cu)
                } else {
                    tile("einmalig", Format.money(cp, cu), cu)
                }
            }
            .padding(.top, 12)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("income.tiles")
        }
    }

    /// Web `#iKz > *`: Fläche Feldfarbe, Rundung 12, Wert Serif 22 mit Währung Serif 13
    private func tile(_ label: String, _ value: String, _ cu: Currency) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: label)
                .font(.system(size: 12.5))
                .foregroundStyle(KColor.ink2)
                .frame(height: 18)
            (Text(verbatim: value).font(KFont.serif(22, .medium))
                + Text(verbatim: " " + cu.rawValue).font(KFont.serif(13, .medium)).foregroundStyle(KColor.ink2))
                .tracking(-0.22)
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(height: 31.9)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(KColor.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Betrag (Verlauf, Betrag, Änderungen, Rhythmus, Zahlung am)

    private var amountLabel: String { draft.prices.isEmpty ? "Betrag netto" : "Anfangsbetrag netto" }

    /// «+ Änderung» erst mit Betrag oder vorhandenen Änderungen (Web v222 `iSyncPOpen`)
    private var showChangePill: Bool {
        !subOpen && (!amountText.trimmingCharacters(in: .whitespaces).isEmpty || !draft.prices.isEmpty)
    }

    private var amountCard: some View {
        let d = draftForCalc
        let chart = model.calc.priceChart(amount: d.amount, prices: d.prices, start: d.start, currency: d.currency, income: true)
        return KBFormCard {
            if let ch = chart {
                KBIncomeChart(chart: ch, identifier: "income.form.chart")
                    .padding(.top, 12)
                    .padding(.bottom, 8)
            }
            if chart != nil { KBRowDivider() }
            KBFormRow(label: amountLabel, miss: miss == "amount") {
                // Web: Feld (Innenabstand 2) + 4 + Auswahl (Innenabstand 2) → 8 zwischen Betrag und Währung
                HStack(spacing: 8) {
                    TextField("", text: $amountText, prompt: Text("hinzufügen").foregroundColor(KColor.ink3))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.system(size: 16, weight: .medium).monospacedDigit())
                        .foregroundStyle(KColor.teal)
                        .focused($focus, equals: .amount)
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
                        KBSelectValue(text: draft.currency.rawValue)
                    }
                    .accessibilityLabel("Währung")
                    .accessibilityValue(Text(verbatim: draft.currency.rawValue))
                    .accessibilityIdentifier("income.currency")
                }
            }
            .id("amount")
            priceRows
            if showChangePill {
                HStack {
                    Spacer()
                    Button {
                        priceFrom = nil
                        priceAmountText = ""
                        subOpen = true
                    } label: {
                        HStack(spacing: 5) {
                            KBPlusGlyph()
                                .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                                .frame(width: 12, height: 12)
                            Text("Änderung")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(KColor.teal)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(KColor.teal.opacity(0.13)))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("income.addChange")
                }
                .padding(.top, -4)
                .padding(.bottom, 10)
            }
            if subOpen {
                KBRowDivider()
                priceSubForm
            }
            KBRowDivider()
            KBFormRow(label: "Zahlungsrhythmus") {
                Menu {
                    Picker("Zahlungsrhythmus", selection: $draft.cycle) {
                        ForEach(KBIncomeForm.cycleOrder, id: \.self) { m in
                            Text(verbatim: Format.incomeCycleTexts[m] ?? "").tag(m)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    KBSelectValue(text: Format.incomeCycleTexts[draft.cycle] ?? "monatlich")
                }
                .accessibilityLabel("Zahlungsrhythmus")
                .accessibilityValue(Text(verbatim: Format.incomeCycleTexts[draft.cycle] ?? ""))
                .accessibilityIdentifier("income.cycle")
            }
            KBRowDivider()
            dueRows
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
            KBRowDivider()
            priceRow(p, tag: i == ni ? "aktuell" : (p.from > today ? "geplant" : nil), planned: p.from > today, prev: prev)
        }
    }

    private func priceRow(_ p: PriceChange, tag: String?, planned: Bool, prev: Double) -> some View {
        let pc: Double? = prev != 0 ? (p.amount - prev) / prev * 100 : nil
        return HStack(spacing: 12) {
            Button {
                editPrice(p)
            } label: {
                HStack(spacing: 12) {
                    HStack(spacing: 6) {
                        Text(verbatim: "ab " + Format.fmtShort(p.from))
                            .font(.system(size: 15))
                            .foregroundStyle(KColor.ink)
                            .lineLimit(1)
                        if let t = tag {
                            Text(verbatim: t)
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(planned ? KColor.warn : Color.white)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(planned ? KColor.warn.opacity(0.15) : KColor.teal))
                        }
                    }
                    Spacer(minLength: 6)
                    Text(verbatim: Format.money(p.amount, draft.currency))
                        .font(.system(size: 16, weight: .medium).monospacedDigit())
                        .foregroundStyle(KColor.teal)
                        .lineLimit(1)
                    if let v = pc {
                        let tone: PriceChartTone = v > 0.05 ? .down : (v < -0.05 ? .up : .neutral)
                        Text(verbatim: Format.pctText(v))
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .foregroundStyle(KBIncomeChart.color(tone, neutral: KColor.ink2))
                            .background(Capsule().fill(KBIncomeChart.color(tone, neutral: KColor.ink).opacity(tone == .neutral ? 0.07 : 0.15)))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Antippen zum Ändern")
            .accessibilityIdentifier("income.price." + p.from.iso)
            Button {
                removePrice(p.from)
            } label: {
                Text(verbatim: "×")
                    .font(.system(size: 20))
                    .foregroundStyle(KColor.ink3)
                    .padding(.vertical, 8)
                    .padding(.leading, 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Änderung entfernen")
        }
        .padding(.vertical, 4)
        .frame(minHeight: 48)
    }

    /// Unterformular «Gültig ab» / «Neuer Betrag» / «Änderung hinzufügen» / «Abbrechen»
    @ViewBuilder
    private var priceSubForm: some View {
        dateRow("Gültig ab", key: "priceFrom", date: $priceFrom)
            .accessibilityIdentifier("income.priceFrom")
        KBRowDivider()
        KBFormRow(label: "Neuer Betrag", miss: miss == "priceAmount") {
            TextField("", text: $priceAmountText, prompt: Text("hinzufügen").foregroundColor(KColor.ink3))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 16, weight: .medium).monospacedDigit())
                .foregroundStyle(KColor.teal)
                .focused($focus, equals: .priceAmount)
                .accessibilityLabel("Neuer Betrag")
                .accessibilityIdentifier("income.priceAmount")
        }
        .id("priceAmount")
        Button {
            _ = addPrice()
        } label: {
            Text("Änderung hinzufügen")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(11)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.brassFab))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .accessibilityIdentifier("income.priceAdd")
        Button {
            cancelSub()
        } label: {
            Text("Abbrechen")
                .font(.system(size: 15))
                .foregroundStyle(KColor.ink2)
                .frame(maxWidth: .infinity)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, -6)
        .padding(.bottom, 10)
        .accessibilityIdentifier("income.priceCancel")
    }

    /// «Zahlung am» als Tag im Monat (Tagesraster, Monatsreihe ab 2 Monaten); einmalig ein Datum (Web `iPaintDue`)
    @ViewBuilder
    private var dueRows: some View {
        if draft.cycle == 0 {
            dateRow("Datum", key: "due", date: Binding(get: { draft.due }, set: { draft.due = $0 ?? draft.due }))
                .accessibilityIdentifier("income.dueDate")
        } else {
            let txt = ContractFormRules.dueText(draft.due, cycle: draft.cycle)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { dueOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Text("Zahlung am")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                    Spacer(minLength: 8)
                    Text(verbatim: txt)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(KColor.teal)
                        .multilineTextAlignment(.trailing)
                    Text(verbatim: "›")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink)
                        .rotationEffect(.degrees(dueOpen ? 90 : 0))
                }
                .padding(.vertical, 4)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
                .padding(.bottom, 4)
            }
        }
    }

    /// Tag antippen übernimmt und klappt zu, Monat antippen übernimmt und bleibt offen (Web v159, `iDueFrom`)
    private func pickDue(day: Int?, month: Int?) {
        let v = draft.due ?? model.today
        draft.due = ContractFormRules.incomeDueFrom(day: day ?? v.day, month: month ?? v.month, cycle: draft.cycle, today: model.today)
        if day != nil {
            withAnimation(.easeInOut(duration: 0.2)) { dueOpen = false }
        }
    }

    /// Datumszeile: leer «hinzufügen» (Tinte 3, v217), sonst Datum in Akzentfarbe; Antippen öffnet die Datumsauswahl darunter
    @ViewBuilder
    private func dateRow(_ title: String, key: String, date: Binding<Day?>) -> some View {
        let open = dateOpen == key
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { dateOpen = open ? nil : key }
            } label: {
                HStack(spacing: 12) {
                    Text(verbatim: title)
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                    Spacer(minLength: 8)
                    if let d = date.wrappedValue {
                        Text(verbatim: String(format: "%02d.%02d.%04d", d.day, d.month, d.year))
                            .font(.system(size: 16, weight: .medium).monospacedDigit())
                            .foregroundStyle(KColor.teal)
                    } else {
                        Text("hinzufügen")
                            .font(.system(size: 16))
                            .foregroundStyle(KColor.ink3)
                    }
                }
                .padding(.vertical, 4)
                .frame(minHeight: 49.2)
                .background(KBMissFlash(on: miss == key))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            if open {
                DatePicker(title, selection: Binding(get: { (date.wrappedValue ?? model.today).date() },
                                                     set: { date.wrappedValue = Day(date: $0) }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(KColor.teal)
                    .environment(\.locale, Locale(identifier: "de_CH"))
                if date.wrappedValue != nil && key != "due" {
                    Button {
                        date.wrappedValue = nil
                        dateOpen = nil
                    } label: {
                        Text("Datum entfernen")
                            .font(.system(size: 14))
                            .foregroundStyle(KColor.ink2)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .id(key)
    }

    // MARK: Zuordnung

    private var assignmentCard: some View {
        KBFormCard {
            Menu {
                Picker("Art", selection: $draft.kind) {
                    ForEach(IncomeKind.allCases, id: \.self) { k in
                        Label { Text(k.displayName) } icon: { KIcon.image(KIcon.symbol(forKey: k.icon)) }.tag(k)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: 10) {
                    Text("Art")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                    Spacer(minLength: 8)
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: CategoryPalette.display(draft.kind.colorHex, key: draft.kind.displayName)))
                        .frame(width: 28, height: 28)
                        .overlay(KIcon.view(KIcon.symbol(forKey: draft.kind.icon), 15)
                            .foregroundStyle(.white))
                        .accessibilityHidden(true)
                    Text(verbatim: draft.kind.displayName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(KColor.teal)
                        .lineLimit(1)
                    Text(verbatim: "›")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink)
                }
                .padding(.vertical, 4)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Art")
            .accessibilityValue(Text(verbatim: draft.kind.displayName))
            .accessibilityIdentifier("income.kind")
            if !model.data.persons.isEmpty {
                KBRowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Empfänger – genau eine Person")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                        .frame(minHeight: 21.75)
                    KBChipFlow(spacing: 6) {
                        ForEach(model.data.persons) { p in
                            KBInkChip(title: p.name, isOn: draft.holderID == p.id) { draft.holderID = p.id }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
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

    /// Fehlende Angabe (Web v218 `goMiss`): Meldung, Fokus/Datumsauswahl, ins Feld scrollen, Zeile 1.8 s markieren
    private func goMiss(_ key: String, _ msg: String) {
        model.toast(msg)
        switch key {
        case "label": focus = .label
        case "amount": focus = .amount
        case "priceAmount": focus = .priceAmount
        default:
            focus = nil
            withAnimation(.easeInOut(duration: 0.2)) { dateOpen = key }
        }
        miss = key
        missTick += 1
        let tick = missTick
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            if missTick == tick { miss = nil }
        }
    }

    private func save() {
        guard !closed else { return }
        // eingetippte, nicht hinzugefügte Änderung übernehmen (Web v143); misslingt das, bleibt das Formular offen.
        // Bewusst strenger als Web `iSave` (dort wird eine halb ausgefüllte Änderung still verworfen): nichts geht verloren.
        if subOpen && subTyped && !addPrice() { return }
        let hasTitle = !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draft.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasTitle else {
            goMiss("label", "Bezeichnung fehlt")
            return
        }
        guard let a = Format.parseAmount(amountText), a >= 0 else {
            goMiss("amount", amountText.trimmingCharacters(in: .whitespaces).isEmpty ? "Betrag fehlt" : "Betrag prüfen")
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
            goMiss("priceFrom", "Datum fehlt")
            return false
        }
        guard let a = Format.parseAmount(priceAmountText), a >= 0 else {
            goMiss("priceAmount", priceAmountText.trimmingCharacters(in: .whitespaces).isEmpty ? "Betrag fehlt" : "Betrag prüfen")
            return false
        }
        draft.prices.removeAll { $0.from == f }
        draft.prices.append(PriceChange(from: f, amount: Format.round2(a)))
        draft.prices.sort { $0.from < $1.from }
        priceBak = nil
        priceFrom = nil
        priceAmountText = ""
        subOpen = false
        if dateOpen == "priceFrom" { dateOpen = nil }
        return true
    }

    /// «Abbrechen» im Unterformular: angetippte Änderung zurück in die Liste
    private func cancelSub() {
        restoreBak()
        priceFrom = nil
        priceAmountText = ""
        subOpen = false
        if dateOpen == "priceFrom" { dateOpen = nil }
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

// MARK: - Bausteine des Formulars (Web `.fsec`, `.fcard`, `.frow`)

/// Abschnittstitel (Web `h3.fsec`: 13 px Semibold Tinte 2, Abstand 22 oben, 8 unten)
struct KBFormSection: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(KColor.ink2)
            .frame(minHeight: 18.85)
            .padding(.horizontal, 2)
            .padding(.top, 22)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Weisse Karte (Web `.fcard`: Rundung 16, Innenrand 13)
struct KBFormCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(.horizontal, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: KBM.cardRadius, style: .continuous).fill(KColor.surface))
    }
}

/// Zeile (Web `.frow`): Bezeichnung 15 px Tinte 2 links, Wert rechts, mind. 48 pt; `miss` = kurze Markierung (v219)
struct KBFormRow<Value: View>: View {
    let label: String
    var miss = false
    @ViewBuilder var value: Value

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: label)
                .font(.system(size: 15))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            value
        }
        // Web `.frow`: 4 + Feld 39.2 + 4 (mit Linie 48.2)
        .padding(.vertical, 4)
        .frame(minHeight: 47.2)
        .background(KBMissFlash(on: miss))
    }
}

/// Markierung einer Zeile mit fehlender Angabe (Web v219 `.frow.miss::before`): Warnfarbe 16 % als abgerundete Fläche bis an den
/// Kartenrand (−8 pt), 3 pt oben/unten; bleibt 40 % der Zeit sichtbar und blendet in 1.8 s aus.
struct KBMissFlash: View {
    let on: Bool
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(KColor.alert.opacity(0.16))
            .padding(.vertical, 3)
            .padding(.horizontal, -8)
            .opacity(opacity)
            .onChange(of: on) { _, v in
                guard v else { return }
                opacity = 1
                withAnimation(.easeOut(duration: 1.08).delay(0.72)) { opacity = 0 }
            }
            .allowsHitTesting(false)
    }
}

/// Roter Rahmen um ein Kopffeld (Web v219 `.fht.miss`: 2 px, blendet aus)
struct KBMissRing: View {
    let on: Bool
    @State private var opacity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(KColor.alert, lineWidth: 2)
            .padding(-1)
            .opacity(opacity)
            .onChange(of: on) { _, v in
                guard v else { return }
                opacity = 1
                withAnimation(.easeOut(duration: 1.08).delay(0.72)) { opacity = 0 }
            }
            .allowsHitTesting(false)
    }
}

/// Wert einer Auswahl (Web `select`: 16 px Medium Akzent, Winkel rechts)
struct KBSelectValue: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: text)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(KColor.teal)
                .lineLimit(1)
            KBChevronDown(expanded: false, color: KColor.ink2)
                .scaleEffect(0.9)
                .padding(.trailing, -6)
        }
        .padding(.vertical, 8)
    }
}

/// Chip «Empfänger» (Web `.chips button`): gewählt Tinte mit Papierschrift, sonst Rand
struct KBInkChip: View {
    let title: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 14, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? KColor.paper : KColor.ink2)
                .lineLimit(1)
                .padding(.horizontal, 13)
                // Web: Rand 1 + Innenabstand 7/12 + Zeile 20.3 (Höhe 36.3)
                .padding(.vertical, 8 + KBM.pad(20.3, 14))
                .background(Capsule().fill(isOn ? KColor.ink : .clear))
                .overlay(Capsule().strokeBorder(isOn ? KColor.ink : KColor.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Knopf der Logo-Auswahl (Web `.lbtn`)
struct KBLogoButtonLabel: View {
    let title: String
    var destructive = false

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 13.5, weight: .medium))
            .foregroundStyle(destructive ? KColor.alert : KColor.ink)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.field))
            .contentShape(Rectangle())
    }
}

/// Vorschaubild eines Internet-Treffers (Commons-Logo bzw. Website-Symbol) auf weisser Kachel 34 pt
struct KBWebThumb: View {
    let url: URL?

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(Color.white)
            .frame(width: 34, height: 34)
            .overlay {
                if let url {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFit()
                    } placeholder: {
                        Color.clear
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
    }
}

/// Stift (Web `.ledit svg`: M4 20h4L19 9l-4-4L4 16z)
struct KBPencilGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 4 * s, y: 20 * s))
        p.addLine(to: CGPoint(x: 8 * s, y: 20 * s))
        p.addLine(to: CGPoint(x: 19 * s, y: 9 * s))
        p.addLine(to: CGPoint(x: 15 * s, y: 5 * s))
        p.addLine(to: CGPoint(x: 4 * s, y: 16 * s))
        p.closeSubpath()
        return p.offsetBy(dx: r.minX, dy: r.minY)
    }
}

/// Plus (Web `M12 5v14M5 12h14`)
struct KBPlusGlyph: Shape {
    func path(in r: CGRect) -> Path {
        let s = r.width / 24
        var p = Path()
        p.move(to: CGPoint(x: 12 * s, y: 5 * s)); p.addLine(to: CGPoint(x: 12 * s, y: 19 * s))
        p.move(to: CGPoint(x: 5 * s, y: 12 * s)); p.addLine(to: CGPoint(x: 19 * s, y: 12 * s))
        return p.offsetBy(dx: r.minX, dy: r.minY)
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

/// Einfache Fliess-Anordnung (Empfänger-Chips, Budget-Zeile «verfügbar nach Fixkosten · …»); Zeilen senkrecht zentriert.
struct KBChipFlow: Layout {
    var spacing: CGFloat = 8
    /// Abstand zwischen Zeilen (nil = `spacing`)
    var lineSpacing: CGFloat? = nil

    private func rows(_ maxW: CGFloat, _ subviews: Subviews) -> [[(Int, CGSize)]] {
        var out: [[(Int, CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                out.append([])
                x = 0
            }
            out[out.count - 1].append((i, sz))
            x += sz.width + spacing
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let rs = rows(maxW, subviews)
        let ls = lineSpacing ?? spacing
        var h: CGFloat = 0, w: CGFloat = 0
        for (k, r) in rs.enumerated() {
            h += (r.map { $0.1.height }.max() ?? 0) + (k > 0 ? ls : 0)
            w = max(w, r.reduce(0) { $0 + $1.1.width } + spacing * CGFloat(max(0, r.count - 1)))
        }
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rs = rows(bounds.width, subviews)
        let ls = lineSpacing ?? spacing
        var y = bounds.minY
        for r in rs {
            let rh = r.map { $0.1.height }.max() ?? 0
            var x = bounds.minX
            for (i, sz) in r {
                subviews[i].place(at: CGPoint(x: x, y: y + (rh - sz.height) / 2), anchor: .topLeading, proposal: ProposedViewSize(sz))
                x += sz.width + spacing
            }
            y += rh + ls
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
