import Foundation

// MARK: - Kontoauszug: Gruppe bewerten (Web `bankEval`, Stand v346)

extension BankImport {
    static let BKONCE = BRX("versicherung|jahresmitgliedschaft|amazon prime|amzn prime|bahncard|\\bpraemie|\\bpramie|\\bpolice|kfz steuer|kfzsteuer|kraftfahrzeugsteuer|motorfahrzeugsteuer|verkehrssteuer|hundesteuer|grundsteuer|rundfunk|serafe|mitgliedsbeitrag|mitgliederbeitrag|jahresbeitrag|vereinsbeitrag|jahresabo|jahresgebuehr|jahresgebuhr|abonnement|\\bvignette|haftpflicht|hausrat|rechtsschutz|kautionsversicherung|kautionsservice|kautionskasse|kautionsfrei|caution|strassenverkehrsamt|verkehrsamt|bundessteuer|steuer bund\\b|staatssteuer|gemeindesteuer|kantonssteuer|kirchensteuer|steuerverwaltung")
    static let BKONCENO = BRX("erstattung|ruckzahlung|rueckzahlung|storno|gutschrift|schaden|selbstbehalt|franchise|arzt|apotheke|rechnung nr .* behandlung|kostenbeteiligung|leistungsabrechnung|ruckforderung|rueckforderung|pruefung|prufung|\\bmfk\\b|fahrzeugkontrolle|mietkaution|kautionskonto")
    static let rxDdSig = BRX("lastschrift|\\blsv\\b|einzug")
    static let rxEbillOnce = BRX("e ?rechnung|ebill")
    static let rxKK = BRX("krankenkasse|krankenversicherung|gesundheitsorganisation|grundversicherung|\\bkvg\\b|krankenkassenpramie|krankenkassenpraemie")
    static let rxKKTpl = BRX("krankenkasse|krankenversicherung", i: true)
    static let rxYearWord = BRX("jahres|jaehrlich|jahrlich|annual|yearly")
    static let rxOnceYearWord = BRX("jahresrechnung|jahresgebuhr|jahresgebuehr|jahresabo|jahresmitglied|\\byearly\\b|\\bannual\\b|12 monate|\\be v\\b|\\bev\\b")
    static let rxOnceContractWord = BRX("beitrag|abo|rechnung|yearly|annual|plus|premium|mitglied|domain|hosting")
    static let rxYearly = BRX("jahres|jaehrlich|jahrlich|bahncard|12 monate|annual|yearly")
    static let rxLsv = BRX("lastschriftverfahren|\\blsv\\b")
    static let rxFxWords = BRX("\\busd\\b|\\bgbp\\b|\\bchf\\b|fremdw|kurs|wechselkurs|auslandseinsatz|devisen|\\beur\\b|€|\\bsek\\b|\\bnok\\b|\\bdkk\\b|\\bpln\\b|\\bczk\\b|\\bhuf\\b")
    static let rxEnergyName = BRX("energie|strom|\\bgas\\b|wasser|stadtwerk|elektrizit|\\bekz\\b|\\bewz\\b|\\bewb\\b|\\biwb\\b")

    /// Gruppe bewerten: Rhythmus, Betrag, Preisänderung, Sicherheit, nächste Zahlung (Web `bankEval`).
    static func eval(_ k: String, _ g: Group, fallbackEnd: Day, span: Int, today: Day) -> BankSuggestion? {
        // Stichtag = Ende der Datei, aus der die Buchungen stammen (mehrere Dateien, Web v325)
        let ref = gEnd(g.tx, fallbackEnd)
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
        // Pause über 13 Monate (SWICA 2023–24 per LSV, dann 2 Jahre nichts, jetzt wieder): nur die laufende Phase zählt
        var gi = tx.count - 1
        var preCyc = 0
        while gi > 0 {
            if tx[gi - 1].date.days(to: tx[gi].date) > (g.yearly || g.period ? 460 : 400) {
                let pre = Array(tx[0..<gi])
                tx = Array(tx[gi...])
                // nur eine Zahlung nach der Pause: zählt nur, wenn es davor einen regelmässigen Vertrag gab (SWICA), nicht bei sporadischen Zahlungen
                if tx.count == 1 {
                    var pi: [Int] = []
                    for pj in 1..<Swift.max(pre.count, 1) { pi.append(cycle(pre[pj - 1].date.days(to: pre[pj].date))) }
                    if pre.count < 3 || Double(pi.filter { $0 != 0 }.count) < Double(pi.count) * 0.7 { return nil }
                    // Rhythmus der früheren Phase übernehmen (SWICA monatlich per LSV, Pause, wieder eine Abbuchung → monatlich)
                    var pc = BOrdered<Int>()
                    for c in pi where c != 0 { pc[String(c)] = (pc[String(c)] ?? 0) + 1 }
                    preCyc = Int(BU.sorted(pc.orderedKeys) { a, b in Double((pc[b] ?? 0) - (pc[a] ?? 0)) }.first ?? "0") ?? 0
                }
                break
            }
            gi -= 1
        }
        let name = groupName(g)
        var am = tx.map { BU.r2(-$0.amount) }
        var last = am[am.count - 1]
        var n = tx.count
        // einmalige Zusatzzahlung mitten im Verlauf (Jahresabrechnung, Servicepauschale) nicht als Preis werten:
        // genau ein Betrag kommt nur einmal vor und liegt nicht am Rand → herausnehmen (Web v223); nicht beim Anlauf (Teilbeträge, dann voll)
        let rampUp = n >= 3 && Swift.abs(am[n - 1] - am[n - 2]) < 0.005 && am.allSatisfy { $0 <= am[n - 1] + 0.005 }
        if n >= 5 && !rampUp {
            var cA: [String: Int] = [:]
            for v in am { cA[String(format: "%.2f", v), default: 0] += 1 }
            let lone = am.indices.filter { cA[String(format: "%.2f", am[$0])] == 1 && $0 > 0 && $0 < n - 1 }
            if lone.count == 1 && cA.count <= 3 {
                let li = lone[0]
                tx.remove(at: li)
                am.remove(at: li)
                n = tx.count
                last = am[n - 1]
            }
        }
        var iv: [Int] = []
        for i in 1..<Swift.max(n, 1) { iv.append(tx[i - 1].date.days(to: tx[i].date)) }
        var cyc = 0
        var conf = BankConfidence.low
        var varies = false
        var ch: BankPriceChange? = nil
        var prevTx: [BankTx] = []
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
            // Jahresreihe ist schon über 300–430 Tage geprüft; Rechnungen je Steuer-/Abrechnungsjahr: Zahldatum beliebig, Rhythmus jährlich
            if g.period || (g.yearly && !g.half) { cyc = 12 }
            if g.half { cyc = 6 }
            if cyc == 0 { return nil }
            // Beträge: höchstens zwei Stufen (Preisänderung) oder ±5 % um den Median, sonst variabel (Einkäufe)
            var lv: [Double] = []
            for v in am where lv.isEmpty || Swift.abs(lv[lv.count - 1] - v) > 0.004 { lv.append(v) }
            let dist = Set(am).count
            // ohne Katalog/Gläubiger-ID braucht der Name ein markantes Wort (nicht «M», «SB 12»)
            if g.tpl == nil && tx[0].cred.isEmpty && !Partners.lusable(name) { return nil }
            func nlv(_ v: Double) -> Int { am.filter { Swift.abs($0 - v) <= 0.004 }.count }
            if g.yearly || g.period {
                // Jahresreihe nach Kalendermonat: Betrag darf jährlich wechseln
                varies = dist > 1
                last = g.period ? g.periodAmt : am[n - 1]
            } else if dist <= 2 && lv.count <= 2 {
                if lv.count == 2 {
                    // Preisänderung nur, wenn der alte Preis mindestens zweimal vorkommt und sich höchstens um 35 % ändert
                    if nlv(lv[0]) < 2 || Swift.abs(lv[1] - lv[0]) > lv[0] * 0.35 {
                        if nlv(lv[0]) == 1 && nlv(lv[1]) >= 3 && am[0] == lv[0] && Swift.abs(lv[1] - lv[0]) <= lv[0] * 0.35 {
                            // alter Preis nur einmal ganz am Anfang des Auszugs: Vertrag mit dem neuen Preis vorschlagen
                            tx = Array(tx.dropFirst())
                            am = Array(am.dropFirst())
                            n = tx.count
                            last = lv[1]
                        } else if nlv(lv[0]) >= 2 && nlv(lv[1]) >= 2, let i1 = am.firstIndex(of: lv[1]), let l0 = am.lastIndex(of: lv[0]), i1 > l0,
                                  Swift.abs(lv[1] - lv[0]) <= lv[0] * 1.5 {
                            // grosse Preisstufe, beide Preise mehrfach und nacheinander (Web v272)
                            ch = BankPriceChange(from: tx[i1].date, prev: lv[0], amount: lv[1])
                        } else if n < 3 || Swift.abs(lv[1] - lv[0]) > lv[0] * (kind == "card" ? 0.05 : 0.10) {
                            return nil
                        }
                    } else if let j = am.firstIndex(of: lv[1]) {
                        ch = BankPriceChange(from: tx[j].date, prev: lv[0], amount: lv[1])
                    }
                }
            } else {
                if n < 3 { return nil }
                // Preisstufen: mehr als zwei Stufen, aber die letzten ≥ 3 Zahlungen gleich (Steuerraten je Jahr neu, Krankenkasse jeden Januar)
                // → fester Vertrag mit aktuellem Preis, Änderung ab Beginn der letzten Stufe; nicht bei Kartenzahlungen ohne Katalog
                var tr = 1
                while tr < n && Swift.abs(am[n - 1 - tr] - am[n - 1]) <= am[n - 1] * 0.005 { tr += 1 }
                if tr >= 3 && tr < n && (kind != "card" || g.tpl != nil) && tx[n - tr].date.days(to: tx[n - 1].date) >= (tr - 1) * cyc * 25 {
                    ch = BankPriceChange(from: tx[n - tr].date, prev: am[n - tr - 1], amount: am[n - 1])
                    last = am[n - 1]
                } else {
                // schwankende Beträge nur bei Rechnungen/Lastschriften (Strom, Handy); Kartenabos haben einen festen Preis.
                // Ausnahme: Kartenabo in Fremdwährung – Betrag schwankt nur durch den Kurs: monatlich, eng (±5 %), mind. 3×
                var fx = false
                if kind == "card" && n >= 3 && cyc == 1 {
                    let s0 = am.sorted(), m0 = s0[s0.count / 2]
                    fx = am.allSatisfy { Swift.abs($0 - m0) <= m0 * 0.05 }
                        && rxFxWords.test(Partners.lnorm(tx.map { $0.text + " " + $0.type }.joined(separator: " ")))
                }
                if kind == "card" && g.tpl == nil && !fx { return nil }
                // Schwankung nur über die letzten 13 Monate prüfen (lange Auszüge driften); Strom/Energie schwankt mit dem Verbrauch: ±20 %
                var amR = tx.indices.filter { tx[$0].date.days(to: ref) <= 400 }.map { am[$0] }
                if amR.count < 3 { amR = am }
                let sR = amR.sorted(), mR = sR[sR.count / 2]
                let tol = (g.tpl?.category == "Energie & Wasser") || rxEnergyName.test(Partners.lnorm(name)) ? 0.20 : 0.10
                // Anlauf: anteilige erste Rechnungen, dann zweimal der volle Betrag → ok mit vollem Betrag
                let ramp = n >= 3 && Swift.abs(am[n - 2] - am[n - 1]) < 0.005 && am.allSatisfy { $0 <= am[n - 1] + 0.005 }
                if !ramp && Double(amR.filter({ Swift.abs($0 - mR) <= mR * tol }).count) < Double(amR.count) * 0.7 { return nil }
                // aktueller Betrag: Median der letzten 3 Rechnungen (Abo-Wechsel), nicht des ganzen Auszugs
                varies = true
                let l3 = Array(am.suffix(3)).sorted()
                // Jahres-/Halbjahresprämie: aktuelle Rechnung zählt
                last = cyc >= 6 ? am[n - 1] : l3[l3.count / 2]
                // Verbrauch (Strom, Gas, Wasser) schwankt mit der Jahreszeit: Durchschnitt der Rechnungen der letzten 12 Monate statt Median
                // der letzten 3; mind. ¾ der Rechnungen eines Jahres. Nur Rechnungen alle 2–3 Monate, Ausreisser ausserhalb ±20 % zählen nicht
                if tol == 0.20 && cyc >= 2 && cyc < 6 && !ramp {
                    let aY = tx.indices.filter { tx[$0].date.days(to: ref) <= 365 && Swift.abs(am[$0] - mR) <= mR * tol }.map { am[$0] }
                    if Double(aY.count) >= Swift.max(2, (12 / Double(cyc) * 0.75).rounded(.up)) { last = BU.r2(aY.reduce(0, +) / Double(aY.count)) }
                }
                }
            }
            if ch == nil, let p = g.prevC, cyc == 1, Swift.abs(p.amount - last) > 0.004 {
                ch = BankPriceChange(from: tx[0].date, prev: p.amount, amount: last)
                prevTx = p.tx
            }
            // beendet? letzte Zahlung deutlich länger her als der Rhythmus
            if Double(tx[n - 1].date.days(to: ref)) > Double(cyc) * 30.5 * 1.5 + 7 { return nil }
            // erst ab 3 Zahlungen sicher; Quartal/Jahr ab 2. Lastschrift/Dauerauftrag monatlich mit 2 Zahlungen «mittel»
            if n >= 3 || cyc >= 3 {
                conf = varies ? .medium : .high
            } else {
                conf = (kind == "dd" || kind == "so") ? .medium : .low
            }
            // Kartenzahlung nur zweimal im Jahresabstand (App-Kauf 7.– zweimal im Februar): Zufall möglich → nur nachfragen
            if kind == "card" && n < 3 && cyc >= 3 { conf = .low }
            // nur zwei Zahlungen im Quartals-/Halbjahres-/Jahresabstand ohne Vertragssignal (Katalog, Gläubiger-ID, Lastschrift/Dauerauftrag,
            // Mitteilung, Vertragswort, Verein): Zufall möglich (Dentalhygiene 2× 140.–) → nur nachfragen (Web Review B-M1)
            if n < 3 && cyc >= 3 && g.tpl == nil && kind != "dd" && kind != "so" && !tx.contains(where: { !$0.cred.isEmpty || !$0.memo.isEmpty })
                && !BKONCE.test(Partners.lnorm(name + " " + tx[n - 1].text)) && !BankClub.isClub(name, name) {
                conf = .low
            }
            if g.yearly && n < 3 { conf = .low }
        } else {
            // Einzelzahlung nur bei bekanntem Anbieter, SEPA-Lastschrift mit Gläubiger-ID oder eindeutigem Vertragswort im Text
            // (Versicherung, Prämie, Kfz-Steuer, Mitgliedsbeitrag …) bzw. Jahreswort + Vertragswort (IONOS «Domain Jahresrechnung»)
            let t0 = tx[0]
            let h0 = Partners.lnorm(name + " " + t0.text)
            let ow = (BKONCE.test(h0) || BankClub.isClub(name, name) || (rxOnceYearWord.test(h0) && rxOnceContractWord.test(h0))) && !BKONCENO.test(h0)
                && Partners.lusable(name)
            // einzelne eBill/Lastschrift ohne Gläubiger-ID, Mandat oder Vertragswort ist meist ein Einkauf (Web Review B-M2)
            let tt = Partners.lnorm(t0.text + " " + t0.type)
            let ddSig = kind == "dd" && (!t0.cred.isEmpty || !t0.mref.isEmpty || rxDdSig.test(tt)) && !rxEbillOnce.test(tt)
            if g.tpl == nil && !ow && (!(!t0.cred.isEmpty || ddSig) || BankCatalog.BKVIA.test(Partners.lnorm(name))) { return nil }
            // Schadenzahlung, Selbstbehalt, Arztrechnung: auch beim bekannten Versicherer keine Prämie
            if BKONCENO.test(h0) { return nil }
            // Zeitraum im Zahlungsgrund setzt den Rhythmus («Rundfunk 07.2026 - 09.2026», «Jahresgebühr»)
            var per = BankCatalog.period(t0.text)
            var yr = rxYearly.test(h0)
            if Swift.abs(t0.amount) < 5 { return nil }
            // Vertragswort: eher Jahreszahlung, auch am Ende eines kurzen Auszugs; kleine Lastschrift (< 150) bleibt bei der Monatsvermutung
            if per == 0 && !yr && (BKONCE.test(h0) || BankClub.isClub(name, name)) && !(kind == "dd" && Swift.abs(t0.amount) < 150) { yr = true }
            // kurzer Auszug und Zahlung ganz am Ende: eher monatlich; bei langem Auszug (> 10 Monate) wäre eine Monatszahlung mehrfach drin
            let dRef = t0.date.days(to: ref)
            // Krankenkasse: Prämie wird praktisch immer monatlich bezahlt (CH Grundversicherung, DE private KV) – auch bei nur einer Zahlung
            let kk = rxKK.test(h0) || (g.tpl.map { rxKKTpl.test($0.label + " " + $0.category) } ?? false)
            if per == 0 && !rxYearWord.test(h0) {
                if preCyc != 0 {
                    per = preCyc
                } else if kk {
                    // monatlich nur bei plausibler Monatsprämie (< 2'500) und jüngerer Zahlung; sonst Jahresprämie (Web Review B-H4)
                    if -t0.amount < 2500 && dRef <= 45 { per = 1 } else { yr = true }
                }
            }
            cyc = per != 0 ? per : (yr ? 12 : ((dRef < 40 && span > 40 && (span <= 300 || rxLsv.test(Partners.lnorm(t0.text + " " + t0.type)))) ? 1 : 12))
            // internationale Monatsabos (Netflix…) mit nur einer Zahlung: eher Einkauf
            if per == 0 && !yr, let t = g.tpl, t.country.isEmpty, cyc == 12, dRef > 45 { return nil }
            // langer Auszug: eine Jahreszahlung, die über 13 Monate zurückliegt, hätte sich wiederholt → kein laufender Vertrag
            if Double(dRef) > Double(cyc) * 30.5 + 30 { return nil }
            conf = .low
        }
        let due = nextDue(tx.map { $0.date }, cycle: cyc, today: today)
        let lt = tx[n - 1]
        var s = BankSuggestion(id: k, key: k, name: name, raw: !lt.name.isEmpty ? lt.name : BankName.from(lt.text), text: lt.text, currency: g.cur,
                               amount: BU.r2(last), cycle: cyc, due: due, first: tx[0].date, last: lt.date, count: n, dates: tx.map { $0.date },
                               amounts: am, confidence: conf, varies: varies, change: ch, catalog: g.tpl, category: "",
                               kind: BankKind(web: kind), cred: lt.cred, mref: lt.mref, alias: nil, ignored: false)
        s.memo = lt.memo
        // Vorpreis-Stufe (Steuerraten 760 bis Juni, ab Juli 340): deren Zahlungen gehören zum selben Vertrag → in Zahlungsliste
        // und Preisverlauf (Web v326)
        let pt = prevTx.filter { $0.date < tx[0].date }
        if !pt.isEmpty {
            s.dates = pt.map { $0.date } + s.dates
            s.amounts = pt.map { BU.r2(-$0.amount) } + s.amounts
            s.count = s.dates.count
            s.first = s.dates[0]
        }
        return s
    }
}
