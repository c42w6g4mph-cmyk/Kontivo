import SwiftUI
import KontivoCore

// Teile des Vertragsdetails (Web 69d9888, f0e1dab, 40701ff, 4be2078, c8a6e62):
// Kennzahlen (Variante 4), Hinweis «Angaben fehlen», Fristen-Kasten «Kündigen bis …».

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

    private func widths(_ w: CGFloat) -> (CGFloat, CGFloat) {
        let avail = max(0, w - spacing)
        let a = (avail * ratio / (ratio + 1)).rounded(.down)
        return (a, avail - a)
    }
}

// MARK: - Kennzahlen

/// Grosse Kachel «pro Monat» (Rappen klein, Anteil an den Fixkosten als Balken), rechts «pro Jahr» und
/// «insgesamt bezahlt» (ohne Beginn «nächste Zahlung»). Beträge in Vertragswährung, bei Fremdwährung ≈ Hauptwährung.
struct CTDetailKeyFigures: View {
    @Environment(AppModel.self) private var model
    let contract: Contract

    var body: some View {
        let c = contract
        let calc = model.calc
        let home = model.data.settings.homeCurrency
        let cu = c.currency
        let fx = cu != home
        let mon = calc.curPrice(c) / Double(c.cycleForCalc)
        let paid = CTDetailKeyFigures.paidSoFar(c, calc: calc)
        let nd = calc.nextDue(c)
        let share = CTDetailKeyFigures.share(c, calc: calc)
        CTRatioRow().callAsFunction {
            VStack(alignment: .leading, spacing: 10) {
                Text("pro Monat")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(KColor.ink2)
                VStack(alignment: .leading, spacing: 3) {
                    bigAmount(mon, currency: cu)
                    if fx {
                        Text(verbatim: "≈ " + Format.money0(calc.conv(mon, cu)) + " " + home.rawValue)
                            .font(.caption).foregroundStyle(KColor.ink2)
                    }
                    if let pc = share {
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(KColor.line)
                                Capsule().fill(KColor.teal)
                                    .frame(width: g.size.width * CGFloat(max(2, min(100, pc))) / 100)
                            }
                        }
                        .frame(height: 6)
                        .padding(.top, 7)
                        .accessibilityHidden(true)
                        Text(verbatim: "\(pc) % deiner Fixkosten")
                            .font(.caption).foregroundStyle(KColor.ink2)
                            .padding(.top, 3)
                    }
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(KColor.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.kz.month")
            VStack(spacing: 8) {
                tile("pro Jahr", value: Format.money0(mon * 12, cu), currency: cu.rawValue,
                     extra: fx ? "≈ " + Format.money0(calc.conv(mon * 12, cu)) + " " + home.rawValue : "")
                if let p = paid {
                    tile("insgesamt bezahlt", value: Format.money0(p, cu), currency: cu.rawValue, extra: "")
                } else {
                    tile("nächste Zahlung", value: nd.map { Format.fmtShort($0) } ?? "—", currency: "", extra: "")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 2)
        .padding(.bottom, 12)
    }

    /// Summe aller Zahlungen von Vertragsbeginn bis heute in Vertragswährung (Web `paidSoFar` im Detail); nil ohne Beginn.
    /// (`Calc.paidSoFar` rechnet in die Hauptwährung um, die Kachel zeigt die Vertragswährung.)
    static func paidSoFar(_ c: Contract, calc: Calc) -> Double? {
        guard let s0 = c.start, s0 < calc.today else { return nil }
        let sum = calc.payments(c, from: s0, to: calc.today).reduce(0.0) { $0 + $1.amount }
        return sum > 0.005 ? sum : nil
    }

    /// Anteil an den monatlichen Fixkosten in % (nur laufend, nicht pausiert, begonnen)
    static func share(_ c: Contract, calc: Calc) -> Int? {
        if CTDetailState.gone(c, calc: calc) || calc.isPaused(c) || calc.notStarted(c) { return nil }
        let tot = calc.running.filter { !calc.notStarted($0) }.reduce(0.0) { $0 + calc.monthlyCost($1) }
        guard tot > 0.005 else { return nil }
        return Int(Format.jsRound(calc.monthlyCost(c) / tot * 100))
    }

    /// «59» gross, «.90» bzw. «,90» klein, Währung klein (Web decAt)
    private func bigAmount(_ v: Double, currency: Currency) -> some View {
        let parts = Format.decimalSplit(Format.money(v, currency))
        let intPart = parts.whole
        let decPart = parts.fraction
        return (Text(verbatim: intPart).font(.system(size: 34, weight: .bold))
            + Text(verbatim: decPart).font(.system(size: 19, weight: .semibold))
            + Text(verbatim: " " + currency.rawValue).font(.caption.weight(.semibold)).foregroundStyle(KColor.ink2))
            .foregroundStyle(KColor.ink)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private func tile(_ label: String, value: String, currency: String, extra: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(KColor.ink2)
            (Text(verbatim: value).font(.system(size: 20, weight: .bold))
                + Text(verbatim: currency.isEmpty ? "" : " " + currency).font(.caption.weight(.semibold)).foregroundStyle(KColor.ink2))
                .foregroundStyle(KColor.ink)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !extra.isEmpty {
                Text(verbatim: extra).font(.caption2).foregroundStyle(KColor.ink2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(KColor.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hinweis «Angaben fehlen»

/// «1 Angabe fehlt noch · Logo · Kündigungsfrist – …  Ergänzen ›» → Vollständigkeit nur für diesen Vertrag
struct CTDetailCompletenessHint: View {
    @Environment(AppModel.self) private var model
    let contract: Contract

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
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KColor.teal)
                        Text(h.detail)
                            .font(.footnote)
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
                .background(KColor.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2).padding(.bottom, 10)
            .accessibilityIdentifier("detail.vkHint")
        }
    }
}

// MARK: - Fristen-Kasten

/// Nur bei Frist in ≤ 60 Tagen (Web .dfrist): «Kündigen bis 1. November» · «sonst verlängert bis …» · «noch n Tage»,
/// Knöpfe «Kündigen»/«Wechseln» und «Behalten».
struct CTDetailDeadlineBox: View {
    @Environment(AppModel.self) private var model
    let contract: Contract
    let onCancel: () -> Void
    let onKeep: () -> Void

    var body: some View {
        let c = contract
        let calc = model.calc
        let u = calc.urgency(c)
        if let D = u.date, let T = calc.termEnd(c), let dn = u.days {
            let rt = CTDetailState.gone(c, calc: calc) ? nil : calc.renewTo(c)
            let alert = dn <= 7
            let tone = alert ? KColor.alert : KColor.warn
            let title = (c.mandatory ? "Wechseln bis " : "Kündigen bis ") + "\(D.day). " + Format.monthNames[D.month - 1]
                + (D.year != calc.today.year ? " \(D.year)" : "")
            let sub = (rt.map { "sonst verlängert bis " + Format.fmtShort($0) } ?? "Vertragsende " + Format.fmtShort(T))
                + " · " + (dn == 0 ? "heute" : "noch \(dn)" + (dn == 1 ? " Tag" : " Tage"))
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(tone)
                    Text(verbatim: sub)
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                }
                .accessibilityElement(children: .combine)
                HStack(spacing: 8) {
                    Button(action: onCancel) {
                        Text(c.mandatory ? "Wechseln" : "Kündigen")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(KColor.teal, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail.deadline.cancel")
                    Button(action: onKeep) {
                        Text("Behalten")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(KColor.ink)
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(KColor.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("detail.deadline.keep")
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(alert ? 0.09 : 0.11), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 2).padding(.bottom, 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("detail.deadline")
        }
    }
}
