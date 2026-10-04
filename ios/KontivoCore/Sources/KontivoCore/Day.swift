import Foundation

/// Kalenderdatum ohne Uhrzeit (proleptischer gregorianischer Kalender, wie JS `Date` mit lokaler Mitternacht).
/// JSON-Form: "YYYY-MM-DD". Alle Rechnungen laufen über ganze Tage, nie über Zeitzonen.
public struct Day: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    /// 1–12
    public let month: Int
    /// 1–31
    public let day: Int

    /// Wie JS `new Date(y, m - 1, d)`: Monat und Tag dürfen überlaufen.
    /// Beispiele: `Day(2026, 13, 1)` = 01.01.2027, `Day(2026, 3, 0)` = 28.02.2026 (letzter Tag des Vormonats).
    public init(_ year: Int, _ month: Int, _ day: Int) {
        let m0 = month - 1
        let y = year + Day.floorDiv(m0, 12)
        let m = Day.floorMod(m0, 12) + 1
        let c = Day.civilFromDays(Day.daysFromCivil(y, m, 1) + (day - 1))
        self.year = c.0
        self.month = c.1
        self.day = c.2
    }

    public init(year: Int, month: Int, day: Int) {
        self.init(year, month, day)
    }

    /// Tag Nummer `ordinal` (0 = 01.01.1970).
    public init(ordinal: Int) {
        let c = Day.civilFromDays(ordinal)
        year = c.0
        month = c.1
        day = c.2
    }

    /// Liest «JJJJ-MM-TT» wie `parseD` der Web-App: genau drei Teile, ungültige Tage rollen über (31.02. → 03.03.).
    /// Leer oder nicht lesbar → nil.
    public init?(iso: String) {
        let parts = iso.split(separator: "-", omittingEmptySubsequences: false)
        if iso.isEmpty || parts.count != 3 { return nil }
        var v: [Int] = []
        for p in parts {
            let t = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { v.append(0); continue }
            guard let n = Int(t) else { return nil }
            v.append(n)
        }
        self.init(v[0], v[1], v[2])
    }

    /// Kurzform für `Day(iso:)`.
    public init?(_ iso: String) {
        self.init(iso: iso)
    }

    /// Gregorianischer Kalender in der aktuellen Zeitzone des Geräts. `Day` ist immer gregorianisch –
    /// der Gerätekalender (japanisch, buddhistisch …) darf nie für die Umrechnung verwendet werden.
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// Kalenderdatum eines Zeitpunkts im angegebenen Kalender (Standard: gregorianisch, aktuelle Zeitzone).
    public init(date: Date, calendar: Calendar = Day.calendar) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// Heute (lokales Datum ohne Zeit). Für Tests einen festen Tag übergeben statt `today` aufzurufen.
    public static func today(calendar: Calendar = Day.calendar, now: Date = Date()) -> Day {
        Day(date: now, calendar: calendar)
    }

    /// Heute in einer bestimmten Zeitzone.
    public static func today(in timeZone: TimeZone, now: Date = Date()) -> Day {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return Day(date: now, calendar: cal)
    }

    /// Mitternacht dieses Tages im angegebenen Kalender (Standard: gregorianisch, aktuelle Zeitzone).
    public func date(calendar: Calendar = Day.calendar) -> Date {
        var dc = DateComponents()
        dc.year = year
        dc.month = month
        dc.day = day
        return calendar.date(from: dc) ?? Date(timeIntervalSince1970: TimeInterval(ordinal) * 86_400)
    }

    // MARK: Werte

    /// Tage seit 01.01.1970.
    public var ordinal: Int { Day.daysFromCivil(year, month, day) }

    /// «JJJJ-MM-TT»
    public var iso: String { Day.pad(year, 4) + "-" + Day.pad(month, 2) + "-" + Day.pad(day, 2) }

    public var description: String { iso }

    /// Monatszähler (Jahr × 12 + Monat − 1), für Monatsdifferenzen.
    public var monthIndex: Int { year * 12 + (month - 1) }

    public var isLeapYear: Bool { Day.isLeap(year) }

    public var daysInMonth: Int { Day.daysIn(year, month) }

    /// Letzter Tag des Monats (wie JS `new Date(y, m + 1, 0)`).
    public var lastDayOfMonth: Day { Day(year, month, daysInMonth) }

    /// Erster Tag des Monats.
    public var firstDayOfMonth: Day { Day(year, month, 1) }

    /// Monatsletzter? (JS `isEOM`)
    public var isEndOfMonth: Bool { day == daysInMonth }

    // MARK: Rechnen

    /// Wie JS `addMonths`: Zielmonat = Monat + n, Tag auf das Monatsende begrenzt (31.01. + 1 = 28./29.02.).
    public func addingMonths(_ n: Int) -> Day {
        let total = (month - 1) + n
        let y = year + Day.floorDiv(total, 12)
        let m = Day.floorMod(total, 12) + 1
        return Day(y, m, Swift.min(day, Day.daysIn(y, m)))
    }

    /// Wie JS `addMonthsE` (Vertragsenden): Monatsletzter bleibt Monatsletzter (31.01. + 2 = 31.03., 30.04. + 1 = 31.05.).
    public func addingMonthsE(_ n: Int) -> Day {
        isEndOfMonth ? Day(year, month + n + 1, 0) : addingMonths(n)
    }

    /// Kalendertage addieren (negativ möglich).
    public func addingDays(_ n: Int) -> Day {
        Day(ordinal: ordinal + n)
    }

    /// Tage von `self` bis `other` (JS `daysBetween(self, other)`), negativ wenn `other` früher liegt.
    public func days(to other: Day) -> Int {
        other.ordinal - ordinal
    }

    /// Ganze Monate von `self` bis `other` nach Kalendermonaten (ohne Tage).
    public func months(to other: Day) -> Int {
        other.monthIndex - monthIndex
    }

    public static func < (a: Day, b: Day) -> Bool {
        if a.year != b.year { return a.year < b.year }
        if a.month != b.month { return a.month < b.month }
        return a.day < b.day
    }

    // MARK: Kalender-Hilfen

    static func isLeap(_ y: Int) -> Bool {
        (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
    }

    static func daysIn(_ y: Int, _ m: Int) -> Int {
        switch m {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        default: return isLeap(y) ? 29 : 28
        }
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
    }

    static func floorMod(_ a: Int, _ b: Int) -> Int {
        a - floorDiv(a, b) * b
    }

    static func pad(_ v: Int, _ width: Int) -> String {
        let s = String(Swift.abs(v))
        let p = s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
        return v < 0 ? "-" + p : p
    }

    /// Tage seit 01.01.1970 für ein gültiges Datum (H. Hinnant, «days_from_civil»).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let mp = (m + 9) % 12
        let doy = (153 * mp + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// Umkehrung von `daysFromCivil` («civil_from_days»).
    static func civilFromDays(_ z0: Int) -> (Int, Int, Int) {
        let z = z0 + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}

extension Day: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        guard let d = Day(iso: s) else {
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Ungültiges Datum: \(s)")
        }
        self = d
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(iso)
    }
}

/// Zeitstempel ohne DateFormatter: UTC-Bestandteile und ISO-8601-Text wie JS `toISOString()`.
public enum Timestamp {
    /// «2026-10-03T08:15:42.123Z»
    public static func isoString(_ date: Date) -> String {
        let msTotal = Int((date.timeIntervalSince1970 * 1000).rounded(.down))
        let dayNo = Day.floorDiv(msTotal, 86_400_000)
        let rest = msTotal - dayNo * 86_400_000
        let d = Day(ordinal: dayNo)
        let h = rest / 3_600_000
        let mi = (rest / 60_000) % 60
        let s = (rest / 1_000) % 60
        let ms = rest % 1_000
        return d.iso + "T" + Day.pad(h, 2) + ":" + Day.pad(mi, 2) + ":" + Day.pad(s, 2) + "." + Day.pad(ms, 3) + "Z"
    }

    /// Liest «JJJJ-MM-TTTHH:MM:SS(.mmm)Z» (UTC). Fehlende Teile zählen als 0.
    public static func parse(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 10, let d = Day(iso: String(t.prefix(10))) else { return nil }
        var secs = 0.0
        if t.count > 11 {
            let time = t.dropFirst(11).replacingOccurrences(of: "Z", with: "")
            let parts = time.split(separator: ":")
            if parts.count >= 1, let h = Double(parts[0]) { secs += h * 3600 }
            if parts.count >= 2, let m = Double(parts[1]) { secs += m * 60 }
            if parts.count >= 3, let sec = Double(parts[2]) { secs += sec }
        }
        return Date(timeIntervalSince1970: TimeInterval(d.ordinal) * 86_400 + secs)
    }

    /// Kalendertag (UTC) eines ISO-Zeitstempels.
    public static func day(ofISO s: String) -> Day? {
        guard s.count >= 10 else { return nil }
        return Day(iso: String(s.prefix(10)))
    }
}
