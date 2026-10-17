import Foundation

// MARK: - Kontoauszug: Einnahmen, Zahlungsart, Nummern, Bezeichnung, Person
// 1:1 nach Web v177/v180: BKINSKIP, bankIncCat, bankFindInc, bankPayM, bankNums, BKLABEL, bankLabel, bkWho.

extension BankImport {
    static let BKINSKIP = BRX("umbuchung|uebertrag|kontouebertrag|eigene?s? konto|sparkonto|twint|paypal|revolut|wise\\b|rueckerstattung|ruckerstattung|erstattung|refund|retoure?|storno|gutschrift karte|zinsen|zins\\b|interest|bargeld|einzahlung|bancomat|geldautomat|\\batm\\b|leistungsabrechnung|kostenbeteiligung|cashback|ausgleich|steuerrueck")
    static let rxIncLohn = BRX("\\blohn|gehalt|salaer|salair|salary|payroll|bezuege|lohnzahlung|monatslohn")
    static let rxIncRente = BRX("rente|\\bahv\\b|\\biv\\b|pension|\\bbvg\\b|pensionskasse|vorsorgeeinrichtung|drv\\b|rentenversicherung")
    static let rxIncZulagen = BRX("kindergeld|kinderzulage|familienzulage|familienkasse|ausbildungszulage|elterngeld")
    static let rxIncMiete = BRX("mietzins|\\bmiete\\b|untermiete")

    /// Art einer Gutschrift aus dem normalisierten Text (Web `bankIncCat`)
    static func incomeCategory(_ h: String) -> String {
        if rxIncLohn.test(h) { return "Lohn" }
        if rxIncRente.test(h) { return "Rente" }
        if rxIncZulagen.test(h) { return "Zulagen" }
        if rxIncMiete.test(h) { return "Vermietung" }
        return "Sonstiges"
    }

    /// Wiederkehrende Gutschriften (Lohn, Rente, Zulagen) finden (Web `bankFindInc`): gleiche Quelle, fester Rhythmus,
    /// ähnlicher Betrag. Umbuchungen, TWINT, Rückerstattungen, Zinsen und Zahlungen von dir selbst (Name einer Person)
    /// werden ausgeschlossen. Nur Vorschläge – übernommen wird erst nach Bestätigung.
    public static func findIncome(_ r: BankFile, data: AppData, today: Day) -> BankIncomeResult {
        let home = data.settings.homeCurrency.rawValue
        guard let ref = r.to else { return BankIncomeResult() }
        struct G {
            var tx: [BankTx] = []
            var names = BOrdered<Int>()
            var cur: String
            var cats = BOrdered<Int>()
        }
        var groups = BOrdered<G>()
        // Web: Personen (settings.holders) und der alte Einzel-Absender (settings.sender, in Swift nicht vorhanden)
        let me: [[String]] = data.persons.map { p in BankName.tok(p.name).filter { $0.count >= 3 } }
        for t in r.tx {
            if !(t.amount > 0) || t.sub { continue }
            var nm = !t.name.isEmpty && !BankName.isType(t.name) ? BankName.clean(BankName.rxComma.split(t.name)[0]) : BankName.from(t.text)
            nm = BU.trim(rxNameCut.split(nm)[0])
            if nm.isEmpty { continue }
            let hay = Partners.lnorm(nm + " " + t.text + " " + t.type)
            if BKINSKIP.test(hay) { continue }
            let tk = BankName.tok(nm)
            // Zahlung von dir selbst (anderes Konto): Name enthält einen Personennamen
            if me.contains(where: { w in !w.isEmpty && w.contains(where: { tk.contains($0) }) }) { continue }
            let cat = incomeCategory(hay)
            let cur = t.currency.isEmpty ? home : t.currency
            // Anbieter aus dem Katalog (Krankenkasse, Telekom) zahlen meist Rückerstattungen – nur mit Lohn-/Rentenwort
            if BankCatalog.tpl(nm, t.text, cur) != nil && cat == "Sonstiges" { continue }
            var key: String
            if !t.cred.isEmpty {
                key = "cred:" + t.cred
            } else {
                key = tk.prefix(2).joined(separator: " ")
                if key.isEmpty { key = Partners.lnorm(nm) }
            }
            key += "|" + cur
            var g = groups[key] ?? G(cur: cur)
            g.tx.append(t)
            g.names[nm] = (g.names[nm] ?? 0) + 1
            g.cats[cat] = (g.cats[cat] ?? 0) + 1
            groups[key] = g
        }
        var out: [BankIncomeSuggestion] = []
        var known: [BankIncomeKnown] = []
        var used = Set<UUID>()
        for k in groups.orderedKeys {
            guard let g = groups[k] else { continue }
            let tx = BU.sorted(g.tx, byDate)
            let n = tx.count
            if n < 2 { continue }
            let cat = BU.sorted(g.cats.orderedKeys) { a, b in Double((g.cats[b] ?? 0) - (g.cats[a] ?? 0)) }.first ?? "Sonstiges"
            var iv: [Int] = []
            for i in 1..<n { iv.append(tx[i - 1].date.days(to: tx[i].date)) }
            let cs = iv.map { cycle($0) }
            var cnt = BOrdered<Int>()
            for c in cs where c != 0 { cnt[String(c)] = (cnt[String(c)] ?? 0) + 1 }
            let top = BU.sorted(cnt.orderedKeys) { a, b in Double((cnt[b] ?? 0) - (cnt[a] ?? 0)) }.first
            let cyc = top.flatMap { Int($0) } ?? 0
            if cyc == 0 || Double(cnt[String(cyc)] ?? 0) < Double(iv.count) * 0.6 { continue }
            if cyc == 1 && n < (cat == "Sonstiges" ? 4 : 2) { continue }
            let am = tx.map { BU.r2($0.amount) }
            let srt = am.sorted()
            let med = srt[srt.count / 2]
            // Ausreisser nach oben (13. Monatslohn, Bonus) zählen nicht
            let core = am.filter { $0 <= med * 1.5 }
            let tol = cat == "Sonstiges" ? 0.05 : 0.2
            if Double(core.filter({ Swift.abs($0 - med) <= med * tol }).count) < Double(core.count) * 0.7 { continue }
            let last = tx[n - 1]
            if Double(last.date.days(to: ref)) > Double(cyc) * 30.5 * 1.5 + 7 { continue }
            let recent = Array(core.suffix(3))
            let typ = recent.sorted()[recent.count / 2]
            let lo = core.min() ?? 0, hi = core.max() ?? 0
            var due = last.date
            var gg = 0
            while due < today && gg < 400 {
                gg += 1
                due = last.date.addingMonthsE(cyc * gg)
            }
            let ks = BU.sorted(g.names.orderedKeys) { a, b in Double((g.names[b] ?? 0) - (g.names[a] ?? 0)) }
            let name = BankName.pretty(ks.first ?? "")
            let cur = Currency(rawValue: g.cur) == nil ? home : g.cur
            let s = BankIncomeSuggestion(key: k, name: name, label: cat == "Sonstiges" ? "" : cat, category: cat, currency: cur, amount: typ,
                                         cycle: cyc, due: due, count: n, first: tx[0].date, last: last.date, dates: tx.map { $0.date },
                                         amounts: am, lo: lo, hi: hi, varies: hi - lo > 0.005, skipped: am.count - core.count,
                                         raw: !last.name.isEmpty ? last.name : name, text: last.text,
                                         confidence: (cat != "Sonstiges" && n >= 2) || n >= 6 ? .high : .low)
            // schon erfasst? gleiche Quelle oder gleiche Art mit ähnlichem Betrag
            let k1 = key1(name)
            var hit: UUID? = nil
            for c in data.incomes {
                if hit != nil || used.contains(c.id) { continue }
                if c.currency.rawValue != s.currency { continue }
                var ck = key1(c.name)
                if ck.isEmpty { ck = key1(c.label) }
                if (!ck.isEmpty && ck == k1) || (c.kind.displayName == s.category && s.category != "Sonstiges" && Swift.abs(c.amount - s.amount) <= s.amount * 0.2) {
                    hit = c.id
                }
            }
            if let h = hit {
                used.insert(h)
                known.append(BankIncomeKnown(incomeID: h, suggestion: s))
                continue
            }
            out.append(s)
        }
        out = BU.sorted(out) { a, b in
            let ra = a.confidence == .high ? 0 : 1, rb = b.confidence == .high ? 0 : 1
            if ra != rb { return Double(ra - rb) }
            return b.amount / Double(b.cycle) - a.amount / Double(a.cycle)
        }
        return BankIncomeResult(items: out, known: known)
    }

    // MARK: Zahlungsart, Nummern, Bezeichnung

    static let rxEbill = BRX("e ?bill|e ?rechnung")
    static let rxQR = BRX("\\bqr\\b|qr rechnung|qr-rechnung")

    /// Zahlungsart aus der Buchungsart (Web `bankPayM`): eBill, Lastschrift, Dauerauftrag, Karte, QR-Rechnung, sonst ""
    public static func payMethod(_ s: BankSuggestion) -> String {
        let h = Partners.lnorm(s.text + " " + s.raw)
        if rxEbill.test(h) { return "eBill" }
        if s.kind == .dd || !s.cred.isEmpty || !s.mref.isEmpty { return "Lastschrift (LSV/SEPA)" }
        if s.kind == .so { return "Dauerauftrag" }
        if s.kind == .card { return "Kreditkarte" }
        if rxQR.test(h) { return "QR-Rechnung" }
        return ""
    }

    static let rxCustNo = BRX("(?:kunden?[- ]?(?:nr|nummer)|kd\\.?[- ]?nr|kundennr|customer (?:no|number|id))\\.?:?\\s*([A-Z0-9][A-Z0-9.\\-/]{3,24})", i: true)
    static let rxContrNo = BRX("(?:vertrags?[- ]?(?:nr|nummer)|police(?:n[- ]?nr)?|polizze|policy (?:no|number)|versicherungs[- ]?(?:nr|nummer)|abo[- ]?nr)\\.?:?\\s*([A-Z0-9][A-Z0-9.\\-/]{3,24})", i: true)
    static let rxNoTail = BRX("[.\\-/]$")
    static let rxHasDigit = BRX("\\d")

    /// Kunden- und Vertragsnummer, wenn sie ausdrücklich im Buchungstext steht (Web `bankNums`: «Kd-Nr. 123456», «Police 12.345.678»)
    public static func numbers(_ s: BankSuggestion) -> (customer: String, contract: String) {
        let t = s.text + " " + s.raw
        var cust = "", contr = ""
        if let m = rxCustNo.match(t) { cust = rxNoTail.replaceFirst(m.s(1), "") }
        if let v = rxContrNo.match(t) { contr = rxNoTail.replaceFirst(v.s(1), "") }
        if !cust.isEmpty && !rxHasDigit.test(cust) { cust = "" }
        if !contr.isEmpty && !rxHasDigit.test(contr) { contr = "" }
        return (cust, contr)
    }

    /// Bezeichnung ohne Katalog aus dem Zahlungsgrund (Web `BKLABEL`): «Miete Wohnung 3.OG» → Miete
    static let BKLABEL: [(BRX, String)] = [
        (BRX("\\bmiete\\b|mietzins|wohnungsmiete"), "Miete"), (BRX("nebenkosten|heizkosten"), "Nebenkosten"),
        (BRX("parkplatz|einstellplatz|tiefgarage|garage"), "Parkplatz"),
        (BRX("hypothek|darlehen|kreditrate|\\bkredit\\b"), "Kredit"), (BRX("leasing"), "Leasing"), (BRX("steuer|steuerverwaltung|finanzamt"), "Steuern"),
        (BRX("krankenkasse|krankenversicherung|grundversicherung"), "Krankenkasse"), (BRX("hausrat"), "Hausrat"), (BRX("haftpflicht"), "Haftpflicht"),
        (BRX("fitness|\\bgym\\b"), "Fitness"), (BRX("mitgliederbeitrag|mitgliedsbeitrag|jahresbeitrag|vereinsbeitrag"), "Mitgliedschaft"), (BRX("spende"), "Spende"),
        (BRX("kita|krippe|tagesmutter|hort"), "Kinderbetreuung"), (BRX("schulgeld|studiengebuehr|semestergebuehr"), "Ausbildung"),
    ]

    /// Bezeichnung eines Vorschlags (Web `bankLabel`): Katalog-Bezeichnung, sonst aus dem Zahlungsgrund, sonst ""
    public static func label(_ s: BankSuggestion) -> String {
        if let t = s.catalog, !t.label.isEmpty { return t.label }
        let h = Partners.lnorm(s.text + " " + s.raw + " " + s.name)
        for (r, l) in BKLABEL where r.test(h) { return l }
        return ""
    }

    /// Name aus dem Auszug (Kontoinhaber, «Lohn Max Muster») → Personen (Web `bkWho`). Treffer über den Vornamen, sonst über
    /// den ganzen Namen. Mehrere Treffer (Gemeinschaftskonto «Max und Lena Muster») → alle Treffer (Aufrufer ordnet nur bei genau einem zu).
    public static func who(_ txt: String, persons: [Person]) -> [UUID] {
        if persons.count < 2 || txt.isEmpty { return [] }
        let t = BankName.tok(txt)
        return persons.filter { p in
            let w = BankName.tok(p.name)
            return !w.isEmpty && (t.contains(w[0]) || w.allSatisfy { t.contains($0) })
        }.map { $0.id }
    }
}
