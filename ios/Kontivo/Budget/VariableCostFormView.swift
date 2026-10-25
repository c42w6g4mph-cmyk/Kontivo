import SwiftUI
import KontivoCore

/// Variable Kosten erfassen (nil) oder bearbeiten (Web v226/v227/v231 `#sheetVar`, `openVar`): weisse Kopfleiste
/// «Abbrechen | Variable Kosten bzw. Bearbeiten | Sichern», Kopf mit Symbol (76 pt, Stift → Bild- und Symbolauswahl) und
/// Bezeichnung, Vorschläge (nur beim Erfassen), Kacheln «pro Monat | pro Jahr», Betrag, Zeitraum, Personen, Löschen.
/// Prüfung beim Sichern: `VariableCostForm.missing`; Übernahme: `AppData.putVariableCost`.
struct VariableCostFormView: View {
    @Environment(AppModel.self) private var model
    let variableID: UUID?

    var body: some View {
        if let v = model.data.variableCost(variableID) {
            KBVariableForm(initial: v, isNew: false)
        } else {
            // Vorbelegung (Web `openVar(null)`): Symbol «Sonstiges», Hauptwährung, alle Personen
            KBVariableForm(initial: VariableCost(icon: .sonst, currency: model.data.settings.homeCurrency,
                                                 holderIDs: model.data.persons.map { $0.id }), isNew: true)
        }
    }
}

private enum KBVarField: Hashable { case label, amount }

struct KBVariableForm: View {
    @Environment(AppModel.self) private var model
    @State private var draft: VariableCost
    private let original: VariableCost
    @State private var amountText: String
    private let originalAmount: String
    private let isNew: Bool
    @State private var iconsOpen = false
    @State private var dateOpen: String?
    @State private var confirmDelete = false
    @State private var confirmDiscard = false
    @State private var closed = false
    @State private var miss: String?
    @State private var missTick = 0
    @FocusState private var focus: KBVarField?

    init(initial: VariableCost, isNew: Bool) {
        let at = isNew ? "" : Format.amountInput(initial.amount, initial.currency)
        _draft = State(initialValue: initial)
        original = initial
        _amountText = State(initialValue: at)
        originalAmount = at
        self.isNew = isNew
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headSection
                        if iconsOpen {
                            KBVarIconPanel(draft: $draft, name: draft.label.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                withAnimation(.easeInOut(duration: 0.2)) { iconsOpen = false }
                            }
                        }
                        suggestions
                        KBVarFormTiles(amount: amountValue, currency: draft.currency)
                        KBFormSection("Betrag")
                        KBFormCard {
                            KBFormRow(label: "Pro Monat (ca.)", miss: miss == "amount") {
                                HStack(spacing: 8) {
                                    TextField("", text: $amountText, prompt: Text("hinzufügen").foregroundColor(KColor.ink3))
                                        .keyboardType(.decimalPad)
                                        .multilineTextAlignment(.trailing)
                                        .font(.system(size: 16, weight: .medium).monospacedDigit())
                                        .foregroundStyle(KColor.teal)
                                        .focused($focus, equals: .amount)
                                        .frame(minWidth: 80)
                                        .accessibilityLabel("Pro Monat (ca.)")
                                        .accessibilityIdentifier("var.amount")
                                    Text(verbatim: draft.currency.rawValue)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(KColor.ink2)
                                }
                            }
                            .id("amount")
                        }
                        hint("Geschätzter Planwert. Zählt nur im Budget, nicht in Kosten und Fristen.")
                        KBFormSection("Zeitraum")
                        KBFormCard {
                            dateRow("Ab", key: "start", date: $draft.start)
                            KBRowDivider()
                            dateRow("Bis", key: "end", date: $draft.end)
                        }
                        hint("Leer = unbefristet. Nach dem Bis-Datum wandert der Eintrag ins Archiv und zählt nicht mehr.")
                        personsSection
                        if !isNew {
                            Button {
                                confirmDelete = true
                            } label: {
                                Text("Löschen")
                                    .font(.system(size: 14))
                                    .foregroundStyle(KColor.alert)
                                    .frame(maxWidth: .infinity)
                                    .padding(13)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 14 + 9)
                            .accessibilityIdentifier("var.delete")
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
        .alert("Löschen?", isPresented: $confirmDelete) {
            Button("Löschen", role: .destructive) { delete() }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text(verbatim: "«" + original.label + "» wird aus den variablen Kosten entfernt.")
        }
        .confirmationDialog("Änderungen verwerfen?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Verwerfen", role: .destructive) { close() }
            Button("Weiter bearbeiten", role: .cancel) {}
        } message: {
            Text("Deine Eingaben in diesem Formular gehen verloren.")
        }
        .onChange(of: draft.label) { _, l in
            // Symbol zum Vorschlag passend setzen, solange noch keins gewählt ist
            let ic = VariableCostForm.icon(forLabel: l, current: draft.icon)
            if ic != draft.icon { draft.icon = ic }
            if l.count > 60 { draft.label = String(l.prefix(60)) }
        }
    }

    private var amountValue: Double? {
        guard let a = Format.parseAmount(amountText), a > 0 else { return nil }
        return a
    }

    // MARK: Kopf

    private var headerBar: some View {
        ZStack {
            Text(verbatim: isNew ? "Variable Kosten" : "Bearbeiten")
                .font(KFont.title(18))
                .tracking(-0.216)
                .foregroundStyle(KColor.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("var.form.title")
            HStack {
                Button("Abbrechen") { cancel() }
                    .font(.system(size: 16))
                    .foregroundStyle(KColor.ink2)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("var.cancel")
                Spacer()
                Button("Sichern") { save() }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(KColor.teal)
                    .padding(.vertical, 6)
                    .accessibilityIdentifier("var.save")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, KBM.side)
        .padding(.top, 6 + 14)
        .padding(.bottom, 10)
        .background(KColor.surface.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(KColor.line).frame(height: 1) }
    }

    /// Web `.fhead`: Symbol 76 mit Stift, Bezeichnung 21 px, darunter «Variable Kosten · geschätzt» (13.5 Tinte 2)
    private var headSection: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { iconsOpen.toggle() }
            } label: {
                MarkView(variable: draft, size: 76)
                    .overlay(alignment: .bottomTrailing) {
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
            .accessibilityLabel("Symbol ändern")
            .accessibilityValue(iconsOpen ? Text("aufgeklappt") : Text("zugeklappt"))
            .accessibilityIdentifier("var.iconToggle")
            VStack(alignment: .leading, spacing: 6) {
                TextField("", text: $draft.label, prompt: Text("Bezeichnung, z.B. Benzin").foregroundColor(KColor.ink3))
                    .font(KFont.title(21))
                    .tracking(-0.252)
                    .foregroundStyle(KColor.ink)
                    .focused($focus, equals: .label)
                    .submitLabel(.next)
                    .onSubmit { focus = .amount }
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(KColor.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(KBMissRing(on: miss == "label"))
                    .id("label")
                    .accessibilityLabel("Bezeichnung")
                    .accessibilityIdentifier("var.label")
                Text("Variable Kosten · geschätzt")
                    .font(.system(size: 13.5))
                    .foregroundStyle(KColor.ink2)
                    .padding(.horizontal, 10)
            }
        }
        .padding(.bottom, 4)
    }

    /// Vorschläge (Web `#vcSug`, nur beim Erfassen): Antippen setzt Bezeichnung und Symbol, danach zum Betrag
    @ViewBuilder private var suggestions: some View {
        let sg = model.calc.variableSuggestions(excluding: draft.id)
        if isNew && !sg.isEmpty {
            let lb = draft.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            KBChipFlow(spacing: 6) {
                ForEach(sg, id: \.self) { ic in
                    let on = lb == ic.displayName.lowercased()
                    Button {
                        draft.label = ic.displayName
                        draft.icon = ic
                        if amountText.trimmingCharacters(in: .whitespaces).isEmpty { focus = .amount }
                    } label: {
                        Text(verbatim: ic.displayName)
                            .font(.system(size: 13.5, weight: on ? .semibold : .regular))
                            .foregroundStyle(on ? KColor.paper : KColor.ink2)
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Capsule().fill(on ? KColor.ink : .clear))
                            .overlay(Capsule().strokeBorder(on ? KColor.ink : KColor.line, lineWidth: 1))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("var.sug." + ic.rawValue)
                }
            }
            .padding(.top, 12)
        }
    }

    /// «Zuordnung · Personen» (Web `#vcHWrap`): nur bei mehreren Personen; die letzte gewählte bleibt
    @ViewBuilder private var personsSection: some View {
        let persons = model.data.persons
        if persons.count > 1 {
            KBFormSection("Zuordnung")
            KBFormCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personen")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                        .frame(minHeight: 21.75)
                    KBChipFlow(spacing: 6) {
                        ForEach(persons) { p in
                            KBInkChip(title: p.name, isOn: draft.holderIDs.contains(p.id)) { toggle(p.id) }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if draft.holderIDs.contains(id) {
            if draft.holderIDs.count > 1 { draft.holderIDs.removeAll { $0 == id } }
        } else {
            let all = model.data.persons.map { $0.id }
            draft.holderIDs = all.filter { draft.holderIDs.contains($0) || $0 == id }
        }
    }

    private func hint(_ t: String) -> some View {
        Text(verbatim: t)
            .font(.system(size: 12.5))
            .kLineHeight(12.5, 17.5)
            .foregroundStyle(KColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 2)
            .padding(.top, 8)
    }

    /// Datumszeile: leer «hinzufügen», sonst Datum; Antippen öffnet die Datumsauswahl darunter
    private func dateRow(_ title: String, key: String, date: Binding<Day?>) -> some View {
        let open = dateOpen == key
        return VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { dateOpen = open ? nil : key }
            } label: {
                HStack(spacing: 12) {
                    Text(verbatim: title).font(.system(size: 15)).foregroundStyle(KColor.ink2)
                    Spacer(minLength: 8)
                    if let d = date.wrappedValue {
                        Text(verbatim: String(format: "%02d.%02d.%04d", d.day, d.month, d.year))
                            .font(.system(size: 16, weight: .medium).monospacedDigit())
                            .foregroundStyle(KColor.teal)
                    } else {
                        Text("hinzufügen").font(.system(size: 16)).foregroundStyle(KColor.ink3)
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
            .accessibilityIdentifier("var." + key)
            if open {
                DatePicker(title, selection: Binding(get: { (date.wrappedValue ?? model.today).date() },
                                                     set: { date.wrappedValue = Day(date: $0) }),
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(KColor.teal)
                    .environment(\.locale, Locale(identifier: "de_CH"))
                if date.wrappedValue != nil {
                    Button {
                        date.wrappedValue = nil
                        dateOpen = nil
                    } label: {
                        Text("Datum entfernen").font(.system(size: 14)).foregroundStyle(KColor.ink2).padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .id(key)
    }

    // MARK: Aktionen

    private var isDirty: Bool { draft != original || amountText != originalAmount }

    private func cancel() {
        if isDirty { confirmDiscard = true } else { close() }
    }

    private func close() {
        guard !closed else { return }
        closed = true
        model.dismissTop()
    }

    /// Fehlende Angabe (Web `goMiss`): Meldung, Fokus bzw. Datumsauswahl, ins Feld scrollen, 1.8 s markieren
    private func goMiss(_ key: String, _ msg: String) {
        model.toast(msg)
        switch key {
        case "label": focus = .label
        case "amount": focus = .amount
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
        if let m = VariableCostForm.missing(label: draft.label, amountText: amountText, start: draft.start, end: draft.end) {
            goMiss(m.field, m.message)
            return
        }
        var d = draft
        d.amount = Format.parseAmount(amountText) ?? 0
        let wasNew = isNew
        if model.update({ _ = $0.putVariableCost(d) }) {
            close()
            model.toast(wasNew ? "Variable Kosten erfasst" : "Aktualisiert")
        }
    }

    /// Löschen schliesst auch die Ansicht darunter (Web `closeSheets`)
    private func delete() {
        guard !closed else { return }
        closed = true
        let id = draft.id
        model.update { $0.deleteVariableCost(id) }
        let n = model.sheets.count
        if n >= 2, model.sheets[n - 2] == .variableDetail(id) {
            model.dismiss(level: n - 2)
        } else {
            model.dismissTop()
        }
        model.toast("Gelöscht")
    }
}
