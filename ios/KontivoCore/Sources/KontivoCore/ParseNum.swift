import Foundation

extension Format {
    /// Zahl aus einem Eingabefeld lesen – 1:1 wie `parseNum` der Web-App (index.html «Helfer»).
    /// Entfernt ' ’ ʼ und Leerzeichen (auch geschützte); führendes - oder − = negativ.
    /// Kommen . und , vor, ist das letzte der Dezimaltrenner; mehrfach dasselbe Zeichen = Tausender;
    /// sonst wird , zu . ; alles andere (z.B. «12abc») ist ungültig → nil.
    /// Beispiele: «1’234.50» → 1234.5, «1 234,50» → 1234.5, «1.234,50» → 1234.5, «1,234.50» → 1234.5, «1.234.567» → 1234567.
    public static func parseNum(_ s: String?) -> Double? {
        var t = String((s ?? "").unicodeScalars.filter { u in
            !(u == "'" || u == "\u{2019}" || u == "\u{02BC}" || CharacterSet.whitespacesAndNewlines.contains(u)
              || u == "\u{00A0}" || u == "\u{202F}")
        })
        var sign = 1.0
        if t.hasPrefix("-") || t.hasPrefix("\u{2212}") { sign = -1; t.removeFirst() }
        if t.isEmpty { return nil }
        let d = t.lastIndex(of: "."), c = t.lastIndex(of: ",")
        if let d, let c {
            let dec: Character = d > c ? "." : ","
            let other: Character = dec == "." ? "," : "."
            t.removeAll { $0 == other }
            if t.filter({ $0 == dec }).count > 1 { return nil }
            t = t.replacingOccurrences(of: String(dec), with: ".")
        } else if d != nil || c != nil {
            let sp: Character = d != nil ? "." : ","
            if t.filter({ $0 == sp }).count > 1 { t.removeAll { $0 == sp } }
            else { t = t.replacingOccurrences(of: String(sp), with: ".") }
        }
        // ^(\d+\.?\d*|\.\d+)$
        let digits = CharacterSet(charactersIn: "0123456789")
        let parts = t.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else { return nil }
        let a = String(parts[0]), b = parts.count == 2 ? String(parts[1]) : ""
        let allDigits: (String) -> Bool = { $0.unicodeScalars.allSatisfy { digits.contains($0) } }
        guard allDigits(a), allDigits(b), !(a.isEmpty && b.isEmpty) else { return nil }
        if a.isEmpty && parts.count == 2 && b.isEmpty { return nil }
        guard let n = Double(a.isEmpty ? "0." + b : (b.isEmpty ? a : a + "." + b)), n.isFinite else { return nil }
        return sign * n
    }
}
