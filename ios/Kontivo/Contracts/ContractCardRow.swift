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
        // Web `.card`: padding 9 8 9 6, Abstand 10, Kachel 50 (Radius 12); pausiert: Kachel, Titel, Betrag 50 %
        HStack(alignment: .center, spacing: 10) {
            MarkView(contract: contract, data: data, size: 50)
                .opacity(paused ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 0) {
                // Titel 14.5/600 gerundet, lange Titel bis 13 px verkleinern, dann «…» (Web `fitQ`)
                Text(data.title(of: contract))
                    .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(13 / 14.5)
                    .ctLine(18.125)
                    .padding(.bottom, 1)
                    .opacity(paused ? 0.5 : 1)
                let meta = data.meta(of: contract)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(KColor.ink2)
                        .lineLimit(1)
                        .ctLine(17.4)
                }
                ForEach(tagTexts(calc: calc), id: \.self) { t in
                    CTTag(text: t).padding(.top, 3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(right.amount)
                        .font(.system(size: 15, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(KColor.ink)
                    Text(right.unit)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(KColor.ink2)
                }
                .lineLimit(1)
                .ctLine(21.75)
                if let s = right.sub {
                    Text(s)
                        .font(.system(size: 10.5, weight: right.subWarn ? .semibold : .regular))
                        .foregroundStyle(right.subWarn ? KColor.warn : (right.subMuted ? KColor.ink3 : KColor.ink2))
                        .lineLimit(1)
                        .monospacedDigit()
                        .ctLine(15.225)
                }
            }
            .opacity(paused ? 0.5 : 1)
            .fixedSize()
        }
        .padding(.top, 9).padding(.bottom, 9).padding(.leading, 6).padding(.trailing, 8)
        .frame(minHeight: 68)
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
        /// Web `.due` (Fälligkeit, Tinte 3)
        var subMuted = false
    }

    private func rightColumn(calc: Calc, data: AppData) -> Right {
        let c = contract
        let home = data.settings.homeCurrency.rawValue
        switch mode {
        case .pay:
            let pd = calc.nextDue(c)
            let t = calc.today
            var r = Right(amount: Format.money(calc.priceAt(c, pd ?? t), c.currency), unit: c.currency.rawValue, sub: nil)
            r.subMuted = true
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

/// Wischaktionen und Kontextmenü einer Vertragskarte: Kündigen/Wechseln, Pausieren/Fortsetzen, Duplizieren, Bearbeiten,
/// «Schon gekündigt …»/«Beendet …» bzw. «Wieder aktiv setzen». Regeln wie im Menü ••• des Vertragsdetails (`Calc.detailMenu`):
/// keine Pause bei «Nur Anbieter wechseln», Miete und nicht kündbaren, beendete Verträge nur Duplizieren/Wieder aktiv.
struct CTCardActions: ViewModifier {
    @Environment(AppModel.self) private var model
    let contract: Contract
    @Binding var pauseTarget: CTIDItem?
    /// «Schon gekündigt …» / «Beendet …» (Rückfrage «Läuft bis» in ContractsTab)
    @Binding var cancelledTarget: CTIDItem?

    func body(content: Content) -> some View {
        let calc = model.calc
        let m = calc.detailMenu(contract)
        let trial = calc.trialOn(contract)
        let paused = calc.isPaused(contract)
        let cancelTitle = contract.mandatory ? "Wechseln" : CTText.cancelButton(calc.cancVia(contract))
        let cancelSymbol = contract.mandatory ? "arrow.left.arrow.right" : "xmark.circle"
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if m.pause != nil {
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
                if m.cancel != nil {
                    Button {
                        model.startCancel(contract.id, trial: trial)
                    } label: {
                        Label(cancelTitle, systemImage: cancelSymbol)
                    }
                    .tint(contract.mandatory ? KColor.teal : KColor.alert)
                }
            }
            .contextMenu {
                if m.cancel != nil {
                    Button {
                        model.startCancel(contract.id, trial: trial)
                    } label: {
                        Label(cancelTitle, systemImage: cancelSymbol)
                    }
                }
                if m.pause != nil {
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
                if m.reactivate {
                    Button {
                        model.ctReactivate(contract.id)
                    } label: {
                        Label("Wieder aktiv setzen", systemImage: "arrow.uturn.backward")
                    }
                } else if let a = m.alreadyCancelled {
                    Button {
                        cancelledTarget = CTIDItem(id: contract.id)
                    } label: {
                        Label(a.title, systemImage: "checkmark.circle")
                    }
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
