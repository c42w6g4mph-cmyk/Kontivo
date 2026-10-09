import Foundation

// MARK: - Hilfen für den Kontoauszug-Import: JS-Regex-Semantik auf NSRegularExpression (ICU), UTF-16-Indizes wie JS

/// Treffer eines regulären Ausdrucks (wie JS `match`): Gruppen (0 = ganzer Treffer, nicht beteiligt = nil), Position in UTF-16.
struct BMatch {
    var groups: [String?]
    var range: NSRange

    /// JS `m.index`
    var index: Int { range.location }
    subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    /// Gruppe oder "" (JS `m[i]||""`)
    func s(_ i: Int) -> String { self[i] ?? "" }
}

/// Regulärer Ausdruck mit JS-ähnlichen Methoden. Muster in ICU-Syntax (wie JS ohne `u`-Flag, hier nur ASCII-Fälle).
/// Ungültige Muster landen in `failed` (Test prüft, dass die Liste leer bleibt) und treffen nie.
final class BRX {
    let re: NSRegularExpression
    let pattern: String

    private static let lock = NSLock()
    private static var _failed: [String] = []
    static var failed: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _failed
    }

    init(_ pattern: String, i: Bool = false) {
        self.pattern = pattern
        if let r = try? NSRegularExpression(pattern: pattern, options: i ? [.caseInsensitive] : []) {
            re = r
        } else {
            BRX.lock.lock()
            BRX._failed.append(pattern)
            BRX.lock.unlock()
            // trifft nie
            re = BRX.never
        }
    }

    // swiftlint:disable:next force_try
    private static let never = try! NSRegularExpression(pattern: "(?!x)x", options: [])

    private static func full(_ s: String) -> NSRange { NSRange(location: 0, length: (s as NSString).length) }

    private static func make(_ m: NSTextCheckingResult, _ s: String) -> BMatch {
        let ns = s as NSString
        var g: [String?] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            g.append(r.location == NSNotFound ? nil : ns.substring(with: r))
        }
        return BMatch(groups: g, range: m.range)
    }

    /// JS `re.test(s)`
    func test(_ s: String) -> Bool {
        re.firstMatch(in: s, options: [], range: BRX.full(s)) != nil
    }

    /// JS `s.match(re)` ohne g
    func match(_ s: String) -> BMatch? {
        guard let m = re.firstMatch(in: s, options: [], range: BRX.full(s)) else { return nil }
        return BRX.make(m, s)
    }

    /// Alle Treffer (JS `s.match(/…/g)` bzw. `replace` mit Funktion)
    func matches(_ s: String) -> [BMatch] {
        re.matches(in: s, options: [], range: BRX.full(s)).map { BRX.make($0, s) }
    }

    /// Anzahl Treffer (JS `(s.match(/…/g)||[]).length`)
    func count(_ s: String) -> Int {
        re.numberOfMatches(in: s, options: [], range: BRX.full(s))
    }

    /// JS `s.replace(/…/g, tmpl)` – Vorlage mit $1; `literal` = Text ohne $-Ersetzung
    func replaceAll(_ s: String, _ tmpl: String, literal: Bool = false) -> String {
        re.stringByReplacingMatches(in: s, options: [], range: BRX.full(s),
                                    withTemplate: literal ? NSRegularExpression.escapedTemplate(for: tmpl) : tmpl)
    }

    /// JS `s.replace(/…/, tmpl)` – nur der erste Treffer
    func replaceFirst(_ s: String, _ tmpl: String, literal: Bool = false) -> String {
        guard let m = re.firstMatch(in: s, options: [], range: BRX.full(s)) else { return s }
        let ns = s as NSString
        let rep = re.replacementString(for: m, in: s, offset: 0,
                                       template: literal ? NSRegularExpression.escapedTemplate(for: tmpl) : tmpl)
        return ns.replacingCharacters(in: m.range, with: rep)
    }

    /// JS `s.replace(/…/g, fn)`
    func replaceAll(_ s: String, _ fn: (BMatch) -> String) -> String {
        let ns = s as NSString
        var out = ""
        var pos = 0
        for m in re.matches(in: s, options: [], range: BRX.full(s)) {
            out += ns.substring(with: NSRange(location: pos, length: m.range.location - pos))
            out += fn(BRX.make(m, s))
            pos = m.range.location + m.range.length
        }
        out += ns.substring(from: pos)
        return out
    }

    /// JS `s.split(re)` (Muster ohne Gruppen). Leere Treffer trennen nicht.
    func split(_ s: String) -> [String] {
        let ns = s as NSString
        var out: [String] = []
        var pos = 0
        for m in re.matches(in: s, options: [], range: BRX.full(s)) {
            if m.range.length == 0 { continue }
            out.append(ns.substring(with: NSRange(location: pos, length: m.range.location - pos)))
            pos = m.range.location + m.range.length
        }
        out.append(ns.substring(from: pos))
        return out
    }
}

enum BU {
    /// JS `String.prototype.trim` (inkl. BOM)
    static let trimSet: CharacterSet = {
        var c = CharacterSet.whitespacesAndNewlines
        c.insert(charactersIn: "\u{FEFF}\u{00A0}\u{2028}\u{2029}")
        return c
    }()

    static func trim(_ s: String) -> String { s.trimmingCharacters(in: trimSet) }

    /// JS `s.slice(a, b)` auf UTF-16
    static func slice(_ s: String, _ a: Int, _ b: Int? = nil) -> String {
        let ns = s as NSString
        let n = ns.length
        var x = a < 0 ? max(0, n + a) : min(a, n)
        var y = b.map { $0 < 0 ? max(0, n + $0) : min($0, n) } ?? n
        if y < x { y = x }
        x = min(x, n)
        return ns.substring(with: NSRange(location: x, length: y - x))
    }

    /// JS `s.length` (UTF-16)
    static func len(_ s: String) -> Int { (s as NSString).length }

    /// JS `Math.round` (bei .5 aufwärts)
    static func round(_ x: Double) -> Double {
        let f = x.rounded(.down)
        return x - f >= 0.5 ? f + 1 : f
    }

    /// JS `Math.round(x * 100) / 100`
    static func r2(_ x: Double) -> Double { round(x * 100) / 100 }

    /// JS unäres Plus `+s` auf Text: leer → 0, ungültig → NaN
    static func num(_ s: String) -> Double {
        var t = trim(s)
        if t.isEmpty { return 0 }
        if t.hasSuffix(".") { t += "0" }
        if t.hasPrefix(".") { t = "0" + t } else if t.hasPrefix("-.") { t = "-0" + t.dropFirst() }
        return JS.num(.string(t))
    }

    /// JS Wahrheitswert einer Zahl (≠ 0, nicht NaN)
    static func truthy(_ v: Double?) -> Bool {
        guard let v = v else { return false }
        return v != 0 && !v.isNaN
    }

    /// JS `Object.keys`-Reihenfolge: ganzzahlige Schlüssel aufsteigend, dann Einfügereihenfolge.
    static func keyOrder(_ keys: [String]) -> [String] {
        let ints = keys.filter { JSObject.isIndex($0) }.sorted { (UInt64($0) ?? 0) < (UInt64($1) ?? 0) }
        return ints + keys.filter { !JSObject.isIndex($0) }
    }

    /// Stabil sortieren mit Dreiweg-Vergleich (JS `sort(cmp)`, cmp < 0 = a zuerst).
    static func sorted<T>(_ a: [T], _ cmp: (T, T) -> Double) -> [T] {
        a.enumerated().sorted { x, y in
            let c = cmp(x.element, y.element)
            if c < 0 { return true }
            if c > 0 { return false }
            return x.offset < y.offset
        }.map { $0.element }
    }

    /// Zeilen trennen (JS `split(/\r?\n/)`)
    static func lines(_ s: String) -> [String] {
        BU.rxLines.split(s)
    }

    static let rxLines = BRX("\\r?\\n")
}

/// Objekt mit Schlüsseln in Einfügereihenfolge (JS-Objekt `groups`, `names`).
struct BOrdered<V> {
    private(set) var keys: [String] = []
    private var values: [String: V] = [:]

    subscript(key: String) -> V? {
        get { values[key] }
        set {
            if let v = newValue {
                if values[key] == nil { keys.append(key) }
                values[key] = v
            } else if values[key] != nil {
                values[key] = nil
                keys.removeAll { $0 == key }
            }
        }
    }

    /// Wie `Object.keys`
    var orderedKeys: [String] { BU.keyOrder(keys) }
}
