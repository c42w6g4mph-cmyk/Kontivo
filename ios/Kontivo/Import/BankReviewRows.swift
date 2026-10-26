import SwiftUI
import KontivoCore

// MARK: - Zeilen der Vorschlagsliste (Web bkRow, bkIncRow, bkPriceRow, bkKnownRow, bkKnownIncRow, Stand v330)
// `.bkr`: Innenabstand 14 links / 12 rechts; Kachel 36 pt mit Haken-Abzeichen; Plaketten 47 pt eingerückt; Zahlungen, Ja/Nein und
// Rückfrage-Box als eigene Blöcke darunter (Abstand 10, unten 12).

/// Text-Block `.bktx`: Titel 15.5 pt halbfett (umbrechend), Unterzeile 12.5 pt ink2
struct BankRowText: View {
    let title: String
    let sub: String
    var off = false
    var known = false
    /// keine Bezeichnung erkannt (Web `.bknol`): Titel «Ohne Bezeichnung» in Akzentfarbe, wird nie gespeichert
    var noLabel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .lineSpacing(BankType.extra(15.5, 19.375))
                .padding(.vertical, BankType.halfLeading(15.5, 19.375))
                .foregroundStyle(off ? KColor.ink3 : (noLabel ? KColor.teal : (known ? KColor.ink2 : KColor.ink)))
                .fixedSize(horizontal: false, vertical: true)
            if !sub.isEmpty {
                Text(sub)
                    .font(.system(size: 12.5))
                    .lineSpacing(BankType.extra(12.5, 16.25))
                    .padding(.vertical, BankType.halfLeading(12.5, 16.25))
                    .foregroundStyle(KColor.ink2)
                    .opacity(off ? 0.6 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Betrag `.bkam`: 15.5 pt halbfett (Tabellenziffern), darunter «CHF pro Monat» 11 pt
struct BankAmount: View {
    let value: Double
    let currency: String
    let per: String
    var dim = false
    var known = false

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Format.money(value, Currency(rawValue: currency)))
                .font(.system(size: 15.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(dim ? KColor.ink3 : (known ? KColor.ink2 : KColor.ink))
                .kLineHeight(15.5, 22.475)
            Text(currency + " " + per)
                .font(.system(size: 11))
                .foregroundStyle(KColor.ink2)
                .kLineHeight(11, 15.95)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

struct BankChevron: View {
    var body: some View {
        Text("›")
            .font(.system(size: 18))
            .foregroundStyle(KColor.ink3)
            .padding(.leading, 2)
            .padding(.top, 1)
            .accessibilityHidden(true)
    }
}

/// Block unter der Kopfzeile, 47 pt eingerückt (Kachel 36 + Abstand 11), Abstand 10 nach oben, 12 nach unten
private struct BankBelow: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.leading, 47).padding(.top, 10).padding(.bottom, 12)
    }
}

extension View {
    func bankBelow() -> some View { modifier(BankBelow()) }
}

/// Neuer Vertrag (Web `bkRow`): Haken am Logo (bei «gehört das dazu?» stattdessen Ja/Nein), Plaketten, Zahlungen, Rückfrage
struct BankItemRow: View {
    @Bindable var review: BankReview
    let it: BankReview.Item
    let open: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        let maybe = it.s.confidence == .low
        let title = review.title(it)
        let cat = d.category(it.ed.categoryID) ?? d.otherCategory
        let color: String = cat?.displayColorHex ?? KCategory.displayFallbackColor
        let mark = MarkView(logoID: it.logo?.id, logoBg: it.logo?.bg, colorHex: color, symbol: KIcon.symbol(for: cat), size: 36)
        let r = review, id = it.id
        let toggle: (() -> Void)? = maybe ? nil : { r.toggle(id) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                BankMarkBadge(mark: mark, on: it.on, dim: !it.on, badge: !maybe, label: title + " übernehmen", toggle: toggle)
                    .accessibilityIdentifier("bankCheck-" + it.s.name)
                Button(action: open) {
                    HStack(alignment: .top, spacing: 11) {
                        // keine Bezeichnung erkannt (Web v331 ff., Entscheid Sinan): «Ohne Bezeichnung», Vertragspartner darunter
                        if it.ed.label.isEmpty {
                            BankRowText(title: "Ohne Bezeichnung", sub: it.ed.name, off: !it.on, noLabel: true)
                        } else {
                            BankRowText(title: title, sub: review.sub(it, d), off: !it.on)
                        }
                        BankAmount(value: it.ed.amount, currency: it.s.currency, per: BankReview.per(it.ed.cycle) + (maybe ? "?" : ""), dim: !it.on)
                        BankChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bankRow-" + it.s.name)
            }
            .padding(.top, 11)
            BankChipsRow(chips: review.chips(it), expanded: it.pay, id: it.s.name) {
                withAnimation(.easeInOut(duration: 0.2)) { review.togglePay(it.id) }
            }
            .opacity(it.on ? 1 : 0.6)
            .padding(.leading, 47)
            .padding(.top, 8)
            .padding(.bottom, 11)
            if it.pay {
                BankPayList(rows: BankImport.payRows(dates: it.s.dates, amounts: it.s.amounts, cycle: it.s.cycle, income: false),
                            currency: it.s.currency, all: it.payAll) { review.showAllPay(it.id) }
                    .bankBelow()
            }
            if maybe {
                HStack(spacing: 8) {
                    BankYesNo(title: "Ja, übernehmen", on: it.on) { withAnimation { review.setOn(it.id, true) } }
                        .accessibilityIdentifier("bankYes-" + it.s.name)
                    BankYesNo(title: "Nein", on: !it.on) { withAnimation { review.setOn(it.id, false) } }
                }
                .bankBelow()
            }
            dupBox(d)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }

    /// Rückfrage «Derselbe Vertrag?» bzw. «ist im Archiv» (Web `bkDupBox`)
    @ViewBuilder private func dupBox(_ d: AppData) -> some View {
        if let cid = it.s.archived ?? it.s.sameAs, let c = d.contract(cid) {
            let pn: String = d.partnerName(of: c)
            let both: Bool = !c.label.isEmpty && !pn.isEmpty && Partners.lnorm(c.label) != Partners.lnorm(pn)
            let nm: String = both ? "\(d.title(of: c)) · \(pn)" : d.title(of: c)
            let arch: Bool = it.s.archived != nil
            let lastDay: String = BankReview.day(it.s.last)
            let head: String = BankImport.archiveEnd(c).map { "Gekündigt per \(BankReview.day($0)), wurde" } ?? "Wurde"
            let price: String = Format.money(model.calc.curPrice(c), c.currency)
            let title: String = arch ? "«\(nm)» ist im Archiv" : "Gleicher Betrag wie «\(nm)»"
            let text: String = arch ? "\(head) aber am \(lastDay) noch bezahlt." : "\(price) \(c.currency.rawValue). Derselbe Vertrag?"
            BankAskBox(title: title, text: text, yes: arch ? "Wieder aktivieren" : "Ja, schon erfasst", no: arch ? "Neu anlegen" : "Nein, neu",
                       answer: it.q == "y" ? true : it.q == "n" ? false : nil, id: it.s.name,
                       onYes: { withAnimation { review.answerDup(it.id, yes: true, model: model) } },
                       onNo: { withAnimation { review.answerDup(it.id, yes: false, model: model) } })
                .bankBelow()
        }
    }
}

/// Einnahme (Web `bkIncRow`): Haken am Logo, Plaketten, Zahlungen, Nachfrage bei abweichender letzter Gutschrift
struct BankIncRow: View {
    @Bindable var review: BankReview
    let it: BankReview.IncItem
    let open: () -> Void

    var body: some View {
        let title = review.incTitle(it)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                BankMarkBadge(mark: MarkView(logoID: it.logo?.id, logoBg: it.logo?.bg, colorHex: it.ed.kind.colorHex,
                                             symbol: KIcon.symbol(forKey: it.ed.kind.icon), size: 36),
                              on: it.on, dim: !it.on, label: title + " übernehmen", toggle: { review.toggleInc(it.id) })
                    .accessibilityIdentifier("bankIncCheck-" + it.s.name)
                Button(action: open) {
                    HStack(alignment: .top, spacing: 11) {
                        BankRowText(title: title, sub: review.incSub(it), off: !it.on)
                        BankAmount(value: review.incAmount(it), currency: it.s.currency, per: BankReview.per(it.ed.cycle), dim: !it.on)
                        BankChevron()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bankIncRow-" + it.s.name)
            }
            .padding(.top, 11)
            BankChipsRow(chips: review.chips(it), expanded: it.pay, id: it.s.name) {
                withAnimation(.easeInOut(duration: 0.2)) { review.togglePay(it.id) }
            }
            .opacity(it.on ? 1 : 0.6)
            .padding(.leading, 47)
            .padding(.top, 8)
            .padding(.bottom, 11)
            if it.pay {
                BankPayList(rows: BankImport.payRows(dates: it.s.dates, amounts: it.s.amounts, cycle: it.s.cycle, income: true),
                            currency: it.s.currency, all: it.payAll) { review.showAllPay(it.id) }
                    .bankBelow()
            }
            if let v = review.deviation(it) {
                let cur = Currency(rawValue: it.s.currency)
                let wage: Bool = review.isWage(it)
                let day6: String = String(BankReview.day(v.date).prefix(6))
                let got: String = Format.money(v.amount, cur), diff: String = Format.money(Swift.abs(v.diff), cur)
                let more: String = v.diff > 0 ? "mehr" : "weniger"
                let than: String = wage ? "als dein Lohn bisher." : "als bisher."
                BankAskBox(title: "Am \(day6) kamen \(got)", text: "\(diff) \(more) \(than)",
                           yes: "Einmalig", no: wage ? "Neuer Lohn" : "Neuer Betrag", answer: !it.nl, id: it.s.name,
                           onYes: { withAnimation { review.setNewLevel(it.id, false) } },
                           onNo: { withAnimation { review.setNewLevel(it.id, true) } })
                    .bankBelow()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }
}

/// Neuer Preis bei einem erfassten Vertrag (Web `bkPriceRow`)
struct BankPriceRowView: View {
    @Bindable var review: BankReview
    let p: BankReview.PriceRow
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        if let c = d.contract(p.m.contractID) {
            let cur = c.currency
            let title: String = d.title(of: c) + (p.m.amount > p.m.old ? " ist teurer" : " ist günstiger")
            let old: String = Format.money(p.m.old, cur), new: String = Format.money(p.m.amount, cur)
            let sub: String = "\(old) → \(new) \(cur.rawValue) ab \(BankReview.day(p.m.from))"
            HStack(alignment: .top, spacing: 11) {
                BankMarkBadge(mark: MarkView(contract: c, data: d, size: 36), on: p.on, dim: !p.on,
                              label: "Neuen Preis für \(d.partnerName(of: c)) übernehmen", toggle: { review.togglePrice(p.id) })
                BankRowText(title: title, sub: sub, off: !p.on)
            }
            .padding(.vertical, 11)
            .padding(.leading, 14)
            .padding(.trailing, 12)
        }
    }
}

/// Schon erfasster Vertrag (Web `bkKnownRow`): Haken am Logo, «unverändert», «im Auszug gefunden» bzw. «gekündigt per …»
struct BankKnownRow: View {
    let k: BankKnown
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        if let c = d.contract(k.contractID) {
            let end: String = BankImport.archiveEnd(c).map { BankReview.day($0) } ?? ""
            let sub: String = k.archived ? "gekündigt per \(end) · letzte Zahlung \(BankReview.day(k.suggestion.last))"
                : (k.loose ? "im Auszug gefunden" : "unverändert")
            HStack(alignment: .top, spacing: 11) {
                BankMarkBadge(mark: MarkView(contract: c, data: d, size: 36), badge: false, known: true)
                BankRowText(title: d.title(of: c), sub: sub, known: true)
                BankAmount(value: model.calc.curPrice(c), currency: c.currency.rawValue, per: BankReview.per(c.cycle == 0 ? 1 : c.cycle), known: true)
            }
            .padding(.vertical, 11)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Schon erfasste Einnahme (Web v281 `bkKnownIncRow`): «Lohn · bereits erfasst»
struct BankKnownIncRow: View {
    let k: BankIncomeKnown
    @Environment(AppModel.self) private var model

    var body: some View {
        if let c = model.data.income(k.incomeID) {
            let t: String = c.label.isEmpty ? c.name : c.label
            let both: Bool = !c.label.isEmpty && !c.name.isEmpty && Partners.lnorm(c.label) != Partners.lnorm(c.name)
            let sub: String = both ? "\(c.name) · bereits erfasst" : "bereits erfasst"
            HStack(alignment: .top, spacing: 11) {
                BankMarkBadge(mark: MarkView(income: c, size: 36), badge: false, known: true)
                BankRowText(title: t, sub: sub, known: true)
                BankAmount(value: model.calc.curPrice(c), currency: c.currency.rawValue, per: c.cycle == 0 ? "einmalig" : BankReview.per(c.cycle), known: true)
            }
            .padding(.vertical, 11)
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("bankKnownInc-" + t)
        }
    }
}

/// Fehlende Kündigungsfrist (Web Schritt «term»): Schnellwahl 1 Monat · 3 Monate · nicht kündbar · weiss nicht
struct BankTermRow: View {
    @Bindable var review: BankReview
    let it: BankReview.Item
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        let t = review.title(it)
        let cat = d.category(it.ed.categoryID) ?? d.otherCategory
        let choices: [(String, String)] = [("1", "1 Monat"), ("3", "3 Monate"), ("x", "nicht kündbar"), ("", "weiss nicht")]
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                MarkView(logoID: it.logo?.id, logoBg: it.logo?.bg, colorHex: cat?.displayColorHex ?? KCategory.displayFallbackColor,
                         symbol: KIcon.symbol(for: cat), size: 36)
                BankRowText(title: t, sub: it.ed.name != t ? it.ed.name : review.categoryName(it, d))
            }
            .padding(.top, 11)
            .padding(.bottom, 6)
            // `.bkr` ist ein umbrechender Flex-Container mit gap 10: die Chips-Zeile steht 10 pt unter dem Kopf
            BankFlow(spacing: 6) {
                ForEach(choices.indices, id: \.self) { j in
                    BankTermChip(title: choices[j].1, on: it.term == choices[j].0) { review.setTerm(it.id, choices[j].0) }
                }
            }
            .padding(.leading, 47)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kündigungsfrist " + t)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }
}
