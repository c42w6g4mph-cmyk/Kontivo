import SwiftUI
import KontivoCore

// Karte «Laufzeit & Kündigung» des Vertragsformulars (Web v145–v160, #fsTerm):
// Vertragsart als 2×2-Knöpfe, Probeabo-Dauer, Vertragsbeginn, Mindestlaufzeit (Knöpfe + Drehrad «Andere …»), Vertragsende,
// Verlängerung, Kündigungsfrist (Knöpfe + Drehrad mit «keine» und Einheit), Kündbar per, Kündigungsweg mit genau einem
// Folgefeld, «An Frist erinnern», «Nur Anbieter wechseln», bei gekündigten Verträgen «Gekündigt am»/«Läuft bis».
// Darunter der Laufzeit-Hinweis aus dem Kern (`ContractFormRules.termHint`).

struct CTFormTermSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    var focus: FocusState<ContractFormField?>.Binding

    private struct TrialChip: Identifiable {
        let key: String
        let title: String
        var id: String { key }
    }

    private static let trialChips: [TrialChip] = [
        TrialChip(key: "7d", title: "7 Tage"), TrialChip(key: "14d", title: "14 Tage"), TrialChip(key: "1m", title: "1 Monat"),
        TrialChip(key: "3m", title: "3 Monate"), TrialChip(key: "date", title: "Datum …"),
    ]

    var body: some View {
        let today = model.today
        let m = form.termMode
        Section {
            modeRow
            if m == .trial {
                trialRows(today: today)
            }
            CTFormDateRow(title: "Vertragsbeginn", day: form.start, fallback: today, identifier: "form.start") { d in
                if let t = form.setStart(d, today: model.today) { model.toast(t) }
            }
            .id(ContractFormField.start)
            if m == .fixed {
                termMonthsRows
                CTFormDateRow(title: "Vertragsende", day: form.end, fallback: (form.start ?? today).addingMonths(12).addingDays(-1),
                              identifier: "form.end") { form.setEnd($0) }
                    .id(ContractFormField.end)
                Picker(selection: $form.renewMonths) {
                    Text("nicht automatisch").tag(0)
                    Text("1 Monat").tag(1)
                    ForEach([3, 6, 12, 24], id: \.self) { n in
                        Text("\(n) Monate").tag(n)
                    }
                    if ![0, 1, 3, 6, 12, 24].contains(form.renewMonths) {
                        Text("\(form.renewMonths) Monate").tag(form.renewMonths)
                    }
                } label: {
                    CTRowLabel("Verlängert sich um")
                }
                .pickerStyle(.menu)
                .tint(KColor.teal)
                .accessibilityIdentifier("form.renew")
            }
            if m == .open || m == .fixed {
                noticeRows
            }
            if m == .open || m == .trial {
                Picker(selection: $form.cancelTerm) {
                    ForEach([CancelTerm.anytime, .period, .monthEnd, .quarterEnd, .halfYearEnd, .yearEnd, .contractYear], id: \.self) { t in
                        Text(CTFormState.termOptionText(t)).tag(t)
                    }
                } label: {
                    CTRowLabel("Kündbar per")
                }
                .pickerStyle(.menu)
                .tint(KColor.teal)
                .accessibilityIdentifier("form.cancelTerm")
            }
            if m != .tax {
                cancelWayRows
                if form.showsRemindToggle {
                    Toggle(isOn: Binding(get: { !form.noWatch }, set: { form.noWatch = !$0 })) {
                        switchLabel(ContractFormRules.remindTitle, ContractFormRules.remindSubtitle)
                    }
                    .tint(KColor.teal)
                    .accessibilityIdentifier("form.remind")
                }
                Toggle(isOn: $form.mandatory) {
                    switchLabel(ContractFormRules.mandatoryTitle, ContractFormRules.mandatorySubtitle)
                }
                .tint(KColor.teal)
                .accessibilityIdentifier("form.mandatory")
                // Nativ zusätzlich (README «Bewusst anders»): Mietvertrag; ohne Wahl gilt die Erkennung aus Bezeichnung/Kategorie
                Toggle(isOn: rentBinding) {
                    switchLabel("Mietvertrag", "Kündigung immer per Brief mit Unterschrift")
                }
                .tint(KColor.teal)
                .accessibilityIdentifier("form.rent")
            }
            if form.showsCancelDates {
                CTFormDateRow(title: "Gekündigt am", day: form.cancelledOn, fallback: today, identifier: "form.cancelOn") { form.cancelledOn = $0 }
                    .id(ContractFormField.cancelOn)
                CTFormDateRow(title: "Läuft bis", day: form.cancelPer, fallback: form.cancelledOn ?? today, identifier: "form.cancelPer") { form.cancelPer = $0 }
                    .id(ContractFormField.cancelPer)
            }
        } header: {
            Text("Laufzeit & Kündigung")
        } footer: {
            let hint = form.termHint(calc: model.calc)
            if !hint.isEmpty {
                Text(hint).accessibilityIdentifier("form.termHint")
            }
        }
        .listRowBackground(KColor.surface)
    }

    private func switchLabel(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(KColor.ink)
            Text(sub).font(.footnote).foregroundStyle(KColor.ink2)
        }
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

    // MARK: Vertragsart (Web #termSeg, v151: 2×2, volle Wörter)

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            CTRowLabel("Vertragsart")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(ContractTermMode.allCases, id: \.self) { tm in
                    CTFormChip(title: tm.title, isOn: form.termMode == tm, enabled: form.termModeEnabled(tm, data: model.data),
                               identifier: "term." + tm.rawValue) {
                        withAnimation(.easeInOut(duration: 0.15)) { form.pickTermMode(tm) }
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Art des Vertrags")
        }
        .padding(.vertical, 4)
    }

    // MARK: Probeabo (Web .tmtrial)

    @ViewBuilder
    private func trialRows(today: Day) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CTRowLabel("Probeabo dauert")
            CTFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(CTFormTermSection.trialChips) { it in
                    CTFormChip(title: it.title, isOn: form.trialChoice == it.key, fill: false, identifier: "trial." + it.key) {
                        form.pickTrial(it.key, today: model.today)
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dauer des Probeabos")
        }
        .padding(.vertical, 4)
        .id(ContractFormField.trial)
        if form.trialChoice == "date" {
            CTFormDateRow(title: "Probeabo endet am", day: form.trial, fallback: (form.start ?? today).addingMonths(1),
                          identifier: "form.trial") { form.setTrial($0) }
        }
    }

    // MARK: Mindestlaufzeit (Web #fTermMC, #fTermMW)

    @ViewBuilder
    private var termMonthsRows: some View {
        let other = form.termMonthsIsOther
        let open = form.termMonthsOpen
        VStack(alignment: .leading, spacing: 8) {
            CTRowLabel("Mindestlaufzeit")
            HStack(spacing: 6) {
                ForEach(ContractFormRules.termMonthsQuick, id: \.self) { n in
                    CTFormChip(title: ContractFormRules.termMonthsText(n), isOn: !other && !open && form.termMonths == n,
                               identifier: "termMonths.\(n)") {
                        if let t = form.pickTermMonths(n) { model.toast(t) }
                    }
                }
                CTFormChip(title: other && !open ? ContractFormRules.termMonthsButtonText(form.termMonths ?? 0) : "Andere …",
                           isOn: other || open, identifier: "termMonths.other") {
                    withAnimation(.easeInOut(duration: 0.2)) { form.toggleTermMonthsWheel() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Mindestlaufzeit")
        }
        .padding(.vertical, 4)
        .id(ContractFormField.termMonths)
        if open {
            VStack(spacing: 10) {
                let values = form.termMonthsWheelValues
                CTWheelPicker(columns: [values.map { String($0) }, ["Monate"]],
                              selection: [values.firstIndex(of: form.termMonthsPend) ?? 23, 0],
                              widths: [0.45, 0.5],
                              accessibilityLabels: ["Monate", "Einheit"]) { col, row in
                    if col == 0, row < values.count { form.termMonthsPend = values[row] }
                }
                .frame(height: 150)
                .accessibilityIdentifier("form.termMonthsWheel")
                CTFormOKButton(title: ContractFormRules.termMonthsText(form.termMonthsPend) + " übernehmen", identifier: "form.termMonthsOK") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if let t = form.applyTermMonthsWheel() { model.toast(t) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Kündigungsfrist (Web #fNoticeC, #fNoticeWh; v156 mit «keine»)

    @ViewBuilder
    private var noticeRows: some View {
        let other = form.noticeIsOther
        let open = form.noticeOpen
        VStack(alignment: .leading, spacing: 8) {
            CTRowLabel("Kündigungsfrist")
            HStack(spacing: 6) {
                ForEach(ContractFormRules.noticeQuick, id: \.self) { n in
                    CTFormChip(title: ContractFormRules.noticeChoiceText(n, .months),
                               isOn: !other && !open && form.noticeUnit == .months && form.noticeN == n,
                               identifier: "notice.\(n)") {
                        withAnimation(.easeInOut(duration: 0.15)) { form.pickNotice(n) }
                    }
                }
                CTFormChip(title: other && !open ? ContractFormRules.noticeChoiceText(form.noticeN, form.noticeUnit) : "Andere …",
                           isOn: other || open, identifier: "notice.other") {
                    withAnimation(.easeInOut(duration: 0.2)) { form.toggleNoticeWheel() }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kündigungsfrist")
        }
        .padding(.vertical, 4)
        .id(ContractFormField.notice)
        if open {
            VStack(spacing: 10) {
                let values = form.noticeWheelValues
                let units = ContractFormRules.noticeUnits
                CTWheelPicker(columns: [values.map { $0 == 0 ? "keine" : String($0) },
                                        units.map { ContractFormRules.noticeUnitLabel($0.unit, count: form.noticePendN) }],
                              selection: [values.firstIndex(of: form.noticePendN) ?? 1,
                                          units.firstIndex { $0.unit == form.noticePendU } ?? 0],
                              widths: [0.4, 0.55],
                              accessibilityLabels: ["Frist", "Einheit"]) { col, row in
                    if col == 0, row < values.count {
                        form.setNoticePending(n: values[row])
                    } else if col == 1, row < units.count {
                        form.setNoticePending(unit: units[row].unit)
                    }
                }
                .frame(height: 150)
                .accessibilityIdentifier("form.noticeWheel")
                CTFormOKButton(title: ContractFormRules.noticeApplyTitle(form.noticePendN, form.noticePendU), identifier: "form.noticeOK") {
                    withAnimation(.easeInOut(duration: 0.2)) { form.applyNoticeWheel() }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Kündigungsweg (Web #fCancT + Folgefeld)

    @ViewBuilder
    private var cancelWayRows: some View {
        let ch = form.cancelChannel
        VStack(alignment: .leading, spacing: 8) {
            CTRowLabel("Kündigungsweg")
            CTCancelWaySegment(value: ch) { v in
                withAnimation(.easeInOut(duration: 0.15)) { form.toggleCancelChannel(v) }
            }
        }
        .padding(.vertical, 4)
        .id(ContractFormField.cancelWay)
        switch ch {
        case .online:
            CTFormTextRow(title: "Kündigungslink", text: $form.cancelURL, placeholder: "sonst Website", keyboard: .URL,
                          contentType: .URL, identifier: "form.cancelURL", field: .cancelURL, focus: focus)
        case .email:
            CTFormTextRow(title: "E-Mail für Kündigung", text: $form.mail, placeholder: "kuendigung@anbieter.ch", keyboard: .emailAddress,
                          contentType: .emailAddress, identifier: "form.cancelMail", field: .cancelMail, focus: focus)
        case .letter:
            addressWayRow
        case .phone:
            // Web v210: kein Folgefeld (Nummer steht unter «Kontakt»)
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    /// Brief: Zeile «Adresse des Vertragspartners» mit «Erfassen»/«Ändern» → Adresse unter «Kontakt»
    private var addressWayRow: some View {
        let line = form.addressLine
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Adresse des Vertragspartners")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.ink)
                Text(line.isEmpty ? "Noch keine Adresse – wird für den Brief gebraucht" : line)
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button(line.isEmpty ? "Erfassen" : "Ändern") {
                withAnimation(.easeInOut(duration: 0.2)) { form.showAddress() }
            }
            .buttonStyle(.borderless)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(KColor.teal)
            .accessibilityIdentifier("form.cancelAddr")
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("form.cancelAddrRow")
    }
}
