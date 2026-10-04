import Foundation

/// Rechenkern (1:1 zum Abschnitt «Rechnen» der Web-App, Stand 03.10.2026). Stichtag `today` ist fix.
public struct Calc {
    public let data: AppData
    public let today: Day
    private let kinds: [UUID: CategoryKind]
    private let taxNames: Set<UUID>
    private let partnerNames: [UUID: String]

    /// Startwerte der Kurse (CHF pro Einheit), bis der erste Abruf erfolgt ist.
    public static let defaultRates: [Currency: Double] = [.EUR: 0.94, .USD: 0.80, .GBP: 1.07, .TRY: 0.02]

    public init(data: AppData, today: Day) {
        self.data = data
        self.today = today
        var k: [UUID: CategoryKind] = [:]
        for c in data.categories { if let kind = c.kind { k[c.id] = kind } }
        kinds = k
        // Web `isTax`: Name beginnt mit «Steuern» (ohne Gross/Klein) zählt immer als Steuern
        taxNames = Set(data.categories.filter { $0.name.lowercased().hasPrefix("steuern") }.map { $0.id })
        var p: [UUID: String] = [:]
        for x in data.partners { p[x.id] = x.name }
        partnerNames = p
    }

    // MARK: Währung

    public var home: Currency { data.settings.homeCurrency }

    /// CHF pro Einheit (`rateOf`).
    public func rate(_ c: Currency) -> Double {
        if c == .CHF { return 1 }
        if let r = data.settings.rates[c.rawValue], r > 0 { return r }
        return Calc.defaultRates[c] ?? 1
    }

    /// Betrag in die Hauptwährung umrechnen (`conv`).
    public func conv(_ amount: Double, _ c: Currency) -> Double {
        if c == home { return amount }
        return amount * rate(c) / rate(home)
    }

    // MARK: Kategorie-Fachregeln

    public func categoryKind(_ c: Contract) -> CategoryKind? {
        guard let id = c.categoryID else { return nil }
        return kinds[id]
    }

    /// Steuern lassen sich nicht kündigen: keine Frist, nicht in «Fristen».
    public func isTax(_ c: Contract) -> Bool {
        if categoryKind(c) == .taxes { return true }
        guard let id = c.categoryID else { return false }
        return taxNames.contains(id)
    }

    /// Mietvertrag: ausdrücklicher Schalter, sonst Heuristik.
    public func isRent(_ c: Contract) -> Bool {
        if let r = c.isRent { return r }
        return Letter.isRentHeuristic(label: c.label, partner: partnerName(c), kind: categoryKind(c))
    }

    public func partnerName(_ c: Contract) -> String {
        guard let id = c.partnerID else { return "" }
        return partnerNames[id] ?? ""
    }

    /// Kündigungsweg. Miete immer Brief (Fix F3); sonst Angabe am Vertrag; ohne Angabe Versicherung → Brief, sonst offen.
    public func cancVia(_ c: Contract) -> CancelVia {
        if isRent(c) { return .post }
        if let ch = c.cancelChannel {
            switch ch {
            case .online: return .online
            case .email: return .mail
            case .letter, .registered: return .post
            }
        }
        if categoryKind(c) == .insurance { return .post }
        return .none
    }

    /// Link für die Online-Kündigung (`cancLink`): Kündigungslink, sonst Website des Vertragspartners.
    public func cancLink(_ c: Contract) -> String {
        if !c.cancelURL.trimmingCharacters(in: .whitespaces).isEmpty { return Format.normUrl(c.cancelURL) }
        return Format.normUrl(data.partner(c.partnerID)?.web ?? "")
    }

    // MARK: Preise und Zahlungen

    /// Preisstufen aufsteigend nach Datum (`pricesOf`).
    public func pricesOf(_ c: Contract) -> [PriceChange] {
        Calc.sortedPrices(c.prices)
    }

    static func sortedPrices(_ p: [PriceChange]) -> [PriceChange] {
        p.filter { $0.amount.isFinite }.stableSorted { $0.from < $1.from }
    }

    static func priceAt(amount: Double, prices: [PriceChange], _ d: Day) -> Double {
        var p = amount.isFinite ? amount : 0
        for e in sortedPrices(prices) where e.from <= d { p = e.amount }
        return p
    }

    /// Preis an einem Tag (Anfangspreis, überschrieben von Stufen mit Datum ≤ d).
    public func priceAt(_ c: Contract, _ d: Day) -> Double {
        Calc.priceAt(amount: c.amount, prices: c.prices, d)
    }

    /// Heutiger Preis.
    public func curPrice(_ c: Contract) -> Double { priceAt(c, today) }

    /// Nächste Preisänderung nach heute.
    public func nextChange(_ c: Contract) -> PriceChange? {
        pricesOf(c).first { $0.from > today }
    }

    /// Sonderzahlungen mit Betrag ≠ 0, aufsteigend nach Datum (`extrasOf`).
    public func extrasOf(_ c: Contract) -> [ExtraPayment] {
        c.extras.filter { $0.amount.isFinite && $0.amount != 0 }.stableSorted { $0.date < $1.date }
    }

    /// Eine Zahlung im Zeitraum (Betrag in Vertragswährung).
    public struct Payment: Hashable, Sendable {
        public var date: Day
        public var amount: Double
        /// Sonderzahlung (nil = regulärer Termin)
        public var extra: ExtraPayment?
    }

    /// Reguläre Termine + Sonderzahlungen im Zeitraum (`payments`).
    public func payments(_ c: Contract, from: Day, to: Day) -> [Payment] {
        var o = occurrences(c, from: from, to: to).map { Payment(date: $0, amount: priceAt(c, $0), extra: nil) }
        for x in extrasOf(c) where x.date >= from && x.date <= to {
            o.append(Payment(date: x.date, amount: x.amount, extra: x))
        }
        return o
    }

    /// Monatskosten in Hauptwährung: heutiger Preis / Turnus (ohne Sonderzahlungen, Pause, Beginn).
    public func monthlyCost(_ c: Contract) -> Double {
        conv(curPrice(c), c.currency) / Double(c.cycleForCalc)
    }

    // MARK: Termine

    /// Zahlungstermine im Zeitraum, immer vom Anker `due` gerechnet (kein Drift bei 29.–31.).
    public func occurrences(_ c: Contract, from: Day, to: Day) -> [Day] {
        Calc.occurrences(due: c.due, cycle: c.cycle, start: c.start, limit: limit(c), pauses: c.pauses, from: from, to: to)
    }

    static func occurrences(due: Day?, cycle: Int, start: Day?, limit lim: Day?, pauses: [Pause], from: Day, to: Day) -> [Day] {
        guard let a = due else { return [] }
        if cycle == 0 { return (a >= from && a <= to) ? [a] : [] }
        let m = cycle
        var out: [Day] = []
        let diff = a.months(to: from)
        var k = Int((Double(diff) / Double(m)).rounded(.down)) - 1
        var g = 0
        while g < 400 {
            g += 1
            let d = a.addingMonths(k * m)
            k += 1
            if d > to { break }
            if d < from { continue }
            if let st = start, d < st { continue }
            if let l = lim, d > l { break }
            if pauses.contains(where: { $0.contains(d) }) { continue }
            out.append(d)
        }
        return out
    }

    /// Nächste Zahlung: erster Termin in [heute, heute + max(13, Turnus + 1) Monate].
    public func nextDue(_ c: Contract) -> Day? {
        occurrences(c, from: today, to: today.addingMonths(Swift.max(13, c.cycleForCalc + 1))).first
    }

    /// Letzter möglicher Zahlungstermin (`limitOf`).
    public func limit(_ c: Contract) -> Day? {
        var base: Day? = nil
        if c.status == .cancelled {
            var e = c.end
            if let e0 = c.end, c.renewMonths != 0, let ca = c.cancelledAt {
                var x = e0
                var g = 0
                while x < ca && g < 400 {
                    g += 1
                    x = e0.addingMonthsE(g * c.renewMonths)
                }
                e = x
            }
            base = e ?? c.cancelledAt
        } else {
            base = (c.end != nil && c.renewMonths == 0) ? c.end : nil
        }
        if let cp = c.cancelPer {
            if let b = base, b < cp { return b }
            return cp
        }
        return base
    }

    /// Effektives Vertragsende: mit Verlängerung so lange + r Monate (vom Anker), bis ≥ heute.
    public func effEnd(_ c: Contract) -> Day? {
        guard let e0 = c.end else { return nil }
        let r = c.renewMonths
        if r == 0 { return e0 }
        var e = e0
        var g = 0
        while e < today && g < 400 {
            g += 1
            e = e0.addingMonthsE(g * r)
        }
        return e
    }

    /// Kündigungsfrist zum Termin e (`nDl`): Monatsletzter bleibt Monatsletzter.
    public func noticeDeadline(for c: Contract, end e: Day) -> Day {
        let n = c.notice
        if n == 0 { return e }
        switch c.noticeUnit {
        case .dayOfMonth: return Day(e.year, e.month, Swift.min(n, 28))
        case .weeks: return e.addingDays(-7 * n)
        case .days: return e.addingDays(-n)
        case .months: return e.isEndOfMonth ? Day(e.year, e.month - n + 1, 0) : e.addingMonths(-n)
        }
    }

    /// Nächster Kündigungstermin bei unbefristeten Verträgen.
    /// `base`: Stichtag (Standard heute). `after`: erster Termin nach diesem Tag, ohne Fristprüfung.
    public func nextTerm(_ c: Contract, base: Day? = nil, after: Day? = nil) -> Day? {
        if c.end != nil || c.cancelTerm == .anytime { return nil }
        let t = base ?? today
        let ok: (Day) -> Bool = { x in
            if let a = after { return x > a }
            return self.noticeDeadline(for: c, end: x) >= t
        }
        switch c.cancelTerm {
        case .period:
            guard let a = c.due else { return nil }
            let m = c.cycleForCalc
            var k: Int
            if let af = after {
                k = Int((Double(a.months(to: af)) / Double(m)).rounded(.down)) - 1
            } else {
                guard let nd = nextDue(c) else { return nil }
                k = Int(Format.jsRound(Double(a.months(to: nd)) / Double(m)))
            }
            for _ in 0..<80 {
                let T = a.addingMonths(k * m).addingDays(-1)
                if ok(T) { return T }
                k += 1
            }
            return nil
        case .contractYear:
            guard let b = c.start ?? c.due else { return nil }
            // Vertragsjahr endet am Vortag des Jahrestags (Beginn 29.02. → 28.02.)
            for i in 1..<300 {
                let T = Day(b.year + i, b.month, b.day).addingDays(-1)
                if let af = after {
                    if T > af { return T }
                } else if T >= t && ok(T) {
                    return T
                }
            }
            return nil
        default:
            let s0 = after ?? t
            for i in 0..<60 {
                let T = Day(s0.year, s0.month + i + 1, 0)
                let m1 = T.month
                if c.cancelTerm == .quarterEnd && m1 % 3 != 0 { continue }
                if c.cancelTerm == .halfYearEnd && m1 % 6 != 0 { continue }
                if c.cancelTerm == .yearEnd && m1 != 12 { continue }
                if ok(T) { return T }
            }
            return nil
        }
    }

    /// Nächstes mögliches Vertragsende. Befristet mit Verlängerung: ist die Frist verpasst, gilt das nächste Ende.
    public func termEnd(_ c: Contract) -> Day? {
        guard let e0 = c.end else { return nextTerm(c) }
        let r = c.renewMonths
        if r == 0 { return e0 }
        var e = e0
        var g = 0
        while g < 400 && (e < today || (c.cancelPer == nil && noticeDeadline(for: c, end: e) < today)) {
            g += 1
            e = e0.addingMonthsE(g * r)
        }
        return e
    }

    /// Verlängerungsende nach T (befristet mit Verlängerung), vom Anker gerechnet.
    public func renewAfter(_ c: Contract, _ T: Day?) -> Day? {
        guard let e0 = c.end, c.renewMonths != 0, let T = T else { return nil }
        var e = e0
        var g = 0
        while e <= T && g < 400 {
            g += 1
            e = e0.addingMonthsE(g * c.renewMonths)
        }
        return e
    }

    /// «Sonst verlängert bis»
    public func renewTo(_ c: Contract) -> Day? { renewAfter(c, termEnd(c)) }

    /// Kündigungsfrist (Steuern: keine).
    public func noticeDeadline(_ c: Contract) -> Day? {
        if isTax(c) { return nil }
        guard let e = termEnd(c) else { return nil }
        return noticeDeadline(for: c, end: e)
    }

    public enum UrgencyLevel: String, Hashable, Sendable {
        case none = "", alert, warn, ok
    }

    public struct Urgency: Hashable, Sendable {
        public var level: UrgencyLevel
        public var days: Int?
        public var date: Day?
    }

    /// Dringlichkeit der Frist.
    public func urgency(_ c: Contract) -> Urgency {
        guard let d = noticeDeadline(c) else { return Urgency(level: .none, days: nil, date: nil) }
        let days = today.days(to: d)
        var lvl: UrgencyLevel = days < 0 ? .none : (days <= 7 ? .alert : (days <= 30 ? .warn : .ok))
        if isAnytime(c) || c.noWatch { lvl = .none }
        if c.cancelPer != nil || (c.keptFor != nil && c.keptFor == termEnd(c)) { lvl = .none }
        return Urgency(level: lvl, days: days, date: d)
    }

    // MARK: Zustände

    /// Pausiert: eine Pause mit from ≤ heute < until (oder offen).
    public func isPaused(_ c: Contract) -> Bool {
        c.pauses.contains { $0.from <= today && ($0.until == nil || today < $0.until!) }
    }

    /// Die heute laufende Pause.
    public func currentPause(_ c: Contract) -> Pause? {
        c.pauses.last { $0.from <= today && ($0.until == nil || today < $0.until!) }
    }

    /// Beginn in der Zukunft.
    public func notStarted(_ c: Contract) -> Bool {
        if let s = c.start { return s > today }
        return false
    }

    /// Gekündigt per Datum vor heute.
    public func endedByNotice(_ c: Contract) -> Bool {
        if let p = c.cancelPer { return p < today }
        return false
    }

    /// Befristet ohne Verlängerung und abgelaufen.
    public func endedByTerm(_ c: Contract) -> Bool {
        if let e = c.end, c.renewMonths == 0 { return e < today }
        return false
    }

    public func isEnded(_ c: Contract) -> Bool { endedByNotice(c) || endedByTerm(c) }

    /// Aktiv: nicht im Archiv (inkl. pausiert und noch nicht begonnen).
    public func isActive(_ c: Contract) -> Bool { c.status != .cancelled && !isEnded(c) }

    /// Für den aktuellen Termin behalten.
    public func isKept(_ c: Contract) -> Bool {
        guard let T = termEnd(c), let k = c.keptFor else { return false }
        return k == T
    }

    /// Jederzeit kündbar: unbefristet und «Monatsende» oder «Ende Periode» bei monatlicher Zahlung.
    public func isAnytime(_ c: Contract) -> Bool {
        c.end == nil && (c.cancelTerm == .monthEnd || (c.cancelTerm == .period && c.cycleForCalc <= 1))
    }

    /// Entscheidung nötig: Frist in 0–30 Tagen (Steuern filtern die Aufrufer). Seit 04.10.2026: 30 statt 90 Tage.
    public func needsAction(_ c: Contract) -> Bool {
        if c.cancelPer != nil { return false }
        guard let T = termEnd(c) else { return false }
        if isAnytime(c) || c.noWatch { return false }
        if let k = c.keptFor, k == T { return false }
        let n = today.days(to: noticeDeadline(for: c, end: T))
        return n >= 0 && n <= 30
    }

    /// Probeabo endet in 0–30 Tagen und ist nicht entschieden.
    public func trialNeeds(_ c: Contract) -> Bool {
        guard let d = c.trial else { return false }
        return d >= today && today.days(to: d) <= 30 && c.trialKept != c.trial && c.cancelPer == nil
    }

    /// Anteil einer Person an einem Vertrag: ohne Person 1, nicht Inhaber 0, sonst 1 / Anzahl Inhaber.
    public func holderShare(_ c: Contract, person: UUID?) -> Double {
        guard let p = person else { return 1 }
        if !c.holderIDs.contains(p) { return 0 }
        return 1 / Double(c.holderIDs.count)
    }

    /// Kündigungsende beim Markieren (Probeabo: Tag vor Probeabo-Ende, sonst termEnd).
    public func cancelEnd(_ c: Contract, trial: Bool) -> Day? {
        if trial { return c.trial?.addingDays(-1) }
        return termEnd(c)
    }

    // MARK: Listen

    /// Aktive Verträge (nicht im Archiv), Speicherreihenfolge.
    public var active: [Contract] { data.contracts.filter { isActive($0) } }

    /// Aktiv und nicht pausiert.
    public var running: [Contract] { active.filter { !isPaused($0) } }

    /// Archiv: ins Archiv verschoben oder beendet.
    public var archived: [Contract] { data.contracts.filter { $0.status == .cancelled || isEnded($0) } }

    /// Aktive Verträge mit Beginn in der Zukunft.
    public var notStartedList: [Contract] { active.filter { notStarted($0) } }

    // MARK: Kopfbereich (renderHero)

    public struct Hero: Hashable, Sendable {
        /// Summe Monatskosten der laufenden, begonnenen Verträge (Hauptwährung)
        public var monthlyTotal: Double
        public var yearlyTotal: Double
        /// laufend und begonnen
        public var activeCount: Int
        public var pausedCount: Int
        public var futureCount: Int
        /// «1’234 CHF pro Jahr · 3 aktive Verträge»
        public var subtitle: String
        /// Chips nur, wenn pausierte oder künftige existieren
        public var showsChips: Bool
    }

    public func hero() -> Hero {
        let run = running
        let fut = run.filter { notStarted($0) }.count
        let a = run.filter { !notStarted($0) }
        let sum = a.reduce(0.0) { $0 + monthlyCost($1) }
        let np = active.count - a.count - fut
        var sub = Format.money0(sum * 12) + " " + home.rawValue + " pro Jahr"
        if np == 0 && fut == 0 && !a.isEmpty {
            sub += " · \(a.count)" + (a.count == 1 ? " aktiver Vertrag" : " aktive Verträge")
        }
        return Hero(monthlyTotal: sum, yearlyTotal: sum * 12, activeCount: a.count, pausedCount: np, futureCount: fut,
                    subtitle: sub, showsChips: np > 0 || fut > 0)
    }

    /// Quartals-Check fällig: ≥ 90 Tage seit letzter Prüfung (sonst seit erster Erfassung), nicht verschoben, mind. 1 aktiver Vertrag.
    public func reviewDue(calendar: Calendar = Day.calendar) -> Bool {
        var rb = data.settings.lastReview
        if rb == nil {
            let ts = data.contracts.map { $0.createdAt }.filter { $0.timeIntervalSince1970 > 0 }
            if let mn = ts.min() { rb = Day(date: mn, calendar: calendar) }
        }
        guard let ref = rb else { return false }
        if let snz = data.settings.reviewSnooze, snz > today { return false }
        return ref.days(to: today) >= 90 && !active.isEmpty
    }

    /// Zähler im Tab «Fristen»: offene Entscheidungen (Fristen + Probeabos, ohne Steuern).
    public var deadlineBadgeCount: Int {
        let a = active
        return a.filter { needsAction($0) && !isTax($0) }.count + a.filter { trialNeeds($0) && !isTax($0) }.count
    }
}

// MARK: - Tab «Fristen»

extension Calc {
    /// Entscheidungskarte (Probeabo oder Frist).
    public struct DeadlineDecision: Hashable, Sendable {
        public var contractID: UUID
        public var trial: Bool
        /// Frist bzw. Probeabo-Ende
        public var date: Day
        public var days: Int
        /// ≤ 7 Tage alert, sonst warn
        public var level: UrgencyLevel
        /// «Frist 30.11. · noch 29 Tage» / «Probeabo endet 20.10. · heute»
        public var line: String
        /// «719 CHF pro Jahr · Pflichtvertrag · pausiert»
        public var subline: String
        /// «Behalten»
        public var keepTitle: String
        /// «Kündigen» bzw. «Wechseln» (Pflichtvertrag)
        public var cancelTitle: String
    }

    public enum UpcomingKind: String, Hashable, Sendable {
        case normal, kept, ended
    }

    /// Zeile «Kommende Termine».
    public struct UpcomingRow: Hashable, Sendable {
        public var contractID: UUID
        /// Sortierdatum
        public var date: Day
        /// «Frist 30.11.26», «behalten · Frist 30.09.27», «gekündigt · endet 30.11.26»
        public var text: String
        public var kind: UpcomingKind
    }

    /// Zeile einer Klappgruppe.
    public struct FoldRow: Hashable, Sendable {
        public var contractID: UUID
        public var text: String
    }

    public struct DeadlineOverview: Hashable, Sendable {
        /// Probeabos zuerst, dann Fristen
        public var decisions: [DeadlineDecision]
        public var openCount: Int
        public var urgentCount: Int
        public var nextDate: Day?
        /// Kopfzeile fett («3 offen» bzw. «Alles erledigt»), nil ohne Kopfzeile
        public var headerBold: String?
        /// Rest der Kopfzeile (« · 1 dringend · nächste Frist in 5 Tagen» bzw. « · keine offenen Entscheidungen»)
        public var headerRest: String
        /// Kopfzeile grün («Alles erledigt»)
        public var allDone: Bool
        public var upcoming: [UpcomingRow]
        /// «Jederzeit kündbar»
        public var anytime: [FoldRow]
        /// «Ohne Frist erfasst» (Titelzusatz « · ergänzen»)
        public var withoutNotice: [FoldRow]
        /// «Nicht beobachtet»
        public var unwatched: [FoldRow]
        /// Gar kein Inhalt → Leerseite
        public var isEmpty: Bool

        public static let upcomingTitle = "Kommende Termine"
        public static let anytimeTitle = "Jederzeit kündbar"
        public static let withoutNoticeTitle = "Ohne Frist erfasst"
        public static let withoutNoticeExtra = " · ergänzen"
        public static let unwatchedTitle = "Nicht beobachtet"
    }

    /// Inhalt des Tabs «Fristen» (Grundmenge: aktive Verträge ohne Steuern, inkl. pausierte).
    public func deadlineOverview() -> DeadlineOverview {
        let a = active.filter { !isTax($0) }
        let y = today.year
        let todo = a.filter { needsAction($0) }.stableSorted { (noticeDeadline($0) ?? today) < (noticeDeadline($1) ?? today) }
        let triTodo = a.filter { trialNeeds($0) }.stableSorted { ($0.trial ?? today) < ($1.trial ?? today) }
        let n = todo.count + triTodo.count

        var up: [UpcomingRow] = []
        for c in a {
            if needsAction(c) || trialNeeds(c) || c.noWatch { continue }
            if let cp = c.cancelPer {
                up.append(UpcomingRow(contractID: c.id, date: cp, text: "gekündigt · endet " + Format.fmtShort(cp), kind: .ended))
                continue
            }
            if isAnytime(c) { continue }
            guard let T = termEnd(c) else { continue }
            if isKept(c) {
                let T2 = c.end != nil ? renewAfter(c, T) : nextTerm(c, base: nil, after: T)
                let d2 = T2.map { noticeDeadline(for: c, end: $0) }
                up.append(UpcomingRow(contractID: c.id, date: d2 ?? T, text: "behalten" + (d2 != nil ? " · Frist " + Format.fmtShort(d2) : ""), kind: .kept))
                continue
            }
            let dl = noticeDeadline(for: c, end: T)
            if dl < today { continue }
            up.append(UpcomingRow(contractID: c.id, date: dl, text: "Frist " + Format.fmtShort(dl), kind: .normal))
        }
        up = up.stableSorted { $0.date < $1.date }

        let anytime = a.filter { c in c.cancelPer == nil && !c.noWatch && (isAnytime(c) || (noticeDeadline(c) == nil && c.notice > 0)) }
            .map { c -> FoldRow in
                if c.end == nil && c.cancelTerm == .period { return FoldRow(contractID: c.id, text: "zum Periodenende") }
                if let T = nextTerm(c) { return FoldRow(contractID: c.id, text: "nächste Frist " + Format.ddmm(noticeDeadline(for: c, end: T), currentYear: y)) }
                return FoldRow(contractID: c.id, text: "Frist " + Format.noticeText(c))
            }
        let nofrist = a.filter { c in c.cancelPer == nil && !c.noWatch && noticeDeadline(c) == nil && c.notice == 0 && !c.mandatory }
            .map { FoldRow(contractID: $0.id, text: "ergänzen") }
        let unw = a.filter { $0.noWatch && $0.cancelPer == nil }
            .map { c -> FoldRow in
                let t = Format.noticeText(c)
                return FoldRow(contractID: c.id, text: t.isEmpty ? "" : "Frist " + t)
            }

        var decisions: [DeadlineDecision] = []
        func card(_ c: Contract, trial: Bool) -> DeadlineDecision? {
            let dOpt = trial ? c.trial : termEnd(c).map { noticeDeadline(for: c, end: $0) }
            guard let d = dOpt else { return nil }
            let dn = today.days(to: d)
            let line = (trial ? "Probeabo endet " : "Frist ") + Format.ddmm(d, currentYear: y) + " · " + (dn == 0 ? "heute" : "noch " + Format.humanDays(dn))
            let sub = Format.money0(monthlyCost(c) * 12) + " " + home.rawValue + " pro Jahr" + (c.mandatory ? " · Pflichtvertrag" : "") + (isPaused(c) ? " · pausiert" : "")
            return DeadlineDecision(contractID: c.id, trial: trial, date: d, days: dn, level: dn <= 7 ? .alert : .warn, line: line, subline: sub,
                                    keepTitle: "Behalten", cancelTitle: c.mandatory ? "Wechseln" : "Kündigen")
        }
        for c in triTodo { if let x = card(c, trial: true) { decisions.append(x) } }
        for c in todo { if let x = card(c, trial: false) { decisions.append(x) } }

        var urgent = 0
        var dates: [Day] = []
        for c in todo {
            if let d = noticeDeadline(c) {
                dates.append(d)
                if today.days(to: d) <= 7 { urgent += 1 }
            }
        }
        for c in triTodo {
            if let d = c.trial {
                dates.append(d)
                if today.days(to: d) <= 7 { urgent += 1 }
            }
        }
        let nx = dates.min()
        var bold: String? = nil
        var rest = ""
        var done = false
        if n > 0 {
            bold = "\(n) offen"
            if urgent > 0 && urgent < n { rest += " · \(urgent) dringend" }
            if let nx = nx { rest += " · nächste Frist " + Format.inDays(today.days(to: nx)) }
        } else if !a.isEmpty {
            bold = "Alles erledigt"
            rest = " · keine offenen Entscheidungen"
            done = true
        }
        let empty = n == 0 && a.isEmpty && up.isEmpty && anytime.isEmpty && nofrist.isEmpty && unw.isEmpty
        return DeadlineOverview(decisions: decisions, openCount: n, urgentCount: urgent, nextDate: nx, headerBold: bold, headerRest: rest, allDone: done,
                                upcoming: up, anytime: anytime, withoutNotice: nofrist, unwatched: unw, isEmpty: empty)
    }
}

// MARK: - Tab «Kosten» und «Budget»

extension Calc {
    public enum FilterDimension: String, Hashable, Sendable {
        case category, partner, holder
    }

    /// Filter in «Verträge» und «Kosten» (Kategorie- und Vertragspartner-Schlüssel wie `statKey`).
    public struct CostFilter: Hashable, Sendable {
        public var category: String?
        public var partner: String?
        public var person: UUID?

        public init(category: String? = nil, partner: String? = nil, person: UUID? = nil) {
            self.category = category
            self.partner = partner
            self.person = person
        }

        /// Anzahl gesetzter Filter (`fltCount`)
        public var count: Int { (category != nil ? 1 : 0) + (partner != nil ? 1 : 0) + (person != nil ? 1 : 0) }
    }

    /// Schlüssel für Filter und Aufteilung: Kategorie (ohne → «Sonstiges») bzw. Vertragspartner (leer → «Ohne Namen»).
    public func statKey(_ c: Contract, _ dim: FilterDimension) -> String {
        switch dim {
        case .category:
            let n = data.category(c.categoryID)?.name ?? ""
            return n.isEmpty ? "Sonstiges" : n
        case .partner:
            let n = partnerName(c).trimmingCharacters(in: .whitespaces)
            return n.isEmpty ? "Ohne Namen" : n
        case .holder:
            return data.holderNames(of: c).joined(separator: " & ")
        }
    }

    /// Passt der Vertrag zu allen Filtern ausser `skip` (`fltMatch`)?
    public func matches(_ c: Contract, _ f: CostFilter, skip: FilterDimension? = nil) -> Bool {
        if skip != .category, let k = f.category, statKey(c, .category) != k { return false }
        if skip != .partner, let k = f.partner, statKey(c, .partner) != k { return false }
        if skip != .holder, let p = f.person, !c.holderIDs.contains(p) { return false }
        return true
    }

    public struct CostItem: Hashable, Sendable {
        public var contractID: UUID
        public var date: Day
        /// Wert in Hauptwährung × Anteil
        public var value: Double
        /// Betrag in Vertragswährung × Anteil
        public var amount: Double
        public var share: Double
        public var extra: ExtraPayment?
    }

    public struct CostMonth: Hashable, Sendable {
        public var sum: Double = 0
        /// Datum vor heute
        public var paid: Double = 0
        /// Datum ab heute
        public var open: Double = 0
        public var items: [CostItem] = []
    }

    public struct CostYear: Hashable, Sendable {
        public var year: Int
        public var months: [CostMonth]
        public var total: Double
        public var maxMonth: Double
        public var average: Double
        /// Aufteilung (Kategorie bzw. Vertragspartner) im Jahr
        public var splitYear: [String: Double]
        /// Aufteilung je Monat (12 Einträge)
        public var splitMonths: [[String: Double]]
        /// Anzahl aller Zahlungen im Jahr (ohne Filter)
        public var paymentCount: Int
        public var previousYearTotal: Double
        /// Veränderung zum Vorjahr in %, nil wenn nicht vergleichbar
        public var yearDelta: Double?
        /// «±0 %», «+4.2 %», «−3.0 %» oder «—»
        public var yearDeltaText: String
        /// Hinweis zu Verträgen ohne Beginn (nur für vergangene Jahre), sonst nil
        public var noStartHint: String?
    }

    /// Zahlungen eines Jahres (alle Verträge inkl. Archiv; Grenzen über `limit`), mit Filtern und Personenanteil.
    public func costYear(_ year: Int, filter: CostFilter, split: FilterDimension = .category) -> CostYear {
        let from = Day(year, 1, 1)
        let to = Day(year, 12, 31)
        var months = Array(repeating: CostMonth(), count: 12)
        var gY: [String: Double] = [:]
        var gM: [[String: Double]] = Array(repeating: [:], count: 12)
        var allN = 0
        for c in data.contracts {
            let inF = matches(c, filter)
            let inG = matches(c, filter, skip: split)
            let sh = holderShare(c, person: filter.person)
            for p in payments(c, from: from, to: to) {
                let val = conv(p.amount, c.currency) * sh
                allN += 1
                let mi = p.date.month - 1
                if inG {
                    let k = statKey(c, split)
                    gY[k, default: 0] += val
                    gM[mi][k, default: 0] += val
                }
                if inF {
                    months[mi].sum += val
                    if p.date < today { months[mi].paid += val } else { months[mi].open += val }
                    months[mi].items.append(CostItem(contractID: c.id, date: p.date, value: val, amount: p.amount * sh, share: sh, extra: p.extra))
                }
            }
        }
        for i in 0..<12 { months[i].items = months[i].items.stableSorted { $0.date < $1.date } }
        let tot = months.reduce(0.0) { $0 + $1.sum }
        let mx = months.reduce(0.0) { Swift.max($0, $1.sum) }
        let pT = periodTotal(from: Day(year - 1, 1, 1), to: Day(year - 1, 12, 31), filter: filter)
        var yd: Double? = pT > 0 ? (tot - pT) / pT * 100 : nil
        if data.contracts.contains(where: { $0.start == nil && matches($0, filter) }) { yd = nil }
        var ydText = "—"
        if let d = yd {
            ydText = Swift.abs(d) < 0.05 ? "±0 %" : (d > 0 ? "+" : Format.minus) + Format.fixed1(Swift.abs(d)) + " %"
        }
        let noStart = data.contracts.filter { $0.start == nil && $0.status != .cancelled }.count
        var hint: String? = nil
        if year < today.year && noStart > 0 {
            hint = "\(noStart)" + (noStart == 1 ? " Vertrag hat" : " Verträge haben") + " keinen Vertragsbeginn und " + (noStart == 1 ? "wird" : "werden") + " deshalb rückwirkend voll gezählt."
        }
        return CostYear(year: year, months: months, total: tot, maxMonth: mx, average: tot / 12, splitYear: gY, splitMonths: gM, paymentCount: allN,
                        previousYearTotal: pT, yearDelta: yd, yearDeltaText: ydText, noStartHint: hint)
    }

    /// Summe aller gefilterten Zahlungen (Hauptwährung × Anteil) im Zeitraum.
    public func periodTotal(from: Day, to: Day, filter: CostFilter) -> Double {
        var s = 0.0
        for c in data.contracts where matches(c, filter) {
            let f = holderShare(c, person: filter.person)
            for p in payments(c, from: from, to: to) { s += conv(p.amount, c.currency) * f }
        }
        return s
    }

    public enum Trend: String, Hashable, Sendable {
        case up, down, same
    }

    /// Vergleich eines Monats mit dem Vorjahresmonat («12 CHF mehr als Oktober 2025»), nil wenn nicht anzeigbar.
    public func monthComparison(year: Int, month: Int, filter: CostFilter, monthSum: Double, items: [CostItem]) -> (text: String, trend: Trend)? {
        if items.contains(where: { data.contract($0.contractID)?.start == nil }) { return nil }
        let pmS = periodTotal(from: Day(year - 1, month, 1), to: Day(year - 1, month + 1, 0), filter: filter)
        if pmS < 0.005 { return nil }
        let pmD = monthSum - pmS
        let pr = Format.jsRound(Swift.abs(pmD))
        let label = Format.monthNames[month - 1] + " \(year - 1)"
        if pr < 1 { return ("gleich wie " + label, .same) }
        return (Format.money0(pr) + " " + home.rawValue + (pmD > 0 ? " mehr" : " weniger") + " als " + label, pmD > 0 ? .up : .down)
    }

    public struct BudgetMonth: Hashable, Sendable {
        public var income: Double = 0
        public var fixed: Double = 0
        public var free: Double { income - fixed }
    }

    public struct BudgetYear: Hashable, Sendable {
        public var year: Int
        public var months: [BudgetMonth]
        public var totalIncome: Double
        public var totalFixed: Double
        public var totalFree: Double { totalIncome - totalFixed }
        public var average: Double { totalFree / 12 }
    }

    /// Anteil einer Person an einer Einnahme (genau ein Empfänger): ohne Person 1, Empfänger 1, sonst 0.
    public func incomeShare(_ i: Income, person: UUID?) -> Double {
        guard let p = person else { return 1 }
        return i.holderID == p ? 1 : 0
    }

    /// Termine einer Einnahme im Zeitraum (Grenze = Ende).
    public func occurrences(_ i: Income, from: Day, to: Day) -> [Day] {
        Calc.occurrences(due: i.due, cycle: i.cycle, start: i.start, limit: i.end, pauses: [], from: from, to: to)
    }

    /// Betrag einer Einnahme an einem Tag.
    public func priceAt(_ i: Income, _ d: Day) -> Double {
        Calc.priceAt(amount: i.amount, prices: i.prices, d)
    }

    /// Heutiger Betrag einer Einnahme.
    public func curPrice(_ i: Income) -> Double { priceAt(i, today) }

    /// Einnahmen und Fixkosten je Monat (Personenanteile wie im Budget).
    public func budgetYear(_ year: Int, person: UUID?) -> BudgetYear {
        budgetPeriod(year: year, from: Day(year, 1, 1), to: Day(year, 12, 31), person: person)
    }

    func budgetPeriod(year: Int, from: Day, to: Day, person: UUID?) -> BudgetYear {
        var m = Array(repeating: BudgetMonth(), count: 12)
        for i in data.incomes {
            let f = incomeShare(i, person: person)
            if f == 0 { continue }
            for d in occurrences(i, from: from, to: to) { m[d.month - 1].income += conv(priceAt(i, d), i.currency) * f }
        }
        for c in data.contracts {
            let f = holderShare(c, person: person)
            if f == 0 { continue }
            for p in payments(c, from: from, to: to) { m[p.date.month - 1].fixed += conv(p.amount, c.currency) * f }
        }
        return BudgetYear(year: year, months: m, totalIncome: m.reduce(0.0) { $0 + $1.income }, totalFixed: m.reduce(0.0) { $0 + $1.fixed })
    }

    /// Vergleich «verfügbar» mit dem Vorjahresmonat (Budget), nil ohne Vorjahreswerte.
    public func budgetMonthComparison(year: Int, month: Int, person: UUID?, free: Double) -> (text: String, trend: Trend)? {
        let p = budgetPeriod(year: year - 1, from: Day(year - 1, month, 1), to: Day(year - 1, month + 1, 0), person: person)
        let bm = p.months[month - 1]
        if !(bm.income > 0.005 || bm.fixed > 0.005) { return nil }
        let d = free - bm.free
        let pr = Format.jsRound(Swift.abs(d))
        let label = Format.monthNames[month - 1] + " \(year - 1)"
        if pr < 1 { return ("gleich wie " + label, .same) }
        return (Format.money0(pr) + " " + home.rawValue + (d > 0 ? " mehr" : " weniger") + " als " + label, d > 0 ? .up : .down)
    }
}
