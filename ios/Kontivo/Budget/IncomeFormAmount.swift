import SwiftUI
import PhotosUI
import UIKit
import KontivoCore

// Einnahmen-Formular: Karte «Betrag» (Zeitstrahl, Rhythmus, Zahlung am) und Datumszeilen

extension KBIncomeForm {
    // MARK: Betrag als Zeitstrahl (Web v314–v320 `tlPaint("i", …, inc)`): Währung, «+ Änderung», neue Änderung als Zeile,
    // Stufen neueste zuerst mit Datum und Betrag direkt in der Zeile, Startzeile «Betrag netto» bzw. «ab …»/«Anfangsbetrag»;
    // danach Rhythmus und Zahlung am. Kein Diagramm im Formular (bleibt in der Ansicht). Löschen/Verwerfen per Wischen.

    /// «+ Änderung» erst mit Betrag oder vorhandenen Änderungen (Web `iSyncPOpen`)
    var showChangePill: Bool {
        !subOpen && (!amountText.trimmingCharacters(in: .whitespaces).isEmpty || !draft.prices.isEmpty)
    }

    /// Zeitstrahl des Entwurfs (Kern `PriceTimelineRules`, Einnahme: mehr ist grün)
    func timeline(today: Day) -> PriceTimeline {
        PriceTimelineRules.make(prices: draft.prices, base: Format.parseAmount(amountText) ?? 0, start: draft.start, today: today, income: true)
    }

    var amountCard: some View {
        let tl = timeline(today: model.today)
        return KBFormCard {
            KBFormRow(label: "Währung") {
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
            if showChangePill {
                KBRowDivider()
                CTFormAddRow(title: "Änderung", identifier: "income.addChange") { openChange() }
            }
            if subOpen {
                KBRowDivider()
                newChangeRow(tl)
            }
            ForEach(Array(tl.rows.enumerated()), id: \.element.from) { i, r in
                KBRowDivider()
                CTSwipeDelete(identifier: "income.priceRow.\(i)", onDelete: { removePrice(r.from) }) {
                    stepRow(r, index: i, tl: tl, top: i == 0 && !subOpen)
                }
            }
            KBRowDivider()
            startRow(tl)
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

    /// Stufe: «ab TT.MM.JJ» (Datum änderbar) mit «aktuell · +5 %», rechts der Betrag (direkt änderbar, Web v277)
    func stepRow(_ r: PriceTimelineRow, index i: Int, tl: PriceTimeline, top: Bool) -> some View {
        CTTimelineRow(on: tl.on, top: top, dot: r.isCurrent ? .current : (r.isFuture ? .future : .normal)) {
            HStack(spacing: 6) {
                CTTimelineDateLabel(day: r.from, identifier: "income.priceDate.\(i)", onPick: { d in setRowDate(r.from, d) }) {
                    CTTimelineStepLabel(row: r)
                }
                CTTimelineAmountField(text: Binding(get: { priceRowTexts[r.from] ?? Format.amountInput(r.amount, draft.currency) },
                                                    set: { priceRowTexts[r.from] = $0 }),
                                      a11y: "Betrag " + r.dateText, identifier: "income.priceAmt.\(i)")
                    .focused($rowFocus, equals: r.from)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("income.price." + r.from.iso)
    }

    /// Neue Änderung als Zeile (Web v320 `#iPForm`): Datum heute vorbelegt, Betrag rechts; Verwerfen per Wischen
    func newChangeRow(_ tl: PriceTimeline) -> some View {
        CTSwipeDelete(title: "Verwerfen", identifier: "income.priceNew", onDelete: { cancelSub() }) {
            CTTimelineRow(on: tl.on, top: true, dot: .new) {
                HStack(spacing: 6) {
                    CTTimelineDateLabel(day: priceFrom ?? model.today, identifier: "income.priceFrom", onPick: { d in
                        priceFrom = d
                        if !priceAmountText.trimmingCharacters(in: .whitespaces).isEmpty { addPrice() }
                    }) {
                        CTTimelineNewLabel(from: priceFrom)
                    }
                    CTTimelineAmountField(text: $priceAmountText, a11y: "Neuer Betrag", identifier: "income.priceAmount")
                        .focused($focus, equals: .priceAmount)
                }
            }
        }
        .background(KBMissFlash(on: miss == "priceAmount" || miss == "priceFrom"))
        .id("priceAmount")
    }

    /// Startzeile (Web `#iAmtR`): «Betrag netto»; mit Änderungen «ab TT.MM.JJ» (Beginn) bzw. «Anfangsbetrag»
    func startRow(_ tl: PriceTimeline) -> some View {
        CTTimelineRow(on: tl.on, bottom: true, dot: tl.startIsCurrent ? .current : .normal) {
            HStack(spacing: 6) {
                CTTimelineStartLabel(timeline: tl)
                CTTimelineAmountField(text: $amountText, placeholder: "hinzufügen", a11y: tl.on ? "Anfangsbetrag" : "Betrag netto",
                                      identifier: "income.amount")
                    .focused($focus, equals: .amount)
            }
        }
        .background(KBMissFlash(on: miss == "amount"))
        .id("amount")
    }

    /// «+ Änderung»: neue Zeile öffnen, Betrag fokussieren
    func openChange() {
        if priceFrom == nil { priceFrom = model.today }
        withAnimation(.easeInOut(duration: 0.2)) { subOpen = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            focus = .priceAmount
        }
    }

    /// Betrag einer Stufe übernehmen (Feld verlassen); ungültig → Meldung, Zeile zurück
    func commitRow(_ from: Day) {
        guard let t = priceRowTexts[from] else { return }
        priceRowTexts[from] = nil
        let e = PriceTimelineRules.editAmount(t)
        if case .reject(let m) = e {
            model.toast(m)
            return
        }
        draft.prices = PriceTimelineRules.apply(e, to: from, in: draft.prices)
    }

    /// Datum einer Stufe ändern (nach dem Beginn «Ab», nicht doppelt)
    func setRowDate(_ old: Day, _ new: Day) {
        let e = PriceTimelineRules.editDate(new, old: old, start: draft.start, prices: draft.prices)
        if case .reject(let m) = e {
            model.toast(m)
            return
        }
        if let t = priceRowTexts[old] {
            priceRowTexts[old] = nil
            priceRowTexts[new] = t
        }
        draft.prices = PriceTimelineRules.apply(e, to: old, in: draft.prices).sorted { $0.from < $1.from }
    }

    /// «Zahlung am» als Tag im Monat (Tagesraster, Monatsreihe ab 2 Monaten); einmalig ein Datum (Web `iPaintDue`)
    @ViewBuilder
    var dueRows: some View {
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
    func pickDue(day: Int?, month: Int?) {
        let v = draft.due ?? model.today
        draft.due = ContractFormRules.incomeDueFrom(day: day ?? v.day, month: month ?? v.month, cycle: draft.cycle, today: model.today)
        if day != nil {
            withAnimation(.easeInOut(duration: 0.2)) { dueOpen = false }
        }
    }

    /// Datumszeile: leer «hinzufügen» (Tinte 3, v217), sonst Datum in Akzentfarbe; Antippen öffnet die Datumsauswahl darunter
    @ViewBuilder
    func dateRow(_ title: String, key: String, date: Binding<Day?>) -> some View {
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

}
