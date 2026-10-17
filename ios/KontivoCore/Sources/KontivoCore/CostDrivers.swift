import Foundation

// «Entwicklung und Preistreiber» im Tab «Kosten» (Web v190–v192, `ptSection`, `ptReason`, `ptYearSum`).
// Beantwortet: Wie entwickeln sich die Fixkosten (Vorjahr · aktuelles Jahr · Folgejahr, je Jahrestotal wie «Total JJJJ»)?
// Was treibt die Veränderung (je Kategorie; Wechsel innerhalb einer Kategorie, z.B. alte → neue Miete, heben sich auf)?
// Künftige Jahre = «Prognose»: nur eingetragene Änderungen (Preise, Beginn, Ende, Pausen), keine Teuerung.
// Filter (Person/Kategorie/Vertragspartner) gilt wie oben in «Kosten».

extension Calc {
    /// Eine Säule (Jahrestotal)
    public struct CostDriverColumn: Hashable, Identifiable, Sendable {
        public var year: Int
        public var total: Double
        /// Säulenhöhe 0…1 (mind. 3 %)
        public var height: Double
        /// «Prognose» über der Zahl (Jahr nach dem aktuellen)
        public var forecast: Bool
        /// Veränderung zum Vorjahr («↑ 49», «↓ 64», «±0»); nil = Platzhalter (erste Säule oder ohne Vorjahr)
        public var deltaText: String?
        public var trend: Trend
        public var id: Int { year }
        /// Lage relativ zum gewählten Jahr
        public enum Place: String, Hashable, Sendable { case past, current, future }
        public var place: Place
        /// VoiceOver: «2027 Prognose: 38’447 CHF»
        public var accessibilityLabel: String
    }

    /// Ein geänderter Vertrag (Differenz gewähltes Jahr − Vorjahr)
    public struct CostDriverChange: Hashable, Identifiable, Sendable {
        public var contractID: UUID
        /// Vorjahr / gewähltes Jahr (Hauptwährung × Anteil)
        public var previous: Double
        public var current: Double
        public var delta: Double { current - previous }
        /// Grund («Preis ↑ 4 % seit Januar», «neu seit März», …)
        public var reason: String
        public var id: UUID { contractID }
    }

    /// Eine Kategorie mit Veränderung
    public struct CostDriverGroup: Hashable, Identifiable, Sendable {
        /// Kategorie (`statKey(c, .category)`)
        public var key: String
        public var previous: Double
        public var current: Double
        public var delta: Double { current - previous }
        /// Verträge mit |Differenz| ≥ 0.5, grösste zuerst
        public var changes: [CostDriverChange]
        /// Zweitzeile («Wechsel: TV → Musik», «Neue Miete: …», «Handy Preis ↑ 5 % seit Januar und 2 weitere»)
        public var why: String
        public var id: String { key }
    }

    public struct CostDrivers: Hashable, Sendable {
        public var year: Int
        /// Drei Säulen (Vorjahr · aktuell · Folgejahr um heute; weiter weg um das gewählte Jahr)
        public var columns: [CostDriverColumn]
        /// false: im Vorjahr keine Zahlungen → nur Hinweis `noCompareNote`
        public var comparable: Bool
        /// «Für 2025 sind keine Zahlungen erfasst – noch kein Vergleich möglich.»
        public var noCompareNote: String?
        /// «Was sich verändert hat · 2025 → 2026» bzw. «Prognose · 2026 → 2027»
        public var listTitle: String
        public var groups: [CostDriverGroup]
        /// «Keine Veränderung gegenüber 2025.»
        public var emptyNote: String?
        /// «Alle anderen Kategorien sind gleich geblieben.» / «… bleiben gleich.»
        public var othersNote: String?
        /// Verträge ohne Beginn, die auch im Vorjahr voll zählen
        public var noStartNote: String?
    }

    /// Jahrestotal eines Vertrags in Hauptwährung × Personenanteil (`ptYearSum`).
    public func yearSum(_ c: Contract, year y: Int, person: UUID?) -> Double {
        let f = holderShare(c, person: person)
        if f == 0 { return 0 }
        var s = 0.0
        for p in payments(c, from: Day(y, 1, 1), to: Day(y, 12, 31)) { s += conv(p.amount, c.currency) * f }
        return s
    }

    /// Pausiert-Flag der Web-App (`c.paused`): Vertrag hat eine Pause.
    func hasPauseFlag(_ c: Contract) -> Bool { !c.pauses.isEmpty }

    /// Grund der Veränderung eines Vertrags von Jahr `ya` zu `yb` (`ptReason`).
    public func driverReason(_ c: Contract, from ya: Int, to yb: Int, previous sa: Double, current sb: Double) -> String {
        let mon = Format.monthNames
        func my(_ d: Day) -> String { mon[d.month - 1] + (d.year != yb ? " \(d.year)" : "") }
        let st = c.start
        let lim = limit(c)
        let t = today
        if sa < 0.005 && sb >= 0.005 {
            var f0: Day? = nil
            for p in payments(c, from: Day(yb, 1, 1), to: Day(yb, 12, 31)) where p.extra == nil {
                if f0 == nil || p.date < f0! { f0 = p.date }
            }
            if let s = st, s.year == yb { return "neu seit " + my(s) }
            if let f = f0 { return "neu ab " + my(f) }
            return "neu"
        }
        if sb < 0.005 && sa >= 0.005 {
            if hasPauseFlag(c) { return "pausiert" }
            if let l = lim { return (l > t ? "endet im " : "beendet im ") + my(l) }
            return "keine Zahlung mehr"
        }
        let pc = pricesOf(c)
        let inB = pc.filter { $0.from.year == yb }
        let inA = pc.filter { $0.from.year == ya }
        func pct(_ e: PriceChange) -> Int? {
            let old = priceAt(c, e.from.addingDays(-1))
            if !(old > 0) { return nil }
            return Int(Format.jsRound((e.amount - old) / old * 100))
        }
        if let e = inB.last {
            let m = mon[e.from.month - 1]
            guard let q = pct(e) else { return "Preis geändert seit " + m }
            if q == 0 { return "Preis angepasst" }
            return "Preis " + (q > 0 ? "↑ " : "↓ ") + "\(Swift.abs(q)) % seit " + m
        }
        if let l = lim, l.year == yb { return (l > t ? "endet im " : "beendet im ") + mon[l.month - 1] }
        if let e = inA.last {
            let qa = pct(e) ?? 0
            return qa > 0 ? "Erhöhung gilt ganzes Jahr" : (qa < 0 ? "Senkung gilt ganzes Jahr" : "Preisänderung gilt ganzes Jahr")
        }
        if let s = st, s.year == ya { return "erstes volles Jahr" }
        let ex = extrasOf(c)
        if let x = ex.first(where: { $0.date.year == yb }) {
            return (x.amount < 0 ? "Gutschrift im " : "Sonderzahlung im ") + mon[x.date.month - 1]
        }
        if let x = ex.first(where: { $0.date.year == ya }) {
            return (x.amount < 0 ? "Gutschrift" : "Sonderzahlung") + " im Vorjahr"
        }
        if hasPauseFlag(c) { return "pausiert" }
        return sb > sa ? "mehr Zahlungen im Jahr" : "weniger Zahlungen im Jahr"
    }

    /// «Entwicklung und Preistreiber» für das gewählte Jahr `Y` mit den Filtern aus «Kosten».
    public func costDrivers(year Y: Int, filter: CostFilter) -> CostDrivers {
        let nowY = today.year
        let B = (Y >= nowY - 1 && Y <= nowY + 1) ? nowY : Y
        var ys = [B - 1, B, B + 1]
        if !ys.contains(Y - 1) { ys.insert(Y - 1, at: 0) }
        var tot: [Int: Double] = [:]
        for y in ys { tot[y] = 0 }
        let inF = data.contracts.filter { matches($0, filter) }
        var per: [UUID: [Int: Double]] = [:]
        for c in inF {
            var m: [Int: Double] = [:]
            for y in ys {
                let v = yearSum(c, year: y, person: filter.person)
                m[y] = v
                tot[y, default: 0] += v
            }
            per[c.id] = m
        }
        let cy = [B - 1, B, B + 1]
        var mx = cy.map { tot[$0] ?? 0 }.max() ?? 0
        if mx == 0 { mx = 1 }
        let H = home.rawValue
        var cols: [CostDriverColumn] = []
        for (i, y) in cy.enumerated() {
            let v = tot[y] ?? 0
            var dt: String? = nil
            var tr = Trend.same
            if i > 0, (tot[y - 1] ?? 0) > 0.004 {
                let d = Format.jsRound(v - (tot[y - 1] ?? 0))
                if d == 0 { dt = "±0" } else {
                    dt = (d > 0 ? "↑ " : "↓ ") + Format.money0(Swift.abs(d))
                    tr = d > 0 ? .up : .down
                }
            }
            let place: CostDriverColumn.Place = y == Y ? .current : (y < Y ? .past : .future)
            cols.append(CostDriverColumn(year: y, total: v, height: Swift.max(3, v / mx * 100) / 100, forecast: y > nowY,
                                         deltaText: dt, trend: tr, place: place,
                                         accessibilityLabel: "\(y)" + (y > nowY ? " Prognose" : "") + ": " + Format.money0(v) + " " + H))
        }
        var out = CostDrivers(year: Y, columns: cols, comparable: true, noCompareNote: nil, listTitle: "", groups: [],
                              emptyNote: nil, othersNote: nil, noStartNote: nil)
        let noSt = inF.filter { $0.start == nil && (per[$0.id]?[Y - 1] ?? 0) > 0.004 }.count
        if !((tot[Y - 1] ?? 0) > 0.004) {
            out.comparable = false
            out.noCompareNote = "Für \(Y - 1) sind keine Zahlungen erfasst – noch kein Vergleich möglich."
            return out
        }
        // je Kategorie: Summe Vorjahr/Jahr und die geänderten Verträge (Reihenfolge des ersten Auftretens wie JS-Objekt)
        var order: [String] = []
        var G: [String: (a: Double, b: Double, ch: [(c: Contract, a: Double, b: Double)])] = [:]
        for c in inF {
            let a = per[c.id]?[Y - 1] ?? 0, b = per[c.id]?[Y] ?? 0
            if a < 0.005 && b < 0.005 { continue }
            let k = statKey(c, .category)
            if G[k] == nil { order.append(k); G[k] = (0, 0, []) }
            G[k]!.a += a
            G[k]!.b += b
            if Swift.abs(b - a) >= 0.5 { G[k]!.ch.append((c, a, b)) }
        }
        var cats: [(k: String, a: Double, b: Double, ch: [(c: Contract, a: Double, b: Double)])] = []
        for k in order {
            let g = G[k]!
            let ch = g.ch.stableSorted { Swift.abs($0.b - $0.a) > Swift.abs($1.b - $1.a) }
            if Swift.abs(g.b - g.a) >= 0.5 || !ch.isEmpty { cats.append((k, g.a, g.b, ch)) }
        }
        cats = cats.stableSorted { Swift.abs($0.b - $0.a) > Swift.abs($1.b - $1.a) }
        let n0 = order.count - cats.count
        func title(_ c: Contract) -> String { data.title(of: c) }
        func partnerOr(_ c: Contract) -> String { let p = partnerName(c); return p.isEmpty ? title(c) : p }
        func why(_ ch: [(c: Contract, a: Double, b: Double)]) -> String {
            if ch.isEmpty { return "" }
            let r0 = ch[0]
            let first = title(r0.c) + " " + driverReason(r0.c, from: Y - 1, to: Y, previous: r0.a, current: r0.b)
            if ch.count == 1 { return first }
            func stY(_ r: (c: Contract, a: Double, b: Double)) -> Bool {
                guard let d = r.c.start else { return false }
                return d.year == Y || d.year == Y - 1
            }
            func endY(_ r: (c: Contract, a: Double, b: Double)) -> Bool {
                if r.b < 0.005 { return true }
                guard let d = limit(r.c) else { return false }
                return (d.year == Y || d.year == Y - 1) && r.b - r.a < 0
            }
            if ch.count == 2,
               let up = ch.first(where: { $0.b - $0.a > 0 && ($0.a < 0.005 || stY($0)) }),
               let dn = ch.first(where: { $0.b - $0.a < 0 && endY($0) }) {
                func nm(_ r: (c: Contract, a: Double, b: Double), other: Contract) -> String {
                    title(r.c) == title(other) ? partnerOr(r.c) : title(r.c)
                }
                if title(up.c) == title(dn.c) { return "Neue " + title(up.c) + ": " + partnerOr(up.c) }
                return "Wechsel: " + nm(dn, other: up.c) + " → " + nm(up, other: dn.c)
            }
            return first + " und \(ch.count - 1)" + (ch.count == 2 ? " weiterer" : " weitere")
        }
        out.listTitle = (Y > nowY ? "Prognose" : "Was sich verändert hat") + " · \(Y - 1) → \(Y)"
        if cats.isEmpty { out.emptyNote = "Keine Veränderung gegenüber \(Y - 1)." }
        out.groups = cats.map { g in
            CostDriverGroup(key: g.k, previous: g.a, current: g.b,
                            changes: g.ch.map { CostDriverChange(contractID: $0.c.id, previous: $0.a, current: $0.b,
                                                                 reason: driverReason($0.c, from: Y - 1, to: Y, previous: $0.a, current: $0.b)) },
                            why: why(g.ch))
        }
        if !cats.isEmpty && n0 > 0 {
            out.othersNote = Y > nowY ? "Alle anderen Kategorien bleiben gleich." : "Alle anderen Kategorien sind gleich geblieben."
        }
        if noSt > 0 {
            out.noStartNote = "\(noSt)" + (noSt == 1 ? " Vertrag hat" : " Verträge haben") + " keinen Vertragsbeginn und "
                + (noSt == 1 ? "wird" : "werden") + " auch für \(Y - 1) voll gezählt."
        }
        return out
    }

    /// Betrag mit Vorzeichen für die Treiberliste (`sgn`): «+49», «−64», «±0»
    public static func driverDeltaText(_ d: Double) -> (text: String, trend: Trend) {
        let r = Format.jsRound(d)
        let s = r > 0 ? "+" : (r < 0 ? Format.minus : "±")
        return (s + Format.money0(Swift.abs(r)), r > 0 ? .up : (r < 0 ? .down : .same))
    }

    // MARK: Filterauswahl mit Betrag (Web v190 `openPick` im Tab «Kosten»)

    /// Werte einer Filterdimension wie `kbFilterValues`, im Tab «Kosten» (Kategorie/Vertragspartner) mit Jahresbetrag und Anteil,
    /// grösste zuerst. Ist ein Personenfilter gesetzt, zählen nur Verträge, die zu den übrigen Filtern (ausser `dim`) passen.
    public func kbFilterValuesWithAmounts(_ dim: FilterDimension, year: Int, filter: CostFilter) -> [(value: KBFilterValue, text: String)] {
        let vals = kbFilterValues(dim)
        if dim == .holder { return vals.map { ($0, $0.countText) } }
        var amt: [String: Double] = [:]
        var aTot = 0.0
        for c in data.contracts {
            if filter.person != nil && !matches(c, filter, skip: dim) { continue }
            let v = yearSum(c, year: year, person: filter.person)
            if v > 0.004 {
                amt[statKey(c, dim), default: 0] += v
                aTot += v
            }
        }
        let sorted = vals.stableSorted { a, b in
            let x = amt[a.key] ?? 0, y = amt[b.key] ?? 0
            if x != y { return x > y }
            return Format.lessDE(a.key, b.key)
        }
        let H = home.rawValue
        return sorted.map { v in
            if let a = amt[v.key], a != 0 {
                return (v, Format.money0(a) + " " + H + " · \(Int(Format.jsRound(a / aTot * 100))) %")
            }
            return (v, "keine Zahlungen \(year)")
        }
    }
}
