import SwiftUI
import KontivoCore

// Betragsbereich der Karte «Kosten» als Zeitstrahl (Web v314–v320): Zeile «Währung», «+ Preisänderung», neue Änderung direkt
// als Zeile (Datum heute vorbelegt, Betrag rechts; übernommen, sobald beides da ist), Stufen neueste zuerst mit Datum und Betrag
// direkt in der Zeile (v277), Startzeile «ab …»/«Anfangspreis» zuletzt. Ohne Preisänderungen gleicher Aufbau ohne Punkte (v319).
// Löschen bzw. Verwerfen per Wischen nach links (v317/v320). Rechnung im Kern (`PriceTimelineRules`).

/// Punkt im Zeitstrahl (Web `.tld`): normal (Rand Tinte 3), aktuell (Messing mit Hof), geplant (gestrichelt Warnfarbe),
/// neu (gestrichelt Akzent)
enum CTTimelineDot {
    case normal, current, future, new
}

/// Zeile im Zeitstrahl: links 28 pt mit senkrechter Linie (x 10, 2 pt) und Punkt (12 pt), daneben der Inhalt.
/// `on` = Zeitstrahl sichtbar (ab 1 Preisänderung); `top`/`bottom`: Linie beginnt bzw. endet in der Zeilenmitte.
struct CTTimelineRow<Content: View>: View {
    let on: Bool
    var top = false
    var bottom = false
    var dot: CTTimelineDot = .normal
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            if on {
                GeometryReader { g in
                    let h = g.size.height
                    let y0: CGFloat = top ? h / 2 : 0
                    let y1: CGFloat = bottom ? h / 2 : h
                    Rectangle().fill(KColor.line)
                        .frame(width: 2, height: Swift.max(0, y1 - y0))
                        .position(x: 11, y: (y0 + y1) / 2)
                    dotView.position(x: 11, y: h / 2)
                }
                .frame(width: 28)
                .accessibilityHidden(true)
            }
            content
        }
        .frame(minHeight: 47)
    }

    @ViewBuilder private var dotView: some View {
        switch dot {
        case .normal:
            Circle().fill(KColor.surface).overlay(Circle().strokeBorder(KColor.ink3, lineWidth: 2.5)).frame(width: 12, height: 12)
        case .current:
            Circle().fill(KColor.brass).frame(width: 12, height: 12)
                .background(Circle().fill(KColor.brass.opacity(0.22)).frame(width: 20, height: 20))
        case .future:
            Circle().fill(KColor.surface).overlay(Circle().strokeBorder(KColor.warn, style: StrokeStyle(lineWidth: 2.5, dash: [2.5, 2]))).frame(width: 12, height: 12)
        case .new:
            Circle().fill(KColor.surface).overlay(Circle().strokeBorder(KColor.teal, style: StrokeStyle(lineWidth: 2.5, dash: [2.5, 2]))).frame(width: 12, height: 12)
        }
    }
}

/// Datum als Text, darüber unsichtbar das kompakte Datumsfeld (Web `.pdl` mit `input.pdi`): Antippen öffnet den Kalender
struct CTTimelineDateLabel<Label: View>: View {
    let day: Day
    var identifier = ""
    let onPick: (Day) -> Void
    @ViewBuilder let label: Label

    var body: some View {
        label
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                DatePicker("Gültig ab", selection: Binding(get: { day.date() }, set: { onPick(Day(date: $0)) }), displayedComponents: .date)
                    .labelsHidden()
                    .opacity(0.011)
                    .accessibilityLabel("Gültig ab")
                    .accessibilityIdentifier(identifier)
            }
    }
}

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

    /// Unterzeile «aktuell · +10 %» mit farbiger Prozentangabe (Web `.tls` + `.tlp`)
    private func subLine(_ r: PriceTimelineRow) -> Text {
        var t = Text(r.status)
        if let pc = r.pctText {
            let c = r.pctTone == .up ? KColor.warn : (r.pctTone == .down ? KColor.ok : KColor.ink3)
            let p = Text(pc).foregroundColor(c).fontWeight(.semibold)
            t = r.status.isEmpty ? p : t + Text(" · ") + p
        }
        return t
    }

    /// Betragsfeld rechts (Web `.pai`, Spalte 7.4em): Messing 16/500, rechtsbündig
    private func amountField(_ text: Binding<String>, placeholder: String, a11y: String, id: String) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(KColor.ink3))
            .font(.system(size: 16, weight: .medium))
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .foregroundStyle(KColor.teal)
            .frame(width: 118)
            .accessibilityLabel(a11y)
            .accessibilityIdentifier(id)
    }

    /// Stufe: links «ab TT.MM.JJ» (Datum änderbar) mit «aktuell · +10 %», rechts der Betrag (direkt änderbar)
    private func stepRow(_ r: PriceTimelineRow, index i: Int, tl: PriceTimeline, top: Bool) -> some View {
        CTTimelineRow(on: tl.on, top: top, dot: r.isCurrent ? .current : (r.isFuture ? .future : .normal)) {
            HStack(spacing: 6) {
                CTTimelineDateLabel(day: r.from, identifier: "form.priceDate.\(i)", onPick: { d in
                    if let m = form.setPriceRowDate(r.from, to: d) { model.toast(m) }
                }) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(r.dateText)
                            .font(.system(size: 15, weight: r.isCurrent ? .bold : .regular))
                            .foregroundStyle(KColor.ink)
                            .monospacedDigit()
                            .lineLimit(1)
                        if !r.subText.isEmpty {
                            subLine(r)
                                .font(.system(size: 12))
                                .foregroundStyle(KColor.ink3)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
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
                        VStack(alignment: .leading, spacing: 1) {
                            Text(form.priceFrom.map { "ab " + Format.fmtShort($0) } ?? "Datum")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(KColor.teal)
                                .monospacedDigit()
                            Text("neu")
                                .font(.system(size: 12))
                                .foregroundStyle(KColor.ink3)
                        }
                        .padding(.vertical, 4)
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
                VStack(alignment: .leading, spacing: 1) {
                    Text(tl.startLabel)
                        .font(.system(size: 15, weight: tl.startIsCurrent ? .bold : .regular))
                        .foregroundStyle(tl.on ? KColor.ink : KColor.ink2)
                        .monospacedDigit()
                        .lineLimit(1)
                    if !tl.startSub.isEmpty {
                        Text(tl.startSub)
                            .font(.system(size: 12))
                            .foregroundStyle(KColor.ink3)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
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
