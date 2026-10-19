import SwiftUI
import KontivoCore

// Teile des Vertragsdetails (Web 69d9888, f0e1dab, 40701ff, 4be2078, c8a6e62, v143–v160):
// Kennzahlen (Variante 4, Anteil bzw. Status), Hinweis «Angaben fehlen», Kasten «Kündigen bis …»/«Probeabo bis …»,
// Rückfrage «Schon gekündigt …».

/// Zwei Spalten im Verhältnis (Web .kz: grosse Kachel flex 1.3, rechte Spalte flex 1)
struct CTRatioRow: Layout {
    var ratio: CGFloat = 1.3
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let w = proposal.width ?? 340
        let (a, b) = widths(w)
        let h = max(subviews[0].sizeThatFits(ProposedViewSize(width: a, height: nil)).height,
                    subviews[1].sizeThatFits(ProposedViewSize(width: b, height: nil)).height)
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        let (a, b) = widths(bounds.width)
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: a, height: bounds.height))
        subviews[1].place(at: CGPoint(x: bounds.minX + a + spacing, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: b, height: bounds.height))
    }

    /// Web `flex: 1.3` / `flex: 1` mit Grundbreite 0: der Innenabstand der grossen Kachel (2 × 14) kommt zur Breite dazu
    var leadingPadding: CGFloat = 28

    private func widths(_ w: CGFloat) -> (CGFloat, CGFloat) {
        let avail = max(0, w - spacing)
        let free = max(0, avail - leadingPadding)
        let a = free * ratio / (ratio + 1) + leadingPadding
        return (a, avail - a)
    }
}

// MARK: - Kennzahlen

/// Grosse Kachel «pro Monat» (Rappen klein; Anteil an den Fixkosten als Balken bzw. ohne Anteil der Status
/// «pausiert»/«beendet»/«startet am …» mit leerem Balken, Web v154/v157), rechts «pro Jahr» und «bisher bezahlt (ca.)»
/// (ohne Beginn «nächste Zahlung»). Beträge in Vertragswährung, bei Fremdwährung ≈ Hauptwährung.
struct CTDetailKeyFigures: View {
    @Environment(AppModel.self) private var model
    let contract: Contract
    /// Anteil bzw. Status aus `Calc.detailInfo(_:).month`
    let month: DetailMonthTile

    var body: some View {
        let c = contract
        let calc = model.calc
        let home = model.data.settings.homeCurrency
        let cu = c.currency
        let fx = cu != home
        let mon = calc.curPrice(c) / Double(c.cycleForCalc)
        let paid = CTDetailKeyFigures.paidSoFar(c, calc: calc)
        let nd = calc.nextDue(c)
        let barText: String? = month.sharePercent.map { "\($0) % deiner Fixkosten" } ?? month.status
        CTRatioRow().callAsFunction {
            // Web `.kzm`: Fläche, Radius 16, 13/14, Abstand 10 (Inhalt oben/unten verteilt)
            VStack(alignment: .leading, spacing: 0) {
                Text("pro Monat")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(KColor.ink2)
                    .ctLine(17.4)
                // Web gap 10 nur einmal (Abstand im VStack käme vor und nach dem Spacer)
                Spacer(minLength: 10)
                VStack(alignment: .leading, spacing: 0) {
                    bigAmount(mon, currency: cu)
                    if fx {
                        Text(verbatim: "≈ " + Format.money0(calc.conv(mon, cu)) + " " + home.rawValue)
                            .font(.system(size: 12)).foregroundStyle(KColor.ink2)
                            .ctLine(17.4)
                            .padding(.top, 3)
                    }
                    if let t = barText {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(KColor.line)
                                if let pc = month.sharePercent {
                                    Capsule().fill(KColor.brass)
                                        .frame(width: g.size.width * CGFloat(max(2, min(100, pc))) / 100)
                                }
                            }
                        }
                        .frame(height: 6)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)
                        Text(verbatim: t)
                            .font(.system(size: 12)).foregroundStyle(KColor.ink2)
                            .ctLine(17.4)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.kz.month")
            VStack(spacing: 8) {
                tile("pro Jahr", value: Format.money0(mon * 12, cu), currency: cu.rawValue,
                     extra: fx ? "≈ " + Format.money0(calc.conv(mon * 12, cu)) + " " + home.rawValue : "")
                if let p = paid {
                    tile(month.paidLabel, value: Format.money0(p, cu), currency: cu.rawValue, extra: "")
                } else {
                    tile(DetailMonthTile.nextLabel, value: nd.map { Format.fmtShort($0) } ?? "—", currency: "", extra: "")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Summe aller Zahlungen von Vertragsbeginn bis heute in Vertragswährung (Web `paidSoFar` im Detail); nil ohne Beginn.
    /// (`Calc.paidSoFar` rechnet in die Hauptwährung um, die Kachel zeigt die Vertragswährung.)
    static func paidSoFar(_ c: Contract, calc: Calc) -> Double? {
        guard let s0 = c.start, s0 < calc.today else { return nil }
        let sum = calc.payments(c, from: s0, to: calc.today).reduce(0.0) { $0 + $1.amount }
        return sum > 0.005 ? sum : nil
    }

    /// «59» gross, «.90» bzw. «,90» klein (0.55 em, 600), Währung 12/600 System (Web v164 `.kzm b` in Serif 34/500)
    private func bigAmount(_ v: Double, currency: Currency) -> some View {
        let parts = Format.decimalSplit(Format.money(v, currency))
        return (Text(verbatim: parts.whole).font(KFont.serif(34, .medium)).tracking(-0.34)
            + Text(verbatim: parts.fraction).font(KFont.serif(18.7, .semibold))
            + Text(verbatim: " " + currency.rawValue).font(.system(size: 12, weight: .semibold)).foregroundColor(KColor.ink2))
            .foregroundStyle(KColor.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .ctLineExact(37.4)
    }

    /// Web `.kzt`: Fläche, Radius 16 (v164), 10/12, senkrecht mittig; Wert Serif 20/500, 3 darüber
    private func tile(_ label: String, value: String, currency: String, extra: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .ctLine(17.4)
            (Text(verbatim: value).font(KFont.serif(20, .medium)).tracking(-0.2)
                + Text(verbatim: currency.isEmpty ? "" : " " + currency).font(.system(size: 12, weight: .semibold)).foregroundColor(KColor.ink2))
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .ctLineExact(22)
                .padding(.top, 3)
            if !extra.isEmpty {
                Text(verbatim: extra).font(.system(size: 11)).foregroundStyle(KColor.ink2).padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(KColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hinweis «Angaben fehlen»

/// «1 Angabe fehlt noch · Logo · Kündigungsfrist – …  Ergänzen ›» → Vollständigkeit nur für diesen Vertrag
struct CTDetailCompletenessHint: View {
    @Environment(AppModel.self) private var model
    let contract: Contract

    /// Hinweis vorhanden? (für die Abstände im Detail)
    static func has(contract: Contract, model: AppModel) -> Bool {
        let f = model.files
        return Completeness.hint(contract: contract.id, data: model.data, today: model.today, hasFile: { f.has($0) }) != nil
    }

    var body: some View {
        // Kern-Vollständigkeit (inkl. «Ohne Logo» aus settings.logoSkip), Web `vkHintHtml`
        let f = model.files
        if let h = Completeness.hint(contract: contract.id, data: model.data, today: model.today, hasFile: { f.has($0) }) {
            Button {
                let id = contract.id
                model.dismissAll()
                model.presentAfterDismiss(.completeness(only: id))
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(KColor.teal)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(h.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(KColor.teal)
                        Text(h.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(KColor.ink2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Text(h.action)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KColor.teal)
                        .fixedSize()
                }
                .padding(.horizontal, 13).padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.teal.opacity(0.09))))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("detail.vkHint")
        }
    }
}

// MARK: - Kasten oben

/// Kasten aus dem Kern (Web .dfrist): «Kündigen/Wechseln bis 1. November» · «sonst verlängert bis … · noch n Tage» bzw.
/// «Probeabo bis 19. Oktober» · «danach kostenpflichtig · noch n Tage», Knöpfe «Kündigen»/«Wechseln» und «Behalten».
struct CTDetailDeadlineBox: View {
    let box: DetailDeadlineBox
    let onCancel: () -> Void
    let onKeep: () -> Void

    var body: some View {
        let alert = box.tone == .alert
        let tone = alert ? KColor.alert : KColor.warn
        VStack(alignment: .leading, spacing: 10) {
            // Web `.dfrist b` 15/700 (Zeile 21.75), `small` 12.5 (18.125, 2 darüber), Knöpfe 10 darunter, 14/600 (20.3) mit 10 Innenabstand
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: box.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tone)
                    .ctLine(21.75)
                Text(verbatim: box.subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
                    .ctLine(18.125)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 8) {
                Button(action: onCancel) {
                    Text(box.cancelTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .ctLine(20.3)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(KColor.tealFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.deadline.cancel")
                Button(action: onKeep) {
                    Text(box.keepTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(KColor.ink)
                        .ctLine(20.3)
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(KColor.ink.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("detail.deadline.keep")
            }
        }
        .padding(.horizontal, 13).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Web: color-mix(Ton 11 % bzw. 9 %, --surface)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.surface)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tone.opacity(alert ? 0.09 : 0.11))))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("detail.deadline")
    }
}

// MARK: - «Schon gekündigt …» / «Beendet …» (Web v154)

/// Rückfrage «Schon gekündigt» bzw. «Vertrag beendet» mit Feld «Läuft bis» (vorbelegt: nächster Termin, nicht kündbar: heute)
/// und Chips «heute» / «31.12.26 (Termin)». «Sichern» meldet das Datum; der Aufrufer markiert nach dem Schliessen
/// (`AppModel.cancelFlowMarkCancelled(_:trial:per:)`, Toast und bei «Nur Anbieter wechseln» das Formular «Neuer Vertragspartner»).
struct CTAlreadyCancelledSheet: View {
    let contractID: UUID
    let onSave: (Day) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var day: Day?
    @State private var saved = false

    var body: some View {
        let prompt = model.data.contract(contractID).map { model.calc.alreadyCancelledPrompt($0) }
        NavigationStack {
            Group {
                if let p = prompt {
                    form(p)
                } else {
                    Text("Dieser Vertrag existiert nicht mehr.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(prompt?.ok ?? "Sichern") {
                        guard let p = prompt, !saved else { return }
                        saved = true
                        onSave(day ?? p.defaultDate)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(prompt == nil)
                    .accessibilityIdentifier("detail.cancelled.save")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func form(_ p: AlreadyCancelledPrompt) -> some View {
        let sel = day ?? p.defaultDate
        return Form {
            Section {
                DatePicker(p.fieldLabel, selection: Binding(get: { sel.date() }, set: { day = Day(date: $0) }), displayedComponents: .date)
                    .accessibilityIdentifier("detail.cancelled.date")
                HStack(spacing: 8) {
                    ForEach(Array(p.chips.enumerated()), id: \.offset) { i, ch in
                        Chip(title: ch.title, isOn: sel == ch.day) { day = ch.day }
                            .accessibilityIdentifier("detail.cancelled.chip\(i)")
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text(p.text)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .textCase(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 6)
            }
            .listRowBackground(KColor.surface)
        }
        .scrollContentBackground(.hidden)
        .background(KColor.paper.ignoresSafeArea())
        .navigationTitle(p.title)
    }
}

/// Zielvertrag für «Schon gekündigt …» und gewähltes «Läuft bis»; markiert nach dem Schliessen des Fensters.
private struct CTAlreadyCancelledModifier: ViewModifier {
    @Binding var target: CTIDItem?
    @Environment(AppModel.self) private var model
    @State private var chosen: (id: UUID, day: Day)?

    func body(content: Content) -> some View {
        content.sheet(item: $target, onDismiss: run) { t in
            CTAlreadyCancelledSheet(contractID: t.id) { d in chosen = (id: t.id, day: d) }
                .environment(model)
                .environment(\.locale, Locale(identifier: "de_CH"))
        }
    }

    private func run() {
        guard let c = chosen else { return }
        chosen = nil
        model.cancelFlowMarkCancelled(c.id, trial: false, per: c.day)
    }
}

extension View {
    /// «Schon gekündigt …» / «Beendet …» für den Vertrag in `target` (Detail-Menü, Vertragskarten).
    func ctAlreadyCancelledSheet(_ target: Binding<CTIDItem?>) -> some View {
        modifier(CTAlreadyCancelledModifier(target: target))
    }
}
