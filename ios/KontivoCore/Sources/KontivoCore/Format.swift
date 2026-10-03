import Foundation

/// Zahlen, Daten und Texte wie in der Web-App (de-CH, Schweizer Schreibweise).
public enum Format {
    /// Minuszeichen für Anzeigen (U+2212).
    public static let minus = "\u{2212}"
    /// Tausendertrennzeichen de-CH (U+2019).
    public static let thousandsSeparator = "\u{2019}"

    /// Monatsnamen lang (MON).
    public static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    /// Monatsnamen kurz (MS).
    public static let monthShort = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

    /// Turnus-Texte (CYCLE).
    public static let cycleTexts: [Int: String] = [1: "monatlich", 2: "alle 2 Monate", 3: "quartalsweise", 6: "halbjährlich", 12: "jährlich", 24: "alle 2 Jahre"]
    /// Turnus-Texte für Einnahmen (ICYCLE, zusätzlich 0 «einmalig»).
    public static let incomeCycleTexts: [Int: String] = [0: "einmalig", 1: "monatlich", 2: "alle 2 Monate", 3: "quartalsweise", 6: "halbjährlich", 12: "jährlich", 24: "alle 2 Jahre"]
    /// Wählbare Turnusse in Monaten.
    public static let cycleOptions: [Int] = [1, 2, 3, 6, 12, 24]

    /// Text eines Turnus (unbekannt → nil).
    public static func cycleText(_ months: Int) -> String? { cycleTexts[months] }

    /// Text eines Turnus, unbekannt → «monatlich» (wie `CYCLE[c.cycle]||"monatlich"`).
    public static func cycleTextOrMonthly(_ months: Int) -> String { cycleTexts[months] ?? "monatlich" }

    /// Kündigungstermine (TERMS).
    public static func termText(_ t: CancelTerm) -> String {
        switch t {
        case .anytime: return "jederzeit"
        case .period: return "Ende der Zahlungsperiode"
        case .monthEnd: return "Monatsende"
        case .quarterEnd: return "Quartalsende"
        case .halfYearEnd: return "Halbjahresende"
        case .yearEnd: return "Jahresende"
        case .contractYear: return "Ende Vertragsjahr"
        }
    }

    // MARK: Zahlen

    /// Betrag mit genau 2 Nachkommastellen: «1’284.50», negativ «−5.00».
    public static func money(_ v: Double) -> String {
        let p = decimalParts(v, digits: 2)
        return (p.negative ? minus : "") + group(p.integer) + "." + p.fraction
    }

    /// Betrag ohne Nachkommastellen (gerundet): «1’285».
    public static func money0(_ v: Double) -> String {
        let p = decimalParts(v, digits: 0)
        return (p.negative ? minus : "") + group(p.integer)
    }

    /// Betrag mit Vorzeichen: negativ «−», positiv «+» (wenn `plus`), null ohne Zeichen.
    public static func moneySigned(_ v: Double, plus: Bool = false) -> String {
        let p = decimalParts(v, digits: 2)
        let zero = p.integer == "0" && p.fraction.allSatisfy { $0 == "0" }
        let sign = p.negative ? minus : ((plus && !zero) ? "+" : "")
        return sign + group(p.integer) + "." + p.fraction
    }

    /// Zahl mit höchstens `maxFractionDigits` Nachkommastellen (ohne Nullen am Ende), de-CH.
    public static func number(_ v: Double, maxFractionDigits: Int) -> String {
        let p = decimalParts(v, digits: maxFractionDigits)
        var frac = p.fraction
        while frac.hasSuffix("0") { frac.removeLast() }
        return (p.negative ? minus : "") + group(p.integer) + (frac.isEmpty ? "" : "." + frac)
    }

    /// Wie JS `x.toFixed(2)` (Punkt, ohne Tausendertrennzeichen; Gleichstand weg von 0).
    public static func fixed2(_ x: Double) -> String {
        if x == 0 || !x.isFinite { return "0.00" }
        let a = Swift.abs(x)
        let y = a * 8
        if y == y.rounded(.down) && y.truncatingRemainder(dividingBy: 2) == 1 && a < 1e15 {
            // exakter Gleichstand auf der dritten Stelle: aufrunden wie JS
            let n = Int((a * 100).rounded(.down)) + 1
            let s = String(n / 100) + "." + Day.pad(n % 100, 2)
            return (x < 0 ? "-" : "") + s
        }
        return String(format: "%.2f", x)
    }

    /// JS `Math.round` (Gleichstand Richtung +∞).
    public static func jsRound(_ x: Double) -> Double {
        let f = x.rounded(.down)
        return (x - f >= 0.5) ? f + 1 : f
    }

    /// JS `Math.round(x * 100) / 100`.
    public static func round2(_ x: Double) -> Double {
        jsRound(x * 100) / 100
    }

    /// Tausendertrennzeichen einsetzen (ab 4 Stellen).
    static func group(_ digits: String) -> String {
        if digits.count <= 3 { return digits }
        var out = ""
        let chars = Array(digits)
        for (i, ch) in chars.enumerated() {
            if i > 0 && (chars.count - i) % 3 == 0 { out += thousandsSeparator }
            out.append(ch)
        }
        return out
    }

    /// Ziffern einer Zahl, gerundet auf `digits` Nachkommastellen: halb weg von 0, auf der kürzesten
    /// Dezimaldarstellung (wie `Intl.NumberFormat`/ICU).
    static func decimalParts(_ x: Double, digits: Int) -> (negative: Bool, integer: String, fraction: String) {
        let zeros = String(repeating: "0", count: Swift.max(0, digits))
        guard x.isFinite, x != 0 else { return (false, "0", zeros) }
        let negative = x < 0
        let s = "\(Swift.abs(x))"
        var mantissa = s
        var exp = 0
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            mantissa = String(s[s.startIndex..<e])
            exp = Int(String(s[s.index(after: e)...])) ?? 0
        }
        var intPart = mantissa
        var fracPart = ""
        if let dot = mantissa.firstIndex(of: ".") {
            intPart = String(mantissa[mantissa.startIndex..<dot])
            fracPart = String(mantissa[mantissa.index(after: dot)...])
        }
        var ds: [Int] = (intPart + fracPart).compactMap { $0.wholeNumberValue }
        var point = intPart.count + exp
        while ds.count > 1 && ds[0] == 0 {
            ds.removeFirst()
            point -= 1
        }
        if ds.allSatisfy({ $0 == 0 }) { return (false, "0", zeros) }
        let keep = point + digits
        var kept: [Int]
        if keep < 0 {
            return (false, "0", zeros)
        } else if keep >= ds.count {
            kept = ds + Array(repeating: 0, count: keep - ds.count)
        } else {
            kept = Array(ds[0..<keep])
            if ds[keep] >= 5 {
                var i = kept.count - 1
                var carry = true
                while carry && i >= 0 {
                    kept[i] += 1
                    if kept[i] == 10 {
                        kept[i] = 0
                        i -= 1
                    } else {
                        carry = false
                    }
                }
                if carry {
                    kept.insert(1, at: 0)
                    point += 1
                }
            }
        }
        let allZero = kept.allSatisfy { $0 == 0 }
        var integer = ""
        var fraction = ""
        if point <= 0 {
            integer = "0"
            fraction = String(repeating: "0", count: -point) + kept.map(String.init).joined()
        } else {
            integer = kept[0..<Swift.min(point, kept.count)].map(String.init).joined()
            if point < kept.count { fraction = kept[point...].map(String.init).joined() }
        }
        if integer.isEmpty { integer = "0" }
        while integer.count > 1 && integer.hasPrefix("0") { integer.removeFirst() }
        if fraction.count < digits { fraction += String(repeating: "0", count: digits - fraction.count) }
        if fraction.count > digits { fraction = String(fraction.prefix(digits)) }
        return (negative && !allZero, integer, fraction)
    }

    // MARK: Daten

    /// «3. Oktober 2026», ohne Datum «—».
    public static func fmtD(_ d: Day?) -> String {
        guard let d = d else { return "—" }
        return "\(d.day). " + monthNames[d.month - 1] + " \(d.year)"
    }

    /// «3. Oktober 2026» aus «JJJJ-MM-TT», leer/ungültig «—».
    public static func fmtD(iso: String) -> String {
        fmtD(Day(iso: iso))
    }

    /// «03.10.26», ohne Datum «—».
    public static func fmtShort(_ d: Day?) -> String {
        guard let d = d else { return "—" }
        let y = String(d.year)
        return Day.pad(d.day, 2) + "." + Day.pad(d.month, 2) + "." + String(y.dropFirst(2))
    }

    /// «TT.MM.» im laufenden Jahr, sonst «TT.MM.JJ» (Fristen-Tab).
    public static func ddmm(_ d: Day, currentYear: Int) -> String {
        let y = String(d.year)
        return Day.pad(d.day, 2) + "." + Day.pad(d.month, 2) + "." + (d.year == currentYear ? "" : String(y.suffix(2)))
    }

    /// «Monat Jahr», z.B. «Oktober 2026».
    public static func monthYear(_ d: Day) -> String {
        monthNames[d.month - 1] + " \(d.year)"
    }

    /// Backup-Datum wie `toLocaleDateString("de-CH")`: «3.10.2026».
    public static func shortNumericDate(_ d: Day) -> String {
        "\(d.day).\(d.month).\(d.year)"
    }

    // MARK: Zeiträume

    /// 0 «heute», 1 «morgen», ≤ 60 «in n Tagen», sonst Monate bzw. Jahre.
    public static func inDays(_ d: Int) -> String {
        if d == 0 { return "heute" }
        if d == 1 { return "morgen" }
        if d <= 60 { return "in \(d) Tagen" }
        let m = Int(jsRound(Double(d) / 30.44))
        if m < 24 { return "in \(m)" + (m == 1 ? " Monat" : " Monaten") }
        let y = Int(jsRound(Double(d) / 365.25))
        return "in \(y)" + (y == 1 ? " Jahr" : " Jahren")
    }

    /// 0 «heute», 1 «1 Tag», ≤ 60 «n Tage», sonst «m Monate» bzw. «y Jahre».
    public static func humanDays(_ d: Int) -> String {
        if d == 0 { return "heute" }
        if d == 1 { return "1 Tag" }
        if d <= 60 { return "\(d) Tage" }
        let m = Int(jsRound(Double(d) / 30.44))
        if m < 24 { return "\(m) Monate" }
        return "\(Int(jsRound(Double(d) / 365.25))) Jahre"
    }

    /// Fristtext: 0 → "", «bis zum n. des Monats», «n Woche/Wochen», «n Tag/Tage», «n Monat/Monate».
    public static func noticeText(notice n: Int, unit: NoticeUnit) -> String {
        if n == 0 { return "" }
        switch unit {
        case .dayOfMonth: return "bis zum \(n). des Monats"
        case .weeks: return "\(n) " + (n == 1 ? "Woche" : "Wochen")
        case .days: return "\(n) " + (n == 1 ? "Tag" : "Tage")
        case .months: return "\(n) " + (n == 1 ? "Monat" : "Monate")
        }
    }

    public static func noticeText(_ c: Contract) -> String {
        noticeText(notice: c.notice, unit: c.noticeUnit)
    }

    // MARK: Texte

    /// «Anteil 50 %»
    public static func shareText(_ f: Double) -> String {
        "Anteil \(Int(jsRound(f * 100))) %"
    }

    /// «1 Vertrag» / «3 Verträge»
    public static func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n) " + (n == 1 ? one : many)
    }

    /// URL mit «https://», wenn kein Schema angegeben ist (`normUrl`).
    public static func normUrl(_ u: String) -> String {
        let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let l = t.lowercased()
        return (l.hasPrefix("http://") || l.hasPrefix("https://")) ? t : "https://" + t
    }

    /// Hostname ohne «www.» (`domainOf`).
    public static func domain(of u: String) -> String {
        let n = normUrl(u)
        guard !n.isEmpty, let host = URL(string: n)?.host else { return "" }
        return host.lowercased().hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Vergleich wie `localeCompare(…, "de-CH", {sensitivity:"base"})`.
    public static func compareDE(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: Locale(identifier: "de_CH"))
    }

    /// `true`, wenn `a` vor `b` kommt (de-CH, ohne Gross/Klein und Akzente).
    public static func lessDE(_ a: String, _ b: String) -> Bool {
        compareDE(a, b) == .orderedAscending
    }

    /// Erstes Wort eines Namens (`firstName`).
    public static func firstName(_ h: String) -> String {
        let t = h.trimmingCharacters(in: .whitespaces)
        return t.split(whereSeparator: { $0 == " " || $0 == "\t" }).first.map(String.init) ?? h
    }

    /// Leerzeichen trimmen und mehrfache zusammenfassen (`.trim().replace(/\s+/g," ")`).
    public static func collapseSpaces(_ s: String) -> String {
        s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

extension Array {
    /// Stabil sortieren (wie JS `Array.prototype.sort`).
    func stableSorted(by less: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if less(a.element, b.element) { return true }
            if less(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map { $0.element }
    }
}
