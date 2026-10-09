import Foundation

// MARK: - Kontoauszug: wiederkehrende Belastungen finden, mit erfassten Verträgen abgleichen, Vorschlag → Vertrag
// 1:1 nach Web bankCycle, bankFind (mit bankLooseKnown, bankEval), bankIgnKey, bankApplyAlias, bankKey1, bankCands,
// bankMatchName, bankMatch, bankToContract.

public enum BankImport {
    /// Datei lesen: CSV, camt.052/053/054 oder MT940 (Web `bankRead`). Grösser als 20 MB → `.tooBig`.
    public static func read(_ data: Data) throws -> BankFile {
        try BankReader.read(data)
    }

    /// Mehrere Dateien zu einer Buchungsliste (Web `bankMerge`); gleiche Buchung aus überlappenden Exporten nur einmal.
    public static func merge(_ files: [BankFile]) -> BankFile {
        BankReader.merge(files)
    }

    /// Schlüssel für «Nie mehr vorschlagen» und gelernte Korrekturen (Web `bankIgnKey`): Gruppenschlüssel ohne Währung.
    public static func ignoreKey(_ s: BankSuggestion) -> String {
        s.key.components(separatedBy: "|")[0]
    }

    /// Zahlungsrhythmus aus einem Abstand in Tagen (Web `bankCycle`), 0 = keiner.
    static func cycle(_ days: Int) -> Int {
        let C = [(1, 25, 36), (2, 55, 66), (3, 84, 98), (6, 170, 195), (12, 350, 380)]
        for c in C where days >= c.1 && days <= c.2 { return c.0 }
        return 0
    }

    /// Markantes Wort eines Namens: erstes Wort ≥ 3 Zeichen, nicht generisch (Versicherung, Stadt …) (Web `bankKey1`).
    static func key1(_ n: String) -> String {
        BankName.tok(n).first { $0.count >= 3 && !Partners.LGEN.contains($0) && !Partners.LPLACE.contains($0) } ?? ""
    }

    // MARK: Gruppen

    struct Group {
        var key: String
        var tpl: CatalogEntry?
        var tx: [BankTx]
        var names: BOrdered<Int>
        var cur: String
    }

    /// Laufender Vertrag für den Abgleich (vorberechnet).
    struct Cand {
        let c: Contract
        let partner: String
        let cur: String
        let cycle: Int
        let price: Double
        let tplName: String?
        let ck: String
        let cl: String
    }

    enum Match {
        case known(UUID)
        case price(UUID, amount: Double, old: Double, from: Day)

        var id: UUID {
            switch self {
            case .known(let i): return i
            case .price(let i, _, _, _): return i
            }
        }
    }

    static let rxNameCut = BRX(";|\\s·\\s")
    static let rxVia = BRX("(?:einkauf bei|purchase at|payment to|zahlung an|abo bei|bei)\\s+([^,;·/]{3,40})", i: true)
    static let rxViaTail = BRX("\\s+\\d.*$")
    static let rxBankATM = BRX("^(sparkasse|volksbank|raiffeisen|commerzbank|deutsche bank|postbank|hypovereinsbank|targobank|santander|ubs|postfinance|zkb|kantonalbank|migros bank|valiant|atm|geldautomat)\\b")
    static let rxCardWords = BRX("\\bkarten?\\b|\\bcard\\b|kartenzahlung|kauf dienstleistung|\\bpos\\b|maestro|\\bvisa\\b|mastercard")

    static func byDate(_ a: BankTx, _ b: BankTx) -> Double { a.date < b.date ? -1 : (b.date < a.date ? 1 : 0) }

    /// Erstes «|» ersetzen (JS `k.replace("|", x)`).
    static func replacePipe(_ k: String, _ with: String) -> String {
        guard let r = k.range(of: "|") else { return k }
        return k.replacingCharacters(in: r, with: with)
    }

    // MARK: bankFind

    /// Wiederkehrende Belastungen finden und mit den erfassten Verträgen abgleichen (Web `bankFind`).
    /// Ausgeblendete (`settings.bankIgn`) bleiben mit `ignored = true` drin, gelernte Korrekturen (`settings.bankAlias`) gelten.
    public static func find(_ r: BankFile, data: AppData, today: Day) -> BankFindResult {
        let ign = data.settings.bankIgn
        let home = data.settings.homeCurrency.rawValue
        var groups = BOrdered<Group>()
        for t in r.tx {
            if t.amount >= 0 { continue }
            var nm = !t.name.isEmpty && !BankName.isType(t.name) ? BankName.clean(BankName.rxComma.split(t.name)[0]) : BankName.from(t.text)
            nm = BU.trim(rxNameCut.split(nm)[0])
            // PayPal, Klarna & Co.: eigentlicher Händler steht im Text («Ihr Einkauf bei Muster Cloud»)
            if BankCatalog.BKVIA.test(Partners.lnorm(nm)), let vm = rxVia.match(t.text), !BankCatalog.BKVIA.test(Partners.lnorm(vm.s(1))) {
                nm = BU.trim(rxViaTail.replaceFirst(vm.s(1), ""))
            }
            let nd = BankName.desc(nm)
            if BU.len(nd) >= 2 { nm = nd }
            let cur = t.currency.isEmpty ? home : t.currency
            let tp = BankCatalog.tpl(nm, t.text, cur)
            let hay = Partners.lnorm(nm + " " + t.text + " " + t.type)
            let ln = Partners.lnorm(nm)
            if tp == nil && BankCatalog.BKRETAIL.test(ln) { continue }
            // Kartenbezug am Automaten einer Bank («Sparkasse Konstanz», «UBS») = Bargeld
            if (t.kind == .card || (t.kind == .unknown && Swift.abs(t.amount).truncatingRemainder(dividingBy: 10) == 0)) && rxBankATM.test(ln) { continue }
            if BankCatalog.BKSKIP.test(hay) || BankCatalog.BKSHOP.test(ln) { continue }
            let tk = BankName.tok(nm)
            var key: String
            if let tp = tp {
                key = "tpl:" + tp.name
            } else if !t.cred.isEmpty {
                key = "cred:" + t.cred
            } else {
                key = tk.prefix(2).joined(separator: " ")
                if key.isEmpty { key = ln }
            }
            if key.isEmpty { continue }
            key += "|" + cur
            var g = groups[key] ?? Group(key: key, tpl: tp, tx: [], names: BOrdered<Int>(), cur: cur)
            g.tx.append(t)
            g.names[nm] = (g.names[nm] ?? 0) + 1
            groups[key] = g
        }
        // Nur eine Kartenzahlung und Katalogname aus einem Wort (Spiegel, Salt, Zeit): reicht nicht als Beleg.
        // Katalog nur behalten, wenn die Website im Buchungstext steht («spiegel.de»), sonst als unbekannter Händler behandeln
        for k in groups.orderedKeys {
            guard var g = groups[k], let tpl = g.tpl else { continue }
            if g.tx.count >= 2 || BankCatalog.BKALIAS[tpl.name] != nil || Partners.ltok(tpl.name).count != 1 { continue }
            // nur Kartenzahlungen: Lastschriften mit Mandat/Gläubiger-ID (Jahresprämie Allianz) sind echte Belege
            if g.tx.contains(where: { t in !t.cred.isEmpty || !t.mref.isEmpty || !(t.kind == .card || rxCardWords.test(Partners.lnorm(t.text + " " + t.type))) }) { continue }
            let raw = g.tx.map { $0.name + " " + $0.text }.joined(separator: " ").lowercased()
            var dom = tpl.web.lowercased()
            if dom.hasPrefix("www.") { dom = String(dom.dropFirst(4)) }
            if !dom.isEmpty && raw.contains(dom) { continue }
            g.tpl = nil
            groups[k] = g
        }
        // Gleiches erstes Wort, ähnlicher Betrag → zusammenführen (NETFLIX.COM / Netflix.com Amsterdam)
        let ks = groups.orderedKeys
        for a in ks {
            for b in ks {
                guard a != b, var A = groups[a], let B = groups[b], A.tpl == nil, B.tpl == nil, A.cur == B.cur,
                      !a.hasPrefix("cred:"), !b.hasPrefix("cred:") else { continue }
                let fa = a.components(separatedBy: "|")[0].components(separatedBy: " ")[0]
                let fb = b.components(separatedBy: "|")[0].components(separatedBy: " ")[0]
                if fa != fb || BU.len(fa) < 4 { continue }
                let ma = A.tx[A.tx.count - 1].amount, mb = B.tx[B.tx.count - 1].amount
                if Swift.abs(ma - mb) > Swift.abs(ma) * 0.1 { continue }
                A.tx = BU.sorted(A.tx + B.tx, byDate)
                for n in B.names.orderedKeys { A.names[n] = (A.names[n] ?? 0) + (B.names[n] ?? 0) }
                groups[a] = A
                groups[b] = nil
            }
        }
        // Gleiche Gläubiger-ID, verschiedene Mandate (zwei Policen bei derselben Versicherung): je Mandat eine Gruppe
        for k in groups.orderedKeys {
            guard let g = groups[k] else { continue }
            var by = BOrdered<[BankTx]>()
            for t in g.tx where !t.mref.isEmpty { by[t.mref] = (by[t.mref] ?? []) + [t] }
            let ms = by.orderedKeys.filter { (by[$0]?.count ?? 0) >= 2 }
            if ms.count < 2 { continue }
            groups[k] = nil
            for m in ms {
                let nk = replacePipe(k, "~" + Partners.lnorm(m).replacingOccurrences(of: " ", with: "") + "|")
                groups[nk] = Group(key: nk, tpl: g.tpl, tx: by[m] ?? [], names: g.names, cur: g.cur)
            }
        }
        // Gleicher Vertragspartner mit mehreren Verträgen (Hausrat + Haftpflicht, Strom + Gas): Beträge, die sich zeitlich
        // abwechseln, werden in eigene Gruppen getrennt. Nacheinander (Preisänderung) bleibt eine Gruppe.
        for k in groups.orderedKeys {
            guard let g = groups[k], g.tx.count >= 4 else { continue }
            // Cluster nach Lücken: neuer Cluster erst, wenn der nächste Betrag > 15 % über dem vorherigen liegt
            var cl: [(last: Double, tx: [BankTx])] = []
            for t in BU.sorted(g.tx, { x, y in y.amount - x.amount }) {
                let v = -t.amount
                if let c = cl.last, v <= c.last * 1.15 {
                    cl[cl.count - 1].tx.append(t)
                } else {
                    cl.append((last: v, tx: [t]))
                }
                cl[cl.count - 1].last = v
            }
            cl = cl.filter { $0.tx.count >= 2 }
            if cl.count < 2 { continue }
            let rng: [(Day, Day)] = cl.map { (c: (last: Double, tx: [BankTx])) -> (Day, Day) in
                let ds = c.tx.map { $0.date }.sorted()
                return (ds[0], ds[ds.count - 1])
            }
            var inter = false
            for a in rng.indices {
                for b in rng.indices where b > a && rng[a].0 < rng[b].1 && rng[b].0 < rng[a].1 { inter = true }
            }
            if !inter { continue }
            groups[k] = nil
            for (i, c) in cl.enumerated() {
                let nk = replacePipe(k, "#" + String(i + 1) + "|")
                groups[nk] = Group(key: nk, tpl: g.tpl, tx: BU.sorted(c.tx, byDate), names: g.names, cur: g.cur)
            }
        }

        // Abgleich vorbereiten: laufende Verträge
        let calc = Calc(data: data, today: today)
        let cands: [Cand] = data.contracts.compactMap { (c: Contract) -> Cand? in
            if c.status == .cancelled || calc.isEnded(c) { return nil }
            let p = data.partnerName(of: c)
            return Cand(c: c, partner: p, cur: c.currency.rawValue, cycle: c.cycleForCalc, price: calc.curPrice(c),
                        tplName: BankCatalog.tpl(p, "", c.currency.rawValue)?.name, ck: key1(p), cl: key1(c.label))
        }
        let alias = data.settings.bankAlias

        var out: [(s: BankSuggestion, match: Match?)] = []
        var known: [BankKnown] = []
        var used = Set<UUID>()
        guard let from = r.from, let to = r.to else {
            return BankFindResult(items: [], known: [], prices: [], ignoredCount: 0, all: [], from: r.from, to: r.to, count: r.tx.count, bank: r.bank, format: r.format)
        }
        let span = from.days(to: to)

        func applyAlias(_ s: inout BankSuggestion) {
            if let a = alias[ignoreKey(s)], !a.n.isEmpty {
                s.alias = a
                s.name = a.n
            }
        }

        // passende laufende Verträge (gleiche Währung): Katalogeintrag gleich oder erstes markantes Wort gleich (Web `bankCands`)
        func candidates(_ s: BankSuggestion, _ tpl: CatalogEntry?) -> [Cand] {
            let k1 = key1(s.name), k2 = key1(s.raw)
            return cands.filter { c in
                if c.cur != s.currency { return false }
                if let t = tpl, Partners.lnorm(c.partner) == Partners.lnorm(t.name) || c.tplName == t.name { return true }
                if !c.ck.isEmpty && (c.ck == k1 || c.ck == k2) { return true }
                return c.ck.isEmpty && !c.cl.isEmpty && (c.cl == k1 || c.cl == k2)
            }
        }

        // Web `bankMatchName`: Vertrag mit dem nächstgelegenen aktuellen Preis
        func matchName(_ s: BankSuggestion, _ tpl: CatalogEntry?) -> Cand? {
            let v = s.amounts[s.amounts.count - 1]
            return BU.sorted(candidates(s, tpl)) { a, b in Swift.abs(a.price - v) - Swift.abs(b.price - v) }.first
        }

        // Web `bankMatch`: gleicher Preis → bereits erfasst, sonst Preisänderung (höchstens 35 %)
        func match(_ s: BankSuggestion, _ tpl: CatalogEntry?) -> Match? {
            var best: (c: Cand, dm: Double)? = nil
            for c in candidates(s, tpl) {
                let dm = Swift.abs(c.price / Double(c.cycle) - s.amount / Double(s.cycle))
                if best == nil || dm < best!.dm { best = (c, dm) }
            }
            guard let b = best else { return nil }
            let cp = b.c.price, cc = Double(b.c.cycle), same = b.c.cycle == s.cycle
            let diff = same ? Swift.abs(cp - s.amount) : Swift.abs(cp / cc - s.amount / Double(s.cycle)) * cc
            if diff <= Swift.max(0.05, cp * 0.01) || s.varies { return .known(b.c.c.id) }
            // nur als Preisänderung melden, wenn der neue Betrag nach dem letzten erfassten Preis beginnt
            let fromD = (s.change != nil && same) ? s.change!.from : s.last
            // grosser Sprung (> 35 %) ist eher ein zweiter Vertrag beim gleichen Vertragspartner als eine Preisänderung
            let na = same ? s.amount : s.amount / Double(s.cycle) * cc
            if Swift.abs(na - cp) > cp * 0.35 { return nil }
            return .price(b.c.c.id, amount: same ? s.amount : BU.r2(s.amount / Double(s.cycle) * cc), old: cp, from: fromD)
        }

        for k in groups.orderedKeys {
            guard let g = groups[k] else { continue }
            if var s = eval(k, g, ref: to, span: span, today: today) {
                applyAlias(&s)
                s.category = BankCatalog.category(catalog: g.tpl, name: s.name, text: s.text, data: data)
                if let a = s.alias, !a.c.isEmpty, data.categories.contains(where: { $0.name == a.c }) { s.category = a.c }
                let m = match(s, g.tpl)
                if case .known(let id)? = m {
                    if !used.contains(id) {
                        used.insert(id)
                        known.append(BankKnown(contractID: id, suggestion: s, loose: false))
                    }
                    continue
                }
                if let m = m { used.insert(m.id) }
                if ign.contains(ignoreKey(s)) { s.ignored = true }
                out.append((s, m))
            } else if var s = loose(k, g) {
                // erkannte Gruppe, die als Vertrag bereits existiert, aber die strengen Regeln nicht erfüllt (schwankende Rechnung, nur 1 Zahlung)
                applyAlias(&s)
                guard let c = matchName(s, g.tpl) else { continue }
                let cp = c.price
                if !s.amounts.contains(where: { Swift.abs($0 - cp) <= cp * 0.35 }) { continue }
                if !used.contains(c.c.id) {
                    used.insert(c.c.id)
                    known.append(BankKnown(contractID: c.c.id, suggestion: s, loose: true))
                }
            }
        }
        out = BU.sorted(out) { a, b in
            let ma = a.match == nil ? 1 : 0, mb = b.match == nil ? 1 : 0
            if ma != mb { return Double(ma - mb) }
            if a.s.confidence.rank != b.s.confidence.rank { return Double(a.s.confidence.rank - b.s.confidence.rank) }
            return b.s.amount / Double(b.s.cycle) - a.s.amount / Double(a.s.cycle)
        }
        var prices: [BankPriceMatch] = []
        for o in out {
            if case .price(let id, let amount, let old, let fromD)? = o.match {
                prices.append(BankPriceMatch(contractID: id, from: fromD, amount: amount, old: old, suggestion: o.s))
            }
        }
        let items = out.filter { $0.match == nil }.map { $0.s }
        return BankFindResult(items: items, known: known, prices: prices, ignoredCount: items.filter { $0.ignored }.count,
                              all: out.map { $0.s }, from: from, to: to, count: r.tx.count, bank: r.bank, format: r.format)
    }

    /// Häufigster Name einer Gruppe, aufbereitet (Katalogname gewinnt).
    static func groupName(_ g: Group) -> String {
        if let t = g.tpl { return t.name }
        let ks = BU.sorted(g.names.orderedKeys) { a, b in Double((g.names[b] ?? 0) - (g.names[a] ?? 0)) }
        return BankName.pretty(ks.first ?? "")
    }

    /// Gruppe, die die strengen Regeln nicht erfüllt, als Kandidat für «bereits erfasst» (Web `bankLooseKnown`).
    static func loose(_ k: String, _ g: Group) -> BankSuggestion? {
        let tx = g.tx
        guard let lt = tx.last, let ft = tx.first else { return nil }
        let am = tx.map { BU.r2(-$0.amount) }
        return BankSuggestion(id: k, key: k, name: groupName(g), raw: lt.name, text: lt.text, currency: g.cur, amount: am[am.count - 1],
                              cycle: 1, due: lt.date, first: ft.date, last: lt.date, count: tx.count, dates: tx.map { $0.date }, amounts: am,
                              confidence: .low, varies: false, change: nil, catalogName: g.tpl?.name, category: "", kind: .unknown,
                              cred: "", mref: "", alias: nil, ignored: false)
    }

    /// Gruppe bewerten: Rhythmus, Betrag, Preisänderung, Sicherheit, nächste Zahlung (Web `bankEval`).
    static func eval(_ k: String, _ g: Group, ref: Day, span: Int, today: Day) -> BankSuggestion? {
        var kc = BOrdered<Int>()
        for t in g.tx where t.kind != .unknown { kc[t.kind.rawValue] = (kc[t.kind.rawValue] ?? 0) + 1 }
        let kind = BU.sorted(kc.orderedKeys) { a, b in Double((kc[b] ?? 0) - (kc[a] ?? 0)) }.first ?? ""
        var tx: [BankTx] = []
        var seen = Set<String>()
        for t in g.tx {
            let id = t.date.iso + "|" + String(t.amount)
            if seen.contains(id) { continue }
            seen.insert(id)
            tx.append(t)
        }
        let name = groupName(g)
        var am = tx.map { BU.r2(-$0.amount) }
        var last = am[am.count - 1]
        var n = tx.count
        var iv: [Int] = []
        for i in 1..<Swift.max(n, 1) { iv.append(tx[i - 1].date.days(to: tx[i].date)) }
        var cyc = 0
        var conf = BankConfidence.low
        var varies = false
        var ch: BankPriceChange? = nil
        if n >= 2 {
            let cs = iv.map { cycle($0) }
            var cnt: [Int: Int] = [:]
            for c in cs where c != 0 { cnt[c, default: 0] += 1 }
            // kleinster Rhythmus, bei dem ≥ 70 % der Abstände passen; eine fehlende Zahlung (doppelter Abstand) zählt mit
            let dbl: [Int: Int] = [1: 2, 2: 4, 3: 6, 6: 12]
            for c0 in cnt.keys.sorted() {
                let h = cs.filter { $0 == c0 || $0 == dbl[c0] }.count
                if Double(h) >= Double(iv.count) * 0.7 && Double(cnt[c0] ?? 0) >= Swift.max(1, Double(iv.count) * 0.3) {
                    cyc = c0
                    break
                }
            }
            if cyc == 0 { return nil }
            // Beträge: höchstens zwei Stufen (Preisänderung) oder ±5 % um den Median, sonst variabel (Einkäufe)
            var lv: [Double] = []
            for v in am where lv.isEmpty || Swift.abs(lv[lv.count - 1] - v) > 0.004 { lv.append(v) }
            let dist = Set(am).count
            // ohne Katalog/Gläubiger-ID braucht der Name ein markantes Wort (nicht «M», «SB 12»)
            if g.tpl == nil && tx[0].cred.isEmpty && !Partners.lusable(name) { return nil }
            func nlv(_ v: Double) -> Int { am.filter { Swift.abs($0 - v) <= 0.004 }.count }
            if dist <= 2 && lv.count <= 2 {
                if lv.count == 2 {
                    // Preisänderung nur, wenn der alte Preis mindestens zweimal vorkommt und sich höchstens um 35 % ändert
                    if nlv(lv[0]) < 2 || Swift.abs(lv[1] - lv[0]) > lv[0] * 0.35 {
                        // alter Preis nur einmal ganz am Anfang des Auszugs: Vertrag mit dem neuen Preis vorschlagen
                        if nlv(lv[0]) == 1 && nlv(lv[1]) >= 3 && am[0] == lv[0] && Swift.abs(lv[1] - lv[0]) <= lv[0] * 0.35 {
                            tx = Array(tx.dropFirst())
                            am = Array(am.dropFirst())
                            n = tx.count
                            last = lv[1]
                        } else if n < 3 || Swift.abs(lv[1] - lv[0]) > lv[0] * 0.05 {
                            return nil
                        }
                    } else if let j = am.firstIndex(of: lv[1]) {
                        ch = BankPriceChange(from: tx[j].date, prev: lv[0], amount: lv[1])
                    }
                }
            } else {
                if n < 3 { return nil }
                // schwankende Beträge nur bei Rechnungen/Lastschriften (Strom, Handy); Kartenabos haben einen festen Preis
                if kind == "card" && g.tpl == nil { return nil }
                let srt = am.sorted()
                let med = srt[srt.count / 2]
                if Double(am.filter({ Swift.abs($0 - med) <= med * 0.10 }).count) < Double(am.count) * 0.7 { return nil }
                varies = true
                last = med
            }
            // beendet? letzte Zahlung deutlich länger her als der Rhythmus
            if Double(tx[n - 1].date.days(to: ref)) > Double(cyc) * 30.5 * 1.5 + 7 { return nil }
            // erst ab 3 Zahlungen sicher; Quartal/Jahr ab 2. Lastschrift/Dauerauftrag monatlich mit 2 Zahlungen «mittel»
            if n >= 3 || cyc >= 3 {
                conf = varies ? .medium : .high
            } else {
                conf = (kind == "dd" || kind == "so") ? .medium : .low
            }
        } else {
            // Einzelzahlung nur bei bekanntem Anbieter oder SEPA-Lastschrift mit Gläubiger-ID; Rhythmus vermutlich jährlich
            let t0 = tx[0]
            if g.tpl == nil && ((t0.cred.isEmpty && kind != "dd") || BankCatalog.BKVIA.test(Partners.lnorm(name))) { return nil }
            // kurzer Auszug und Zahlung ganz am Ende: eher monatlich; bei langem Auszug (> 10 Monate) wäre eine Monatszahlung mehrfach drin
            cyc = (t0.date.days(to: ref) < 40 && span > 40 && span <= 300) ? 1 : 12
            // internationale Monatsabos (Netflix…) mit nur einer Zahlung: eher Einkauf
            if let t = g.tpl, t.country.isEmpty, cyc == 12, t0.date.days(to: ref) > 45 { return nil }
            conf = .low
        }
        // nächste Zahlung: ab letzter Buchung im Rhythmus weiter bis heute
        let lastD = tx[n - 1].date
        var due = lastD
        var gg = 0
        while due < today && gg < 400 {
            gg += 1
            due = lastD.addingMonthsE(cyc * gg)
        }
        let lt = tx[n - 1]
        return BankSuggestion(id: k, key: k, name: name, raw: !lt.name.isEmpty ? lt.name : BankName.from(lt.text), text: lt.text, currency: g.cur,
                              amount: BU.r2(last), cycle: cyc, due: due, first: tx[0].date, last: lt.date, count: n, dates: tx.map { $0.date },
                              amounts: am, confidence: conf, varies: varies, change: ch, catalogName: g.tpl?.name, category: "",
                              kind: BankKind(web: kind), cred: lt.cred, mref: lt.mref, alias: nil, ignored: false)
    }

    // MARK: Vorschlag → Vertrag

    /// Vorschlag → Vertrag (Web `bankToContract`): Katalogwerte (Bezeichnung, Frist, Kündigungsweg, Kontakt), Preisverlauf bei
    /// Preisänderung. `persons`: Namen der Personen. Vertragspartner nur verknüpft, wenn es ihn schon gibt (sonst `add` verwenden).
    public static func toContract(_ s: BankSuggestion, persons: [String], data: AppData, today: Day, now: Date = Date()) -> Contract {
        let t = s.catalogEntry
        let base = s.change?.prev ?? s.amount
        var c = Contract(label: t?.label ?? "", amount: BU.r2(base), currency: Currency(rawValue: s.currency) ?? data.settings.homeCurrency,
                         cycle: s.cycle, due: s.due, createdAt: now)
        c.partnerID = Partners.find(s.name, in: data)?.id
        c.categoryID = (data.category(named: s.category) ?? data.categories.first(where: { $0.name.lowercased() == s.category.lowercased() }))?.id
        if let t = t {
            c.notice = t.notice
            c.noticeUnit = t.noticeUnit
            c.cancelTerm = t.cancelTerm
            c.mandatory = t.mandatory
            c.cancelChannel = t.cancelChannel
            c.cancelURL = t.cancelChannel == .online ? t.cancelURL : ""
            c.tel = t.tel
            c.mail = t.mail
        }
        for p in persons {
            if let id = (data.person(named: p) ?? data.persons.first(where: { $0.name.lowercased() == p.lowercased() }))?.id, !c.holderIDs.contains(id) {
                c.holderIDs.append(id)
            }
        }
        if let chg = s.change { c.prices = [PriceChange(from: chg.from, amount: chg.amount)] }
        // Steuern & Gebühren: nicht kündbar
        if let tax = BankCatalog.categoryName(key: "Steuern & Gebühren", in: data), tax == s.category {
            c.noCancel = true
            c.mandatory = false
            c.cancelTerm = .anytime
        }
        return c
    }

    /// Vorschlag als Vertrag anlegen: Vertragspartner finden oder anlegen (Website und Adresse aus dem Katalog), Vertrag anhängen.
    @discardableResult
    public static func add(_ s: BankSuggestion, persons: [String], to data: inout AppData, today: Day, now: Date = Date()) -> UUID {
        var c = toContract(s, persons: persons, data: data, today: today, now: now)
        let pn = BU.trim(s.name)
        if c.partnerID == nil && !pn.isEmpty {
            let t = s.catalogEntry
            let addr = (t?.address ?? "").replacingOccurrences(of: "\r\n", with: "\n")
            let p = Partner(name: pn, web: t?.web ?? "", address: addr.isEmpty ? PostalAddress() : WebImport.addrSplit(addr, partnerName: pn))
            data.partners.append(p)
            c.partnerID = p.id
        } else if let pid = c.partnerID, let pi = data.partnerIndex(pid), let t = s.catalogEntry {
            if data.partners[pi].web.isEmpty && !t.web.isEmpty { data.partners[pi].web = t.web }
            if data.partners[pi].address.isEmpty && !t.address.isEmpty { data.partners[pi].address = WebImport.addrSplit(t.address, partnerName: pn) }
        }
        data.contracts.append(c)
        return c.id
    }

    /// «Nie mehr vorschlagen» (Web `bankIgn`).
    public static func ignore(_ s: BankSuggestion, in data: inout AppData) {
        let k = ignoreKey(s)
        if !data.settings.bankIgn.contains(k) { data.settings.bankIgn.append(k) }
    }

    /// Korrektur merken, wenn Vertragspartner oder Kategorie beim Anlegen geändert wurden (Web `settings.bankAlias`).
    public static func rememberCorrection(_ original: BankSuggestion, name: String, category: String, in data: inout AppData) {
        if name != original.name || category != original.category {
            data.settings.bankAlias[ignoreKey(original)] = BankAlias(n: name, c: category)
        }
    }

    /// Neuen Preis übernehmen (Web: Preisstufe am gleichen Datum ersetzen, nach Datum sortiert).
    public static func applyPrice(_ p: BankPriceMatch, to data: inout AppData) {
        guard let i = data.contractIndex(p.contractID) else { return }
        var pr = data.contracts[i].prices.filter { $0.from != p.from }
        pr.append(PriceChange(from: p.from, amount: p.amount))
        data.contracts[i].prices = BU.sorted(pr) { a, b in a.from < b.from ? -1 : (b.from < a.from ? 1 : 0) }
    }
}
