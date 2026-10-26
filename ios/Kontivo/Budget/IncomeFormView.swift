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
    @Environment(AppModel.self) var model
    @Environment(\.openURL) var openURL
    @Environment(\.scenePhase) var scenePhase

    @State var draft: Income
    @State var original: Income
    @State var amountText: String
    @State var originalAmountText: String
    @State var isNew: Bool
    /// Unterformular «Änderung» offen
    @State var subOpen = false
    @State var priceFrom: Day?
    @State var priceAmountText = ""
    /// Beträge der Stufen, wie gerade in der Zeile getippt (Web v277), Schlüssel = «ab»-Datum
    @State var priceRowTexts: [Day: String] = [:]
    /// Betragsfeld einer Stufe
    @FocusState var rowFocus: Day?
    /// Tagesraster «Zahlung am» offen
    @State var dueOpen = false
    /// Offene Datumsauswahl (Ab, Bis, Gültig ab, Datum bei einmalig)
    @State var dateOpen: String?
    @State var showLogo = false
    @State var confirmDelete = false
    @State var confirmDiscard = false
    @State var photoItem: PhotosPickerItem?
    /// Fenster wird geschlossen (Doppeltippen auf «Sichern»/«Löschen» schliesst sonst das Fenster darunter)
    @State var closed = false
    @State var cropImage: KBCropImage?
    @State var showLogoSearch = false
    /// Hinweis nach «Google»
    @State var webHint = false
    /// Zurück aus Google: an «Einfügen» erinnern
    @State var webWait = false
    /// Fehlende Angabe: markierte Zeile (Web `.miss`, 1.8 s)
    @State var miss: String?
    @State var missTick = 0
    @FocusState var focus: KBIncomeField?
    /// Trefferliste unter «Quelle» (Web v222 `iSug`)
    @State var sugWeb: [WebPartnerHit] = []
    @State var sugLoading = false
    @State var sugSelected: String
    @State var sugHidden = true
    @State var sugTask: Task<Void, Never>?

    /// Zahlungsrhythmus wie in der Web-App (einmalig zuletzt)
    static let cycleOrder = [1, 2, 3, 6, 12, 24, 0]

    /// Bereich import: Vorschlag aus dem Kontoauszug – Titel «Vorschlag», «Sichern» geht zurück in die Vorschlagsliste
    let bankSuggestion: Bool

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
        .onChange(of: focus) { old, f in
            if f == .name { scheduleSuggestions() } else if f != nil { hideSuggestions() }
            // neue Änderung: Betrag fertig getippt (Feld verlassen) → übernehmen (Web v320)
            if old == .priceAmount && f != .priceAmount && subOpen && priceFrom != nil
                && !priceAmountText.trimmingCharacters(in: .whitespaces).isEmpty {
                addPrice()
            }
        }
        // Stufe verlassen: Betrag übernehmen (Web v277)
        .onChange(of: rowFocus) { old, new in
            if let o = old, o != new { commitRow(o) }
        }
        .onDisappear { sugTask?.cancel() }
    }

    /// Web v154: «Neue Einnahme» bzw. «Bearbeiten»
    var formTitle: String { bankSuggestion ? "Vorschlag" : (isNew ? "Neue Einnahme" : "Bearbeiten") }

    /// Web `.shbar`: weisse Leiste mit Linie unten; «Abbrechen» 16 px Tinte 2, Titel 18 px Semibold, «Sichern» 16 px Bold Akzent
    var headerBar: some View {
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

}
