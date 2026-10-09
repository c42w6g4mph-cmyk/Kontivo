import SwiftUI
import KontivoCore

/// Darstellung der Vertragskarte (cardHtml): «list» Standard, «cost» Monatskosten, «pay» nächste Zahlung.
enum CTCardMode: Hashable {
    case list, cost, pay
}

/// Vertragskarte: Logo/Symbol | Titel, Vertragspartner, Etiketten | Betrag
struct ContractCardRow: View {
    @Environment(AppModel.self) private var model
    let contract: Contract
    let mode: CTCardMode

    var body: some View {
        let calc = model.calc
        let data = model.data
        let paused = calc.isPaused(contract)
        let right = rightColumn(calc: calc, data: data)
        HStack(alignment: .center, spacing: 12) {
            MarkView(contract: contract, data: data, size: 40)
                .opacity(paused ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(data.title(of: contract))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                let meta = data.meta(of: contract)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .lineLimit(1)
                }
                let tags = tagTexts(calc: calc)
                if !tags.isEmpty {
                    CTFlowLayout(spacing: 4, lineSpacing: 4) {
                        ForEach(tags, id: \.self) { t in CTTag(text: t) }
                    }
                    .padding(.top, 1)
                }
            }
            .opacity(paused ? 0.5 : 1)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(right.amount)
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(KColor.ink)
                    Text(right.unit)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(KColor.ink2)
                }
                .lineLimit(1)
                if let s = right.sub {
                    Text(s)
                        .font(right.subWarn ? Font.caption.weight(.semibold) : Font.caption)
                        .foregroundStyle(right.subWarn ? KColor.warn : KColor.ink2)
                        .lineLimit(1)
                        .monospacedDigit()
                }
            }
            .opacity(paused ? 0.5 : 1)
            .layoutPriority(1)
        }
        .padding(.vertical, 2)
        .opacity(contract.status == .cancelled ? 0.6 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// Etiketten: «gekündigt per», «ab», «pausiert (bis)»
    private func tagTexts(calc: Calc) -> [String] {
        var out: [String] = []
        if let cp = contract.cancelPer { out.append("gekündigt per " + Format.fmtShort(cp)) }
        if calc.notStarted(contract) { out.append("ab " + Format.fmtShort(contract.start)) }
        if calc.isPaused(contract) {
            if let u = calc.currentPause(contract)?.until {
                out.append("pausiert bis " + Format.fmtShort(u))
            } else {
                out.append("pausiert")
            }
        }
        return out
    }

    private struct Right {
        var amount: String
        var unit: String
        var sub: String?
        var subWarn = false
    }

    private func rightColumn(calc: Calc, data: AppData) -> Right {
        let c = contract
        let home = data.settings.homeCurrency.rawValue
        switch mode {
        case .pay:
            let pd = calc.nextDue(c)
            let t = calc.today
            var r = Right(amount: Format.money(calc.priceAt(c, pd ?? t), c.currency), unit: c.currency.rawValue, sub: nil)
            if let d = pd {
                let dn = t.days(to: d)
                if dn < 0 {
                    r.sub = "am " + Format.fmtShort(d)
                } else if dn == 0 {
                    r.sub = "heute fällig"
                } else if dn <= 7 {
                    r.sub = "in \(dn)" + (dn == 1 ? " Tag" : " Tagen")
                    r.subWarn = true
                } else {
                    r.sub = "fällig " + Format.fmtShort(d)
                }
            } else {
                r.sub = "fällig " + Format.fmtShort(nil)
            }
            return r
        case .cost:
            let same = c.cycleForCalc == 1 && c.currency == data.settings.homeCurrency
            let sub = same ? "monatlich"
                : Format.money(calc.curPrice(c), c.currency) + " " + c.currency.rawValue + " " + Format.cycleTextOrMonthly(c.cycle)
            return Right(amount: Format.money(calc.monthlyCost(c)), unit: home + "/Mt.", sub: sub)
        case .list:
            let sub: String? = c.cycleForCalc != 1 ? Format.cycleText(c.cycle) : nil
            return Right(amount: Format.money(calc.curPrice(c), c.currency), unit: c.currency.rawValue, sub: sub)
        }
    }
}

// MARK: - Aktionen auf Karten (Wischen und langes Drücken, native Ergänzung)

/// Wischaktionen und Kontextmenü einer Vertragskarte: Pausieren/Fortsetzen, Duplizieren, Kündigen/Wechseln.
/// Bedingungen wie im Menü ••• des Vertragsdetails.
struct CTCardActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let contract: Contract
    @Binding var pauseTarget: CTIDItem?

    func body(content: Content) -> some View {
        let calc = model.calc
        let archived = contract.status == .cancelled
        let fixd = calc.isFixed(contract)
        let canCancel = !(contract.cancelPer != nil || archived || fixd)
        let canPause = !archived && !fixd && !contract.mandatory && !calc.isRent(contract)
        let paused = calc.isPaused(contract)
        let cancelTitle = contract.mandatory ? "Wechseln" : CTText.cancelButton(calc.cancVia(contract))
        let cancelSymbol = contract.mandatory ? "arrow.left.arrow.right" : "xmark.circle"
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if canPause {
                    Button {
                        togglePause(paused)
                    } label: {
                        Label(paused ? "Fortsetzen" : "Pausieren", systemImage: paused ? "play.fill" : "pause.fill")
                    }
                    .tint(paused ? KColor.teal : KColor.warn)
                }
                Button {
                    model.present(.contractForm(.duplicate(contract.id)))
                } label: {
                    Label("Duplizieren", systemImage: "plus.square.on.square")
                }
                .tint(KColor.ink3)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                if canCancel {
                    Button {
                        model.startCancel(contract.id, trial: false)
                    } label: {
                        Label(cancelTitle, systemImage: cancelSymbol)
                    }
                    .tint(contract.mandatory ? KColor.teal : KColor.alert)
                }
            }
            .contextMenu {
                if canCancel {
                    Button {
                        model.startCancel(contract.id, trial: false)
                    } label: {
                        Label(cancelTitle, systemImage: cancelSymbol)
                    }
                }
                if canPause {
                    Button {
                        togglePause(paused)
                    } label: {
                        Label(paused ? "Fortsetzen" : "Pausieren", systemImage: paused ? "play" : "pause")
                    }
                }
                Button {
                    model.present(.contractForm(.duplicate(contract.id)))
                } label: {
                    Label("Duplizieren", systemImage: "plus.square.on.square")
                }
                Button {
                    model.present(.contractForm(.edit(contract.id)))
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }
            }
    }

    private func togglePause(_ paused: Bool) {
        if paused {
            let t = model.today
            let id = contract.id
            if model.update({ $0.resume(id, today: t) }) { model.toast("Fortgesetzt") }
        } else {
            pauseTarget = CTIDItem(id: contract.id)
        }
    }
}
