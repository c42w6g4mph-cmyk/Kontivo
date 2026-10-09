import Foundation

// MARK: - Kontoauszug als Text (PDF-Text oder OCR eines Fotos) – nur nativ, ohne Web-Gegenstück
// Zeilen mit Datum und Betrag werden Buchungen; Folgezeilen ohne Datum ergänzen den Buchungstext.
// Vorzeichen: ausdrücklich (−, «-» hinten, CR/DR, S/H) → Saldo-Verlauf → Spalten «Belastung»/«Gutschrift» → Stichwörter.

extension BankImport {
    /// Liest Buchungen aus Text (PDF/Foto). Weniger als 5 erkannte Buchungen → nil.
    /// `defaultCurrency`: Währung, wenn der Text weder «CHF» noch «EUR» eindeutig nennt.
    public static func readStatementText(_ text: String, defaultCurrency: String) -> BankFile? {
        StatementText.read(text, defaultCurrency: defaultCurrency)
    }
}

enum StatementText {
    /// Ein Betrag in einer Zeile.
    struct Amount {
        var value: Double
        /// -1 Belastung, +1 Gutschrift, 0 ohne Angabe
        var sign: Int
        /// Position in der Zeile (UTF-16), für die Spaltenzuordnung
        var pos: Int
    }

    /// Eine Buchung im Aufbau.
    struct Entry {
        var date: Day
        var text: [String]
        var amounts: [Amount]
        /// Betrag/Saldo stammen aus der Datumszeile (für die Spaltenposition)
        var linePos: Bool
        var amount: Amount?
        var balance: Double?
        /// Saldo der Zeile davor (Saldovortrag), falls bekannt
        var prevBalance: Double?
    }

    // Datum am Zeilenanfang: 31.01.2026, 31.01.26, 2026-01-31, 31/01/2026, 31.01. (Jahr aus dem Dokument)
    static let rxLeadDate = BRX("^\\s*(\\d{1,2}[./]\\d{1,2}[./](?:\\d{4}|\\d{2})(?!\\d)|\\d{4}-\\d{2}-\\d{2}(?!\\d)|\\d{1,2}\\.\\d{1,2}\\.(?![\\d]))")
    // alle Datumsangaben (zum Entfernen vor der Betragssuche)
    static let rxAnyDate = BRX("(?<![\\d.])(?:\\d{1,2}[./]\\d{1,2}[./](?:\\d{4}|\\d{2})|\\d{4}-\\d{2}-\\d{2}|\\d{1,2}\\.\\d{1,2}\\.)(?![\\d])")
    static let rxYear = BRX("(?<!\\d)\\d{1,2}[./]\\d{1,2}[./](\\d{4})(?!\\d)")
    // Betrag mit genau zwei Nachkommastellen: 1'234.50, 1’234.50, 1.234,50, 1,234.50, 79.00-, -39,95, 12.50 CR
    // (Tausender mit normalem Leerzeichen bewusst nicht: «Rechnung 24 123.45» wäre sonst 24'123.45)
    static let rxAmount = BRX("(?<![\\d'’.,])([-−+]\\s?)?(\\d{1,3}(?:['’.,\u{00A0}\u{202F}]\\d{3})+|\\d+)([.,])(\\d{2})(?![\\d%])(\\s?(?:-(?![\\d])|CR\\b|DR\\b|Cr\\b|Dr\\b|S\\b|H\\b))?")
    static let rxSkip = BRX("\\b(saldo|saldovortrag|kontostand|uebertrag|ubertrag|vortrag|total|summe|zwischensumme|balance|seite|page|endsaldo|anfangssaldo|schlusssaldo)\\b")
    static let rxCredit = BRX("\\b(gutschrift|gutschriften|eingang|zahlungseingang|lohn|gehalt|salaer|salar|rente|rueckerstattung|ruckerstattung|rueckverguetung|erstattung|einzahlung|credit|refund|zins gutschrift|ueberweisung von|zahlung von|received)\\b")
    static let rxHeadDebit = BRX("belastung|lastschrift|soll|debit|ausgang|auszahlung", i: true)
    static let rxHeadCredit = BRX("gutschrift|haben|credit|eingang|einzahlung", i: true)
    static let rxHeadSaldo = BRX("saldo|kontostand|balance", i: true)
    static let rxHeadDate = BRX("datum|date|buchung|valuta", i: true)
    static let rxCurrency = BRX("\\b(?:CHF|EUR|USD|GBP|SFr|Fr)\\.?(?=\\s|$)|€")
    static let rxChf = BRX("\\bCHF\\b")
    static let rxEur = BRX("\\bEUR\\b|€")

    static func read(_ raw: String, defaultCurrency: String) -> BankFile? {
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\t", with: "   ")
        let lines = text.components(separatedBy: "\n")
        // Jahr für Daten ohne Jahr («31.01.»): häufigstes Jahr im Text
        var years: [Int: Int] = [:]
        for m in rxYear.matches(text) { if let y = Int(m.s(1)) { years[y, default: 0] += 1 } }
        let docYear = years.max { a, b in a.value != b.value ? a.value < b.value : a.key < b.key }?.key

        // Kopfzeile mit Spalten (Position der Wörter Belastung/Gutschrift/Saldo)
        var debitPos: Int? = nil, creditPos: Int? = nil, hasSaldo = false
        for l in lines.prefix(400) where isHeader(l) {
            if let m = rxHeadDebit.match(l) { debitPos = m.index + m.range.length / 2 }
            if let m = rxHeadCredit.match(l) { creditPos = m.index + m.range.length / 2 }
            if rxHeadSaldo.test(l) { hasSaldo = true }
            break
        }

        var entries: [Entry] = []
        var cur: Entry? = nil
        var cont = 0
        // Saldo aus Saldo-/Vortragszeilen für die nächste Buchung
        var lastSaldo: Double? = nil
        func flush() {
            if let e = cur, !e.amounts.isEmpty { entries.append(e) }
            cur = nil
        }
        for line in lines {
            let l = line.replacingOccurrences(of: "\u{00A0}", with: " ")
            if BU.trim(l).isEmpty { continue }
            let norm = Partners.lnorm(l)
            if let dm = rxLeadDate.match(l), let d = parseDate(dm.s(1), docYear) {
                flush()
                let (amts, rest) = amounts(l, lead: true)
                if rxSkip.test(norm) {
                    lastSaldo = amts.last?.value
                    continue
                }
                cur = Entry(date: d, text: rest.isEmpty ? [] : [rest], amounts: amts, linePos: true, amount: nil, balance: nil, prevBalance: lastSaldo)
                lastSaldo = nil
                cont = 0
                continue
            }
            // Saldo-/Summenzeilen und wiederholte Spaltenköpfe (neue Seite) beenden die Buchung
            if rxSkip.test(norm) || isHeader(l) {
                flush()
                if rxSkip.test(norm) && !isHeader(l) { lastSaldo = amounts(l, lead: false).0.last?.value }
                continue
            }
            guard var e = cur else { continue }
            let (amts, rest) = amounts(l, lead: false)
            if e.amounts.isEmpty && !amts.isEmpty {
                e.amounts = amts
                e.linePos = false
            }
            if !rest.isEmpty && cont < 3 && BU.len(rest) > 1 {
                e.text.append(rest)
                cont += 1
            }
            cur = e
        }
        flush()
        if entries.count < 5 { return nil }

        // Betrag und Saldo: zwei oder mehr Beträge und Saldo-Spalte oder passender Saldo-Verlauf → letzter ist der Saldo
        let multi = entries.filter { $0.amounts.count >= 2 }.count
        var useBalance = hasSaldo && multi >= entries.count / 2
        if !useBalance && multi >= 4 {
            useBalance = balanceFits(entries) >= 0.6
        }
        for i in entries.indices {
            let a = entries[i].amounts
            if useBalance && a.count >= 2 {
                entries[i].amount = a[a.count - 2]
                entries[i].balance = a[a.count - 1].value
            } else {
                entries[i].amount = a[a.count - 1]
            }
        }
        // Reihenfolge des Saldo-Verlaufs (aufsteigend oder neueste zuerst)
        let asc = balanceDirection(entries)
        let signedDoc = entries.contains { ($0.amount?.sign ?? 0) < 0 }
        var tx: [BRawTx] = []
        for (i, e) in entries.enumerated() {
            guard let am = e.amount else { continue }
            // Folgezeilen wie in den CSV-Exporten mit Leerzeichen anhängen («KAUF/DIENSTLEISTUNG VOM … KARTEN NR. … NETFLIX.COM»)
            let body = e.text.joined(separator: " ")
            var sign = am.sign
            if sign == 0, let b = e.balance {
                // Saldo-Verlauf: Saldo − vorheriger Saldo = ± Betrag
                let prevIdx = asc ? i - 1 : i + 1
                let pbOpt = prevIdx >= 0 && prevIdx < entries.count ? entries[prevIdx].balance : (asc ? e.prevBalance : nil)
                if let pb = pbOpt {
                    let diff = b - pb
                    if Swift.abs(diff - am.value) < 0.011 { sign = 1 } else if Swift.abs(diff + am.value) < 0.011 { sign = -1 }
                }
            }
            if sign == 0 && signedDoc { sign = 1 }
            if sign == 0, e.linePos, let dp = debitPos, let cp = creditPos {
                sign = Swift.abs(am.pos - dp) <= Swift.abs(am.pos - cp) ? -1 : 1
            }
            if sign == 0 { sign = rxCredit.test(Partners.lnorm(body)) ? 1 : -1 }
            let v = Double(sign) * am.value
            if v == 0 { continue }
            tx.append(BRawTx(d: e.date, a: v, cur: "", name: "", text: body, kind: BankReader.kind("", body)))
        }
        if tx.count < 5 { return nil }
        // Währung: CHF/EUR im Text, sonst Vorgabe
        let nC = rxChf.count(text), nE = rxEur.count(text)
        let cur0 = nC != nE ? (nC > nE ? "CHF" : "EUR") : defaultCurrency
        for i in tx.indices { tx[i].cur = cur0 }
        let out = BU.sorted(tx.map { $0.tx }) { a, b in a.date < b.date ? -1 : (b.date < a.date ? 1 : 0) }
        return BankFile(bank: "", tx: out, from: out.first?.date, to: out.last?.date, format: "Text")
    }

    /// Spaltenkopf («Datum Text Gutschrift Lastschrift Valuta Saldo»), keine Buchung.
    static func isHeader(_ l: String) -> Bool {
        rxHeadDate.test(l) && (rxHeadDebit.test(l) || rxHeadCredit.test(l) || rxHeadSaldo.test(l)) && !rxLeadDate.test(l)
    }

    /// Datum aus dem Zeilenanfang; «31.01.» mit Jahr aus dem Dokument.
    static func parseDate(_ s: String, _ year: Int?) -> Day? {
        if s.hasSuffix(".") && s.filter({ $0 == "." }).count == 2 {
            guard let y = year else { return nil }
            return BankReader.date(s + String(y))
        }
        return BankReader.date(s)
    }

    static let rxStartDate = BRX("^\\s*(?:\\d{1,2}[./]\\d{1,2}[./](?:\\d{4}|\\d{2})(?!\\d)|\\d{4}-\\d{2}-\\d{2}(?!\\d)|\\d{1,2}\\.\\d{1,2}\\.(?!\\d))\\s*")

    /// Beträge einer Zeile und der übrige Text. Entfernt werden: Buchungs-/Valutadatum am Zeilenanfang (`lead`), Beträge,
    /// Daten nach dem ersten Betrag (Valuta-Spalte) und Währungscodes. Daten im Buchungstext («VOM 11.10.2025») bleiben.
    static func amounts(_ line: String, lead: Bool) -> ([Amount], String) {
        let ns = line as NSString
        var cut: [NSRange] = []
        // Datum (und direkt folgendes Valutadatum) am Zeilenanfang
        if lead {
            var end = 0
            while end < ns.length, let m = rxStartDate.match(ns.substring(from: end)), m.range.length > 0 {
                end += m.range.length
            }
            if end > 0 { cut.append(NSRange(location: 0, length: end)) }
        }
        // Daten durch gleich lange Leerzeichen ersetzen (Positionen bleiben für die Spaltenzuordnung)
        let dates = rxAnyDate.matches(line)
        let blank = NSMutableString(string: line)
        for m in dates.reversed() {
            blank.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
        }
        let l = String(blank)
        var out: [Amount] = []
        var firstAmount = Int.max
        for m in rxAmount.matches(l) {
            let intPart = m.s(2).filter { $0.isNumber }
            guard let v = Double(intPart + "." + m.s(4)) else { continue }
            var sign = 0
            let pre = m.s(1).trimmingCharacters(in: .whitespaces)
            let post = m.s(5).trimmingCharacters(in: .whitespaces).uppercased()
            if pre == "-" || pre == "\u{2212}" || post == "-" || post == "DR" || post == "S" {
                sign = -1
            } else if pre == "+" || post == "CR" || post == "H" {
                sign = 1
            }
            out.append(Amount(value: v, sign: sign, pos: m.index + m.range.length / 2))
            firstAmount = Swift.min(firstAmount, m.index)
            cut.append(m.range)
        }
        for m in dates where m.index >= firstAmount { cut.append(m.range) }
        // Bereiche von hinten ersetzen (überlappende zusammenfassen)
        let text = NSMutableString(string: line)
        var lastStart = Int.max
        for r in cut.sorted(by: { $0.location > $1.location }) {
            let end = Swift.min(r.location + r.length, lastStart)
            if end <= r.location { continue }
            text.replaceCharacters(in: NSRange(location: r.location, length: end - r.location), with: " ")
            lastStart = r.location
        }
        let rest = rxCurrency.replaceAll(String(text), " ")
        return (out, BankName.squash(rest))
    }

    /// Anteil der Paare, bei denen der letzte Betrag als Saldo aufgeht (aufsteigend oder absteigend).
    static func balanceFits(_ es: [Entry]) -> Double {
        var n = 0, up = 0, down = 0
        for i in 1..<Swift.max(es.count, 1) {
            let a = es[i - 1].amounts, b = es[i].amounts
            if a.count < 2 || b.count < 2 { continue }
            n += 1
            let ba = a[a.count - 1].value, bb = b[b.count - 1].value
            let amB = b[b.count - 2].value, amA = a[a.count - 2].value
            if Swift.abs(Swift.abs(bb - ba) - amB) < 0.011 { up += 1 }
            if Swift.abs(Swift.abs(ba - bb) - amA) < 0.011 { down += 1 }
        }
        return n == 0 ? 0 : Double(Swift.max(up, down)) / Double(n)
    }

    /// Saldo-Verlauf aufsteigend (ältester zuerst)? Vergleich, welche Richtung mehr Paare erklärt.
    static func balanceDirection(_ es: [Entry]) -> Bool {
        var up = 0, down = 0
        for i in 1..<Swift.max(es.count, 1) {
            guard let ba = es[i - 1].balance, let bb = es[i].balance, let a = es[i].amount, let a0 = es[i - 1].amount else { continue }
            if Swift.abs(Swift.abs(bb - ba) - a.value) < 0.011 { up += 1 }
            if Swift.abs(Swift.abs(ba - bb) - a0.value) < 0.011 { down += 1 }
        }
        if up != down { return up > down }
        // gleich gut: nach Datum entscheiden
        if let f = es.first, let l = es.last { return f.date <= l.date }
        return true
    }
}
