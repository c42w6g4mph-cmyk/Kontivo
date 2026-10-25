import SwiftUI
import KontivoCore

/// Vorschläge prüfen (Web `paintBank`, Stand v330): geführte Schritte mit Fortschrittsbalken.
/// 1. Fixkosten: «Sind das deine Fixkosten?» – «bucht weiter ab», Hinweis kurzer Zeitraum, Kopfkarte, «Zuordnen an», neuer Preis bei
///    erfassten Verträgen, neu gefunden, «Nur einmal im Auszug» bzw. «Unsicher» (Ja/Nein), schon erfasste und ausgeblendete aufklappbar
/// 2. Einnahmen: «Und deine Einnahmen?» mit Kopfkarte, «Bereits in Kontivo»
/// 3. Fristen: «Noch n Kündigungsfristen» mit Schnellwahl 1 Monat · 3 Monate · nicht kündbar · weiss nicht
/// Haken am Logo wählt aus; Antippen der Zeile öffnet das normale Formular («Vorschlag»). Zeilen: `BankReviewRows.swift`.
struct BankReviewView: View {
    @Bindable var review: BankReview
    let privacy: String
    @Environment(AppModel.self) private var model

    var body: some View {
        let d = model.data
        let st = review.steps(d)
        let step = review.currentStep(d)
        let si = review.stepIndex(d)
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 0).id("bkTop")
                    if st.count > 1 { stepBar(st.count, si) }
                    switch step {
                    case .fix: fixStep(d)
                    case .inc: incStep(d, first: st.first == .inc)
                    case .term: termStep(d)
                    }
                    if step == st.last { privNote }
                }
                .padding(.horizontal, 17)
                .padding(.top, 2)
                .padding(.bottom, 10)
                .frame(maxWidth: KMetric.maxContent)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: review.step) { _, _ in proxy.scrollTo("bkTop", anchor: .top) }
        }
        .accessibilityIdentifier("bankReview")
    }

    // MARK: Bausteine

    /// `.bksteps2`: Balken 3 pt, Abstand 6, Messing bis zum aktuellen Schritt
    private func stepBar(_ n: Int, _ si: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<n, id: \.self) { j in
                RoundedRectangle(cornerRadius: 2).fill(j <= si ? KColor.brass : KColor.line).frame(height: 3)
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 14)
        .accessibilityElement()
        .accessibilityLabel("Schritt \(si + 1) von \(n)")
    }

    /// `h3.bkt`: 24 pt halbfett, Laufweite −0.012em, Zeilenhöhe 34.8
    private func heading(_ t: String) -> some View {
        Text(t)
            .font(KFont.title(24))
            .tracking(-0.288)
            .foregroundStyle(KColor.ink)
            .padding(.vertical, BankType.halfLeading(24, 34.8))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("bankStepTitle")
    }

    /// `.bki`: 14 pt, Zeilenhöhe 1.4, ink2 (`.bkspan`: Warnfarbe)
    private func intro(_ t: String, warn: Bool = false) -> some View {
        Text(t)
            .font(.system(size: 14))
            .lineSpacing(BankType.extra(14, 19.6))
            .foregroundStyle(warn ? KColor.warn : KColor.ink2)
            .padding(.vertical, BankType.halfLeading(14, 19.6))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
    }

    /// `.sheet h4.bkh2`: 13 pt halbfett ink2, Anzahl rechts. Rand oben 16 fällt im Web mit dem unteren Rand des
    /// Vorgängers zusammen (Liste 6, «Zuordnen an» 12, Kopfkarte 14) → `after` = dieser Rand
    private func head(_ t: String, _ n: Int, after: CGFloat = 6) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(t)
            Spacer(minLength: 0)
            Text("\(n)")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(KColor.ink2)
        .kLineHeight(13, 18.85)
        .padding(.horizontal, 4)
        .padding(.top, Swift.max(0, 16 - after))
        .padding(.bottom, 6)
    }

    /// `.bklist`: weisse Fläche, Radius 16, Trennlinien ab 61 pt
    private func list<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 6)
    }

    @ViewBuilder private func separator(_ first: Bool) -> some View {
        if !first {
            Rectangle().fill(KColor.line).frame(height: 1).padding(.leading, 61)
        }
    }

    /// `.bkshow`: Messing, 14 pt halbfett
    private func showButton(_ t: String, top: CGFloat = 0, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(KColor.teal)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, top)
        .accessibilityIdentifier(id)
    }

    /// `.bkload2`: «Logos werden gesucht … x von y»
    @ViewBuilder private var logoLine: some View {
        if review.logoTotal > 0 && review.logoDone < review.logoTotal {
            HStack(spacing: 8) {
                BankSpinner(size: 12, line: 2, period: 0.9, top: KColor.brass, track: KColor.line)
                Text("Logos werden gesucht … \(review.logoDone) von \(review.logoTotal)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(KColor.ink2)
            }
            .padding(.top, -4)
            .padding(.bottom, 10)
        }
    }

    private var privNote: some View {
        Text(privacy)
            .font(.system(size: 12.5))
            .lineSpacing(BankType.extra(12.5, 19.375))
            .foregroundStyle(KColor.ink3)
            .padding(.vertical, BankType.halfLeading(12.5, 19.375))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    // MARK: «Zuordnen an» (Web `bkWhoBar`)

    @ViewBuilder private func whoBar(_ d: AppData) -> some View {
        if review.showsWhoBar(d) {
            let cur = review.commonHolder
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("Zuordnen an")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(KColor.ink)
                        .fixedSize()
                    BankSegment(options: d.persons.map { ($0.id, $0.name) }, selected: cur) { p in
                        withAnimation(.easeInOut(duration: 0.15)) { review.assignAll(p) }
                    }
                }
                Text(review.whoReason(d))
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink2)
                    .kLineHeight(12, 17.4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.surface))
            .padding(.bottom, 12)
            .accessibilityIdentifier("bankWho")
        }
    }

    // MARK: Schritt 1: Fixkosten

    @ViewBuilder private func fixStep(_ d: AppData) -> some View {
        let vis = review.items.indices.filter { review.showIgnored || !review.items[$0].s.ignored }
        let mo: (Int) -> Double = { i in review.items[i].ed.amount / Double(Swift.max(1, review.items[i].ed.cycle)) }
        let sure = vis.filter { review.items[$0].s.confidence != .low }.enumerated()
            .sorted { a, b in mo(a.element) != mo(b.element) ? mo(a.element) > mo(b.element) : a.offset < b.offset }.map { $0.element }
        let maybe = vis.filter { review.items[$0].s.confidence == .low }
        let nIgn = review.items.filter { $0.s.ignored }.count
        let known = review.result.known
        let hasHero = !vis.isEmpty || !review.prices.isEmpty
        heading(sure.isEmpty && maybe.isEmpty ? "Keine neuen Fixkosten" : "Sind das deine Fixkosten?")
        ForEach(Array(review.result.after.enumerated()), id: \.offset) { _, a in afterWarning(a, d) }
        if let t = review.shortSpanText { intro(t, warn: true).accessibilityIdentifier("bankShortSpan") }
        if hasHero { BankHeroCard(hero: review.hero(d, income: false), income: false) }
        logoLine
        whoBar(d)
        let before: CGFloat = review.showsWhoBar(d) ? 12 : (hasHero ? 14 : 12)
        if !review.prices.isEmpty {
            head("Neuer Preis bei erfassten Verträgen", review.prices.count, after: before)
            list {
                ForEach(Array(review.prices.enumerated()), id: \.element.id) { k, p in
                    separator(k == 0)
                    BankPriceRowView(review: review, p: p)
                }
            }
        }
        if !sure.isEmpty {
            if !review.prices.isEmpty { head("Neu gefunden", sure.count) }
            list {
                ForEach(Array(sure.enumerated()), id: \.element) { k, i in
                    separator(k == 0)
                    BankItemRow(review: review, it: review.items[i]) { open(review.items[i]) }
                }
            }
        }
        if !maybe.isEmpty {
            let once = maybe.allSatisfy { review.items[$0].s.count == 1 }
            head((once ? "Nur einmal im Auszug" : "Unsicher") + " – gehört das dazu?", maybe.count,
                 after: sure.isEmpty && review.prices.isEmpty ? before : 6)
            list {
                ForEach(Array(maybe.enumerated()), id: \.element) { k, i in
                    separator(k == 0)
                    BankItemRow(review: review, it: review.items[i]) { open(review.items[i]) }
                }
            }
        }
        if vis.isEmpty && review.prices.isEmpty {
            Text(known.isEmpty
                 ? "Wiederkehrende Zahlungen werden erst erkannt, wenn sie mindestens zweimal im Auszug stehen. Am besten einen Auszug über 6–12 Monate exportieren."
                 : "Alle wiederkehrenden Zahlungen sind schon erfasst.")
                .font(.system(size: 12.5))
                .lineSpacing(BankType.extra(12.5, 19.375))
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
        }
        if !known.isEmpty {
            let knownText: String = known.count == 1 ? "1 Vertrag ist schon in Kontivo ›" : "\(known.count) Verträge sind schon in Kontivo ›"
            showButton(review.showKnown ? "Schon erfasste ausblenden" : knownText, top: 18, id: "bankKnownToggle") {
                withAnimation(.easeInOut(duration: 0.2)) { review.showKnown.toggle() }
            }
            if review.showKnown {
                list {
                    ForEach(Array(known.enumerated()), id: \.offset) { k, kn in
                        separator(k == 0)
                        BankKnownRow(k: kn)
                    }
                }
            }
        }
        if nIgn > 0 {
            let ignText: String = nIgn == 1 ? "1 ausgeblendeter Vorschlag ›" : "\(nIgn) ausgeblendete Vorschläge ›"
            showButton(review.showIgnored ? "Ausgeblendete verbergen" : ignText, id: "bankIgnToggle") {
                withAnimation(.easeInOut(duration: 0.2)) { review.showIgnored.toggle() }
            }
        }
    }

    /// Zahlung trotz Kündigung (Web `.bkwarn`): Abbuchung nach «Läuft bis» – öffnet den Vertrag
    @ViewBuilder private func afterWarning(_ a: BankAfterEnd, _ d: AppData) -> some View {
        if let c = d.contract(a.contractID) {
            let pn = d.partnerName(of: c)
            Button {
                let m = model, id = c.id
                m.dismissTop { m.present(.contractDetail(id)) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text((pn.isEmpty ? d.title(of: c) : pn) + " bucht weiter ab")
                        .font(.system(size: 14.5, weight: .bold))
                        .foregroundStyle(KColor.warn)
                    Text("Gekündigt per " + (c.cancelPer.map { BankReview.day($0) } ?? "") + ", trotzdem "
                         + (a.count == 1 ? "eine Abbuchung" : "\(a.count) Abbuchungen") + " danach, zuletzt " + BankReview.day(a.last)
                         + " (" + Format.money(a.amount, Currency(rawValue: a.currency)) + " " + a.currency + "). Beim Vertragspartner nachfragen.")
                        .font(.system(size: 12.5))
                        .lineSpacing(BankType.extra(12.5, 16.875))
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .background(BankMix(color: KColor.warn, p: 0.14, radius: 12))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
            .accessibilityIdentifier("bankAfter")
        }
    }

    // MARK: Schritt 2: Einnahmen

    @ViewBuilder private func incStep(_ d: AppData, first: Bool) -> some View {
        let ik = review.incKnown
        if review.inc.isEmpty {
            heading("Deine Einnahmen")
            intro("Nichts Neues gefunden – alles ist schon in Kontivo.")
        } else {
            heading("Und deine Einnahmen?")
            BankHeroCard(hero: review.hero(d, income: true), income: true)
        }
        logoLine
        if first { whoBar(d) }
        if !review.inc.isEmpty {
            list {
                ForEach(Array(review.inc.enumerated()), id: \.element.id) { k, it in
                    separator(k == 0)
                    BankIncRow(review: review, it: it) { openInc(it) }
                }
            }
        }
        if !ik.isEmpty {
            if !review.inc.isEmpty { head("Bereits in Kontivo", ik.count) }
            list {
                ForEach(Array(ik.enumerated()), id: \.offset) { k, kn in
                    separator(k == 0)
                    BankKnownIncRow(k: kn)
                }
            }
        }
    }

    // MARK: Schritt 3: Kündigungsfristen

    @ViewBuilder private func termStep(_ d: AppData) -> some View {
        let tl = review.termList(d)
        heading(tl.count == 1 ? "Noch 1 Kündigungsfrist" : "Noch \(tl.count) Kündigungsfristen")
        intro("Damit Kontivo dich rechtzeitig erinnert. Ein Tipp pro Vertrag genügt – Genaueres (z.B. feste Laufzeit) ergänzt du später im Vertrag.")
        list {
            ForEach(Array(tl.enumerated()), id: \.element) { k, i in
                separator(k == 0)
                BankTermRow(review: review, it: review.items[i])
            }
        }
    }

    // MARK: Formular öffnen (Web bkOpenForm / bkOpenInc)

    private func open(_ it: BankReview.Item) {
        let r = review, m = model, id = it.id
        let draft = review.draft(it, model.data, today: model.today)
        BankFormBridge.shared.openContract(draft, model: model, done: { res in
            r.formDone(id, res, model: m)
        }, ignore: {
            r.ignore(id, model: m)
        })
    }

    private func openInc(_ it: BankReview.IncItem) {
        let r = review, m = model, id = it.id
        BankFormBridge.shared.openIncome(review.incomeDraft(it), model: model) { x in
            r.incFormDone(id, x, model: m)
        }
    }
}
