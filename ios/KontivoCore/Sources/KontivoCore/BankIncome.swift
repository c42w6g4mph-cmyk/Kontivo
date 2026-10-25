import Foundation

// MARK: - Kontoauszug: Einnahmen, Zahlungsart, Nummern, Bezeichnung, Person
// 1:1 nach Web v177/v180: BKINSKIP, bankIncCat, bankFindInc, bankPayM, bankNums, BKLABEL, bankLabel, bkWho.

extension BankImport {
    static let BKINSKIP = BRX("umbuchung|uebertrag|kontouebertrag|eigene?s? konto|sparkonto|twint|paypal|revolut|wise\\b|rueckerstattung|ruckerstattung|erstattung|refund|retoure?|storno|gutschrift karte|bargeld|einzahlung|bancomat|geldautomat|\\batm\\b|leistungsabrechnung|kostenbeteiligung|cashback|\\bausgleich\\b|saldoausgleich|steuerrueck|kontoubertrag|steuerruck")
    static let rxIncNotPay = BRX("(zins|ruck|rueck|aufwands|spesen|kosten)verg(ue|u)tung")
    static let rxIncBonus1 = BRX("\\b13 (monatslohn|gehalt)|\\bbonus|gratifikation|weihnachtsgeld|urlaubsgeld")
    static let rxIncLohn = BRX("\\blohn|nettolohn|gehalt|salaer|\\bsalar|salair|salary|payroll|bezuege|bezuge|besoldung|dienstbezug|entgelt|verguetung|vergutung|lohnzahlung|monatslohn")
    static let rxIncRente = BRX("rente|\\bahv\\b|\\biv\\b|pension|\\bbvg\\b|pensionskasse|vorsorgeeinrichtung|drv\\b|rentenversicherung")
    static let rxIncZulagen = BRX("kindergeld|kinderzulage|familienzulage|familienkasse|ausbildungszulage|elterngeld")
    static let rxIncMiete = BRX("mietzins|\\bmiete\\b|untermiete|mieteinnahme|mieteingang|mietertrag|jahresmiete|garagenmiete|\\bpacht")
    static let rxIncBonus2 = BRX("\\bbonus|gratifikation|erfolgsbeteiligung|weihnachtsgeld|urlaubsgeld|13 monatslohn|13 gehalt|jahresprämie|jahrespraemie|jahrespramie")
    static let rxIncKapital = BRX("ausschuettung|ausschuttung|dividende|dividend|ertragsgutschrift|ertraegnis|ertragnis|zinsgutschrift|zinsen|\\bzins\\b|interest|coupon|kupon")
    static let rxIncHilfe = BRX("unterhalt|alimente|kinderunterhalt|\\bbafoeg|\\bbafog|stipendium|wohngeld|buergergeld|burgergeld|sozialhilfe|arbeitslosengeld|\\balg\\b|krankengeld|elterngeld|taggeld")
    static let rxIncNeben = BRX("honorar|provision|nebenjob|minijob")
    static let rxTypeVerg = BRX("verg(ü|ue|u)tung", i: true)
    static let rxIncYearCat = BRX("^(Kapitalerträge|Vermietung|Bonus)$")
    static let rxIncYearWord = BRX("jahres|jaehrlich|jahrlich|annual|yearly|dividende|ausschuttung|ausschuettung")
    static let rxIncOnceCat = BRX("^(Lohn|Rente|Zulagen)$")

    /// Art einer Gutschrift aus dem normalisierten Text (Web `bankIncCat`; `h` mit lnorm: Umlaute ohne e, Bezüge → bezuge)
    static func incomeCategory(_ h0: String) -> String {
        let h = rxIncNotPay.replaceAll(h0, " ")
        if rxIncBonus1.test(h) { return "Bonus" }
        if rxIncLohn.test(h) { return "Lohn" }
        if rxIncRente.test(h) { return "Rente" }
        if rxIncZulagen.test(h) { return "Zulagen" }
        if rxIncMiete.test(h) { return "Vermietung" }
        if rxIncBonus2.test(h) { return "Bonus" }
        if rxIncKapital.test(h) { return "Kapitalerträge" }
        if rxIncHilfe.test(h) { return "Unterstützung" }
        if rxIncNeben.test(h) { return "Nebeneinkommen" }
        return "Sonstiges"
    }

    /// Wiederkehrende Gutschriften (Lohn, Rente, Zulagen …) finden (Web `bankFindInc`): gleiche Quelle, fester Rhythmus,
    /// ähnlicher Betrag. Umbuchungen, TWINT, Rückerstattungen und Zahlungen von dir selbst (Name einer Person)
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
            let nm = BankName.txName(t)
            if nm.isEmpty { continue }
            let hay = Partners.lnorm(nm + " " + t.text + " " + t.type)
            if BKINSKIP.test(hay) { continue }
            let tk = BankName.tok(nm)
            // Zahlung von dir selbst (anderes Konto): Name enthält einen Personennamen
            if me.contains(where: { w in !w.isEmpty && w.contains(where: { tk.contains($0) }) }) { continue }
            let cat = incomeCategory(Partners.lnorm(nm + " " + t.text + " " + rxTypeVerg.replaceAll(t.type, "")))
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
            key += (cat == "Bonus" ? "·bonus" : "") + "|" + cur
            var g = groups[key] ?? G(cur: cur)
            // gleiche Gutschrift in zwei Dateien nur einmal (Web v325)
            if let fi = t.fi, g.tx.contains(where: { $0.fi != fi && $0.date == t.date && $0.amount == t.amount }) {
                groups[key] = g
                continue
            }
            g.tx.append(t)
            g.names[nm] = (g.names[nm] ?? 0) + 1
            g.cats[cat] = (g.cats[cat] ?? 0) + 1
            groups[key] = g
        }
        var out: [BankIncomeSuggestion] = []
        var known: [BankIncomeKnown] = []
        var used = Set<UUID>()
        // Namen aller Quellen: eine erfasste Einnahme, deren Name zu einer anderen Quelle passt, darf nicht über Kategorie+Betrag
        // einer fremden Quelle zugeordnet werden (zwei Löhne im Haushalt, Web v272)
        var srcK = Set<String>()
        for k in groups.orderedKeys {
            for n in groups[k]?.names.orderedKeys ?? [] {
                let q = key1(BankName.pretty(n))
                if !q.isEmpty { srcK.insert(q) }
            }
        }
        for k in groups.orderedKeys {
            guard let g = groups[k] else { continue }
            var tx = BU.sorted(g.tx, byDate)
            var n = tx.count
            // Spesen, Korrekturen u.ä. von derselben Quelle (Arbeitgeber zahlt Lohn + Spesen): Beträge unter halbem Median stören den Rhythmus
            if n >= 4 {
                let s0 = tx.map { $0.amount }.sorted()
                let m0 = s0[s0.count / 2]
                let tk0 = tx.filter { $0.amount >= m0 * 0.5 }
                if tk0.count >= 3 && tk0.count < n {
                    tx = tk0
                    n = tx.count
                }
            }
            let cat = BU.sorted(g.cats.orderedKeys) { a, b in Double((g.cats[b] ?? 0) - (g.cats[a] ?? 0)) }.first ?? "Sonstiges"
            // einmal im Auszug: Lohn/Rente/Zulage → monatlich (neue Stelle); Jahreseinnahme (Dividende, Jahresmiete, Bonus, Jahresrente) → jährlich
            let h1 = Partners.lnorm(tx[0].name + " " + tx[0].text)
            let yrI = n == 1 && (rxIncYearCat.test(cat) || rxIncYearWord.test(h1))
            let once = n == 1 && (yrI || rxIncOnceCat.test(cat))
            if n < 2 && !once { continue }
            if cat == "Kapitalerträge" && !tx.contains(where: { $0.amount >= 20 }) { continue }
            var cyc = yrI ? 12 : 1
            if !once {
                var iv: [Int] = []
                for i in 1..<n { iv.append(tx[i - 1].date.days(to: tx[i].date)) }
                let cs = iv.map { cycle($0) }
                var cnt = BOrdered<Int>()
                for c in cs where c != 0 { cnt[String(c)] = (cnt[String(c)] ?? 0) + 1 }
                let top = BU.sorted(cnt.orderedKeys) { a, b in Double((cnt[b] ?? 0) - (cnt[a] ?? 0)) }.first
                cyc = top.flatMap { Int($0) } ?? 0
                if cyc == 0 || Double(cnt[String(cyc)] ?? 0) < Double(iv.count) * 0.6 { continue }
                if cyc == 1 && n < (cat == "Sonstiges" ? 4 : 2) { continue }
            }
            let am = tx.map { BU.r2($0.amount) }
            let srt = am.sorted()
            let med = srt[srt.count / 2]
            // Ausreisser nach oben (13. Monatslohn, Bonus) zählen nicht
            let core = am.filter { $0 <= med * 1.5 }
            let tol = cat == "Sonstiges" ? 0.05 : 0.2
            if Double(core.filter({ Swift.abs($0 - med) <= med * tol }).count) < Double(core.count) * 0.7 { continue }
            let last = tx[n - 1]
            if Double(last.date.days(to: gEnd(tx, ref))) > Double(cyc) * 30.5 * 1.5 + 7 { continue }
            let recent = Array(core.suffix(3))
            let typ = recent.sorted()[recent.count / 2]
            let lo = core.min() ?? 0, hi = core.max() ?? 0
            let due = nextDue(tx.map { $0.date }, cycle: cyc, today: today)
            let ks = BU.sorted(g.names.orderedKeys) { a, b in Double((g.names[b] ?? 0) - (g.names[a] ?? 0)) }
            let name = BankName.pretty(ks.first ?? "")
            let cur = Currency(rawValue: g.cur) == nil ? home : g.cur
            let s = BankIncomeSuggestion(key: k, name: name, label: cat == "Sonstiges" ? "" : cat, category: cat, currency: cur, amount: typ,
                                         cycle: cyc, due: due, count: n, first: tx[0].date, last: last.date, dates: tx.map { $0.date },
                                         amounts: am, lo: lo, hi: hi, varies: hi - lo > 0.005, skipped: am.count - core.count,
                                         raw: !last.name.isEmpty ? last.name : name, text: last.text, once: once,
                                         confidence: (cat != "Sonstiges" && n >= 2) || n >= 6 ? .high : .low)
            // schon erfasst? gleiche Quelle oder gleiche Art mit ähnlichem Betrag
            let k1 = key1(name)
            var hit: UUID? = nil
            for c in data.incomes {
                if hit != nil || used.contains(c.id) { continue }
                if c.currency.rawValue != s.currency { continue }
                var ck = key1(c.name)
                if ck.isEmpty { ck = key1(c.label) }
                if (!ck.isEmpty && ck == k1)
                    || (!(!ck.isEmpty && srcK.contains(ck)) && c.kind.displayName == s.category && s.category != "Sonstiges"
                        && Swift.abs(c.amount - s.amount) <= s.amount * 0.2) {
                    hit = c.id
                }
            }
            if let h = hit {
                used.insert(h)
                known.append(BankIncomeKnown(incomeID: h, suggestion: s))
            } else {
                out.append(s)
            }
            // Lohn mit Ausreisser nach oben (13. Monatslohn, Bonus im selben Lohnlauf): Zusatzbetrag als eigene Jahreseinnahme vorschlagen, ohne Häkchen
            if cat == "Lohn" && cyc == 1 && n >= 6 {
                // langer Auszug: nur der letzte 13. Monatslohn
                let big = tx.indices.filter { tx[$0].amount > med * 1.5 && tx[$0].date.days(to: ref) < 400 }
                if big.count == 1 {
                    let bi = big[0], bt = tx[bi]
                    let sep = tx.indices.contains { $0 != bi && BU.slice(tx[$0].date.iso, 0, 7) == BU.slice(bt.date.iso, 0, 7) }
                    let extra = BU.r2(sep ? bt.amount : bt.amount - med)
                    var bdue = bt.date
                    var gb = 0
                    while bdue < today && gb < 20 {
                        gb += 1
                        bdue = bt.date.addingMonthsE(12 * gb)
                    }
                    if extra >= 100 && !data.incomes.contains(where: { $0.kind == .bonus && $0.currency.rawValue == s.currency }) {
                        out.append(BankIncomeSuggestion(key: k + "·bonus", name: name, label: "13. Monatslohn / Bonus", category: "Bonus", currency: s.currency,
                                                        amount: extra, cycle: 12, due: bdue, count: 1, first: bt.date, last: bt.date, dates: [bt.date],
                                                        amounts: [extra], lo: extra, hi: extra, varies: false, skipped: 0,
                                                        raw: !bt.name.isEmpty ? bt.name : name, text: bt.text, once: true, confidence: .low))
                    }
                }
            }
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
        (BRX("hundesteuer"), "Hundesteuer"), (BRX("grundsteuer"), "Grundsteuer"), (BRX("bahncard"), "BahnCard"), (BRX("amazon prime|amzn prime"), "Amazon Prime"),
        (BRX("kfz steuer|kfzsteuer|kraftfahrzeugsteuer|motorfahrzeugsteuer|verkehrssteuer|strassenverkehrsamt"), "Kfz-Steuer"),
        (BRX("kfz|autoversicherung|motorfahrzeugversicherung|fahrzeugversicherung|kasko"), "Autoversicherung"), (BRX("rechtsschutz"), "Rechtsschutz"),
        (BRX("wohngebaeude|wohngebaude|gebaeudeversicherung|gebaudeversicherung"), "Gebäudeversicherung"), (BRX("unfallversicherung"), "Unfallversicherung"),
        (BRX("zahnzusatz|zusatzversicherung"), "Zusatzversicherung"), (BRX("berufsunfaehig|berufsunfahig|\\bbu\\b"), "Berufsunfähigkeit"),
        (BRX("risikoleben|lebensversicherung"), "Lebensversicherung"), (BRX("reiseversicherung|reiseruecktritt|reiseruckritt|reiseruecktritt"), "Reiseversicherung"),
        (BRX("tierhalter|hundehaftpflicht|tierkranken"), "Tierversicherung"),
        (BRX("\\bmiete\\b|mietzins|wohnungsmiete"), "Miete"), (BRX("nebenkosten|heizkosten"), "Nebenkosten"),
        (BRX("parkplatz|einstellplatz|tiefgarage|garage"), "Parkplatz"),
        (BRX("hypothek|darlehen|kreditrate|\\bkredit\\b"), "Kredit"), (BRX("leasing"), "Leasing"), (BRX("steuer|steuerverwaltung|finanzamt"), "Steuern"),
        (BRX("krankenkasse|krankenversicherung|grundversicherung"), "Krankenkasse"), (BRX("hausrat"), "Hausrat"), (BRX("haftpflicht"), "Haftpflicht"),
        (BRX("fitness|\\bgym\\b"), "Fitness"), (BRX("mitgliederbeitrag|mitgliedsbeitrag|jahresbeitrag|vereinsbeitrag"), "Mitgliedschaft"), (BRX("spende"), "Spende"),
        (BRX("kita|krippe|tagesmutter|hort"), "Kinderbetreuung"), (BRX("schulgeld|studiengebuehr|semestergebuehr"), "Ausbildung"),
    ]
    /// Allgemeine Katalog-Bezeichnung, die ein Zweck aus dem Buchungstext schlägt (Web v272 `BK_GENERIC`)
    static let BK_GENERIC = BRX("^(versicherung|versicherungen|mitgliedschaft|abo|vertrag|bank|konto)$", i: true)
    static let rxStartsDigit = BRX("^\\d")

    /// Bezeichnung eines Vorschlags (Web `bankLabel`): Mitteilung des Einzelpostens, sonst Katalog-Bezeichnung (ausser einer allgemeinen
    /// wie «Versicherung», wenn der Zahlungsgrund genauer ist), sonst aus dem Zahlungsgrund, sonst ""
    public static func label(_ s: BankSuggestion) -> String {
        if !s.memo.isEmpty && Partners.lusable(s.memo) && !rxStartsDigit.test(s.memo) {
            return BU.slice(s.memo, 0, 1).uppercased() + BU.slice(s.memo, 1)
        }
        let h = Partners.lnorm(s.text + " " + s.raw + " " + s.name)
        var t = ""
        for (r, l) in BKLABEL where r.test(h) {
            t = l
            break
        }
        // mehrere Policen beim selben Versicherer: Katalog-Bezeichnung (Hausrat) wäre geraten → leer lassen (Web v330)
        if s.multi { return t }
        if let c = s.catalog, !c.label.isEmpty, !(!t.isEmpty && BK_GENERIC.test(c.label)) { return c.label }
        return t
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
