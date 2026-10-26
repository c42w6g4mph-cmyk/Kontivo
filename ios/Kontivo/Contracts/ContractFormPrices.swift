import SwiftUI
import KontivoCore

// Betragsbereich der Karte «Kosten» als Zeitstrahl (Web v314–v320): Zeile «Währung», «+ Preisänderung», neue Änderung direkt
// als Zeile (Datum heute vorbelegt, Betrag rechts; übernommen, sobald beides da ist), Stufen neueste zuerst mit Datum und Betrag
// direkt in der Zeile (v277), Startzeile «ab …»/«Anfangspreis» zuletzt. Ohne Preisänderungen gleicher Aufbau ohne Punkte (v319).
// Löschen bzw. Verwerfen per Wischen nach links (v317/v320). Rechnung im Kern (`PriceTimelineRules`).

extension CTFormCostSection {
    /// Alle Zeilen des Betragsbereichs (je eine Kartenzeile)
    @ViewBuilder
    func priceArea(today: Day) -> some View {
        let tl = form.priceTimeline(today: today)
        let showAdd = !form.priceOpen && (!form.amountText.ctTrimmed.isEmpty || !form.prices.isEmpty)
        currencyRow
        if showAdd {
            CTFormAddRow(title: "Preisänderung", identifier: "form.priceOpen") {
                withAnimation(.easeInOut(duration: 0.2)) { form.openPriceForm(today: today) }
                let f = focus
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    f.wrappedValue = .priceAmount
                }
            }
        }
        if form.priceOpen {
            newRow(tl, today: today)
        }
        ForEach(Array(tl.rows.enumerated()), id: \.element.from) { i, r in
            CTSwipeDelete(identifier: "form.priceRow.\(i)", onDelete: { form.removePrice(r.from) }) {
                stepRow(r, index: i, tl: tl, top: i == 0 && !form.priceOpen)
            }
        }
        startRow(tl)
    }

    /// «Währung» oben (Web v316 Variante B: Währung als eigene Zeile)
    private var currencyRow: some View {
        CTMenuRow("Währung", value: form.currency.rawValue, identifier: "form.currency") {
            Picker("Währung", selection: $form.currency) {
                ForEach(Currency.allCases, id: \.self) { c in
                    Text(c.rawValue).tag(c)
                }
            }
        }
    }

    private func amountField(_ text: Binding<String>, placeholder: String, a11y: String, id: String) -> some View {
        CTTimelineAmountField(text: text, placeholder: placeholder, a11y: a11y, identifier: id)
    }

    /// Stufe: links «ab TT.MM.JJ» (Datum änderbar) mit «aktuell · +10 %», rechts der Betrag (direkt änderbar)
    private func stepRow(_ r: PriceTimelineRow, index i: Int, tl: PriceTimeline, top: Bool) -> some View {
        CTTimelineRow(on: tl.on, top: top, dot: r.isCurrent ? .current : (r.isFuture ? .future : .normal)) {
            HStack(spacing: 6) {
                CTTimelineDateLabel(day: r.from, identifier: "form.priceDate.\(i)", onPick: { d in
                    if let m = form.setPriceRowDate(r.from, to: d) { model.toast(m) }
                }) {
                    CTTimelineStepLabel(row: r)
                }
                amountField(Binding(get: { form.priceRowText(r) }, set: { form.priceRowTexts[r.from] = $0 }),
                            placeholder: "Betrag", a11y: "Betrag " + r.dateText, id: "form.priceAmt.\(i)")
                    .focused($rowFocus, equals: r.from)
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Neue Preisänderung als Zeile (Web v320 #pForm): Datum links (heute vorbelegt), Betrag rechts; Verwerfen per Wischen
    private func newRow(_ tl: PriceTimeline, today: Day) -> some View {
        CTSwipeDelete(title: "Verwerfen", identifier: "form.priceNew", onDelete: { form.cancelPriceForm() }) {
            CTTimelineRow(on: tl.on, top: true, dot: .new) {
                HStack(spacing: 6) {
                    CTTimelineDateLabel(day: form.priceFrom ?? today, identifier: "form.priceFrom", onPick: { d in
                        form.priceFrom = d
                        if !form.priceAmountText.ctTrimmed.isEmpty { addPrice(force: false) }
                    }) {
                        CTTimelineNewLabel(from: form.priceFrom)
                    }
                    amountField($form.priceAmountText, placeholder: "Betrag", a11y: "Neuer Betrag", id: "form.priceAmount")
                        .focused(focus, equals: .priceAmount)
                }
            }
        }
        .ctMiss(form, .priceAmount)
        .ctMiss(form, .prices)
        .id(ContractFormField.priceAmount)
    }

    /// Startzeile (Web #fAmtR `.tlstart`): ohne Änderungen «Betrag», sonst «ab TT.MM.JJ» mit «Anfangspreis»
    private func startRow(_ tl: PriceTimeline) -> some View {
        let a11y = tl.on ? "Anfangspreis" : "Betrag"
        return CTTimelineRow(on: tl.on, bottom: true, dot: tl.startIsCurrent ? .current : .normal) {
            HStack(spacing: 6) {
                CTTimelineStartLabel(timeline: tl)
                amountField($form.amountText, placeholder: ContractFormRules.placeholder, a11y: a11y, id: "form.amount")
                    .focused(focus, equals: .amount)
            }
        }
        .ctMiss(form, .amount)
        .id(ContractFormField.amount)
    }

    /// Neue Preisänderung übernehmen; «Preis bleibt gleich» fragt nicht blockierend nach («Trotzdem hinzufügen»)
    func addPrice(force: Bool) {
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
}
