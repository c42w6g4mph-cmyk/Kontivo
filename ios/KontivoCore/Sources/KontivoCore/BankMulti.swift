import Foundation

// MARK: - Kontoauszug: mehrere Dateien, eigene Namen, Rückfallebene (Web v325–v346)

extension BankImport {
    /// Mehrere Dateien (Web v325/v328, IIFE in `bankFind`): derselbe Vertragspartner in zwei Exporten unterschiedlich benannt (mit/ohne
    /// Gläubiger-ID) → Gruppen aus verschiedenen Dateien mit grösstenteils gleichen Zahlungen (Datum + Betrag) zusammenführen.
    /// Umgekehrt: derselbe Vertragspartner gleichzeitig in zwei Konten (zwei Handyabos) → je Datei eine eigene Gruppe.
    static func mergeFiles(_ groups: inout BOrdered<Group>) {
        let K = groups.orderedKeys.filter { k in
            guard let g = groups[k] else { return false }
            return g.tx.count >= 2 && g.tx.allSatisfy { $0.fi != nil }
        }
        if K.count < 2 { return }
        struct Sig {
            var S: Set<String>
            var F: Set<Int>
            let n: Int
        }
        func id(_ t: BankTx) -> String { t.date.iso + "|" + String(t.amount) }
        var G: [String: Sig] = [:]
        for k in K {
            guard let g = groups[k] else { continue }
            let S = Set(g.tx.map(id))
            G[k] = Sig(S: S, F: Set(g.tx.compactMap { $0.fi }), n: S.count)
        }
        for a in K {
            if groups[a] == nil { continue }
            for b in K {
                guard a != b, var ga = groups[a], let gb = groups[b], ga.cur == gb.cur, var A = G[a], let B = G[b] else { continue }
                if !B.F.isDisjoint(with: A.F) { continue }
                let m = B.S.filter { A.S.contains($0) }.count
                if Double(m) < Swift.max(2, Double(Swift.min(A.n, B.n)) * 0.5) { continue }
                for t in gb.tx where !A.S.contains(id(t)) {
                    ga.tx.append(t)
                    A.S.insert(id(t))
                }
                A.F.formUnion(B.F)
                G[a] = A
                for n in gb.names.orderedKeys { ga.names[n] = (ga.names[n] ?? 0) + (gb.names[n] ?? 0) }
                if ga.tpl == nil && gb.tpl != nil { ga.tpl = gb.tpl }
                ga.tx = BU.sorted(ga.tx, byDate)
                groups[a] = ga
                groups[b] = nil
            }
        }
        // Zahlen beide Dateien im selben Zeitraum (je ≥ 2 Zahlungen im Zeitraum der anderen) → je Datei eine eigene Gruppe.
        // Nacheinander (Konto → Karte) bleibt eins
        for k in groups.orderedKeys {
            guard let g = groups[k] else { continue }
            var F: [Int: [BankTx]] = [:]
            for t in g.tx { if let f = t.fi { F[f, default: []].append(t) } }
            let fs = F.keys.sorted()
            if fs.count < 2 { continue }
            func inRange(_ L: [BankTx], of R: [BankTx]) -> Int {
                let lo = R[0].date, hi = R[R.count - 1].date
                return L.filter { $0.date >= lo && $0.date <= hi }.count
            }
            let par = fs.contains { a in
                fs.contains { b in a != b && inRange(F[a] ?? [], of: F[b] ?? []) >= 2 && inRange(F[b] ?? [], of: F[a] ?? []) >= 2 }
            }
            if !par { continue }
            groups[k] = nil
            for f in fs {
                let L = F[f] ?? []
                var names = BOrdered<Int>()
                for t in L { names[t.groupName] = (names[t.groupName] ?? 0) + 1 }
                let nk = k + "#" + String(f)
                groups[nk] = Group(key: nk, tpl: g.tpl, tx: L, names: names, cur: g.cur)
            }
        }
    }

    /// Eigene Namen (Web `ME` in `bankFind`): Kontoinhaber der Datei (Vor- und Nachname), Personen mit ganzem Namen; Personen nur mit
    /// Vornamen zählen zusammen mit einem Nachnamen bzw. als «^Vorname» (Dauerauftrag an «Vorname …»). Der alte Einzel-Absender
    /// (Web `settings.sender`) existiert in Swift nicht.
    static func selfNames(_ r: BankFile, _ data: AppData) -> [[String]] {
        let full = [r.owner].map { BankName.tok($0).filter { $0.count >= 3 } }.filter { $0.count >= 2 }
        var sur: [String] = []
        for w in full where !sur.contains(w[w.count - 1]) { sur.append(w[w.count - 1]) }
        var out = full
        for p in data.persons {
            let w = BankName.tok(p.name).filter { $0.count >= 3 }
            if w.count >= 2 {
                out.append(w)
            } else if w.count == 1 {
                for sn in sur { out.append([w[0], sn]) }
                out.append(["^" + w[0]])
            }
        }
        return out
    }

    /// Grundschlüssel des Vertragspartners (Web `bankBase`): ohne Datei-/Betragsstufe (#…); bei Namensschlüsseln nur das erste Wort,
    /// wenn es markant ist («Strassenverkehrsamt» / «Strassenverkehrsamt des Kantons Thurgau»), nicht bei Gemeinde, Stadt, Orten, Vornamen
    static func base(_ k: String) -> String {
        let b = rxBaseCut.replaceAll(k, "")
        var p = b.components(separatedBy: "|")
        let f = p[0].components(separatedBy: " ")[0]
        if !rxBaseTag.test(p[0]) && !p[0].contains("~") && BU.len(f) >= 8 && !Partners.LGEN.contains(f) && !Partners.LPLACE.contains(f)
            && !rxBaseStop.test(f) {
            p[0] = f
        }
        return p.joined(separator: "|")
    }

    static let rxMitteilungRest = BRX("mitteilung:\\s*([\\s\\S]+)", i: true)
    static let rxDateDots = BRX("\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}")
    static let rxYear = BRX("\\b(19|20)\\d{2}\\b")
    static let rxYearSpan = BRX("\\b(19|20)\\d{2}(/\\d{2,4})?\\b")
    static let rxDigits = BRX("\\d+")
    static let rxWS = BRX("\\s+")

    /// Rückfallebene ohne erkannte Reihe (Web `bankFallback`): Jahresreihen nach Kalendermonat (wechselnde Prämien, auch halbjährlich),
    /// Rechnungen mit Jahr in der Mitteilung (Steuer Bund 2023/2024/2025) und – bei Vertragswort – jede Zahlung der letzten 12 Monate
    /// als mögliche Jahresprämie. Liefert die neuen Gruppen mit Bewertung (mehrere → `multi`).
    static func fallback(_ k: String, _ gk: Group, fallbackEnd: Day, span: Int, today: Day) -> [(k: String, g: Group, s: BankSuggestion)] {
        guard gk.tx.count >= 2 else { return [] }
        let ref0 = gEnd(gk.tx, fallbackEnd)
        let names = gk.names.orderedKeys
        let onceW = BKONCE.test(Partners.lnorm(names.joined(separator: " ") + " " + gk.tx[0].text)) || names.contains { BankClub.isClub($0, $0) }
        var subs: [(k: String, g: Group, s: BankSuggestion)] = []
        var useT = Set<Int>()
        func evalSub(_ k2: String, _ g2: Group) -> BankSuggestion? { eval(k2, g2, fallbackEnd: fallbackEnd, span: span, today: today) }
        // Jahresreihen nach Kalendermonat: nur mit Vertragssignal, keine Kartenkäufe, nur bei dünn besetzten Gruppen (höchstens jeder zweite
        // Monat mit Zahlung); Abstand 300–430 Tage, Betrag ±35 % zur letzten Zahlung der Reihe; 2 Jahre = Rückfrage, ab 3 Jahren Vorschlag
        let gm = Set(gk.tx.map { BU.slice($0.date.iso, 0, 7) })
        let gspan = Swift.max(1, Int(BU.round(Double(gk.tx[0].date.days(to: gk.tx[gk.tx.count - 1].date)) / 30.44)) + 1)
        if Double(gm.count) <= Double(gspan) * 0.5 && (onceW || gk.tpl != nil || gk.tx.contains { !$0.cred.isEmpty || $0.kind == .dd || $0.kind == .so }) {
            var SR: [[BankTx]] = []
            var byD = BOrdered<[BankTx]>()
            for t in gk.tx where -t.amount >= 20 && t.kind != .card { byD[t.date.iso] = (byD[t.date.iso] ?? []) + [t] }
            // je Buchungstag: beste Paare (Betrag am nächsten) zuerst – zwei Fahrzeuge am selben Tag (168 / 153.15) nicht vertauschen
            for d0 in byD.orderedKeys.sorted() {
                let day = byD[d0] ?? []
                var P: [(rr: Double, t: Int, s: Int)] = []
                for (ti, t) in day.enumerated() {
                    for (si, S) in SR.enumerated() {
                        let L = S[S.count - 1], g0 = L.date.days(to: t.date)
                        if g0 < 300 || g0 > 430 { continue }   // Jahresrechnung ±1 Monat früher/später bezahlt
                        let rr = Swift.abs(-t.amount + L.amount) / (-L.amount)
                        if rr <= 0.35 { P.append((rr, ti, si)) }
                    }
                }
                P = BU.sorted(P) { x, y in x.rr - y.rr }
                var usedS = Set<Int>(), usedT = Set<Int>()
                for x in P where !usedT.contains(x.t) && !usedS.contains(x.s) {
                    usedT.insert(x.t)
                    usedS.insert(x.s)
                    SR[x.s].append(day[x.t])
                }
                for (ti, t) in day.enumerated() where !usedT.contains(ti) { SR.append([t]) }
            }
            // Halbjahresraten: übrige Zahlungen 110–220 Tage neben einer Zahlung der Reihe mit ähnlichem Betrag (±12 %) gehören dazu;
            // liegt eine davon in den letzten 12 Monaten, ist die Reihe halbjährlich (Vollkasko 360.50 Jun / 383.20 Nov / 372.70 Mär)
            var inS = Set<Int>()
            for S in SR where S.count >= 2 { for t in S { inS.insert(t.seq) } }
            var HF = Set<Int>()
            let rest = BU.sorted(gk.tx.filter { -$0.amount >= 20 && $0.kind != .card && !inS.contains($0.seq) }, byDate)
            for t in rest {
                var best: Int? = nil
                var bs = 1e9
                for (si, S) in SR.enumerated() where S.count >= 2 {
                    for u in S {
                        let g0 = Swift.abs(u.date.days(to: t.date)), rr = Swift.abs(-t.amount + u.amount) / (-u.amount)
                        if g0 >= 110 && g0 <= 220 && rr <= 0.12 && rr < bs {
                            bs = rr
                            best = si
                        }
                    }
                }
                if let b = best {
                    SR[b].append(t)
                    SR[b] = BU.sorted(SR[b], byDate)
                    if t.date.days(to: ref0) <= 366 { HF.insert(b) }
                }
            }
            for (si, S) in SR.enumerated() {
                // «beendet?» prüft eval wie bei allen Reihen (Jahr: 1,5 × Rhythmus)
                if S.count < 2 || S[S.count - 1].date.days(to: ref0) > 560 { continue }
                let k2 = k + "%" + String(si)
                var g2 = Group(key: k2, tpl: gk.tpl, tx: S, names: gk.names, cur: gk.cur)
                g2.yearly = true
                g2.half = HF.contains(si)
                if let s2 = evalSub(k2, g2) {
                    subs.append((k2, g2, s2))
                    for t in S { useT.insert(t.seq) }
                }
            }
        }
        // Rechnungen mit Jahr in der Mitteilung («Ordentliche Steuer Bund 2023 / 2024 / 2025») = ein Vertrag, auch wenn zwei Jahre kurz
        // nacheinander bezahlt werden. Gleicher Text ohne Jahr/Datum, mind. 2 verschiedene Jahre; Betrag = Rechnung des neusten Jahres.
        // Nicht, wenn der Vertragspartner schon eine erkannte Reihe hat (Steuerraten sind frühere Raten derselben Reihe)
        var PR = BOrdered<[(t: BankTx, y: Int)]>()
        if (onceW || gk.tpl != nil) && !gk.hasSeries {
            for t in gk.tx where !useT.contains(t.seq) {
                guard let mm = rxMitteilungRest.match(t.text) else { continue }
                let tx0 = rxDateDots.replaceAll(mm.s(1), " ")
                guard let y = rxYear.match(tx0) else { continue }
                let pk = BU.trim(rxWS.replaceAll(Partners.lnorm(rxDigits.replaceAll(rxYearSpan.replaceAll(tx0, " "), " ")), " "))
                if BU.len(pk) < 6 { continue }
                PR[pk] = (PR[pk] ?? []) + [(t, Int(y.s(0)) ?? 0)]
            }
        }
        for (pi, pk) in PR.orderedKeys.enumerated() {
            let L = PR[pk] ?? []
            if Set(L.map { $0.y }).count < 2 { continue }
            let T = BU.sorted(L.map { $0.t }, byDate)
            if T[T.count - 1].date.days(to: ref0) > 400 { continue }
            let ny = L.map { $0.y }.max() ?? 0
            guard let la = L.filter({ $0.y == ny }).last else { continue }
            let k2 = k + "^" + String(pi)
            var g2 = Group(key: k2, tpl: gk.tpl, tx: T, names: gk.names, cur: gk.cur)
            g2.period = true
            g2.periodAmt = BU.r2(-la.t.amount)
            if var s2 = evalSub(k2, g2) {
                s2.text = la.t.text
                subs.append((k2, g2, s2))
                for t in T { useT.insert(t.seq) }
            }
        }
        // Versicherer mit mehreren Policen ohne Bezeichnung (Mobiliar: Hausrat 404.10, andere 372.70, 383.20): jede Zahlung der letzten
        // 12 Monate ist eine mögliche Jahresprämie → einzeln als «gehört das dazu?» (ab 50.–, je Betrag einmal)
        if onceW && !gk.hasSeries {
            var seenA = Set<String>()
            for (ti, t) in gk.tx.enumerated() {
                let a = String(format: "%.2f", t.amount)
                if useT.contains(t.seq) || seenA.contains(a) || -t.amount < 50 || t.date.days(to: ref0) > 366 { continue }
                seenA.insert(a)
                let k2 = k + "@" + String(ti)
                var nn = BOrdered<Int>()
                nn[!t.groupName.isEmpty ? t.groupName : (names.first ?? "")] = 1
                let g2 = Group(key: k2, tpl: gk.tpl, tx: [t], names: nn, cur: gk.cur)
                if let s2 = evalSub(k2, g2) { subs.append((k2, g2, s2)) }
            }
        }
        if subs.count > 1 { for i in subs.indices { subs[i].s.multi = true } }
        return subs
    }
}
