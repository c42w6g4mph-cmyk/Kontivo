import SwiftUI
import KontivoCore

/// Vorschläge prüfen (Web `paintBank`, v177–v223): geführte Schritte mit Fortschrittsbalken.
/// 1. Fixkosten: «Sind das deine Fixkosten?» – «Zuordnen an», neuer Preis bei erfassten Verträgen, neu gefunden, «Nur einmal im Auszug»
///    (Ja/Nein), schon erfasste und ausgeblendete aufklappbar
/// 2. Einnahmen: «Und deine Einnahmen?»
/// 3. Fristen: «Noch n Kündigungsfristen» mit Schnellwahl 1 Monat · 3 Monate · nicht kündbar · weiss nicht
/// Antippen eines Eintrags öffnet das normale Formular («Vorschlag»).
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
                .frame(maxWidth: KMetric.maxContent + 34)
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

    /// `.bki`: 14 pt, Zeilenhöhe 1.4, ink2
    private func intro(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 14))
            .lineSpacing(BankType.extra(14, 19.6))
            .foregroundStyle(KColor.ink2)
            .padding(.vertical, BankType.halfLeading(14, 19.6))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 12)
    }

    /// `.sheet h4.bkh2`: 13 pt halbfett ink2, Anzahl rechts
    private func head(_ t: String, _ n: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(t)
            Spacer(minLength: 0)
            Text("\(n)")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(KColor.ink2)
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    /// `.bklist`: weisse Fläche, Radius 16, Trennlinien ab 62 pt
    private func list<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        VStack(spacing: 0) { content() }
            .background(KColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.bottom, 6)
    }

    private func separator(_ first: Bool) -> some View {
        Group {
            if !first {
                Rectangle().fill(KColor.line).frame(height: 1).padding(.leading, 62)
            }
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
        let sure = vis.filter { review.items[$0].s.confidence != .low }
        let maybe = vis.filter { review.items[$0].s.confidence == .low }
        let nIgn = review.items.filter { $0.s.ignored }.count
        let known = review.result.known
        heading(sure.isEmpty && maybe.isEmpty ? "Keine neuen Fixkosten" : "Sind das deine Fixkosten?")
        if !sure.isEmpty || !maybe.isEmpty {
            intro("Alles mit Häkchen wird übernommen. Kategorie, Logo und – bei bekannten Anbietern – die Kündigungsfrist sind schon ergänzt. Tippe auf einen Eintrag, um etwas zu ändern.")
        }
        logoLine
        whoBar(d)
        if !review.prices.isEmpty {
            head("Neuer Preis bei erfassten Verträgen", review.prices.count)
            list {
                ForEach(Array(review.prices.enumerated()), id: \.element.id) { k, p in
                    separator(k == 0)
                    priceRow(p, d)
                }
            }
        }
        if !sure.isEmpty {
            if !review.prices.isEmpty { head("Neu gefunden", sure.count) }
            list {
                ForEach(Array(sure.enumerated()), id: \.element) { k, i in
                    separator(k == 0)
                    row(review.items[i], d)
                }
            }
        }
        if !maybe.isEmpty {
            head("Nur einmal im Auszug – gehört das dazu?", maybe.count)
            list {
                ForEach(Array(maybe.enumerated()), id: \.element) { k, i in
                    separator(k == 0)
                    row(review.items[i], d)
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
                .padding(.top, 24 + 14)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
        }
        if !known.isEmpty {
            showButton(review.showKnown ? "Schon erfasste ausblenden"
                       : "\(known.count)" + (known.count == 1 ? " Vertrag ist schon in Kontivo" : " Verträge sind schon in Kontivo") + " ›",
                       top: 18, id: "bankKnownToggle") {
                withAnimation(.easeInOut(duration: 0.2)) { review.showKnown.toggle() }
            }
            if review.showKnown {
                list {
                    ForEach(Array(known.enumerated()), id: \.offset) { k, kn in
                        separator(k == 0)
                        knownRow(kn, d)
                    }
                }
            }
        }
        if nIgn > 0 {
            showButton(review.showIgnored ? "Ausgeblendete verbergen"
                       : "\(nIgn)" + (nIgn == 1 ? " ausgeblendeter Vorschlag" : " ausgeblendete Vorschläge") + " ›", id: "bankIgnToggle") {
                withAnimation(.easeInOut(duration: 0.2)) { review.showIgnored.toggle() }
            }
        }
    }

    // MARK: Schritt 2: Einnahmen

    @ViewBuilder private func incStep(_ d: AppData, first: Bool) -> some View {
        let ik = review.incResult.known
        heading("Und deine Einnahmen?")
        intro("Regelmässige Gutschriften aus dem Auszug. Umbuchungen, TWINT und Rückerstattungen sind ausgeschlossen. Alles mit Häkchen wird übernommen.")
        logoLine
        if first { whoBar(d) }
        list {
            ForEach(Array(review.inc.enumerated()), id: \.element.id) { k, it in
                separator(k == 0)
                incRow(it, d)
            }
        }
        if !ik.isEmpty {
            intro(ik.count == 1 ? "1 Einnahme ist schon in Kontivo." : "\(ik.count) Einnahmen sind schon in Kontivo.")
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
                termRow(review.items[i], d)
            }
        }
    }

    // MARK: Zeilen

    private func mark(_ it: BankReview.Item, _ d: AppData, size: CGFloat = 36) -> some View {
        let cat = d.category(it.ed.categoryID) ?? d.otherCategory
        return MarkView(logoID: it.logo?.id, logoBg: it.logo?.bg, colorHex: cat?.colorHex ?? KCategory.fallbackColor,
                        symbol: KIcon.symbol(for: cat), size: size)
    }

    private func incMark(_ it: BankReview.IncItem) -> some View {
        MarkView(logoID: it.logo?.id, logoBg: it.logo?.bg, colorHex: it.ed.kind.colorHex, symbol: KIcon.symbol(forKey: it.ed.kind.icon), size: 36)
    }

    /// Text-Block `.bktx`: Titel 15.5 pt halbfett (umbrechend), Unterzeile 12.5 pt ink2 mit Hinweis in Messing, Plaketten
    private func textBlock(title: String, sub: (text: String, em: String?), tags: [BankTag], off: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15.5, weight: .semibold))
                .lineSpacing(BankType.extra(15.5, 19.375))
                .foregroundStyle(off ? KColor.ink3 : KColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            subText(sub)
                .font(.system(size: 12.5))
                .lineSpacing(BankType.extra(12.5, 16.25))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 1)
            if !tags.isEmpty {
                BankFlow(spacing: 5) {
                    ForEach(tags) { t in t.view }
                }
                .padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subText(_ sub: (text: String, em: String?)) -> Text {
        var t = Text(sub.text).foregroundColor(KColor.ink2)
        if let em = sub.em { t = t + Text(" · ").foregroundColor(KColor.ink2) + Text(em).foregroundColor(KColor.teal) }
        return t
    }

    /// Betrag `.bkam`: 15.5 pt halbfett (Tabellenziffern), darunter «CHF pro Monat» 11 pt
    private func amountBlock(_ v: Double, _ cur: String, _ cycle: Int, maybe: Bool = false, dim: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(Format.money(v, Currency(rawValue: cur)))
                .font(.system(size: 15.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(dim ? KColor.ink3 : KColor.ink)
            Text(cur + " " + BankReview.per(cycle) + (maybe ? "?" : ""))
                .font(.system(size: 11))
                .foregroundStyle(KColor.ink2)
        }
        .lineLimit(1)
        .fixedSize()
    }

    private var chevron: some View {
        Text("›")
            .font(.system(size: 18))
            .foregroundStyle(KColor.ink3)
            .padding(.leading, 2)
            .accessibilityHidden(true)
    }

    private func row(_ it: BankReview.Item, _ d: AppData) -> some View {
        let maybe = it.s.confidence == .low
        let catName = review.categoryName(it, d)
        var tags = [BankTag(catName, .plain)]
        if !(maybe || review.noCancel(it, d)) {
            tags.append(review.hasTerm(it, d) ? BankTag("✓ Frist", .ok) : BankTag("Frist fehlt", .miss))
        }
        let title = review.title(it)
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                if !maybe {
                    BankCheck(on: it.on, label: title + " übernehmen") { review.toggle(it.id) }
                        .accessibilityIdentifier("bankCheck-" + it.s.name)
                }
                Button { open(it) } label: {
                    HStack(spacing: 11) {
                        mark(it, d).opacity(it.on ? 1 : 0.45)
                        textBlock(title: title, sub: review.sub(it), tags: tags, off: !it.on)
                        amountBlock(it.ed.amount, it.s.currency, it.ed.cycle, maybe: maybe, dim: !it.on)
                        chevron
                    }
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("bankRow-" + it.s.name)
            }
            if maybe {
                HStack(spacing: 8) {
                    BankYesNo(title: "Ja, übernehmen", on: it.on) { withAnimation { review.setOn(it.id, true) } }
                    BankYesNo(title: "Nein", on: !it.on) { withAnimation { review.setOn(it.id, false) } }
                }
                .padding(.leading, 47)
                .padding(.bottom, 12)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }

    private func incRow(_ it: BankReview.IncItem, _ d: AppData) -> some View {
        let title = review.incTitle(it)
        return HStack(spacing: 10) {
            BankCheck(on: it.on, label: title + " übernehmen") { review.toggleInc(it.id) }
            Button { openInc(it) } label: {
                HStack(spacing: 11) {
                    incMark(it).opacity(it.on ? 1 : 0.45)
                    textBlock(title: title, sub: review.incSub(it), tags: [BankTag(it.ed.kind.displayName, .plain)], off: !it.on)
                    amountBlock(it.ed.amount, it.s.currency, it.ed.cycle, dim: !it.on)
                    chevron
                }
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bankIncRow-" + it.s.name)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
    }

    @ViewBuilder private func priceRow(_ p: BankReview.PriceRow, _ d: AppData) -> some View {
        if let c = d.contract(p.m.contractID) {
            let cur = c.currency
            let t = d.title(of: c)
            HStack(spacing: 10) {
                BankCheck(on: p.on, label: "Neuen Preis für \(d.partnerName(of: c)) übernehmen") { review.togglePrice(p.id) }
                HStack(spacing: 11) {
                    MarkView(contract: c, data: d, size: 36)
                    textBlock(title: t + (p.m.amount > p.m.old ? " ist teurer" : " ist günstiger"),
                              sub: (text: Format.money(p.m.old, cur) + " → " + Format.money(p.m.amount, cur) + " " + cur.rawValue + " ab " + BankReview.day(p.m.from), em: nil),
                              tags: [], off: false)
                }
                .padding(.vertical, 11)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
        }
    }

    @ViewBuilder private func knownRow(_ k: BankKnown, _ d: AppData) -> some View {
        if let c = d.contract(k.contractID) {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(KColor.brass.opacity(0.18))
                    BankCheckGlyph().stroke(KColor.teal, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 15, height: 15)
                }
                .frame(width: 26, height: 26)
                .padding(.trailing, 2)
                .accessibilityHidden(true)
                HStack(spacing: 11) {
                    MarkView(contract: c, data: d, size: 36)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.title(of: c))
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(KColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(k.loose ? "im Auszug gefunden" : "unverändert")
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink2)
                            .padding(.top, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Format.money(model.calc.curPrice(c), c.currency))
                            .font(.system(size: 15.5, weight: .semibold).monospacedDigit())
                            .foregroundStyle(KColor.ink2)
                        Text(c.currency.rawValue + " " + BankReview.per(c.cycle == 0 ? 1 : c.cycle))
                            .font(.system(size: 11))
                            .foregroundStyle(KColor.ink2)
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                .padding(.vertical, 11)
            }
            .padding(.leading, 14)
            .padding(.trailing, 12)
            .accessibilityElement(children: .combine)
        }
    }

    private func termRow(_ it: BankReview.Item, _ d: AppData) -> some View {
        let t = review.title(it)
        let choices: [(String, String)] = [("1", "1 Monat"), ("3", "3 Monate"), ("x", "nicht kündbar"), ("", "weiss nicht")]
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                mark(it, d)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t)
                        .font(.system(size: 15.5, weight: .semibold))
                        .foregroundStyle(KColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(it.ed.name != t ? it.ed.name : review.categoryName(it, d))
                        .font(.system(size: 12.5))
                        .foregroundStyle(KColor.ink2)
                        .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 11)
            .padding(.bottom, 6)
            BankFlow(spacing: 6) {
                ForEach(choices.indices, id: \.self) { j in
                    BankChip(title: choices[j].1, on: it.term == choices[j].0) { review.setTerm(it.id, choices[j].0) }
                }
            }
            .padding(.leading, 47)
            .padding(.bottom, 12)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Kündigungsfrist " + t)
        }
        .padding(.leading, 14)
        .padding(.trailing, 12)
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

// MARK: - Kleine Bausteine

/// Zeilenhöhen der Web-App in SwiftUI (SF Pro: natürliche Zeilenhöhe ≈ 1.193 × Schriftgrösse)
enum BankType {
    /// Zusätzlicher Zeilenabstand für CSS `line-height`
    static func extra(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat { Swift.max(0, lineHeight - size * 1.193) }
    /// Halber Durchschuss oben/unten (erste/letzte Zeile)
    static func halfLeading(_ size: CGFloat, _ lineHeight: CGFloat) -> CGFloat { extra(size, lineHeight) / 2 }
}

/// Häkchen `.bkck`: 26 pt, Rand 1.6 pt ink3; an = Messing mit Haken in onBrass
struct BankCheck: View {
    let on: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if on {
                    Circle().fill(KColor.brass)
                    BankCheckGlyph().stroke(KColor.onBrass, style: StrokeStyle(lineWidth: 2.2, lineCap: .butt, lineJoin: .miter))
                        .frame(width: 12, height: 9)
                } else {
                    Circle().strokeBorder(KColor.ink3, lineWidth: 1.6)
                }
            }
            .frame(width: 26, height: 26)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityValue(on ? "ausgewählt" : "nicht ausgewählt")
    }
}

/// Haken (Web `M5 12.5l4.5 4.5L19 7.5` bzw. CSS-Winkel): in den Rahmen eingepasst
struct BankCheckGlyph: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.5))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.32, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

/// Plakette `.bkq i`: 11 pt, 4/7 Innenabstand, Radius 20; ok wie normal (Design-Schicht), fehlt = Messing 16 %
struct BankTag: Identifiable {
    enum Kind { case plain, ok, miss }
    let text: String
    let kind: Kind
    var id: String { text }
    init(_ text: String, _ kind: Kind) {
        self.text = text
        self.kind = kind
    }

    var view: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(kind == .miss ? KColor.teal : KColor.ink2)
            .padding(.vertical, 4)
            .padding(.horizontal, 7)
            .background(
                ZStack {
                    if kind == .miss {
                        Capsule().fill(KColor.surface)
                        Capsule().fill(KColor.brass.opacity(0.16))
                    } else {
                        Capsule().fill(KColor.sunken)
                    }
                }
            )
            .lineLimit(1)
    }
}

/// Segment `.hseg` (in «Zuordnen an»): Fläche sunken mit Ring, Knopf 13.5 pt; gewählt = ink mit paper
struct BankSegment: View {
    let options: [(UUID, String)]
    let selected: UUID?
    let action: (UUID) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { j in
                let o = options[j]
                let on = o.0 == selected
                Button { action(o.0) } label: {
                    Text(o.1)
                        .font(.system(size: 13.5, weight: on ? .semibold : .medium))
                        .foregroundStyle(on ? KColor.paper : KColor.ink2)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .padding(.horizontal, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(on ? KColor.ink : Color.clear)
                                .shadow(color: on ? .black.opacity(0.08) : .clear, radius: 1, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(KColor.sunken))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
    }
}

/// «Ja, übernehmen» / «Nein» (`.bkyn button`): Fläche sunken, 14.5 pt halbfett, Radius 11; gewählt = Messing
struct BankYesNo: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(on ? KColor.onBrass : KColor.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .padding(.horizontal, 6)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(on ? KColor.brassFab : KColor.sunken))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Schnellwahl `.bkchips button`: 13.5 pt, 7/12 Innenabstand, Rand line, Radius 20; gewählt = Messing
struct BankChip: View {
    let title: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(on ? KColor.onBrass : KColor.ink)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(Capsule().fill(on ? KColor.brassFab : KColor.surface))
                .overlay(Capsule().strokeBorder(on ? KColor.brassFab : KColor.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

/// Umbrechende Reihe (CSS `flex-wrap`)
struct BankFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, w: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > maxW {
                y += rowH + spacing
                x = 0
                rowH = 0
            }
            x += sz.width + spacing
            rowH = Swift.max(rowH, sz.height)
            w = Swift.max(w, x - spacing)
        }
        return CGSize(width: proposal.width ?? w, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > bounds.minX && x + sz.width > bounds.maxX {
                y += rowH + spacing
                x = bounds.minX
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = Swift.max(rowH, sz.height)
        }
    }
}
