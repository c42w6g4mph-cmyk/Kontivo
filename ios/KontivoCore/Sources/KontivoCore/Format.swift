import Foundation

/// Zahlenformat (Web `numStyle`, Entscheid 09.10.2026): EUR deutsch «1.234,50», CHF schweizerisch «1’234.50».
public enum NumberStyle: String, Hashable, Sendable {
    /// de-CH: Tausender ’ (U+2019), Dezimalpunkt
    case ch
    /// de-DE: Tausender Punkt, Dezimalkomma
    case de

    public var groupSeparator: String { self == .de ? "." : Format.thousandsSeparator }
    public var decimalSeparator: String { self == .de ? "," : "." }
}

/// Zahlen, Daten und Texte wie in der Web-App (Schweizer Schreibweise; Zahlen je nach Währung de-CH bzw. de-DE).
public enum Format {
    /// Minuszeichen für Anzeigen (U+2212).
    public static let minus = "\u{2212}"
    /// Tausendertrennzeichen de-CH (U+2019).
    public static let thousandsSeparator = "\u{2019}"

    /// Hauptwährung für Beträge ohne eigene Währung (Summen) und für USD/GBP/TRY (Web: `state.settings.home` in `numStyle`).
    /// Wird von `Calc.init` aus den Daten gesetzt, damit alle Ansichten ohne weiteren Parameter richtig formatieren.
    public static var homeCurrency: Currency = .CHF

    /// Zahlenformat einer Währung (Web `numStyle`): EUR → de-DE, CHF → de-CH, übrige und ohne Währung nach der Hauptwährung.
    public static func numberStyle(_ currency: Currency? = nil) -> NumberStyle {
        let c = currency ?? homeCurrency
        if c == .EUR { return .de }
        if c == .CHF { return .ch }
        return homeCurrency == .EUR ? .de : .ch
    }

    /// Monatsnamen lang (MON).
    public static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]
    /// Monatsnamen kurz (MS).
    public static let monthShort = ["Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez"]

    /// Texte des Zahlungsrhythmus (CYCLE).
    public static let cycleTexts: [Int: String] = [1: "monatlich", 2: "alle 2 Monate", 3: "quartalsweise", 6: "halbjährlich", 12: "jährlich", 24: "alle 2 Jahre"]
    /// Texte des Zahlungsrhythmus für Einnahmen (ICYCLE, zusätzlich 0 «einmalig»).
    public static let incomeCycleTexts: [Int: String] = [0: "einmalig", 1: "monatlich", 2: "alle 2 Monate", 3: "quartalsweise", 6: "halbjährlich", 12: "jährlich", 24: "alle 2 Jahre"]
    /// Wählbare Zahlungsrhythmen in Monaten.
    public static let cycleOptions: [Int] = [1, 2, 3, 6, 12, 24]

    /// Text eines Zahlungsrhythmus (unbekannt → nil).
    public static func cycleText(_ months: Int) -> String? { cycleTexts[months] }

    /// Text eines Zahlungsrhythmus, unbekannt → «monatlich» (wie `CYCLE[c.cycle]||"monatlich"`).
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

    /// Betrag mit genau 2 Nachkommastellen im Format der Währung (Web `money(v, cur)`): CHF «1’284.50», EUR «1.284,50»,
    /// negativ «−5.00». Ohne Währung (Summen in der Hauptwährung) nach der Hauptwährung.
    public static func money(_ v: Double, _ currency: Currency? = nil) -> String {
        let st = numberStyle(currency)
        let p = decimalParts(v, digits: 2)
        return (p.negative ? minus : "") + group(p.integer, st) + st.decimalSeparator + p.fraction
    }

    /// Betrag ohne Nachkommastellen (gerundet): «1’285» bzw. «1.285» (Web `nf0`).
    public static func money0(_ v: Double, _ currency: Currency? = nil) -> String {
        let st = numberStyle(currency)
        let p = decimalParts(v, digits: 0)
        return (p.negative ? minus : "") + group(p.integer, st)
    }

    /// Betrag mit Vorzeichen: negativ «−», positiv «+» (wenn `plus`), null ohne Zeichen.
    public static func moneySigned(_ v: Double, plus: Bool = false, currency: Currency? = nil) -> String {
        let st = numberStyle(currency)
        let p = decimalParts(v, digits: 2)
        let zero = p.integer == "0" && p.fraction.allSatisfy { $0 == "0" }
        let sign = p.negative ? minus : ((plus && !zero) ? "+" : "")
        return sign + group(p.integer, st) + st.decimalSeparator + p.fraction
    }

    /// Zahl mit höchstens `maxFractionDigits` Nachkommastellen (ohne Nullen am Ende) im Format der Währung.
    public static func number(_ v: Double, maxFractionDigits: Int, currency: Currency? = nil) -> String {
        number(v, minFractionDigits: 0, maxFractionDigits: maxFractionDigits, style: numberStyle(currency))
    }

    /// Wie `toLocaleString(de-CH|de-DE, {minimumFractionDigits, maximumFractionDigits})` (Rundung halb weg von 0).
    public static func number(_ v: Double, minFractionDigits: Int, maxFractionDigits: Int, style: NumberStyle) -> String {
        let p = decimalParts(v, digits: maxFractionDigits)
        var frac = p.fraction
        while frac.count > minFractionDigits && frac.hasSuffix("0") { frac.removeLast() }
        return (p.negative ? minus : "") + group(p.integer, style) + (frac.isEmpty ? "" : style.decimalSeparator + frac)
    }

    /// Prozent wie Web `pctTxt`: «+12 %», «−3 %», «±0 %»; unter 1 % mit einer Nachkommastelle im Format der Hauptwährung («+0.5 %» bzw. «+0,5 %»).
    public static func pctText(_ p: Double) -> String {
        let a = Swift.abs(p)
        let sign = p > 0 ? "+" : (p < 0 ? minus : "±")
        let body = (a > 0 && a < 1) ? number(a, minFractionDigits: 0, maxFractionDigits: 1, style: numberStyle(nil)) : String(Int(jsRound(a)))
        return sign + body + " %"
    }

    /// Betrag für ein Eingabefeld (Web `amtIn`): «59.90», bei EUR «59,90» (ohne Tausendertrennzeichen).
    public static func amountInput(_ v: Double, _ currency: Currency? = nil) -> String {
        let t = fixed2(v.isFinite ? v : 0)
        return numberStyle(currency) == .de ? t.replacingOccurrences(of: ".", with: ",") : t
    }

    /// Betrag aus einem Eingabefeld (Web `parseAmt`): Geld hat nie 3 Nachkommastellen, also ist «1.234» oder «1,234» ein
    /// Tausender (1234); sonst wie `parseNum`.
    public static func parseAmount(_ s: String?) -> Double? {
        let t = String((s ?? "").unicodeScalars.filter { u in
            !(u == "'" || u == "\u{2019}" || u == "\u{02BC}" || CharacterSet.whitespacesAndNewlines.contains(u)
              || u == "\u{00A0}" || u == "\u{202F}")
        })
        var sc = Array(t.unicodeScalars)
        var neg = false
        if let f = sc.first, f == "-" || f == "\u{2212}" {
            neg = true
            sc.removeFirst()
        }
        // ^([1-9]\d{0,2})[.,](\d{3})$
        if let k = sc.firstIndex(where: { $0 == "." || $0 == "," }), k >= 1, k <= 3, sc.count - k - 1 == 3 {
            let a = sc[0..<k], b = sc[(k + 1)...]
            let isDigit: (Unicode.Scalar) -> Bool = { $0.value >= 0x30 && $0.value <= 0x39 }
            if a.first != "0" && a.allSatisfy(isDigit) && b.allSatisfy(isDigit),
               let n = Double(String(String.UnicodeScalarView(a)) + String(String.UnicodeScalarView(b))) {
                return neg ? -n : n
            }
        }
        return parseNum(s)
    }

    /// Text eines Betrags an der Dezimalstelle teilen (Web `decAt`: letztes «.» oder «,»), z.B. für kleine Rappen/Cent.
    public static func decimalSplit(_ s: String) -> (whole: String, fraction: String) {
        guard let k = s.lastIndex(where: { $0 == "." || $0 == "," }) else { return (s, "") }
        return (String(s[s.startIndex..<k]), String(s[k...]))
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

    /// JS `toFixed(1)`: exakter Gleichstand auf der zweiten Stelle (x.25, x.75) wird aufgerundet (printf rundet zur geraden Ziffer).
    public static func fixed1(_ x: Double) -> String {
        if x == 0 || !x.isFinite { return "0.0" }
        let a = Swift.abs(x)
        let y = a * 4
        if y == y.rounded(.down) && y.truncatingRemainder(dividingBy: 2) == 1 && a < 1e15 {
            let n = Int((a * 10).rounded(.down)) + 1
            return (x < 0 ? "-" : "") + String(n / 10) + "." + String(n % 10)
        }
        return String(format: "%.1f", x)
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

    /// Tausendertrennzeichen einsetzen (ab 4 Stellen, wie de-CH und de-DE).
    static func group(_ digits: String, _ style: NumberStyle = .ch) -> String {
        if digits.count <= 3 { return digits }
        var out = ""
        let chars = Array(digits)
        for (i, ch) in chars.enumerated() {
            if i > 0 && (chars.count - i) % 3 == 0 { out += style.groupSeparator }
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

    /// Hostname ohne «www.» (`domainOf`): wie JS `new URL(…).hostname` klein geschrieben und Umlaut-Domains als Punycode
    /// («müller.ch» → «xn--mller-kva.ch»); nicht lesbar (z.B. Leerzeichen im Host) → "".
    public static func domain(of u: String) -> String {
        let n = normUrl(u)
        if n.isEmpty { return "" }
        var rest = Substring(n)
        if let r = rest.range(of: "://") { rest = rest[r.upperBound...] }
        let end = rest.firstIndex(where: { $0 == "/" || $0 == "?" || $0 == "#" || $0 == "\\" }) ?? rest.endIndex
        var auth = rest[..<end]
        if let at = auth.lastIndex(of: "@") { auth = auth[auth.index(after: at)...] }
        if !auth.hasPrefix("["), let c = auth.lastIndex(of: ":") { auth = auth[..<c] }
        let host = String(auth).precomposedStringWithCanonicalMapping.lowercased()
        if host.isEmpty || host.contains(where: { $0.isWhitespace || $0 == "<" || $0 == ">" || $0 == "%" }) { return "" }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map { punycode(String($0)) }
        let h = labels.joined(separator: ".")
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Punycode einer Domain-Stufe (RFC 3492, «xn--…»); reine ASCII-Stufen bleiben unverändert.
    static func punycode(_ label: String) -> String {
        let s = label.unicodeScalars.map { Int($0.value) }
        if s.allSatisfy({ $0 < 0x80 }) { return label }
        let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700
        var n = 128, delta = 0, bias = 72
        var out = String(String.UnicodeScalarView(label.unicodeScalars.filter { $0.value < 0x80 }))
        let b = out.unicodeScalars.count
        var h = b
        if b > 0 { out += "-" }
        func digit(_ d: Int) -> Character { Character(Unicode.Scalar(UInt8(d < 26 ? 97 + d : 22 + d))) }
        func adapt(_ d0: Int, _ num: Int, _ first: Bool) -> Int {
            var d = first ? d0 / damp : d0 / 2
            d += d / num
            var k = 0
            while d > ((base - tMin) * tMax) / 2 {
                d /= base - tMin
                k += base
            }
            return k + (base - tMin + 1) * d / (d + skew)
        }
        while h < s.count {
            guard let m = s.filter({ $0 >= n }).min() else { break }
            delta += (m - n) * (h + 1)
            n = m
            for c in s {
                if c < n { delta += 1 }
                if c == n {
                    var q = delta
                    var k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        out.append(digit(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    out.append(digit(q))
                    bias = adapt(delta, h + 1, h == b)
                    delta = 0
                    h += 1
                }
            }
            delta += 1
            n += 1
        }
        return "xn--" + out
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

extension Format {
    /// Kündigungsfrist aus einem Eingabefeld – wie Web `noticeVal`: leer → 0; sonst ganze Zahl ≥ 0 (über `parseNum`),
    /// bei «. im Monat» (`.dayOfMonth`) 1–28; alles andere → nil (Toast «Kündigungsfrist prüfen»).
    public static func noticeValue(_ raw: String, unit: NoticeUnit) -> Int? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        guard let n = parseNum(t), n >= 0, n.rounded(.down) == n, n < 1e6 else { return nil }
        if unit == .dayOfMonth && (n < 1 || n > 28) { return nil }
        return Int(n)
    }
}
