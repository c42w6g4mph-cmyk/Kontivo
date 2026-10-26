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

    /// Schlüssel für «Nie mehr vorschlagen» und gelernte Korrekturen (Web `bankIgnKey`): Gruppenschlüssel ohne Währung. Unterreihen eines
    /// Vertragspartners (Policen, zwei Abos, Datei-Trennung: Zusatz %, @, ^, # nach der Währung) bekommen einen inhaltlichen Zusatz –
    /// Rhythmus und Fälligkeitsmonat bzw. Zahltag –, damit eine Korrektur nicht alle trifft (Web Review B-H6)
    public static func ignoreKey(_ s: BankSuggestion) -> String {
        let p = s.key.components(separatedBy: "|")
        var b = p[0]
        if p.dropFirst().joined(separator: "|").contains(where: { "%@^#".contains($0) }) {
            let d = s.due.iso, c = Swift.max(1, s.cycle)
            b += "~c" + String(c) + "-" + (c >= 3 ? BU.slice(d, 5, 7) : jsNum(BU.round(Double(Swift.max(1, s.due.day)) / 7)))
        }
        return b
    }

    /// Schlüssel ohne Unterreihen-/Mitteilungszusatz «~…» (Web: `bankIgnKey(s).split("~")[0]`)
    static func ignoreKeyStem(_ s: BankSuggestion) -> String {
        ignoreKey(s).components(separatedBy: "~")[0]
    }

    /// Schlüssel ohne «·Bezeichnung» (seit Web v212: alte Einträge «tpl:CSS» gelten weiter)
    static func ignoreKeyBase(_ s: BankSuggestion) -> String {
        ignoreKey(s).components(separatedBy: "·")[0]
    }

    /// Zahlungsrhythmus aus einem Abstand in Tagen (Web `bankCycle`), 0 = keiner. Jährlich 330–400 Tage: Jahresrechnungen per QR
    /// werden mal früher, mal später bezahlt (Web v328).
    static func cycle(_ days: Int) -> Int {
        let C = [(1, 25, 36), (2, 55, 66), (3, 80, 105), (6, 170, 195), (12, 330, 400)]
        for c in C where days >= c.1 && days <= c.2 { return c.0 }
        return 0
    }

    /// Jüngstes Dateiende der Buchungen einer Gruppe (beim Zusammenführen gesetzt), sonst Ende des Gesamtzeitraums (Web v325 `bankGEnd`)
    static func gEnd(_ tx: [BankTx], _ fb: Day) -> Day {
        var m: Day? = nil
        for t in tx { if let e = t.end, m == nil || e > m! { m = e } }
        return m ?? fb
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
        /// Vorgänger-Stufe (Web v272 `prevC`): letzte Zahlung und Betrag der vorherigen Preisstufe
        var prevC: (d: Day, amount: Double, tx: [BankTx])? = nil
        /// Rückfallebene (Web `bankFallback`): Jahresreihe nach Kalendermonat, davon halbjährlich; Rechnungen je Jahr mit Betrag
        /// der neusten Rechnung; Vertragspartner hat schon eine erkannte Reihe
        var yearly = false
        var half = false
        var period = false
        var periodAmt: Double = 0
        var hasSeries = false
    }

    /// Laufender Vertrag für den Abgleich (vorberechnet).
    struct Cand {
        let c: Contract
        let partner: String
        let cur: String
        let cycle: Int
        let price: Double
        /// erfasster Zahltermin (Web `c.due`)
        let due: Day?
        let tplName: String?
        let ck: String
        let cl: String
        /// laufend (nicht im Archiv, nicht beendet)
        let live: Bool
        /// Kategorie (Name) und Fachschlüssel (Web `catKey`)
        let catName: String
        let catKind: CategoryKind?
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
    static let rxATMKeep = BRX("\\b3a\\b|vorsorge|saeule|saule|leasing|hypothek|amortisation|darlehen|sparplan|bauspar|kredit|zins")
    static let rxATMHay = BRX("bezug|automat|bancomat|\\batm\\b|\\bgaa\\b|bargeld")
    static let rxInterest = BRX("\\bzinsen\\b|habenzins|sollzins|kontozins")
    static let rxInterestKeep = BRX("hypothek|darlehen|kredit|leasing")
    static let rxNoConKeep = BRX("versicherung|praemie|pramie|zusatz|\\bkvg\\b|\\bvvg\\b|krankenkasse|assekuranz")
    static let rxFirmME = BRX("\\b(ag|gmbh|sa|sarl|kg|ohg|ug|se|ltd|inc|genossenschaft|verein|stiftung|e v|ev)\\b")
    static let rxSelfSo = BRX("dauerauftrag|ubertrag|uebertrag|sparen")
    static let rxTopUp = BRX("^(revolut|wise|transferwise|curve|skrill|neteller)\\b")
    static let rxBaseStop = BRX("^(stadt|gemeinde|kanton|steuer|verwaltung|stiftung|verein|genossenschaft|schweiz|deutsch)")
    static let rxBaseTag = BRX("^(tpl|cred):")
    static let rxBaseCut = BRX("#[^|#]*")
    static let rxRetailKeep = BRX("fitness|mitglied|abo\\b|abonnement")
    static let rxBankATM = BRX("^(sparkasse|volksbank|raiffeisen|commerzbank|deutsche bank|postbank|hypovereinsbank|targobank|santander|ubs|postfinance|zkb|kantonalbank|migros bank|valiant|atm|geldautomat)\\b")
    static let rxCardWords = BRX("\\bkarten?\\b|\\bcard\\b|kartenzahlung|kauf dienstleistung|\\bpos\\b|maestro|\\bvisa\\b|mastercard")

    static func byDate(_ a: BankTx, _ b: BankTx) -> Double { a.date < b.date ? -1 : (b.date < a.date ? 1 : 0) }

    /// Erstes «|» ersetzen (JS `k.replace("|", x)`).
    static func replacePipe(_ k: String, _ with: String) -> String {
        guard let r = k.range(of: "|") else { return k }
        return k.replacingCharacters(in: r, with: with)
    }

    // MARK: bankFind

    static let rxMemoNum = BRX("\\d+")
    static let rxMemoMonth = BRX("\\b(januar|februar|marz|maerz|april|mai|juni|juli|august|september|oktober|november|dezember|jan|feb|mar|apr|jun|jul|aug|sep|sept|okt|oct|nov|dez|dec)\\b")
    static let rxMergeStop = BRX("^(stadt|gemeinde|kanton|steuer)")
    static let rxSameGen = BRX("^(gemeinde|stadt|stadtverwaltung|verwaltung|kanton|finanzabteilung|steueramt|steuerverwaltung|ag|gmbh|sa|kg|co|und|der|die|das|schweiz|schweizerische|deutschland|versicherung|versicherungen|bank|genossenschaft)$")
    /// Abbuchung bis 5 Tage nach dem Ende gilt noch als regulär (Valuta, Wochenende), Web `BK_GRACE`
    static let graceDays = 5

    /// Median der Beträge (positiv) einer Buchungsliste (Web `mdn`)
    static func median(_ L: [BankTx]) -> Double {
        let a = L.map { -$0.amount }.sorted()
        return a[a.count / 2]
    }

    /// JS-Zahl als Text (29.9 → «29.9», 45 → «45»)
    static func jsNum(_ x: Double) -> String {
        if x == x.rounded() && Swift.abs(x) < 1e15 { return String(Int(x)) }
        return "\(x)"
    }

    /// Wiederkehrende Belastungen finden und mit den erfassten Verträgen abgleichen (Web `bankFind`).
    /// Ausgeblendete (`settings.bankIgn`) bleiben mit `ignored = true` drin, gelernte Korrekturen (`settings.bankAlias`) gelten.
    public static func find(_ r: BankFile, data: AppData, today: Day) -> BankFindResult {
        let ign = data.settings.bankIgn
        let home = data.settings.homeCurrency.rawValue
        var groups = BOrdered<Group>()
        let ME = selfNames(r, data)
        for (ti, t0) in r.tx.enumerated() {
            if t0.amount >= 0 { continue }
            var t = t0
            t.seq = ti
            var nm = BankName.txName(t, home: home)
            // Kontoführung ohne Empfänger («ENTGELTABSCHLUSS · Entgeltabrechnung siehe Anlage») → Vertragspartner = die Bank
            if !(!t.name.isEmpty && !BankName.isType(t.name)) && BankCatalog.BKFEE.test(Partners.lnorm(t.type + " " + t.text)) {
                nm = !r.bank.isEmpty ? r.bank : "Bank"
            }
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
            // Detailhändler (Migros, Coop …) nur bei Kartenkäufen ausfiltern – Lastschrift/Dauerauftrag/Abo (z.B. «Migros Fitnesspark») bleibt
            if tp == nil && BankCatalog.BKRETAIL.test(ln) && !(t.kind == .dd || t.kind == .so || !t.cred.isEmpty || rxRetailKeep.test(hay)) { continue }
            // Kartenbezug am Automaten einer Bank («Sparkasse Konstanz», «UBS») = Bargeld
            if (t.kind == .card || (t.kind == .unknown && Swift.abs(t.amount).truncatingRemainder(dividingBy: 10) == 0) || rxATMHay.test(hay))
                && !rxATMKeep.test(hay) && rxBankATM.test(ln) { continue }
            if BankCatalog.BKSKIP.test(hay) || BankCatalog.BKSHOP.test(ln) { continue }
            // Konto-/Habenzinsen sind kein Vertrag, Hypothekar-/Darlehenszinsen schon (Web Review B-M5)
            if rxInterest.test(hay) && !rxInterestKeep.test(hay) { continue }
            // Arzt, Spital, Bussen: nur am Namen erkannt und nicht, wenn es um eine Versicherung geht (Spitalzusatz, Web Review B-H3)
            if BankCatalog.BKNOCON.test(ln) && !rxNoConKeep.test(hay) { continue }
            // Zahlung an dich selbst oder an eine andere erfasste Person (Dauerauftrag «Sinan Bayat Sparen», Web Review B-H2)
            if !ME.isEmpty && !rxFirmME.test(ln) {
                let nt = BankName.tok(nm)
                let me = ME.contains { w in
                    // nur Vorname bekannt: Dauerauftrag an «Vorname …»
                    if w.count == 1, w[0].hasPrefix("^") {
                        return nt.count >= 2 && nt.count <= 4 && nt[0] == String(w[0].dropFirst()) && (t.kind == .so || rxSelfSo.test(hay))
                    }
                    return !w.isEmpty && w.allSatisfy { nt.contains($0) }
                }
                if me { continue }
            }
            // Aufladung eines E-Geld-Kontos per Karte mit rundem Betrag (Revolut, Wise): Umbuchung, kein Vertrag
            if t.kind == .card && Swift.abs(t.amount).truncatingRemainder(dividingBy: 5) == 0 && rxTopUp.test(ln) { continue }
            // Zahlungsdienst (PayPal, Klarna …): alle Händler teilen dieselbe Gläubiger-ID → kein Vertragsmerkmal (Web Review B-H1)
            if !t.cred.isEmpty && BankCatalog.BKVIA.test(Partners.lnorm(t.name + " " + t.cred)) { t.cred = "" }
            let tk = BankName.tok(nm)
            var key: String
            if let tp = tp {
                // gleicher Name mehrfach im Katalog (CSS Krankenkasse/Zusatzversicherung): eigene Gruppe je Bezeichnung
                key = "tpl:" + tp.name + (BankCatalog.duplicateNames.contains(tp.name) ? "·" + tp.label : "")
            } else if !t.cred.isEmpty {
                key = "cred:" + t.cred
            } else {
                key = tk.prefix(2).joined(separator: " ")
                if key.isEmpty { key = ln }
            }
            if key.isEmpty { continue }
            // Einzelposten im Sammelauftrag mit Mitteilung («Vollkasko Audi»): eigene Gruppe je Zweck (Web v272)
            if !t.memo.isEmpty {
                let mk = BU.slice(rxMemoMonth.replaceAll(rxMemoNum.replaceAll(Partners.lnorm(t.memo), " "), " ").replacingOccurrences(of: " ", with: ""), 0, 24)
                if !mk.isEmpty { key += "~" + mk }
            }
            key += "|" + cur
            t.groupName = nm
            var g = groups[key] ?? Group(key: key, tpl: tp, tx: [], names: BOrdered<Int>(), cur: cur)
            // dieselbe Zahlung in zwei Dateien (Sparkasse- und N26-Export desselben Kontos, Konto + Kreditkarte): beim selben
            // Vertragspartner nur einmal (Web v325)
            // nur bei Exporten desselben Kontos (Web Review B-H5)
            if let fi = t.fi, g.tx.contains(where: { $0.fi != fi && $0.acc == t.acc && $0.date == t.date && $0.amount == t.amount }) {
                groups[key] = g
                continue
            }
            g.tx.append(t)
            g.names[nm] = (g.names[nm] ?? 0) + 1
            groups[key] = g
        }
        mergeFiles(&groups)
        // alle Zahlungen je Vertragspartner merken, bevor Betrags-Cluster Ausreisser verwerfen: die Rückfallebene (Jahresreihen) braucht sie
        // (Police 300.50 / 362.94 / 303.69 – die mittlere fiel sonst als Ausreisser weg)
        var ALLB = BOrdered<[BankTx]>()
        for k in groups.orderedKeys {
            let b = base(k)
            var L = ALLB[b] ?? []
            var seen = Set(L.map { $0.seq })
            for t in groups[k]?.tx ?? [] where seen.insert(t.seq).inserted { L.append(t) }
            ALLB[b] = L
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
        // Lastschrift und Einzelrechnungen desselben Anbieters mit ganz anderen Beträgen trennen (Web v272):
        // SWICA Prämie 1'279.50 per LSV vs. Kostenbeteiligungen 28–36 per QR-Rechnung
        for k in groups.orderedKeys {
            guard var g = groups[k] else { continue }
            let D = g.tx.filter { $0.kind == .dd && $0.cred.isEmpty }
            let O = g.tx.filter { !($0.kind == .dd && $0.cred.isEmpty) }
            if D.isEmpty || O.isEmpty { continue }
            let ma = median(D), mb = median(O)
            if Swift.abs(ma - mb) <= Swift.max(ma, mb) * 0.35 { continue }
            g.tx = O
            groups[k] = g
            let nk = replacePipe(k, "~dd|")
            groups[nk] = Group(key: nk, tpl: g.tpl, tx: D, names: g.names, cur: g.cur)
        }
        // Gleiches erstes Wort, ähnlicher Betrag → zusammenführen (NETFLIX.COM / Netflix.com Amsterdam)
        let ks = groups.orderedKeys
        for a in ks {
            for b in ks {
                guard a != b, var A = groups[a], let B = groups[b], A.tpl == nil, B.tpl == nil, A.cur == B.cur,
                      !a.hasPrefix("cred:"), !b.hasPrefix("cred:") else { continue }
                let fa = a.components(separatedBy: "|")[0].components(separatedBy: " ")[0]
                let fb = b.components(separatedBy: "|")[0].components(separatedBy: " ")[0]
                if fa != fb || BU.len(fa) < 4 || Partners.LGEN.contains(fa) || Partners.LPLACE.contains(fa) || rxMergeStop.test(fa) { continue }
                let ma = A.tx[A.tx.count - 1].amount, mb = B.tx[B.tx.count - 1].amount
                if Swift.abs(ma - mb) > Swift.abs(ma) * 0.1 { continue }
                // zahlen beide im selben Monat (Hans Mueller Garage und Hans Meier Putzhilfe je 150.–), sind es zwei Verträge (Web Review B-M3)
                let MA = Set(A.tx.map { BU.slice($0.date.iso, 0, 7) })
                if B.tx.filter({ MA.contains(BU.slice($0.date.iso, 0, 7)) }).count >= 2 { continue }
                A.tx = BU.sorted(A.tx + B.tx, byDate)
                for n in B.names.orderedKeys { A.names[n] = (A.names[n] ?? 0) + (B.names[n] ?? 0) }
                groups[a] = A
                groups[b] = nil
            }
        }
        // Gleiche Gläubiger-ID, verschiedene Mandate (zwei Policen bei derselben Versicherung): je Mandat eine Gruppe,
        // auch Einzelzahlungen je Mandat (Hausrat im Januar, Kfz im Februar bei derselben Versicherung)
        for k in groups.orderedKeys {
            guard let g = groups[k] else { continue }
            var by = BOrdered<[BankTx]>()
            for t in g.tx where !t.mref.isEmpty { by[t.mref] = (by[t.mref] ?? []) + [t] }
            let ms = by.orderedKeys
            if ms.count < 2 { continue }
            // Mandate nacheinander (neues Mandat beim selben Anbieter, Web Review B-M4) = ein Vertrag; nur trennen, wenn sie sich überschneiden
            let rg: [(Day, Day)] = ms.map { m in
                let L = by[m] ?? []
                return (L[0].date, L[L.count - 1].date)
            }
            let ov = rg.indices.contains { i in rg.indices.contains { j in i != j && rg[i].0 < rg[j].1 && rg[j].0 < rg[i].1 } }
            if !ov { continue }
            let rest = g.tx.filter { $0.mref.isEmpty }
            groups[k] = nil
            for m in ms {
                let nk = replacePipe(k, "~" + Partners.lnorm(m).replacingOccurrences(of: " ", with: "") + "|")
                groups[nk] = Group(key: nk, tpl: g.tpl, tx: by[m] ?? [], names: g.names, cur: g.cur)
            }
            if !rest.isEmpty { groups[k] = Group(key: k, tpl: g.tpl, tx: rest, names: g.names, cur: g.cur) }
        }
        // Gleicher Vertragspartner mit mehreren Verträgen (Hausrat + Haftpflicht, Strom + Gas): Beträge, die sich zeitlich
        // abwechseln, werden in eigene Gruppen getrennt. Nacheinander (Preisänderung) bleibt eine Gruppe.
        for k in groups.orderedKeys {
            guard let g = groups[k], g.tx.count >= 4 else { continue }
            // Cluster nach Lücken: neuer Cluster erst, wenn der nächste Betrag > 15 % über dem vorherigen liegt
            var cl: [(v: Double, last: Double, tx: [BankTx])] = []
            for t in BU.sorted(g.tx, { x, y in y.amount - x.amount }) {
                let v = -t.amount
                if let c = cl.last, v <= c.last * 1.15 {
                    cl[cl.count - 1].tx.append(t)
                } else {
                    cl.append((v: v, last: v, tx: [t]))
                }
                cl[cl.count - 1].last = v
            }
            cl = cl.filter { $0.tx.count >= 2 }
            if cl.count < 2 { continue }
            let rng: [(String, String)] = cl.map { c in
                let ds = c.tx.map { $0.date.iso }.sorted()
                return (ds[0], ds[ds.count - 1])
            }
            var inter = false
            for a in rng.indices {
                for b in rng.indices where b > a && rng[a].0 < rng[b].1 && rng[b].0 < rng[a].1 { inter = true }
            }
            if !inter { continue }
            groups[k] = nil
            // Schlüssel je Stufe = gerundeter typischer Betrag (Web v272): «Nicht mehr vorschlagen» und gelernte Namen bleiben am richtigen Vertrag
            var ckeys: [String] = []
            for i in cl.indices {
                cl[i].tx = BU.sorted(cl[i].tx, byDate)
                let a = cl[i].tx.map { -$0.amount }.sorted()
                var nk = replacePipe(k, "#" + jsNum(BU.round(a[a.count / 2])) + "|")
                while groups[nk] != nil { nk = replacePipe(nk, "'|") }
                ckeys.append(nk)
                groups[nk] = Group(key: nk, tpl: g.tpl, tx: cl[i].tx, names: g.names, cur: g.cur)
            }
            // Stufe, die direkt auf eine andere folgt (Steuerraten 760 bis Juni, ab Juli 340): Vorgänger merken → Preisänderung
            for (i, c) in cl.enumerated() {
                let f0 = c.tx[0].date
                var best: (d: Day, amount: Double, tx: [BankTx])? = nil
                for (j, o) in cl.enumerated() where j != i && o.tx.count >= 2 {
                    let lo = o.tx[o.tx.count - 1].date, gap = lo.days(to: f0)
                    // nur plausible Vorgänger: Betrag höchstens Faktor 3 daneben und selbst regelmässig (letzter Abstand 20–40 Tage)
                    let cv = c.v
                    let rt = o.v != 0 && cv != 0 ? Swift.max(o.v / cv, cv / o.v) : 99
                    let g2 = o.tx[o.tx.count - 2].date.days(to: lo)
                    let reg = g2 >= 20 && g2 <= 40
                    if gap > 0 && gap <= 45 && o.tx[0].date < f0 && rt <= 3 && reg && (best == nil || lo > best!.d) {
                        best = (lo, BU.r2(o.v), o.tx)
                    }
                }
                if let b = best, c.tx.count >= 2 { groups[ckeys[i]]?.prevC = b }
            }
        }
        // Parallele Reihen (Web v272): jeden Monat gleich viele Zahlungen beim selben Vertragspartner → so viele Verträge (Swisscom 29.90
        // am 5. und 32.90 am 12., zwei Kinder-Prämien am selben Tag, 2× 45.– am selben Tag). Zuordnung je Monat nach Betrag (Rang).
        for k in groups.orderedKeys {
            guard let g = groups[k] else { continue }
            var bm = BOrdered<[BankTx]>()
            for t in g.tx {
                let m = BU.slice(t.date.iso, 0, 7)
                bm[m] = (bm[m] ?? []) + [t]
            }
            let ms = bm.orderedKeys
            if ms.count < 3 { continue }
            var cnt = BOrdered<Int>()
            for m in ms {
                let c = String(bm[m]?.count ?? 0)
                cnt[c] = (cnt[c] ?? 0) + 1
            }
            let m0 = Int(BU.sorted(cnt.orderedKeys) { a, b in Double((cnt[b] ?? 0) - (cnt[a] ?? 0)) }.first ?? "0") ?? 0
            if m0 < 2 || Double(cnt[String(m0)] ?? 0) < Swift.max(3, Double(ms.count) * 0.7) { continue }
            let reg = ms.filter { bm[$0]?.count == m0 }
            let sameAmt = reg.allSatisfy { m in
                let L = bm[m] ?? []
                return L.allSatisfy { Swift.abs($0.amount - L[0].amount) < 0.005 }
            }
            let sameDay = reg.allSatisfy { m in
                let L = bm[m] ?? []
                return L.allSatisfy { $0.date == L[0].date }
            }
            if sameAmt && !sameDay { continue }
            func srt(_ L: [BankTx]) -> [BankTx] {
                BU.sorted(L) { a, b in
                    if a.amount != b.amount { return a.amount - b.amount }
                    let c = a.text.compare(b.text, locale: Locale(identifier: "en"))
                    if c != .orderedSame { return c == .orderedAscending ? -1 : 1 }
                    return a.date < b.date ? -1 : (b.date < a.date ? 1 : 0)
                }
            }
            var ser: [[BankTx]] = Array(repeating: [], count: m0)
            for m in reg {
                for (j, t) in srt(bm[m] ?? []).enumerated() { ser[j].append(t) }
            }
            let med = ser.map { median($0) }
            // verschiedene Beträge: nur trennen, wenn die Reihen klar getrennt sind (je ±10 % um ihren Wert, Abstand > 3 %)
            if !sameAmt {
                if m0 > 4 { continue }
                let okS = ser.indices.allSatisfy { j in
                    ser[j].allSatisfy { Swift.abs(-$0.amount - med[j]) <= med[j] * 0.10 } && (j == 0 || med[j - 1] - med[j] > med[j - 1] * 0.03)
                }
                if !okS && !sameDay { continue }
            }
            for m in ms where bm[m]?.count != m0 {
                for t in bm[m] ?? [] {
                    var bj = 0
                    for (j, v) in med.enumerated() where Swift.abs(-t.amount - v) < Swift.abs(-t.amount - med[bj]) { bj = j }
                    ser[bj].append(t)
                }
            }
            groups[k] = nil
            for (j, L0) in ser.enumerated() {
                var nk = replacePipe(k, "§" + (sameAmt ? String(j + 1) : jsNum(BU.r2(med[j]))) + "|")
                while groups[nk] != nil { nk = replacePipe(nk, "'|") }
                let L = BU.sorted(L0, byDate)
                var nmS = BOrdered<Int>()
                for t in L where !t.groupName.isEmpty { nmS[t.groupName] = (nmS[t.groupName] ?? 0) + 1 }
                var ng = Group(key: nk, tpl: g.tpl, tx: L, names: nmS.orderedKeys.isEmpty ? g.names : nmS, cur: g.cur)
                ng.prevC = g.prevC
                groups[nk] = ng
            }
        }

        // Abgleich vorbereiten: alle Verträge (laufende für Treffer, gekündigte für Archiv und «weiter abgebucht»)
        let calc = Calc(data: data, today: today)
        let cands: [Cand] = data.contracts.map { (c: Contract) -> Cand in
            let p = data.partnerName(of: c)
            let cat = data.category(c.categoryID)
            return Cand(c: c, partner: p, cur: c.currency.rawValue, cycle: c.cycleForCalc, price: calc.curPrice(c),
                        due: c.due, tplName: BankCatalog.tpl(p, "", c.currency.rawValue)?.name, ck: key1(p), cl: key1(c.label),
                        live: !(c.status == .cancelled || calc.isEnded(c)), catName: cat?.name ?? "", catKind: cat?.kind)
        }
        let alias = data.settings.bankAlias

        var out: [(s: BankSuggestion, match: Match?)] = []
        var known: [BankKnown] = []
        var after: [BankAfterEnd] = []
        var used = Set<UUID>()
        guard let from = r.from, let to = r.to else {
            return BankFindResult(items: [], known: [], prices: [], ignoredCount: 0, after: [], all: [], from: r.from, to: r.to, count: r.tx.count,
                                  bank: r.bank, format: r.format)
        }
        let span = from.days(to: to)

        func applyAlias(_ s: inout BankSuggestion) {
            if let a = alias[ignoreKey(s)] ?? alias[ignoreKeyStem(s)] ?? alias[ignoreKeyBase(s)], !a.n.isEmpty {
                s.alias = a
                s.name = a.n
            }
        }
        // Fachschlüssel einer Kategorie (Web `catKey`): Standardkategorie, sonst keiner
        func catKind(_ name: String) -> CategoryKind? { data.category(named: name)?.kind }

        // passende laufende Verträge (gleiche Währung): gemerkte Gläubiger-ID, Katalogeintrag gleich oder erstes markantes Wort gleich (Web `bankCands`)
        func candidates(_ s: BankSuggestion, _ tpl: CatalogEntry?) -> [Cand] {
            if !s.cred.isEmpty {
                let byId = cands.filter { c in
                    c.live && c.c.creditorID == s.cred && c.cur == s.currency && (s.mref.isEmpty || c.c.mandateRef.isEmpty || c.c.mandateRef == s.mref)
                }
                if !byId.isEmpty { return byId }
            }
            let k1 = key1(s.name), k2 = key1(s.raw)
            return cands.filter { c in
                if !c.live || c.cur != s.currency { return false }
                let byTpl = tpl.map { t in Partners.lnorm(c.partner) == Partners.lnorm(t.name) || c.tplName == t.name } ?? false
                var byKey = (!c.ck.isEmpty && (c.ck == k1 || c.ck == k2)) || (c.ck.isEmpty && !c.cl.isEmpty && (c.cl == k1 || c.cl == k2))
                // nur ein gemeinsames Wort (oft der Ort: «Energie Kreuzlingen» / «Gemeinde Kreuzlingen»): Kategorie muss passen
                if byKey && !byTpl && !s.category.isEmpty && !c.catName.isEmpty && s.category != "Sonstiges" && c.catName != "Sonstiges"
                    && catKind(s.category) != c.catKind {
                    byKey = false
                }
                return byTpl || byKey
            }
        }

        // Web `bankMatchName`: Vertrag mit dem nächstgelegenen aktuellen Preis
        func matchName(_ s: BankSuggestion, _ tpl: CatalogEntry?) -> Cand? {
            let v = s.amounts[s.amounts.count - 1]
            return BU.sorted(candidates(s, tpl)) { a, b in Swift.abs(a.price - v) - Swift.abs(b.price - v) }.first
        }

        // Fälligkeit passt? (Web `bankDueOk`) Bei Quartals-/Halbjahres-/Jahresverträgen mit erfasstem Zahltermin: nächste Zahlung laut
        // Auszug ±45 Tage zum Termin (im Rhythmus des Vertrags). nil = nicht prüfbar
        func dueOk(_ s: BankSuggestion, _ c: Cand) -> Bool? {
            let cy = c.cycle
            guard cy >= 3, Swift.max(1, s.cycle) == cy, let b = c.due else { return nil }
            let P = Double(cy) * 30.4375
            var x = Double(b.days(to: s.due))
            x = (x.truncatingRemainder(dividingBy: P) + P).truncatingRemainder(dividingBy: P)
            return Swift.min(x, P - x) <= 45
        }

        // Web `bankMatch`: gleicher Preis → bereits erfasst, sonst Preisänderung (höchstens 35 %). `excl`: schon belegte Verträge.
        // Fälligkeit nur als Vorrang, nie als Ausschluss (das Datum kann aus dem Vertragsbeginn geschätzt und falsch sein)
        func match(_ s: BankSuggestion, _ tpl: CatalogEntry?, excl: Set<UUID> = []) -> Match? {
            var best: (c: Cand, dm: Double, due: Bool?)? = nil
            for c in candidates(s, tpl) where !excl.contains(c.c.id) {
                let ok = dueOk(s, c)
                let dm = Swift.abs(c.price / Double(c.cycle) - s.amount / Double(s.cycle)) - (ok == true ? 1e6 : 0) + (ok == false ? 1e5 : 0)
                if best == nil || dm < best!.dm { best = (c, dm, ok) }
            }
            guard let b = best else { return nil }
            let cp = b.c.price, cc = Double(b.c.cycle), same = b.c.cycle == s.cycle
            let diff = same ? Swift.abs(cp - s.amount) : Swift.abs(cp / cc - s.amount / Double(s.cycle)) * cc
            if diff <= Swift.max(0.05, cp * 0.01) || (s.varies && diff <= cp * 0.35) { return .known(b.c.c.id) }
            // gleicher Vertragspartner und gleicher Fälligkeitsmonat: auch bei grösserer Abweichung derselbe Vertrag (Prämie neu);
            // keine Preisänderung vorschlagen – der erfasste Betrag ist meist der neuere
            if b.due == true && diff <= cp * 0.6 { return .known(b.c.c.id) }
            // nur als Preisänderung melden, wenn der neue Betrag nach dem letzten erfassten Preis beginnt
            let fromD = (s.change != nil && same) ? s.change!.from : s.last
            // grosser Sprung (> 35 %) ist eher ein zweiter Vertrag beim gleichen Vertragspartner als eine Preisänderung
            let na = same ? s.amount : s.amount / Double(s.cycle) * cc
            if Swift.abs(na - cp) > cp * 0.35 { return nil }
            return .price(b.c.c.id, amount: same ? s.amount : BU.r2(s.amount / Double(s.cycle) * cc), old: cp, from: fromD)
        }

        // Im Archiv (gekündigt/beendet), gleicher Vertragspartner (Web `bankArchMatch`)
        func archMatch(_ s: BankSuggestion, _ tpl: CatalogEntry?) -> Cand? {
            let k1 = key1(s.name), k2 = key1(s.raw)
            var best: (c: Cand, dm: Double)? = nil
            for c in cands where !c.live && c.cur == s.currency {
                let byTpl = tpl.map { t in Partners.lnorm(c.partner) == Partners.lnorm(t.name) || c.tplName == t.name } ?? false
                let ok = (!s.cred.isEmpty && c.c.creditorID == s.cred) || byTpl || (!c.ck.isEmpty && (c.ck == k1 || c.ck == k2))
                    || (c.ck.isEmpty && !c.cl.isEmpty && (c.cl == k1 || c.cl == k2))
                if !ok { continue }
                let dm = Swift.abs(c.price / Double(c.cycle) - s.amount / Double(s.cycle))
                if best == nil || dm < best!.dm { best = (c, dm) }
            }
            return best?.c
        }

        // Gleicher Betrag und Rhythmus, anderer Name (Web `bankSameAmount`); nur gleicher Rhythmus: Wingo 27.95 monatlich ist nicht
        // «gleicher Betrag» wie Serafe 335.– jährlich
        func sameAmount(_ s: BankSuggestion, _ used: Set<UUID>) -> Cand? {
            var best: (c: Cand, d: Double)? = nil
            for c in cands where c.live && c.cur == s.currency && c.cycle == s.cycle {
                let cp = c.price
                var d = Swift.abs(cp - s.amount)
                if d > Swift.max(0.05, cp * 0.01) { continue }
                d += used.contains(c.c.id) ? 1000 : 0
                if best == nil || d < best!.d { best = (c, d) }
            }
            return best?.c
        }

        // gleicher Betrag + gemeinsames markantes Wort («Gemeinde Kreuzlingen» / «Stadtverwaltung Kreuzlingen», «Rechtschutz» /
        // «Rechtsschutz»): derselbe Vertrag (Web `bankSameWord`)
        func sameWord(_ s: BankSuggestion, _ sa: Cand) -> Bool {
            func tw(_ x: String) -> [String] { BankName.tok(x).filter { $0.count >= 4 && !rxSameGen.test($0) } }
            let A1 = tw(s.name + " " + s.raw + " " + s.memo + " " + label(s)), B1 = tw(sa.partner + " " + sa.c.label)
            let catOk = s.category.isEmpty || sa.catName.isEmpty || s.category == "Sonstiges" || sa.catName == "Sonstiges"
                || catKind(s.category) == sa.catKind
            return catOk && A1.contains(where: { w in B1.contains { wordSim(w, $0) } })
        }

        // gekündigter Vertrag, der nach seinem Ende («Läuft bis») noch abgebucht wurde → Hinweis, nicht als neuer Vertrag (Web `cancelledHit`)
        func cancelledHit(_ g: Group) -> Bool {
            let tx = g.tx
            guard let last = tx.last else { return false }
            let nm = g.tpl?.name ?? BankName.pretty(g.names.orderedKeys.first ?? "")
            let k1 = key1(nm), k2 = key1(last.name), la = -last.amount
            func sameP(_ c: Cand) -> Bool {
                if !last.cred.isEmpty && c.c.creditorID == last.cred { return true }
                return (!c.ck.isEmpty && (c.ck == k1 || c.ck == k2)) || (g.tpl.map { Partners.lnorm(c.partner) == Partners.lnorm($0.name) } ?? false)
            }
            // aktiver Vertrag beim selben Vertragspartner mit passendem Betrag: die Zahlungen gehören zu ihm, nicht zum gekündigten
            if cands.contains(where: { c in c.live && c.cur == g.cur && sameP(c) && Swift.abs(c.price - la) <= c.price * 0.35 }) { return false }
            var hit = false
            for c in cands {
                guard let e = c.c.cancelPer, c.cur == g.cur else { continue }
                if !(!last.cred.isEmpty && c.c.creditorID == last.cred) {
                    if !(!c.ck.isEmpty && (c.ck == k1 || c.ck == k2)) && !(g.tpl.map { Partners.lnorm(c.partner) == Partners.lnorm($0.name) } ?? false) { continue }
                }
                // nur Beträge nahe am gekündigten Preis (±25 %) gelten als «weiter abgebucht»
                let cpx = c.price
                let late = tx.filter { e.days(to: $0.date) > graceDays && (cpx == 0 || Swift.abs(-$0.amount - cpx) <= cpx * 0.25) }
                guard let ll = late.last else { continue }
                after.append(BankAfterEnd(contractID: c.c.id, count: late.count, last: ll.date, amount: BU.r2(-ll.amount), currency: g.cur))
                hit = true
            }
            return hit
        }

        // Erst alle Gruppen bewerten, dann zuordnen: exakte Treffer zuerst – zwei ähnliche Verträge beim selben Anbieter
        // (Swisscom 29.90 + 32.90) dürfen nicht beide demselben erfassten Vertrag zugeordnet werden
        var EV: [(k: String, s: BankSuggestion?, m: Match?, q: Int)] = []
        func push(_ k: String, _ g: Group, _ s0: BankSuggestion, multi: Bool) {
            var s2 = s0
            applyAlias(&s2)
            s2.statementFrom = from
            s2.category = BankCatalog.category(catalog: g.tpl, name: s2.name, text: s2.text, memo: s2.memo, data: data)
            if let a = s2.alias, !a.c.isEmpty, data.categories.contains(where: { $0.name == a.c }) { s2.category = a.c }
            let m2 = match(s2, g.tpl)
            let q2: Int
            switch m2 {
            case nil: q2 = 5
            case .known?: q2 = multi ? 0 : (s2.varies ? 1 : 0)
            case .price?: q2 = 2
            }
            EV.append((k, s2, m2, q2))
        }
        var FAIL = BOrdered<[String]>(), OKB = BOrdered<[String]>()
        for k in groups.orderedKeys {
            guard var g = groups[k] else { continue }
            if cancelledHit(g) { continue }
            var s = eval(k, g, fallbackEnd: to, span: span, today: today)
            // Kern-Reihe: Abo mit gleichem Betrag am gleichen Tag, dazwischen Einzelkäufe beim selben Händler → nur die regelmässige Reihe
            if s == nil, let core = core(g) {
                s = eval(k, core, fallbackEnd: to, span: span, today: today)
                if s != nil {
                    g = core
                    groups[k] = core
                }
            }
            // keine Reihe gefunden: erst nach der Schleife gemeinsam mit den Schwestergruppen (gleicher Vertragspartner, andere
            // Datei/Betragsstufe) als Jahresreihen bzw. Einzelprämien prüfen (Web `bankFallback`)
            guard let sv = s else {
                FAIL[base(k)] = (FAIL[base(k)] ?? []) + [k]
                continue
            }
            OKB[base(k)] = (OKB[base(k)] ?? []) + [k]
            push(k, g, sv, multi: false)
        }
        for b0 in FAIL.orderedKeys {
            let ks = FAIL[b0] ?? []
            var OT = Set<Int>()
            for k in OKB[b0] ?? [] { for t in groups[k]?.tx ?? [] { OT.insert(t.seq) } }
            var T: [BankTx] = []
            var inT = Set<Int>()
            for k in ks { for t in groups[k]?.tx ?? [] where inT.insert(t.seq).inserted { T.append(t) } }
            for t in ALLB[b0] ?? [] where !inT.contains(t.seq) && !OT.contains(t.seq) {
                inT.insert(t.seq)
                T.append(t)
            }
            T = BU.sorted(T, byDate)
            guard let g0 = groups[ks[0]] else { continue }
            var names = BOrdered<Int>()
            for k in ks { if let g = groups[k] { for n in g.names.orderedKeys { names[n] = (names[n] ?? 0) + (g.names[n] ?? 0) } } }
            var mg = Group(key: ks[0], tpl: g0.tpl, tx: T, names: names, cur: g0.cur)
            mg.hasSeries = OKB[b0] != nil
            let subs = fallback(ks[0], mg, fallbackEnd: to, span: span, today: today)
            if subs.isEmpty {
                for k in ks { EV.append((k, nil, nil, 9)) }
                continue
            }
            for x in subs {
                groups[x.k] = x.g
                push(x.k, x.g, x.s, multi: true)
            }
        }
        // exakter Betrag + gleiches Wort zuerst (Protekta «Rechtschutz» 341.10 = erfasster «Rechtsschutz» 341.10), danach die unscharfen
        for i in EV.indices {
            guard let sv = EV[i].s, EV[i].m == nil, let sa = sameAmount(sv, []), sameWord(sv, sa) else { continue }
            EV[i].q = -1
        }
        EV = BU.sorted(EV) { a, b in Double(a.q - b.q) }
        for ev in EV {
            guard let g = groups[ev.k] else { continue }
            guard var s = ev.s else {
                // erkannte Gruppe, die als Vertrag bereits existiert, aber die strengen Regeln nicht erfüllt (schwankende Rechnung, nur 1 Zahlung)
                guard var ls = loose(ev.k, g) else { continue }
                applyAlias(&ls)
                ls.category = BankCatalog.category(catalog: g.tpl, name: ls.name, text: ls.text, data: data)
                guard let c = matchName(ls, g.tpl) else { continue }
                let cp = c.price
                if !ls.amounts.contains(where: { Swift.abs($0 - cp) <= cp * 0.35 }) { continue }
                if !used.contains(c.c.id) {
                    used.insert(c.c.id)
                    known.append(BankKnown(contractID: c.c.id, suggestion: ls, loose: true))
                }
                continue
            }
            var m = ev.m
            // Vertrag schon von einer anderen Reihe belegt → nächstbesten freien Vertrag desselben Vertragspartners prüfen (zwei Handyabos),
            // sonst eigener Vorschlag
            if let mm = m, used.contains(mm.id) { m = match(s, g.tpl, excl: used) }
            if case .known(let id)? = m {
                used.insert(id)
                known.append(BankKnown(contractID: id, suggestion: s, loose: false))
                continue
            }
            if let mm = m { used.insert(mm.id) }
            if m == nil {
                if let ar = archMatch(s, g.tpl) {
                    // letzte Abbuchung vor dem Kündigungstermin: Vertrag lief da noch → nur als «gekündigt» bei den erfassten zeigen
                    let ae = ar.c.cancelPer ?? (ar.c.renewMonths == 0 ? ar.c.end : nil)
                    if let e = ae, e.days(to: s.last) <= graceDays {
                        known.append(BankKnown(contractID: ar.c.id, suggestion: s, loose: false, archived: true))
                        continue
                    }
                    s.archived = ar.c.id
                } else if let sa = sameAmount(s, used) {
                    used.insert(sa.c.id)
                    // gleicher Betrag + gemeinsames markantes Wort: schon erfasst, ohne Rückfrage
                    if sameWord(s, sa) {
                        known.append(BankKnown(contractID: sa.c.id, suggestion: s, loose: false))
                        continue
                    }
                    s.sameAs = sa.c.id
                }
            }
            // «·Bezeichnung» seit v212: alte Einträge «tpl:CSS» gelten weiter; «~…» (Unterreihe, Mitteilung) ebenso
            if ign.contains(ignoreKey(s)) || ign.contains(ignoreKeyStem(s)) || ign.contains(ignoreKeyBase(s)) { s.ignored = true }
            out.append((s, m))
        }
        // Teilzahlung: einzelne Zahlung + letzte Zahlung eines schon zugeordneten Vertrags beim selben Vertragspartner = dessen
        // Jahresbetrag (±3 %) → zweite Rate desselben Vertrags (Vollkasko halbjährlich 383.20 + 372.70 ≈ 746.70 jährlich), kein neuer Vorschlag
        let candByID = Dictionary(cands.map { ($0.c.id, $0) }, uniquingKeysWith: { a, _ in a })
        out = out.filter { o in
            let s = o.s
            if s.count != 1 || o.match != nil || s.sameAs != nil || s.archived != nil { return true }
            let ids = Set(candidates(s, s.catalog).map { $0.c.id })
            let hit = known.first { k in
                guard !k.archived, ids.contains(k.contractID), let la = k.suggestion.amounts.last, let c = candByID[k.contractID] else { return false }
                let yr = c.price * 12 / Double(c.cycle)
                return c.cycle >= 6 && Swift.abs(s.amount + la - yr) <= yr * 0.03 && Swift.abs(k.suggestion.last.days(to: s.last)) <= 250
            }
            guard let h = hit else { return true }
            known.append(BankKnown(contractID: h.contractID, suggestion: s, loose: false, part: true))
            return false
        }
        out = BU.sorted(out) { a, b in
            let ma = a.match == nil ? 1 : 0, mb = b.match == nil ? 1 : 0
            if ma != mb { return Double(ma - mb) }
            if a.s.confidence.rank != b.s.confidence.rank { return Double(a.s.confidence.rank - b.s.confidence.rank) }
            return b.s.amount / Double(b.s.cycle) - a.s.amount / Double(a.s.cycle)
        }
        // jeder erfasste Vertrag nur einmal in «schon in Kontivo» – sicherer Treffer vor losem
        var kseen = Set<UUID>()
        known = BU.sorted(known) { a, b in Double((a.loose ? 1 : 0) - (b.loose ? 1 : 0)) }.filter { kseen.insert($0.contractID).inserted }
        var prices: [BankPriceMatch] = []
        for o in out {
            if case .price(let id, let amount, let old, let fromD)? = o.match {
                prices.append(BankPriceMatch(contractID: id, from: fromD, amount: amount, old: old, suggestion: o.s))
            }
        }
        let items = out.filter { $0.match == nil }.map { $0.s }
        return BankFindResult(items: items, known: known, prices: prices, ignoredCount: items.filter { $0.ignored }.count, after: after,
                              all: out.map { $0.s }, from: from, to: to, count: r.tx.count, bank: r.bank, format: r.format)
    }

    /// Zwei Wörter gleich bis auf einen Buchstaben (Rechtschutz/Rechtsschutz), nur ab 6 Zeichen (Web `bankWordSim`).
    static func wordSim(_ a0: String, _ b0: String) -> Bool {
        if a0 == b0 { return true }
        let a = Array(a0.utf16), b = Array(b0.utf16)
        if a.count < 6 || b.count < 6 || Swift.abs(a.count - b.count) > 1 { return false }
        var i = 0, j = 0, e = 0
        while i < a.count && j < b.count {
            if a[i] == b[j] {
                i += 1
                j += 1
                continue
            }
            e += 1
            if e > 1 { return false }
            if a.count > b.count {
                i += 1
            } else if b.count > a.count {
                j += 1
            } else {
                i += 1
                j += 1
            }
        }
        return e + (a.count - i) + (b.count - j) <= 1
    }

    /// Nächste Zahlung (Web v272 `bankNextDue`): üblicher Zahltag der letzten 3–12 Buchungen (häufigster Tag, gleich oft: der spätere;
    /// meist ≥ 28. → Monatsende), ab dem Monat der letzten Zahlung im Rhythmus weiter bis heute oder später.
    public static func nextDue(_ dates: [Day], cycle cyc: Int, today: Day) -> Day {
        guard let last = dates.last else { return today }
        let rec = Array(dates.suffix(12))
        var day = last.day
        if rec.count >= 3 {
            var cnt: [Int: Int] = [:]
            for d in rec { cnt[d.day, default: 0] += 1 }
            let eom = Double(rec.filter { $0.day >= 28 }.count) >= Double(rec.count) * 0.5
            day = eom ? 31 : (cnt.keys.sorted { a, b in cnt[a]! != cnt[b]! ? cnt[a]! > cnt[b]! : a > b }.first ?? day)
        }
        var g = 0
        var dt: Day
        repeat {
            let mm = last.month + cyc * g
            let dim = Day(last.year, mm + 1, 0).day
            dt = Day(last.year, mm, Swift.min(day, dim))
            g += 1
        } while dt < today && g < 400
        return dt
    }

    /// Häufigster Name einer Gruppe, aufbereitet (Katalogname gewinnt).
    static func groupName(_ g: Group) -> String {
        if let t = g.tpl { return t.name }
        let ks = BU.sorted(g.names.orderedKeys) { a, b in Double((g.names[b] ?? 0) - (g.names[a] ?? 0)) }
        return BankName.pretty(ks.first ?? "")
    }

    /// Kern-Reihe (Web v272 `bankCore`): gleicher Betrag am üblichen Tag, höchstens einmal pro Monat, ohne Einzelkäufe dazwischen.
    static func core(_ g: Group) -> Group? {
        let tx = g.tx
        if tx.count < 6 { return nil }
        var ca = BOrdered<Int>()
        for t in tx {
            let a = String(format: "%.2f", t.amount)
            ca[a] = (ca[a] ?? 0) + 1
        }
        guard let am = BU.sorted(ca.orderedKeys, { a, b in Double((ca[b] ?? 0) - (ca[a] ?? 0)) }).first else { return nil }
        let nAm = ca[am] ?? 0
        if nAm < 4 || nAm == tx.count { return nil }
        var S = tx.filter { String(format: "%.2f", $0.amount) == am }
        var dc = BOrdered<Int>()
        for t in S { dc[String(t.date.day)] = (dc[String(t.date.day)] ?? 0) + 1 }
        let md = Int(BU.sorted(dc.orderedKeys) { a, b in Double((dc[b] ?? 0) - (dc[a] ?? 0)) }.first ?? "0") ?? 0
        func near(_ d: Int) -> Bool {
            let x = Swift.abs(d - md)
            return Swift.min(x, 31 - x) <= 3
        }
        S = S.filter { near($0.date.day) }
        // höchstens eine Zahlung pro Monat (die nächste am Stichtag)
        var bm = BOrdered<BankTx>()
        for t in S {
            let m = BU.slice(t.date.iso, 0, 7)
            if let o = bm[m], !(Swift.abs(t.date.day - md) < Swift.abs(o.date.day - md)) { continue }
            bm[m] = t
        }
        S = bm.orderedKeys.sorted().compactMap { bm[$0] }
        // gleicher Betrag auch oft an anderen Tagen (täglicher Kaffee 4.50) → kein Abo
        if S.count < 4 || Double(S.count) < Double(tx.count) * 0.4 || Double(nAm) > Double(S.count) * 1.5 { return nil }
        var ok = 0
        for i in 1..<S.count {
            let g0 = S[i - 1].date.days(to: S[i].date)
            if g0 >= 25 && g0 <= 36 { ok += 1 }
        }
        if Double(ok) < Double(S.count - 1) * 0.7 { return nil }
        var c = Group(key: g.key, tpl: g.tpl, tx: S, names: g.names, cur: g.cur)
        c.prevC = g.prevC
        return c
    }

    /// Gruppe, die die strengen Regeln nicht erfüllt, als Kandidat für «bereits erfasst» (Web `bankLooseKnown`).
    static func loose(_ k: String, _ g: Group) -> BankSuggestion? {
        let tx = g.tx
        guard let lt = tx.last, let ft = tx.first else { return nil }
        let am = tx.map { BU.r2(-$0.amount) }
        return BankSuggestion(id: k, key: k, name: groupName(g), raw: lt.name, text: lt.text, currency: g.cur, amount: am[am.count - 1],
                              cycle: 1, due: lt.date, first: ft.date, last: lt.date, count: tx.count, dates: tx.map { $0.date }, amounts: am,
                              confidence: .low, varies: false, change: nil, catalog: g.tpl, category: "", kind: .unknown,
                              cred: lt.cred, mref: lt.mref, alias: nil, ignored: false)
    }

    /// Vertragsbeginn = erste Zahlung, aber nur wenn sie deutlich nach dem Anfang des Auszugs liegt (> 1,5 Zahlungsrhythmen);
    /// sonst lief der Vertrag schon vorher (Web `bankStart`).
    static func start(first: Day, count: Int, cycle: Int, statementFrom: Day?, hasChange: Bool) -> Day? {
        guard let sf = statementFrom, count >= 2, !hasChange else { return nil }
        return Double(sf.days(to: first)) > Double(cycle == 0 ? 1 : cycle) * 30.44 * 1.5 ? first : nil
    }

    /// Vertragsbeginn eines Vorschlags (Web `bankStart`)
    public static func start(_ s: BankSuggestion) -> Day? {
        start(first: s.first, count: s.count, cycle: s.cycle, statementFrom: s.statementFrom, hasChange: s.change != nil)
    }

    /// Beginn einer Einnahme aus dem Auszug (Web `bankStart(it.s)`); `statementFrom` = Beginn des Auszugs
    public static func start(_ s: BankIncomeSuggestion, statementFrom: Day?) -> Day? {
        start(first: s.first, count: s.count, cycle: s.cycle, statementFrom: statementFrom, hasChange: false)
    }

    // MARK: Vorschlag → Vertrag

    /// Vorschlag → Vertrag (Web `bankToContract`): Katalogwerte (Bezeichnung, Frist, Kündigungsweg, Kontakt), Preisverlauf bei
    /// Preisänderung. `persons`: Namen der Personen. Vertragspartner nur verknüpft, wenn es ihn schon gibt (sonst `add` verwenden).
    public static func toContract(_ s: BankSuggestion, persons: [String], data: AppData, today: Day, now: Date = Date()) -> Contract {
        let t = s.catalogEntry
        // Preisverlauf aus den Zahlungen, sonst die eine erkannte Preisänderung; letzter Preis = gewählter Betrag
        var ph = priceHistory(dates: s.dates, amounts: s.amounts, cycle: s.cycle)
        if var h = ph, !h.prices.isEmpty {
            if Swift.abs(h.current - s.amount) > 0.004 && h.prices[h.prices.count - 1].amount > 0 { h.prices[h.prices.count - 1].amount = s.amount }
            ph = h
        } else if let h = ph, s.change != nil || Swift.abs(h.base - s.amount) > 0.004 {
            // kein Verlauf erkannt: die eine Preisänderung (s.change) gilt (Web v326)
            ph = nil
        }
        let base = ph?.base ?? s.change?.prev ?? s.amount
        var c = Contract(label: t?.label ?? "", amount: BU.r2(base), currency: Currency(rawValue: s.currency) ?? data.settings.homeCurrency,
                         cycle: s.cycle, due: s.due, start: start(s), createdAt: now)
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
        if let h = ph {
            c.prices = h.prices
        } else if let chg = s.change {
            c.prices = [PriceChange(from: chg.from, amount: chg.amount)]
        }
        // Steuern & Gebühren: nicht kündbar
        if let tax = BankCatalog.categoryName(key: "Steuern & Gebühren", in: data), tax == s.category {
            c.noCancel = true
            c.mandatory = false
            c.cancelTerm = .anytime
        }
        // Zahlungsart, Kunden- und Vertragsnummer aus dem Buchungstext (Web v180)
        c.payMethod = payMethod(s)
        let nr = numbers(s)
        c.customerNo = nr.customer
        c.contractNo = nr.contract
        // Gläubiger-ID/Mandat aus dem Auszug merken: beim nächsten Import eindeutiger Treffer, auch wenn der Bank-Text anders lautet
        if !s.cred.isEmpty { c.creditorID = BU.slice(s.cred, 0, 40) }
        if !s.mref.isEmpty { c.mandateRef = BU.slice(s.mref, 0, 40) }
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

    /// Vertragspartner zum (in der Prüfliste ggf. geänderten) Namen: bisheriger bzw. bestehender gleichen Namens, sonst neu
    /// mit Website und Adresse aus dem Katalogeintrag zur Vorschlagswährung (Web `bankToContract`: `t[4]`, `t[12]`;
    /// `catalog` = `BankSuggestion.catalogEntry`). Leerer Name → `current`.
    public static func partnerID(named name: String, current: UUID?, catalog t: CatalogEntry?, in data: inout AppData) -> UUID? {
        let pn = BU.trim(name)
        if let cur = data.partner(current), cur.name.lowercased() == pn.lowercased() { return cur.id }
        if pn.isEmpty { return current }
        if let p = Partners.find(pn, in: data) { return p.id }
        let addr = (t?.address ?? "").replacingOccurrences(of: "\r\n", with: "\n")
        let p = Partner(name: pn, web: t?.web ?? "", address: addr.isEmpty ? PostalAddress() : WebImport.addrSplit(addr, partnerName: pn))
        data.partners.append(p)
        return p.id
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

    /// Schon erfasste Verträge: Gläubiger-ID/Mandat nachtragen, wenn noch keine gespeichert ist – der nächste Import trifft dann sicher
    /// (Web v273 `bkGo`). Gilt für «schon in Kontivo» und Preisänderungen.
    public static func rememberCreditorIDs(_ r: BankFindResult, in data: inout AppData) {
        let pairs = r.known.map { ($0.contractID, $0.suggestion) } + r.prices.map { ($0.contractID, $0.suggestion) }
        for (id, s) in pairs {
            guard let i = data.contractIndex(id), data.contracts[i].creditorID.isEmpty, !s.cred.isEmpty else { continue }
            data.contracts[i].creditorID = BU.slice(s.cred, 0, 40)
            if !s.mref.isEmpty { data.contracts[i].mandateRef = BU.slice(s.mref, 0, 40) }
        }
    }

    /// Archivierten Vertrag wieder aktivieren (Web v287 «Wieder aktivieren» bei `s.archived`): aktiv, ohne Kündigung, abgelaufenes Ende
    /// entfernt; weicht der Betrag ab, gilt er als neuer Preis ab der letzten Zahlung.
    public static func reactivate(_ id: UUID, amount: Double, from: Day, in data: inout AppData, today: Day) {
        guard let i = data.contractIndex(id) else { return }
        var c = data.contracts[i]
        c.status = .active
        c.cancelledAt = nil
        c.cancelPer = nil
        if let e = c.end, e < today { c.end = nil }
        let rp = Calc(data: data, today: today).curPrice(c)
        if Swift.abs(rp - amount) > Swift.max(0.05, rp * 0.01) { c.prices.append(PriceChange(from: from, amount: amount)) }
        data.contracts[i] = c
    }

    /// Neuen Preis übernehmen (Web: Preisstufe am gleichen Datum ersetzen, nach Datum sortiert).
    public static func applyPrice(_ p: BankPriceMatch, to data: inout AppData) {
        guard let i = data.contractIndex(p.contractID) else { return }
        var pr = data.contracts[i].prices.filter { $0.from != p.from }
        pr.append(PriceChange(from: p.from, amount: p.amount))
        data.contracts[i].prices = BU.sorted(pr) { a, b in a.from < b.from ? -1 : (b.from < a.from ? 1 : 0) }
    }
}
