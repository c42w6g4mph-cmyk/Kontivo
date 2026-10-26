import Foundation

extension BankImport {
    // MARK: Preisverlauf aus den Zahlungen (Web v272)

    /// Preisverlauf: Anfangspreis `base`, Preise ab Datum `prices` (inkl. gratis ausgelassener Monate), Preisänderungen `changes`,
    /// gratis Monate `free`, aktueller Preis `current`.
    public struct PriceHistory: Equatable, Sendable {
        public var base: Double
        public var prices: [PriceChange]
        public var changes: [PriceChange]
        public var free: [Day]
        public var current: Double
        /// Stufenwerte (Web `levels[].a`): Zahlungen nahe an keiner Stufe gelten in der Zahlungsliste als «einmalig»
        public var levels: [Double] = []
    }

    /// Kosten (Web `bankPriceHist`): Stufen = mind. 2 aufeinanderfolgende gleiche Beträge (±0,5 %); einzelne Ausreisser zählen nicht.
    /// Nil bei schwankenden Beträgen (höchstens 6 Stufen, Stufen decken ≥ 75 % der Zahlungen). Ausgelassene Monate bei Monatsverträgen
    /// (Lücke > 49 Tage, keine Nachzahlung innert 15 Tagen) = gratis: Preis 0 ab dem fälligen Tag, ab der nächsten Zahlung wieder die Stufe.
    public static func priceHistory(dates D: [Day], amounts A: [Double], cycle: Int) -> PriceHistory? {
        let n = Swift.min(D.count, A.count)
        if n < 3 { return nil }
        let tol = 0.005
        func eq(_ x: Double, _ y: Double) -> Bool { Swift.abs(x - y) <= Swift.max(0.01, Swift.abs(y) * tol) }
        var runs: [(a: Double, from: Day, n: Int)] = []
        for i in 0..<n {
            if let r = runs.last, eq(A[i], r.a) {
                runs[runs.count - 1].n += 1
            } else {
                runs.append((A[i], D[i], 1))
            }
        }
        var lv: [(a: Double, last: Double, from: Day, n: Int)] = []
        var cov = 0
        for r in runs where r.n >= 2 {
            cov += r.n
            if let l = lv.last, eq(r.a, l.a) {
                lv[lv.count - 1].n += r.n
                lv[lv.count - 1].last = r.a
                continue
            }
            lv.append((r.a, r.a, r.from, r.n))
        }
        if lv.isEmpty || lv.count > 6 || Double(cov) < Double(n) * 0.75 { return nil }
        let chg = lv.dropFirst().map { PriceChange(from: $0.from, amount: BU.r2($0.a)) }
        var free: [Day] = []
        var ev = chg
        func at(_ d: Day) -> Double {
            var a = lv[0].a
            for l in lv where l.from <= d { a = l.a }
            return BU.r2(a)
        }
        if cycle == 1 {
            for j in 1..<n {
                let g = D[j - 1].days(to: D[j])
                if g <= 49 { continue }
                if j + 1 < n && D[j].days(to: D[j + 1]) < 15 { continue }
                let miss = Int(BU.round(Double(g) / 30.44)) - 1
                let f0 = D[j - 1]
                if miss < 1 || miss > 3 { continue }
                for k in 1...miss { free.append(f0.addingMonths(k)) }
                ev.append(PriceChange(from: f0.addingMonths(1), amount: 0))
                ev.append(PriceChange(from: D[j], amount: at(D[j])))
            }
        }
        ev = BU.sorted(ev) { x, y in x.from < y.from ? -1 : (y.from < x.from ? 1 : 0) }
        var pr: [PriceChange] = []
        var last = BU.r2(lv[0].a)
        for e in ev {
            if Swift.abs(e.amount - last) < 0.005 { continue }
            if let p = pr.last, p.from == e.from { pr.removeLast() }
            pr.append(e)
            last = e.amount
        }
        return PriceHistory(base: BU.r2(lv[0].a), prices: pr, changes: Array(chg), free: free, current: BU.r2(lv[lv.count - 1].a),
                            levels: lv.map { $0.a })
    }

    /// Einnahmen (Web `bankIncHist`): Ausreisser (> 15 % vom Stufenwert: 13. Lohn, Bonus, Spesen) zählen nicht; neue Stufe erst, wenn
    /// zwei Zahlungen hintereinander > 2 % vom Median der aktuellen Stufe abweichen und unter sich ähnlich sind. Stufenwert = Median.
    public static func incomeHistory(dates D: [Day], amounts A: [Double]) -> PriceHistory? {
        let n = Swift.min(D.count, A.count)
        if n < 3 { return nil }
        func med(_ L: [Double]) -> Double {
            let a = L.sorted()
            return a[a.count / 2]
        }
        var lv: [(from: Day, v: [Double])] = []
        var hasCur = false
        for i in 0..<n {
            let a = A[i]
            if !hasCur {
                if i + 1 < n && Swift.abs(A[i + 1] - a) <= a * 0.02 {
                    lv.append((D[i], [a]))
                    hasCur = true
                }
                continue
            }
            let m = med(lv[lv.count - 1].v), dv = Swift.abs(a - m) / m
            if dv <= 0.02 {
                lv[lv.count - 1].v.append(a)
                continue
            }
            if dv > 0.15 { continue }   // Ausreisser
            if i + 1 < n {
                let b = A[i + 1]
                if Swift.abs(b - a) <= a * 0.02 && Swift.abs(b - m) / m > 0.02 { lv.append((D[i], [a])) }
            }
        }
        if lv.isEmpty || lv.count > 12 { return nil }
        let cov = lv.reduce(0) { $0 + $1.v.count }
        if Double(cov) < Double(n) * 0.6 { return nil }
        let L = lv.map { (a: BU.r2(med($0.v)), from: $0.from, last: $0.v[$0.v.count - 1]) }
        let chg = L.dropFirst().map { PriceChange(from: $0.from, amount: $0.a) }
        return PriceHistory(base: L[0].a, prices: Array(chg), changes: Array(chg), free: [], current: BU.r2(L[L.count - 1].last),
                            levels: L.map { $0.a })
    }

    /// Einnahme aus dem Auszug: Anfangsbetrag und Preisstufen (Web `bkIncPrices`); `amount` = gewählter (ggf. geänderter) Betrag.
    public static func incomePrices(_ s: BankIncomeSuggestion, amount a: Double) -> (amount: Double, prices: [PriceChange]) {
        guard let ph = incomeHistory(dates: s.dates, amounts: s.amounts), !ph.prices.isEmpty else { return (a, []) }
        var pr = ph.prices
        if pr[pr.count - 1].amount > 0 { pr[pr.count - 1].amount = a }
        return (ph.base, pr)
    }
}
