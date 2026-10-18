import Foundation

// Sonderkündigung bei Preiserhöhung (Web v205–v209, `isKvg`/`skrRule`/`skrInfo`/`openSkr`, Stand v224).
// Regeln nach Land (Währung) und Kategorie, keine Rechtsberatung:
// - CH Grundversicherung (nur Erhöhung per 1.1.): Art. 7 Abs. 2 KVG – Kündigung bis letzter Arbeitstag im November.
// - DE Strom/Gas: § 41 Abs. 5 EnWG – bis zum Tag vor dem neuen Preis.
// - DE Telekom: § 57 Abs. 1 TKG – 3 Monate nach Mitteilung (mind. bis Erhöhung + 1 Monat − 1 Tag).
// - DE Miete: § 561 BGB – bis Ende des 2. Monats nach Mitteilung.  - DE Versicherung: § 40 VVG – 1 Monat nach Mitteilung.
// - CH Versicherung/Gesundheit: AVB.  - Übrige: AGB.
// Sichtbar ab Ankündigung bis zur berechneten Frist; ohne berechenbare Frist bis 30 Tage nach Wirksamkeit.
// Neueste Erhöhung zuerst (angekündigte vor vergangenen).

/// Regel für eine Preiserhöhung ab `from` (Web `skrRule`).
public struct SpecialCancelRule: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        /// CH Grundversicherung, Erhöhung per 1.1.
        case kvg
        /// DE Strom/Gas
        case energyDE
        /// DE Mobilfunk & Internet
        case telecomDE
        /// DE Miete
        case rentDE
        /// DE Versicherung
        case insuranceDE
        /// CH (bzw. nicht EUR) Versicherung / Gesundheit: AVB
        case insuranceCH
        /// kein gesetzliches Sonderkündigungsrecht (AGB)
        case other
    }

    public var kind: Kind
    /// «Kündigen bis» als Datum (Web `r.until`), nil = nur Text `when`
    public var until: Day?
    /// «mind.» vor dem Datum (TKG)
    public var untilIsMinimum: Bool = false
    /// «Vertrag endet» als Datum (Web `r.end`)
    public var end: Day?
    /// «frühestens» vor dem Vertragsende (TKG)
    public var endIsMinimum: Bool = false
    /// «Vertrag endet» als Text (Web `r.endTxt`, Miete DE)
    public var endText: String?
    /// «Kündigen bis» als Text ohne Datum (Web `r.when`)
    public var when: String?
    /// Grundlage («Art. 7 Abs. 2 KVG» …), nil ohne Gesetz
    public var source: String?
    /// Kein gesetzliches Sonderkündigungsrecht (Web `r.none`)
    public var none: Bool = false
    /// «Gut zu wissen»
    public var tips: [String]
}

/// Anstehende bzw. kürzliche Preiserhöhung mit Kündigungsrecht (Web `skrInfo`).
public struct SpecialCancelInfo: Hashable, Sendable {
    /// Gültig ab
    public var from: Day
    /// Neuer Preis (Vertragswährung)
    public var amount: Double
    /// Preis davor
    public var previous: Double
    /// Erhöhung in ganzen Prozent (JS `Math.round`)
    public var percent: Int
    public var rule: SpecialCancelRule
    /// «Kündigen bis» (= `rule.until`)
    public var until: Day? { rule.until }
    /// «Sonderkündigung möglich» bzw. «Preis erhöht» (Titel von Zeile und Blatt)
    public var head: String
    /// «bis 30.11.», «bis mind. 31.03.27», «Frist ab Mitteilung», «Kündigungsrecht prüfen»
    public var tail: String
    /// Zeile im Detail: «Sonderkündigung möglich · bis 30.11.»
    public var lineText: String { head + (tail.isEmpty ? "" : " · " + tail) }
    /// Barrierefreiheit der Zeile
    public var accessibilityLabel: String { lineText }
}

/// Erklärblatt «Sonderkündigung» (Web `openSkr`, v208: Einleitung, Eckdaten, Gut zu wissen, Grundlage).
public struct SpecialCancelSheet: Hashable, Sendable {
    public struct Row: Hashable, Sendable, Identifiable {
        /// «Neuer Preis», «Kündigen bis», «Vertrag endet»
        public var key: String
        public var value: String
        /// Zweite Zeile unter dem Wert ("" = keine)
        public var sub: String
        /// Wert in Akzentfarbe (Messing, Web `.skrk`)
        public var accent: Bool
        public var id: String { key }
    }

    /// Fenstertitel (= `SpecialCancelInfo.head`)
    public var title: String
    /// Einleitung (warum)
    public var intro: String
    /// Eckdaten
    public var rows: [Row]
    /// «Gut zu wissen»
    public var tipsTitle: String
    public var tips: [String]
    /// «Grundlage: § 41 Abs. 5 EnWG · Massgebend sind dein Vertrag und die Mitteilung. Keine Rechtsberatung.»
    public var footer: String
}

extension Calc {
    public static let skrHeadRight = "Sonderkündigung möglich"
    public static let skrHeadNone = "Preis erhöht"
    public static let skrTailNone = "Kündigungsrecht prüfen"
    public static let skrTailFromNotice = "Frist ab Mitteilung"
    public static let skrTipsTitle = "Gut zu wissen"
    public static let skrDisclaimer = "Massgebend sind dein Vertrag und die Mitteilung. Keine Rechtsberatung."
    /// Toast nach dem Vormerken einer Preiserhöhung im Formular (Web v205)
    public static let priceIncreaseToast = "Preiserhöhung vorgemerkt – Hinweis zur Kündigung steht im Detail."

    /// Name der Kategorie für Textregeln (Web `c.cat`)
    func skrCategoryName(_ c: Contract) -> String { data.category(c.categoryID)?.name ?? "" }

    /// CH-Grundversicherung (Web `isKvg`): CHF und Bezeichnung/Vertragspartner/Kategorie nennen Krankenkasse, Krankenversicherung,
    /// Grundversicherung oder KVG, aber nicht Zusatz, Spital oder VVG.
    public func isKvg(_ c: Contract) -> Bool {
        let t = [c.label, partnerName(c), skrCategoryName(c)].joined(separator: " ")
        return c.currency == .CHF && RX.test("krankenkass|krankenversich|grundversich|kvg", t, ignoreCase: true)
            && !RX.test("zusatz|spital|vvg", t, ignoreCase: true)
    }

    /// Letzter Arbeitstag (Mo–Fr) an oder vor `d`.
    static func lastWorkday(onOrBefore d: Day) -> Day {
        var x = d
        while x.weekday == 0 || x.weekday == 6 { x = x.addingDays(-1) }
        return x
    }

    /// Regel für eine Erhöhung ab `f` (Web `skrRule`).
    public func specialCancelRule(_ c: Contract, from f: Day) -> SpecialCancelRule {
        let k = categoryKind(c)
        let de = c.currency == .EUR
        let pn = partnerName(c)
        let P = pn.isEmpty ? "dem Vertragspartner" : pn
        let dayB = f.addingDays(-1)
        let lp = [c.label, pn].joined(separator: " ")
        if isKvg(c) && f.month == 1 && f.day == 1 {
            // letzter Arbeitstag im November (Web: new Date(y, m-1, 0) = 30.11. des Vorjahres, dann Wochenende zurück)
            let ku = Calc.lastWorkday(onOrBefore: Day(f.year, f.month - 1, 0))
            return SpecialCancelRule(kind: .kvg, until: ku, end: dayB, source: "Art. 7 Abs. 2 KVG", tips: [
                "Oft kündigt die neue Krankenkasse für dich: Du unterschreibst die vorbereitete Kündigung, sie leitet sie weiter. Kurz vor Ende November besser selbst kündigen.",
                "Die Kündigung muss bis dann bei " + P + " eintreffen – am besten eingeschrieben.",
                "Sie gilt erst, wenn die neue Krankenkasse deine Aufnahme bestätigt hat.",
            ])
        }
        if de && k == .energy && !RX.test("wasser", lp, ignoreCase: true) {
            return SpecialCancelRule(kind: .energyDE, until: dayB, end: dayB, source: "§ 41 Abs. 5 EnWG", tips: [
                "Ohne Kündigungsfrist – die Kündigung muss vor dem neuen Preis eintreffen.",
                "Kündige selbst, nicht über den neuen Anbieter.",
            ])
        }
        if de && k == .telecom {
            // Web: addMonths(f, 1) − 1 Tag
            return SpecialCancelRule(kind: .telecomDE, until: f.addingMonths(1).addingDays(-1), untilIsMinimum: true, end: dayB, endIsMinimum: true,
                                     source: "§ 57 Abs. 1 TKG", tips: [
                "Genau gilt: 3 Monate nach Erhalt der Mitteilung. Das angezeigte Datum ist das früheste mögliche Ende dieser Frist.",
            ])
        }
        if de && isRent(c) {
            return SpecialCancelRule(kind: .rentDE, endText: "Ende des übernächsten Monats", when: "Ende des 2. Monats nach Erhalt der Mitteilung",
                                     source: "§ 561 BGB", tips: ["Von Hand unterschreiben und eingeschrieben senden."])
        }
        if de && k == .insurance {
            return SpecialCancelRule(kind: .insuranceDE, end: dayB, when: "1 Monat nach Erhalt der Mitteilung", source: "§ 40 VVG", tips: [
                "Die Frist läuft ab dem Tag, an dem der Brief bzw. die E-Mail bei dir eingetroffen ist.",
            ])
        }
        if !de && (k == .insurance || k == .health || RX.test("versicher|krankenkass", lp, ignoreCase: true)) {
            return SpecialCancelRule(kind: .insuranceCH, when: "siehe Mitteilung", none: true, tips: [
                "Bei Zusatz- und Sachversicherungen regeln die Versicherungsbedingungen (AVB) das Kündigungsrecht – meist auf den Tag der Erhöhung.",
                "Ohne Kündigung gilt die neue Prämie als angenommen.",
            ])
        }
        let tips = c.currency == .CHF
            ? ["In der Schweiz gibt es dafür kein allgemeines Gesetz. Ob und bis wann du kündigen kannst, steht in den AGB und oft in der Mitteilung."]
            : ["Es gibt kein allgemeines gesetzliches Sonderkündigungsrecht. Ob und bis wann du kündigen kannst, steht in den AGB und meist in der Mitteilung.",
               "Eine Erhöhung ohne gültige Preisklausel musst du nicht hinnehmen."]
        return SpecialCancelRule(kind: .other, when: "siehe Mitteilung", none: true, tips: tips)
    }

    /// Preiserhöhung mit Kündigungsrecht (Web `skrInfo`): neueste Erhöhung zuerst, sichtbar bis «Kündigen bis» bzw. ohne Datum
    /// bis 30 Tage nach Wirksamkeit. Ohne Prüfung von Status/nicht kündbar (dafür `specialCancel(_:)`).
    public func specialCancelInfo(_ c: Contract) -> SpecialCancelInfo? {
        var list: [(f: Day, a: Double, prev: Double, up: Bool, pct: Int)] = []
        var prev = c.amount.isFinite ? c.amount : 0
        for p in pricesOf(c) {
            let a = p.amount
            list.append((p.from, a, prev, prev > 0 && a > prev, prev > 0 ? Int(Format.jsRound((a / prev - 1) * 100)) : 0))
            prev = a
        }
        for x in list.reversed() {
            if !x.up { continue }
            let r = specialCancelRule(c, from: x.f)
            let end = r.until ?? x.f.addingDays(30)
            if end < today { continue }
            let tail: String
            if r.none {
                tail = Calc.skrTailNone
            } else if let u = r.until {
                tail = (r.untilIsMinimum ? "bis mind. " : "bis ") + Format.ddmm(u, currentYear: today.year)
            } else {
                tail = Calc.skrTailFromNotice
            }
            return SpecialCancelInfo(from: x.f, amount: x.a, previous: x.prev, percent: x.pct, rule: r,
                                     head: r.none ? Calc.skrHeadNone : Calc.skrHeadRight, tail: tail)
        }
        return nil
    }

    /// Zeile «Sonderkündigung» im Vertragsdetail (Web `openDetail`: nicht gekündigt/beendet und nicht «nicht kündbar»).
    public func specialCancel(_ c: Contract) -> SpecialCancelInfo? {
        let gone = c.status == .cancelled || c.cancelPer != nil || endedByTerm(c)
        if gone || isFixed(c) { return nil }
        return specialCancelInfo(c)
    }

    /// Erklärblatt zur Zeile (Web `openSkr`, rechnet wie dort mit `skrInfo` ohne Statusprüfung), nil ohne Preiserhöhung.
    public func specialCancelSheet(_ c: Contract) -> SpecialCancelSheet? {
        guard let x = specialCancelInfo(c) else { return nil }
        let r = x.rule
        let fut = x.from > today
        let pn = partnerName(c)
        let P = pn.isEmpty ? data.title(of: c) : pn
        let cy = Double(c.cycleForCalc)
        let dm = (x.amount - x.previous) / cy
        var rows: [SpecialCancelSheet.Row] = []
        rows.append(.init(key: "Neuer Preis", value: Format.money(x.amount) + " " + c.currency.rawValue,
                          sub: (fut ? "ab " : "seit ") + Format.fmtShort(x.from) + " · +\(x.percent)\u{00A0}% (+" + Format.money(dm) + "/Mt.)",
                          accent: false))
        if let u = x.until {
            let dn = today.days(to: u)
            rows.append(.init(key: "Kündigen bis", value: (r.untilIsMinimum ? "mind. " : "") + Format.fmtShort(u),
                              sub: (dn == 0 ? "heute" : "noch \(dn)" + (dn == 1 ? " Tag" : " Tage")) + (r.untilIsMinimum ? "" : " · Eingang zählt"),
                              accent: true))
        } else {
            rows.append(.init(key: "Kündigen bis", value: r.when ?? "", sub: "", accent: !r.none))
        }
        if let e = r.end {
            rows.append(.init(key: "Vertrag endet", value: (r.endIsMinimum ? "frühestens " : "") + Format.fmtShort(e), sub: "", accent: false))
        } else if let et = r.endText {
            rows.append(.init(key: "Vertrag endet", value: et, sub: "", accent: false))
        }
        let intro = r.none
            ? P + " erhöht den Preis. Ob du deshalb ausserordentlich kündigen darfst, regeln die Vertragsbedingungen."
            : "Weil " + P + " den Preis erhöht, darfst du ausserordentlich kündigen – auch wenn der Vertrag sonst noch weiterlaufen würde."
        let footer = (r.source.map { "Grundlage: " + $0 + " · " } ?? "") + Calc.skrDisclaimer
        return SpecialCancelSheet(title: x.head, intro: intro, rows: rows, tipsTitle: Calc.skrTipsTitle, tips: r.tips, footer: footer)
    }
}

extension Day {
    /// Wochentag wie JS `getDay()`: 0 = Sonntag … 6 = Samstag.
    public var weekday: Int {
        // 01.01.1970 war ein Donnerstag (4)
        Day.floorMod(ordinal + 4, 7)
    }
}
