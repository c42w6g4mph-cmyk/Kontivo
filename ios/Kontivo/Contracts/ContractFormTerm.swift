import SwiftUI
import KontivoCore

// Abschnitt «Laufzeit & Kündigung» des Vertragsformulars (Web v132–v141):
// Art des Vertrags als 4 Kacheln (Web setTermMode) mit genau den Feldern der Art,
// darunter «Kündigungsweg» als 4 Kacheln mit genau einem Folgefeld (Web syncCancUrl).

/// Kachel (Web .tmtile): Symbol + Titel, gewählt mit Rand und hellem Hintergrund
struct CTTile: View {
    let title: String
    let symbol: String
    let isOn: Bool
    var enabled = true
    var identifier = ""
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(KColor.teal)
                    .frame(width: 22)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 11).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isOn ? KColor.teal.opacity(0.10) : KColor.field))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOn ? KColor.teal : Color.clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

/// Eintrag einer Kachelreihe (Wert, Titel, SF Symbol)
struct CTTileItem<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    let symbol: String
    var id: Value { value }
}

struct CTFormTermSection: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    @Binding var showMore: Bool
    @FocusState private var noticeFocused: Bool

    private static let modes: [CTTileItem<CTFormState.TermMode>] = [
        CTTileItem(value: .open, title: "Flexibel", symbol: "arrow.counterclockwise"),
        CTTileItem(value: .fixed, title: "Mindestlaufzeit", symbol: "calendar"),
        CTTileItem(value: .trial, title: "Probeabo", symbol: "gift"),
        CTTileItem(value: .tax, title: "Nicht kündbar", symbol: "building.columns"),
    ]

    private static let trialChips: [CTTileItem<String>] = [
        CTTileItem(value: "7d", title: "7 Tage", symbol: ""), CTTileItem(value: "14d", title: "14 Tage", symbol: ""),
        CTTileItem(value: "1m", title: "1 Monat", symbol: ""), CTTileItem(value: "3m", title: "3 Monate", symbol: ""),
        CTTileItem(value: "date", title: "Datum …", symbol: ""),
    ]

    var body: some View {
        let today = model.today
        let m = form.termMode
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(CTFormTermSection.modes) { it in
                    CTTile(title: it.title, symbol: it.symbol, isOn: m == it.value, enabled: form.termModeEnabled(it.value, data: model.data),
                           identifier: "term." + it.value.rawValue) {
                        withAnimation(.easeInOut(duration: 0.15)) { form.setTermMode(it.value) }
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Art des Vertrags")
            if m == .trial {
                trialRows(today: today)
            }
            if m != .trial {
                CTOptionalDateRow(title: "Vertragsbeginn", day: $form.start, fallback: today)
                    .onChange(of: form.start) { _, _ in form.startChanged(today: today) }
            }
            if m == .fixed {
                CTOptionalDateRow(title: "Vertragsende", day: $form.end, fallback: today.addingMonths(12))
            }
            if m == .open || m == .fixed {
                noticeRow
                if m == .fixed {
                    Picker("Verlängert sich um", selection: $form.renewMonths) {
                        Text("— nicht automatisch").tag(0)
                        Text("1 Monat").tag(1)
                        ForEach([3, 6, 12, 24], id: \.self) { n in
                            Text("\(n) Monate").tag(n)
                        }
                        if ![0, 1, 3, 6, 12, 24].contains(form.renewMonths) {
                            Text("\(form.renewMonths) Monate").tag(form.renewMonths)
                        }
                    }
                } else {
                    Picker("Kündbar per", selection: $form.cancelTerm) {
                        ForEach([CancelTerm.anytime, .period, .monthEnd, .quarterEnd, .halfYearEnd, .yearEnd, .contractYear], id: \.self) { t in
                            Text(CTFormState.termOptionText(t)).tag(t)
                        }
                    }
                }
            }
        } header: {
            Text("Laufzeit & Kündigung")
        } footer: {
            let hint = form.termHint(model.data, today: today)
            if !hint.isEmpty {
                Text(hint).accessibilityIdentifier("form.termHint")
            }
        }
        .listRowBackground(KColor.surface)
        if m != .tax {
            CTFormCancelWaySection(form: form, showMore: $showMore)
        }
    }

    @ViewBuilder
    private func trialRows(today: Day) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Probeabo dauert")
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
            CTFlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(CTFormTermSection.trialChips) { it in
                    Chip(title: it.title, isOn: form.trialChoice == it.value) {
                        form.pickTrial(it.value, today: today)
                    }
                    .accessibilityIdentifier("trial." + it.value)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Dauer des Probeabos")
        }
        .padding(.vertical, 4)
        if form.trialChoice == "date" {
            CTOptionalDateRow(title: "Probeabo endet am", day: $form.trial, fallback: (form.start ?? today).addingMonths(1))
        }
    }

    private var noticeRow: some View {
        LabeledContent("Kündigungsfrist") {
            HStack(spacing: 6) {
                TextField("–", text: $form.noticeText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
                    .focused($noticeFocused)
                    .accessibilityLabel("Kündigungsfrist")
                    .accessibilityIdentifier("form.notice")
                    .onChange(of: form.focusNotice) { _, on in
                        if on {
                            noticeFocused = true
                            form.focusNotice = false
                        }
                    }
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
    }
}

/// «Kündigungsweg»: 4 Kacheln (nochmals tippen hebt die Wahl auf) und genau ein Folgefeld:
/// Online → Kündigungslink, E-Mail → E-Mail-Adresse (gleich wie Kontakt-E-Mail), Brief/Einschreiben → Adresse des Vertragspartners.
private struct CTFormCancelWaySection: View {
    @Bindable var form: CTFormState
    @Binding var showMore: Bool

    private static let ways: [CTTileItem<CancelChannel>] = [
        CTTileItem(value: .online, title: "Online", symbol: "globe"),
        CTTileItem(value: .email, title: "E-Mail", symbol: "envelope"),
        CTTileItem(value: .letter, title: "Brief", symbol: "doc.text"),
        CTTileItem(value: .registered, title: "Einschreiben", symbol: "checkmark.seal"),
    ]

    var body: some View {
        let ch = form.cancelChannel
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(CTFormCancelWaySection.ways) { it in
                    CTTile(title: it.title, symbol: it.symbol, isOn: ch == it.value, identifier: "cancelWay." + it.value.rawValue) {
                        withAnimation(.easeInOut(duration: 0.15)) { form.toggleCancelChannel(it.value) }
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kündigungsweg")
            switch ch {
            case .online:
                CTField(title: "Kündigungslink", placeholder: "netflix.com/cancelplan", text: $form.cancelURL,
                        keyboard: .URL, capitalization: .never, autocorrect: false, identifier: "form.cancelURL")
            case .email:
                CTField(title: "E-Mail-Adresse für die Kündigung", placeholder: "kuendigung@anbieter.ch", text: $form.mail,
                        keyboard: .emailAddress, capitalization: .never, autocorrect: false, identifier: "form.cancelMail")
            case .letter, .registered:
                addressRow
            case nil:
                EmptyView()
            }
        } header: {
            Text("Kündigungsweg")
        } footer: {
            if ch == .online {
                Text("Seite im Kundenkonto, auf der du kündigst. Leer: die Website des Vertragspartners wird geöffnet.")
            }
        }
        .listRowBackground(KColor.surface)
    }

    private var addressRow: some View {
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
                form.focusAddress = true
                showMore = true
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
