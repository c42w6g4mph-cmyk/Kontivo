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
        /// Grund als kurzer Satz («+44 % ab Oktober», «beendet im Juni», «neu ab März», Web v248 `ptKind.t`)
        public var reason: String
        /// Symbol (✕ beendet, ↑/↓ Preis, + neu) und Richtung (Farbe)
        public var icon: String
        public var direction: Trend
        public var id: UUID { contractID }
    }

    /// Chip unter der Kategorie (Web v252 `line`): Vertrag + Status-Wort, Punkt nach Richtung; Wechsel alt → neu als ein Chip.
    public struct CostDriverChip: Hashable, Sendable {
        public enum Tone: String, Hashable, Sendable { case up, down, swap }
        public var name: String
        /// «+44 %», «neu», «beendet», «gewechselt», «teurer» … (Web `ptShort`)
        public var word: String
        public var tone: Tone
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
        /// Höchstens 4 Chips (Web v252), Rest als «+ n weitere» (`moreCount`)
        public var chips: [CostDriverChip]
        public var moreCount: Int
        /// Chips als Text (VoiceOver): «TV beendet, Musik neu, + 1 weitere»
        public var why: String {
            (chips.map { $0.name + " " + $0.word } + (moreCount > 0 ? ["+ \(moreCount) weitere"] : [])).joined(separator: ", ")
        }
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
        /// Verträge ohne Beginn, die auch im Vorjahr voll zählen: «Ohne Vertragsbeginn, deshalb auch für 2025 voll gezählt: Strom ›» (Web v251)
        public var noStartNote: String?
        /// Diese Verträge (antippbar, öffnet den Vertrag)
        public var noStartContracts: [UUID] = []
    }

    /// Stück im Kategorien-Donut (Web v254 `ptDonut`)
    public struct CostDonutSlice: Hashable, Identifiable, Sendable {
        public var key: String
        public var value: Double
        /// «58 %», «<1 %»
        public var percentText: String
        /// Farbe nach Rang (#8b7fd9 …), nil = «Übrige» (grau)
        public var colorHex: String?
        /// «Übrige (n)»: nicht antippbar
        public var isRest: Bool
        public var id: String { key }
    }

    public struct CostDonut: Hashable, Sendable {
        public var year: Int
        public var total: Double
        public var slices: [CostDonutSlice]
        /// «Für 2027 sind keine Fixkosten erfasst.» (ohne Fixkosten)
        public var emptyNote: String?
    }

    static let donutPalette = ["#8b7fd9", "#4fb3a9", "#d4a85a", "#5e93cf", "#c9785f", "#9bb85a"]

    /// Fixkosten im Jahr `Y` nach Kategorie: 5 grösste + «Übrige» (Web v254 `ptDonut`), Filter wie in «Kosten».
    public func costDonut(year Y: Int, filter: CostFilter) -> CostDonut {
        var order: [String] = []
        var G: [String: Double] = [:]
        var T = 0.0
        for c in data.contracts where matches(c, filter) {
            let v = yearSum(c, year: Y, person: filter.person)
            if v < 0.005 { continue }
            let k = statKey(c, .category)
            if G[k] == nil { order.append(k) }
            G[k, default: 0] += v
            T += v
        }
        if !(T > 0.004) { return CostDonut(year: Y, total: T, slices: [], emptyNote: "Für \(Y) sind keine Fixkosten erfasst.") }
        var L: [(k: String, v: Double, rest: Bool)] = order.map { ($0, G[$0] ?? 0, false) }.stableSorted { $0.v > $1.v }
        if L.count > 6 {
            let rest = L[5...]
            L = Array(L.prefix(5))
            L.append(("Übrige (\(rest.count))", rest.reduce(0) { $0 + $1.v }, true))
        }
        func pc(_ v: Double) -> String {
            let p = Int(Format.jsRound(v / T * 100))
            return p < 1 ? "<1 %" : "\(p) %"
        }
        let slices = L.enumerated().map { i, r in
            CostDonutSlice(key: r.k, value: r.v, percentText: pc(r.v), colorHex: r.rest ? nil : Calc.donutPalette[i % 6], isRest: r.rest)
        }
        return CostDonut(year: Y, total: T, slices: slices, emptyNote: nil)
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

    /// Grund der Veränderung eines Vertrags von Jahr `ya` zu `yb` (Web v248 `ptKind`): Symbol, Richtung, kurzer Satz.
    public func driverKind(_ c: Contract, from ya: Int, to yb: Int, previous sa: Double, current sb: Double) -> (icon: String, direction: Trend, text: String) {
        let mon = Format.monthNames
        func my(_ d: Day) -> String { mon[d.month - 1] + (d.year != yb ? " \(d.year)" : "") }
        let st = c.start
        let lim = limit(c)
        let t = today
        let dir: Trend = sb > sa ? .up : .down
        func arrow(_ d: Trend) -> String { d == .up ? "↑" : "↓" }
        if sa < 0.005 && sb >= 0.005 {
            var f0: Day? = nil
            for p in payments(c, from: Day(yb, 1, 1), to: Day(yb, 12, 31)) where p.extra == nil {
                if f0 == nil || p.date < f0! { f0 = p.date }
            }
            if let s = st, s.year == yb { return ("+", .up, "neu ab " + my(s)) }
            if let f = f0 { return ("+", .up, "neu ab " + my(f)) }
            return ("+", .up, "neu")
        }
        if sb < 0.005 && sa >= 0.005 {
            if hasPauseFlag(c) { return ("✕", .down, "pausiert") }
            if let l = lim { return ("✕", .down, l.year < yb ? "seit " + my(l) + " beendet" : (l > t ? "endet im " : "beendet im ") + my(l)) }
            return ("✕", .down, "keine Zahlung mehr")
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
            let q = pct(e)
            guard let q = q, q != 0 else { return (arrow(dir), dir, "Preis angepasst ab " + my(e.from)) }
            return (q > 0 ? "↑" : "↓", q > 0 ? .up : .down, (q > 0 ? "+" : Format.minus) + "\(Swift.abs(q)) % ab " + my(e.from))
        }
        if let l = lim, l.year == yb { return ("✕", .down, (l > t ? "endet im " : "beendet im ") + my(l)) }
        if let l = lim, l.year == ya { return ("✕", .down, "seit " + my(l) + " beendet") }
        if let e = inA.last {
            let qa = pct(e) ?? 0
            return (qa > 0 ? "↑" : "↓", qa > 0 ? .up : .down,
                    qa > 0 ? "Erhöhung gilt ganzes Jahr" : (qa < 0 ? "Senkung gilt ganzes Jahr" : "Preisänderung gilt ganzes Jahr"))
        }
        if let s = st, s.year == ya { return ("↑", .up, "erstes volles Jahr") }
        let ex = extrasOf(c)
        if let x = ex.first(where: { $0.date.year == yb }) {
            return (x.amount < 0 ? "↓" : "↑", x.amount < 0 ? .down : .up, (x.amount < 0 ? "Gutschrift im " : "Sonderzahlung im ") + my(x.date))
        }
        if let x = ex.first(where: { $0.date.year == ya }) {
            return (arrow(dir), dir, (x.amount < 0 ? "Gutschrift" : "Sonderzahlung") + " im Vorjahr")
        }
        if hasPauseFlag(c) { return ("✕", .down, "pausiert") }
        return (arrow(dir), dir, sb > sa ? "mehr Zahlungen im Jahr" : "weniger Zahlungen im Jahr")
    }

    /// Grund als Text (Web `ptKind(...).t`)
    public func driverReason(_ c: Contract, from ya: Int, to yb: Int, previous sa: Double, current sb: Double) -> String {
        driverKind(c, from: ya, to: yb, previous: sa, current: sb).text
    }

    /// Kurzwort für den Chip aus dem Grund (Web v252 `ptShort`): «+44 %», «neu», «beendet», «teurer» …
    public static func driverShort(_ direction: Trend, _ t: String) -> String {
        if let m = RX.match("^([+−]\\d+ %)", t), m.count > 1, let p = m[1] { return p }
        if t.hasPrefix("neu") { return "neu" }
        if t.hasPrefix("endet") { return "endet" }
        if t.contains("beendet") || t.contains("keine Zahlung") { return "beendet" }
        if t.hasPrefix("pausiert") { return "pausiert" }
        if t.hasPrefix("gewechselt") { return "gewechselt" }
        if t.hasPrefix("Gutschrift") { return "Gutschrift" }
        if t.hasPrefix("Sonderzahlung") { return "Sonderzahlung" }
        if t.hasPrefix("erstes volles Jahr") { return "ganzes Jahr" }
        return direction == .up ? "teurer" : "günstiger"
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
        let noStL = inF.filter { $0.start == nil && (per[$0.id]?[Y - 1] ?? 0) > 0.004 }
        let noSt = noStL.count
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
        // Chips unter der Kategorie: Wechsel alt → neu als ein Chip, höchstens 4, Rest «+ n weitere» (Web v248/v252 `lines`)
        func chips(_ chIn: [(c: Contract, a: Double, b: Double)]) -> (chips: [CostDriverChip], more: Int) {
            var ch = chIn
            var out: [CostDriverChip] = []
            if ch.isEmpty { return ([], 0) }
            func stY(_ r: (c: Contract, a: Double, b: Double)) -> Bool {
                guard let d = r.c.start else { return false }
                return d.year == Y || d.year == Y - 1
            }
            func endY(_ r: (c: Contract, a: Double, b: Double)) -> Bool {
                if r.b < 0.005 { return true }
                guard let d = limit(r.c) else { return false }
                return (d.year == Y || d.year == Y - 1) && r.b - r.a < 0
            }
            if let ui = ch.firstIndex(where: { $0.b - $0.a > 0 && ($0.a < 0.005 || stY($0)) }),
               let di = ch.firstIndex(where: { $0.b - $0.a < 0 && endY($0) }), ch.count <= 3 {
                let up = ch[ui], dn = ch[di]
                let same = title(up.c) == title(dn.c)
                let a1 = title(dn.c), b1 = title(up.c)
                let wa = a1.components(separatedBy: " "), wb = b1.components(separatedBy: " ")
                var k = 0
                while k < wa.count - 1 && k < wb.count - 1 && wa[k] == wb[k] { k += 1 }
                if same || k > 0 {
                    out.append(CostDriverChip(name: same ? b1 : wa.prefix(k).joined(separator: " "), word: Calc.driverShort(.same, "gewechselt"), tone: .swap))
                    ch = ch.enumerated().filter { $0.offset != ui && $0.offset != di }.map { $0.element }
                }
            }
            for r in ch {
                let k = driverKind(r.c, from: Y - 1, to: Y, previous: r.a, current: r.b)
                out.append(CostDriverChip(name: title(r.c), word: Calc.driverShort(k.direction, k.text), tone: k.direction == .up ? .up : .down))
            }
            return (Array(out.prefix(4)), Swift.max(0, out.count - 4))
        }
        out.listTitle = (Y > nowY ? "Prognose" : "Was sich verändert hat") + " · \(Y - 1) → \(Y)"
        if cats.isEmpty { out.emptyNote = "Keine Veränderung gegenüber \(Y - 1)." }
        out.groups = cats.map { g in
            let cp = chips(g.ch)
            return CostDriverGroup(key: g.k, previous: g.a, current: g.b,
                                   changes: g.ch.map { r in
                                       let k = driverKind(r.c, from: Y - 1, to: Y, previous: r.a, current: r.b)
                                       return CostDriverChange(contractID: r.c.id, previous: r.a, current: r.b, reason: k.text, icon: k.icon, direction: k.direction)
                                   },
                                   chips: cp.chips, moreCount: cp.more)
        }
        if !cats.isEmpty && n0 > 0 {
            out.othersNote = Y > nowY ? "Alle anderen Kategorien bleiben gleich." : "Alle anderen Kategorien sind gleich geblieben."
        }
        if noSt > 0 {
            // Verträge ohne Beginn antippbar: öffnet den Vertrag, dort «Beginn» ergänzen (Web v251)
            out.noStartNote = "Ohne Vertragsbeginn, deshalb auch für \(Y - 1) voll gezählt: " + noStL.map { title($0) + " ›" }.joined(separator: " ")
            out.noStartContracts = noStL.map { $0.id }
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

    /// Wert der Filterauswahl mit rechter Spalte («25’200 CHF · 66 %», «keine Zahlungen 2026» bzw. Zähler bei Personen)
    public struct KBFilterAmountValue: Hashable, Identifiable, Sendable {
        public var value: KBFilterValue
        public var text: String
        public var id: String { value.id }
    }

    /// Werte einer Filterdimension wie `kbFilterValues`, im Tab «Kosten» (Kategorie/Vertragspartner) mit Jahresbetrag und Anteil,
    /// grösste zuerst. Ist ein Personenfilter gesetzt, zählen nur Verträge, die zu den übrigen Filtern (ausser `dim`) passen.
    public func kbFilterValuesWithAmounts(_ dim: FilterDimension, year: Int, filter: CostFilter) -> [KBFilterAmountValue] {
        let vals = kbFilterValues(dim)
        if dim == .holder { return vals.map { KBFilterAmountValue(value: $0, text: $0.countText) } }
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
                return KBFilterAmountValue(value: v, text: Format.money0(a) + " " + H + " · \(Int(Format.jsRound(a / aTot * 100))) %")
            }
            return KBFilterAmountValue(value: v, text: "keine Zahlungen \(year)")
        }
    }
}
