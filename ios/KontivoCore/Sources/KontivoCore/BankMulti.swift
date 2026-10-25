import Foundation

// MARK: - Kontoauszug: mehrere Dateien und mehrere Policen (Web v325–v330)

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

    /// Versicherer mit mehreren Policen ohne Bezeichnung (Web v330): keine Reihe, aber jede Zahlung der letzten 12 Monate ist eine
    /// mögliche Jahresprämie → je Zahlung (ab 50.–, je Betrag einmal) eine eigene Gruppe. Liefert die neuen Gruppen mit Bewertung.
    static func policies(_ k: String, _ gk: Group, fallbackEnd: Day, span: Int, today: Day) -> [(k: String, g: Group, s: BankSuggestion)] {
        guard gk.tx.count >= 2 else { return [] }
        let ref0 = gEnd(gk.tx, fallbackEnd)
        if !BKONCE.test(Partners.lnorm(gk.names.orderedKeys.joined(separator: " ") + " " + gk.tx[0].text)) { return [] }
        var seenA = Set<String>()
        var subs: [(k: String, g: Group, s: BankSuggestion)] = []
        for (ti, t) in gk.tx.enumerated() {
            let a = String(format: "%.2f", t.amount)
            if seenA.contains(a) || -t.amount < 50 || t.date.days(to: ref0) > 366 { continue }
            seenA.insert(a)
            let k2 = k + "@" + String(ti)
            let g2 = Group(key: k2, tpl: gk.tpl, tx: [t], names: gk.names, cur: gk.cur)
            if let s2 = eval(k2, g2, fallbackEnd: fallbackEnd, span: span, today: today) { subs.append((k2, g2, s2)) }
        }
        if subs.count > 1 { for i in subs.indices { subs[i].s.multi = true } }
        return subs
    }
}
