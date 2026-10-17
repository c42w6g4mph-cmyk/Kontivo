import Foundation

// Fixkosten-Bericht als PDF (Web v220 `repData`, Design V3): Kennzahlen, Kategorien, grösste Posten, Handlungsbedarf,
// 12-Monats-Vorschau und Vertragsblätter. Hier nur die Zahlen und Texte; gezeichnet wird in der App (UIGraphicsPDFRenderer).

public struct FixReport: Hashable, Sendable {
    /// Ein laufender Vertrag im Bericht
    public struct Row: Hashable, Identifiable, Sendable {
        public var contractID: UUID
        /// Anteil der gewählten Person (1 ohne Auswahl)
        public var share: Double
        /// Monatskosten in Hauptwährung × Anteil
        public var monthly: Double
        /// Kategorie (`c.cat || "Sonstiges"`)
        public var category: String
        public var id: UUID { contractID }
    }

    public struct CategorySum: Hashable, Sendable {
        public var name: String
        public var value: Double
    }

    /// Frist in den nächsten 90 Tagen
    public struct Deadline: Hashable, Sendable {
        public var contractID: UUID
        public var date: Day
        public var days: Int
        /// «Update Fitness · verlängert sich sonst»
        public var sub: String
    }

    public struct Month: Hashable, Sendable {
        /// Erster Tag des Monats
        public var date: Day
        public var value: Double
        /// grösste Jahres-/Sonderzahlung im Monat (Name, Wert)
        public var bigName: String?
        public var bigValue: Double
        /// Spitze: über Median × 1.12 und mit grosser Zahlung
        public var high: Bool
    }

    public var home: Currency
    public var today: Day
    /// Kopf rechts: gewählte Person oder alle Personen «Sinan & Lara»
    public var who: String
    public var rows: [Row]
    /// Fixkosten pro Monat (Summe der Monatskosten)
    public var total: Double
    public var categories: [CategorySum]
    /// Grösste 5 Posten
    public var top: [Row]
    public var deadlines: [Deadline]
    /// 12 Monate ab dem aktuellen Monat
    public var months: [Month]
    /// Summe der 12 Monate
    public var year: Double
    /// Einnahmen pro Monat (Durchschnitt der nächsten 12 Monate)
    public var income: Double
    /// Veränderung zum Vorjahr (Monatskosten heute − vor 12 Monaten)
    public var diff: Double
    /// Kunden- und Vertragsnummern zeigen
    public var showIDs: Bool

    /// Anzahl Seiten (1 + Vertragsblätter zu je 10)
    public var pageCount: Int { 1 + Swift.max(1, Int((Double(rows.count) / 10).rounded(.up))) }

    /// Vertragsblätter: Reihenfolge wie «Nach Kategorie», innerhalb nach Monatskosten
    public var sheetRows: [Row] {
        var ord: [String: Int] = [:]
        for (i, e) in categories.enumerated() { ord[e.name] = i }
        return rows.stableSorted { a, b in
            let x = ord[a.category] ?? 0, y = ord[b.category] ?? 0
            if x != y { return x < y }
            return a.monthly > b.monthly
        }
    }

    /// «Fixkosten-Bericht» Dateiname
    public var fileName: String { "Kontivo-Fixkosten-" + today.iso + ".pdf" }
}

extension Calc {
    /// Gibt es aktive Verträge für den Bericht? (sonst Hinweis «Noch keine aktiven Verträge für den Bericht»)
    public var reportAvailable: Bool { data.contracts.contains { isActive($0) } }

    public static let reportUnavailableText = "Noch keine aktiven Verträge für den Bericht"
    public static let reportIntro = "PDF mit Übersicht, 12-Monats-Vorschau und allen Vertragsblättern – zum Teilen, Ablegen oder Drucken."

    /// Zahlen des Berichts (`repData`): `person` nil = alle Personen.
    public func fixReport(person: UUID?, showIDs: Bool) -> FixReport {
        let t = today
        func sh(_ c: Contract) -> Double { person == nil ? 1 : holderShare(c, person: person) }
        var L: [FixReport.Row] = []
        for c in data.contracts where isActive(c) && !isPaused(c) && sh(c) > 0 {
            let f = sh(c)
            let ck = data.category(c.categoryID)?.name ?? ""
            L.append(FixReport.Row(contractID: c.id, share: f, monthly: monthlyCost(c) * f, category: ck.isEmpty ? "Sonstiges" : ck))
        }
        let tot = L.reduce(0.0) { $0 + $1.monthly }
        var order: [String] = []
        var cats: [String: Double] = [:]
        for r in L {
            if cats[r.category] == nil { order.append(r.category) }
            cats[r.category, default: 0] += r.monthly
        }
        let CL = order.map { FixReport.CategorySum(name: $0, value: cats[$0] ?? 0) }.stableSorted { $0.value > $1.value }
        let top = Array(L.stableSorted { $0.monthly > $1.monthly }.prefix(5))
        var fr: [FixReport.Deadline] = []
        for r in L {
            guard let c = data.contract(r.contractID), let d = noticeDeadline(c), !isAnytime(c), !c.noWatch else { continue }
            let n = t.days(to: d)
            if n < 0 || n > 90 { continue }
            var sub = partnerName(c)
            if let sk = reportPriceIncrease(c), sk.pct != 0 {
                sub += " · Preis +\(sk.pct) % ab " + Format.fmtShort(sk.from)
            } else {
                sub += c.mandatory ? " · Wechsel möglich" : " · verlängert sich sonst"
            }
            fr.append(FixReport.Deadline(contractID: c.id, date: d, days: n, sub: sub))
        }
        fr = Array(fr.stableSorted { $0.date < $1.date }.prefix(4))
        // 12 Monate ab aktuellem Monat: alle Zahlungen (inkl. Jahreszahlungen, angekündigter Preise, Sonderzahlungen)
        var M: [FixReport.Month] = []
        for i in 0..<12 {
            let a = Day(t.year, t.month + i, 1), b = Day(t.year, t.month + i + 1, 0)
            var s = 0.0
            var bigN: String? = nil
            var bigV = 0.0
            for r in L {
                guard let c = data.contract(r.contractID) else { continue }
                for p in payments(c, from: a, to: b) {
                    let v = conv(p.amount, c.currency) * r.share
                    s += v
                    if c.cycleForCalc > 1 || p.extra != nil {
                        if bigN == nil || v > bigV { bigV = v; bigN = data.title(of: c) }
                    }
                }
            }
            M.append(FixReport.Month(date: a, value: s, bigName: bigN, bigValue: bigV, high: false))
        }
        let year = M.reduce(0.0) { $0 + $1.value }
        let med = M.map(\.value).sorted()[6]
        for i in M.indices { M[i].high = M[i].value > med * 1.12 && M[i].bigName != nil }
        // Einnahmen (Durchschnitt nächste 12 Monate)
        var inc = 0.0
        let a0 = Day(t.year, t.month, 1), b0 = Day(t.year, t.month + 12, 0)
        for i in data.incomes {
            let f = incomeShare(i, person: person)
            if f == 0 { continue }
            for d in occurrences(i, from: a0, to: b0) { inc += conv(priceAt(i, d), i.currency) * f }
        }
        inc /= 12
        // Vorjahr: gleiche Verträge, Preis vor 12 Monaten
        let y1 = Day(t.year - 1, t.month, t.day)
        var prev = 0.0
        for c in data.contracts {
            let f = person == nil ? 1 : holderShare(c, person: person)
            if f == 0 { continue }
            if let st = c.start, st > y1 { continue }
            if c.status == .cancelled, let cp = c.cancelPer, cp < y1 { continue }
            prev += conv(priceAt(c, y1), c.currency) / Double(c.cycleForCalc) * f
        }
        let who: String
        if let p = person, let pp = data.person(p) { who = pp.name } else { who = data.persons.map(\.name).joined(separator: " & ") }
        return FixReport(home: home, today: t, who: who, rows: L, total: tot, categories: CL, top: top, deadlines: fr, months: M,
                         year: year, income: inc, diff: tot - prev, showIDs: showIDs)
    }

    /// Neueste noch anfechtbare Preiserhöhung (Web `skrInfo`, nur Datum und Prozent für den Bericht).
    /// Frist: KVG per 1.1. bis letzter Arbeitstag im November, DE Energie (ohne Wasser) bis Vortag, DE Mobilfunk 1 Monat,
    /// sonst 30 Tage ab der Erhöhung.
    public func reportPriceIncrease(_ c: Contract) -> (from: Day, pct: Int)? {
        var prev = c.amount
        var L: [(f: Day, up: Bool, pct: Int)] = []
        for p in pricesOf(c) {
            let a = p.amount
            L.append((p.from, prev > 0 && a > prev, prev > 0 ? Int(Format.jsRound((a / prev - 1) * 100)) : 0))
            prev = a
        }
        for x in L.reversed() where x.up {
            let end = specialCancelUntil(c, x.f) ?? x.f.addingDays(30)
            if end < today { continue }
            return (x.f, x.pct)
        }
        return nil
    }

    /// Frist für eine Sonderkündigung (Web `skrRule(c, f).until`), nil = keine feste Frist.
    func specialCancelUntil(_ c: Contract, _ f: Day) -> Day? {
        let catName = data.category(c.categoryID)?.name ?? ""
        let kind = categoryKind(c)
        let de = c.currency == .EUR
        let dayB = f.addingDays(-1)
        let p = partnerName(c)
        let t = [c.label, p, catName].joined(separator: " ").lowercased()
        let kvg = c.currency == .CHF && t.range(of: "krankenkass|krankenversich|grundversich|kvg", options: .regularExpression) != nil
            && t.range(of: "zusatz|spital|vvg", options: .regularExpression) == nil
        if kvg && f.month == 1 && f.day == 1 {
            var ku = Day(f.year, f.month - 1, 0)
            while true {
                let wd = Day.calendar.component(.weekday, from: ku.date())
                if wd == 1 || wd == 7 { ku = ku.addingDays(-1) } else { break }
            }
            return ku
        }
        if de && kind == .energy && [c.label, p].joined(separator: " ").lowercased().range(of: "wasser") == nil { return dayB }
        if de && kind == .telecom { return f.addingMonths(1).addingDays(-1) }
        return nil
    }

    // MARK: Texte der Vertragsblätter

    /// Kündigungsregel (`repTerm`)
    public func reportTerm(_ c: Contract) -> String {
        if isFixed(c) { return isTax(c) ? "nicht kündbar (Steuern & Gebühren)" : "nicht kündbar" }
        if endsSelf(c) { return "endet von selbst" }
        let nt = Format.noticeText(c)
        if c.mandatory { return "nur mit neuem Anbieter" + (nt.isEmpty ? "" : " · " + nt) }
        return (nt.isEmpty ? "ohne Frist" : nt) + (c.end == nil ? " · " + (c.cancelTerm == .anytime ? "jederzeit" : "auf " + Format.termText(c.cancelTerm)) : "")
    }

    /// Zeilen eines Vertragsblatts (höchstens 7): Person, Zahlung, Kündigung, Kündbar bis, Nummern, Kontakt
    public func reportSheetLines(_ r: FixReport.Row, showIDs: Bool) -> [(label: String, value: String)] {
        guard let c = data.contract(r.contractID) else { return [] }
        var person = data.holderNames(of: c).joined(separator: ", ")
        if !person.isEmpty && r.share < 1 { person += " (Anteil \(Int(Format.jsRound(r.share * 100))) %)" }
        let nd = noticeDeadline(c)
        let kb = isFixed(c) ? "—" : (isAnytime(c) ? "jederzeit" : (nd.map { Format.fmtShort($0) } ?? "—"))
        var rows: [(String, String)] = [
            ("Person", person.isEmpty ? "—" : person),
            ("Zahlung", (Format.cycleText(c.cycleForCalc) ?? "") + " · " + Format.money(curPrice(c), c.currency) + " " + c.currency.rawValue),
            ("Kündigung", reportTerm(c)),
            ("Kündbar bis", kb),
        ]
        if showIDs {
            var ref: [(String, String)] = []
            if !c.customerNo.isEmpty { ref.append(("Kunden-Nr.", c.customerNo)) }
            if !c.contractNo.isEmpty {
                ref.append((Letter.contractNumberLabel(c, data: data).replacingOccurrences(of: "nummer", with: "-Nr."), c.contractNo))
            }
            rows += ref.isEmpty ? [("Kunden-Nr.", "—")] : ref
        }
        let web = data.partner(c.partnerID)?.web ?? ""
        let contact = [c.cancelChannel?.webText ?? "", Format.domain(of: web), c.tel].filter { !$0.isEmpty }.joined(separator: " · ")
        rows.append(("Kontakt", contact.isEmpty ? "—" : contact))
        return Array(rows.prefix(7))
    }

    /// Zweitzeile «Grösste Posten» (`partnerOf(c) || c.cat`)
    public func reportTopSub(_ c: Contract) -> String {
        let p = partnerName(c).trimmingCharacters(in: .whitespaces)
        let l = c.label.trimmingCharacters(in: .whitespaces)
        if !p.isEmpty && !l.isEmpty && !l.lowercased().contains(p.lowercased()) { return p }
        return data.category(c.categoryID)?.name ?? ""
    }

    /// Zweitzeile eines Vertragsblatts: «Vertragspartner · Kategorie»
    public func reportSheetSub(_ r: FixReport.Row) -> String {
        guard let c = data.contract(r.contractID) else { return r.category }
        let p = partnerName(c)
        return p + (p.isEmpty ? "" : " · ") + r.category
    }
}
