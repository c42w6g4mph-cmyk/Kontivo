import Foundation

// MARK: - Kontoauszug lesen: CSV (Spalten über Stichwörter), camt.052/053/054 (ISO 20022), MT940
// 1:1 nach Web bankDecode, bankDate, bankNum, bankHead, bankBankOf, bankKind, bankKindCamt, bankCsv, bankParent,
// bankGuessCols, bankCamt, bankMt940, bankRead, bankMerge.

/// Buchung während des Lesens (Web-Objekt mit `sub`/`coll` für Sammelbuchungen).
struct BRawTx {
    var d: Day
    var a: Double
    var cur: String
    var name: String
    var text: String
    var type: String = ""
    var cred: String = ""
    var mref: String = ""
    var kind: String = ""
    /// Einzelposten einer Sammelbuchung
    var sub = false
    /// Sammelbuchung mit Einzelposten
    var coll = false

    var tx: BankTx {
        BankTx(date: d, amount: a, currency: cur, name: name, text: text, type: type, kind: BankKind(web: kind), cred: cred, mref: mref)
    }
}

/// Spalten einer CSV-Datei (Web `bankHead` → `col`).
struct BCol {
    var date = -1, sh = -1, sub = -1, amt = -1, deb = -1, cre = -1, cur = -1, payee = -1, payer = -1
    var name = -1, name2 = -1, cred = -1, state = -1, type = -1, prod = -1, mref = -1
    var text: [Int] = []
    var card = false
    var ok = false
    var guess = false
    var head: [String] = []
    var rows: [[String]] = []
}

enum BankReader {
    /// Grösste Datei (Web 20 MB)
    static let maxBytes = 20_000_000

    // MARK: bankDecode

    /// UTF-16 mit BOM, sonst UTF-8 streng, sonst Windows-1252 (Excel). Ein führendes BOM fällt weg (wie TextDecoder).
    static func decode(_ data: Data) -> String {
        let b = [UInt8](data.prefix(3))
        var s: String?
        if b.count >= 2 && b[0] == 0xFF && b[1] == 0xFE {
            s = String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        } else if b.count >= 2 && b[0] == 0xFE && b[1] == 0xFF {
            s = String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if s == nil {
            if b.count >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF {
                s = String(data: data.dropFirst(3), encoding: .utf8)
            } else {
                s = String(data: data, encoding: .utf8)
            }
        }
        if s == nil { s = String(data: data, encoding: .windowsCP1252) }
        if s == nil { s = String(data: data, encoding: .isoLatin1) }
        var t = s ?? ""
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        return t
    }

    // MARK: bankDate

    /// JS `new Date(y, m-1, d)`: Jahre 0–99 zählen als 1900–1999, Überlauf rollt weiter.
    static func jsDate(_ y: Int, _ m: Int, _ d: Int) -> Day {
        Day((y >= 0 && y <= 99) ? y + 1900 : y, m, d)
    }

    static let rxDateISO = BRX("^(\\d{4})-(\\d{1,2})-(\\d{1,2})")
    static let rxDateDMY = BRX("^(\\d{1,2})[./-](\\d{1,2})[./-](\\d{2}|\\d{4})\\b")
    static let rxDateCompact = BRX("^(\\d{4})(\\d{2})(\\d{2})$")

    /// Datum «2026-01-31», «31.01.2026», «31.01.26», «31/01/2026», «01/31/2026» (US), «20260131» → Tag, sonst nil (Web `bankDate`).
    static func date(_ raw: String) -> Day? {
        let s = BU.trim(raw)
        if let m = rxDateISO.match(s) {
            return jsDate(Int(m.s(1)) ?? 0, Int(m.s(2)) ?? 0, Int(m.s(3)) ?? 0)
        }
        if let m = rxDateDMY.match(s) {
            var y = Int(m.s(3)) ?? 0
            var dd = Int(m.s(1)) ?? 0
            var mm = Int(m.s(2)) ?? 0
            if y < 100 { y += 2000 }
            // US-Format MM/TT/JJJJ
            if mm > 12 && dd <= 12, let r = s.range(of: "/"), r.lowerBound > s.startIndex {
                let x = dd
                dd = mm
                mm = x
            }
            if mm > 12 || dd > 31 || mm == 0 || dd == 0 { return nil }
            return jsDate(y, mm, dd)
        }
        if let m = rxDateCompact.match(s) {
            return jsDate(Int(m.s(1)) ?? 0, Int(m.s(2)) ?? 0, Int(m.s(3)) ?? 0)
        }
        return nil
    }

    // MARK: bankNum

    static let rxNumDate = BRX("\\d{1,2}[./-]\\d{1,2}[./-]\\d{2,4}")
    static let rxNumSH = BRX("([\\d\\s])(S|H|DR|CR|D|C|Soll|Haben)\\.?$", i: true)
    static let rxNumSHNeg = BRX("^(S|DR|D|Soll)$", i: true)
    static let rxDigit = BRX("\\d")
    static let rxNumCur = BRX("\\b(?:CHF|EUR|USD|GBP|SFr|Fr|Fr\\.)\\.?", i: true)
    static let rxNumLetters = BRX("[A-Za-z€\\$£\u{00A0}]")
    static let rxQuotesEnds = BRX("^\"+|\"+$")
    static let rxPlusStart = BRX("^\\+")
    static let rxDotsEnds = BRX("^\\.+|\\.+$")
    static let rxParen = BRX("^\\(.*\\)$")
    static let rxSepDot = BRX("[.'’]")
    static let rxSepComma = BRX("[,'’]")

    /// Betrag: «-1'850.00», «1.180,00-», «CHF -49.90», «−12,99 €», «39,95 S»; `dec` = Dezimaltrennzeichen der Datei (Web `bankNum`).
    static func num(_ s: String, _ dec: String = "") -> Double? {
        var t = BU.trim(rxQuotesEnds.replaceAll(s.replacingOccurrences(of: "\u{2212}", with: "-"), ""))
        var neg = false
        // Datum, kein Betrag
        if rxNumDate.test(t) { return nil }
        // Soll/Haben-Kürzel hinten: «39,95 S», «12.50 DR», «20.00 H/CR»
        if let sh = rxNumSH.match(t), rxDigit.test(BU.slice(t, 0, sh.index + 1)) {
            if rxNumSHNeg.test(sh.s(2)) { neg = true }
            t = BU.slice(t, 0, sh.index + 1)
        }
        t = rxNumCur.replaceAll(t, " ")
        t = BU.trim(rxNumLetters.replaceAll(t, ""))
        t = rxPlusStart.replaceFirst(t, "")
        t = BU.trim(rxDotsEnds.replaceAll(t, ""))
        if t.isEmpty { return nil }
        if t.hasSuffix("-") {
            neg = true
            t = BU.trim(BU.slice(t, 0, -1))
        }
        if rxParen.test(t) {
            neg = true
            t = BU.slice(t, 1, -1)
        }
        t = rxPlusStart.replaceFirst(t, "")
        // Dezimaltrennzeichen der Datei: «-1.180» bei Komma-Dateien = 1180
        if dec == "," { t = rxSepDot.replaceAll(t, "") } else if dec == "." { t = rxSepComma.replaceAll(t, "") }
        guard let v = Format.parseNum(t) else { return nil }
        return neg ? -Swift.abs(v) : v
    }

    // MARK: CSV-Spalten (BKCOL)

    static let BKCOL: [String: [String]] = [
        "date": ["buchungsdatum", "buchungstag", "completeddate", "datumdesabschlusses", "abschlussdatum", "buchung", "bookingdate", "bookedat", "datum", "date", "transactiondate", "transaktionsdatum", "starteddate", "startdatum", "datumdesbeginns", "valutadatum", "valuta", "wertstellung", "wertstellungsdatum", "valuedate", "wert"],
        "amt": ["betrag", "umsatz", "amount", "transaktionsbetrag", "nettobetrag", "paymentamount", "buchungsbetrag", "betraginchf", "betragineur", "creditdebitamount", "betragchf", "betrageur", "umsatzineur", "umsatzinchf", "betraginchf", "betragineur", "montant", "importo", "betrag€", "einzelbetrag"],
        "deb": ["belastung", "lastschrift", "soll", "debit", "ausgang", "lastschriftinchf", "belastungchf", "belastungeur", "belastungen", "sollbetrag", "debitamount", "debit chf"],
        "cre": ["gutschrift", "haben", "credit", "eingang", "gutschriftinchf", "gutschriftchf", "gutschrifteur", "gutschriften", "habenbetrag", "creditamount"],
        "cur": ["waehrung", "whg", "whr", "currency", "devise", "valuta waehrung"],
        "name": ["auftraggeberzahlungsempfaenger", "empfaengerzahlungspflichtiger", "senderempfaenger", "auftraggeberbeguenstigter", "nameauftraggeberbeguenstigter", "senderorrecipient", "counterpartyname", "activityname", "empfaenger1", "beguenstigterzahlungspflichtiger", "auftraggeberempfaenger", "namezahlungsbeteiligter", "partnername", "beguenstigterauftraggeber", "begunstigterauftraggeber",
                 "empfaengerauftraggeber", "zahlungsbeteiligter", "gegenpartei", "payee", "merchant", "haendler", "name", "counterparty", "beschreibung1", "empfaenger"],
        "payee": ["zahlungsempfaengerin", "zahlungsempfaenger", "empfaengerin", "beguenstigter", "beguenstigte", "payeename", "recipient"],
        "payer": ["zahlungspflichtiger", "zahlungspflichtigein", "zahlungspflichtige", "auftraggeber", "auftraggeberin", "payername", "sender"],
        "text": ["verwendungszweck", "vorgangverwendungszweck", "transaktionsbeschreibung", "transaktionsbeschreibungzusatz", "buchungsdetails", "reference", "paymentreference", "erscheintaufihrerabrechnungals", "avisierungstext", "buchungstext", "beschreibung2", "beschreibung3", "beschreibung", "description", "text", "zahlungszweck",
                 "details", "mitteilung", "subject", "umsatzart", "vorgang", "texte de notification", "libelle"],
        "cred": ["glaeubigerid", "glaubigerid", "creditorid", "glaeubigeridentifikation"],
        "mref": ["mandatsreferenz", "mandatereference", "mandatereferenz", "mandatsref", "mandateid", "mandatsid"],
        "sh": ["sollhaben", "sh", "dc", "debitcredit", "sollhabenkennzeichen", "kennzeichen", "belastunggutschrift", "gutschriftbelastung", "debitkredit"],
        "sub": ["einzelbetrag", "betragdetail", "betrageinzelzahlung", "betrageinzelzahlungchf", "einzelbetragchf", "betragdetailchf"],
        "state": ["state", "status", "zustand", "info"],
        "type": ["type", "typ", "art", "transaktionstyp", "transactiontype", "transaktionen", "auftragsart", "activitytype", "bewegungstyp", "umsatzart", "umsatztyp", "bookingtype", "buchungsart"],
        "prod": ["product", "produkt"],
    ]

    static let rxHeadBad = BRX("ursprung|original|saldo|balance|fremd|gebuehr|auslagen|kurs|rate|detail|nachbuchung|einzel|gutschriftbelastung|belastunggutschrift|sollhaben|debitkredit")
    static let rxHeadDate = BRX("^(datum|date)|(datum|date)$")
    static let rxHeadNoDate = BRX("geburt|birth|saldo|balance")
    static let rxHeadCard = BRX("^(karte|card|cardnumber|kartennummer|kartennr)")

    /// Kopfzeile erkennen (Web `bankHead`).
    static func head(_ cells: [String]) -> BCol {
        let h = cells.map { CSV.norm($0) }
        var used = Set<Int>()
        var col = BCol()
        func pick(_ k: String, _ loose: Bool = false) -> Int {
            for a in BKCOL[k] ?? [] {
                let na = CSV.norm(a)
                for i in h.indices {
                    if used.contains(i) || h[i].isEmpty { continue }
                    if h[i] == na || (loose && h[i].hasPrefix(na) && !rxHeadBad.test(h[i])) {
                        used.insert(i)
                        return i
                    }
                }
            }
            return -1
        }
        col.date = pick("date")
        col.sh = pick("sh")
        col.sub = pick("sub")
        col.amt = pick("amt")
        col.deb = pick("deb", true)
        col.cre = pick("cre", true)
        if col.amt < 0 { col.amt = pick("amt", true) }
        col.cur = pick("cur", true)
        col.payee = pick("payee")
        col.payer = pick("payer")
        col.name = pick("name")
        col.name2 = pick("name")
        col.cred = pick("cred", true)
        col.state = pick("state")
        col.type = pick("type")
        col.prod = pick("prod")
        col.mref = pick("mref")
        // Rückfall: irgendeine Spalte mit «datum»/«date» (z.B. «Datum/Uhrzeit»)
        if col.date < 0 {
            for di in h.indices where !used.contains(di) && h[di].count <= 24 && !rxDigit.test(h[di]) && rxHeadDate.test(h[di]) && !rxHeadNoDate.test(h[di]) {
                used.insert(di)
                col.date = di
                break
            }
        }
        while true {
            let t = pick("text")
            if t < 0 { break }
            col.text.append(t)
        }
        col.card = h.contains { rxHeadCard.test($0) }
        col.ok = col.date >= 0 && (col.amt >= 0 || col.deb >= 0 || col.cre >= 0) && h.filter { !$0.isEmpty }.count >= 3
        return col
    }

    /// Bank am Spaltenkopf (Web `bankBankOf`).
    static func bankOf(_ head: [String]) -> String {
        let s = "|" + head.map { CSV.norm($0) }.joined(separator: "|") + "|"
        func has(_ x: String) -> Bool { s.contains("|" + x + "|") }
        if has("avisierungstext") { return "PostFinance" }
        if has("beschreibung1") && has("abschlussdatum") { return "UBS" }
        if has("zkbreferenz") { return "ZKB" }
        if has("bookedat") { return "Raiffeisen" }
        if has("wise") && has("spaces") { return "neon" }
        if has("glaeubigerid") && has("auftragskonto") { return "Sparkasse" }
        if has("auftraggeberempfaenger") { return "ING" }
        if has("zahlungsempfaengerin") { return "DKB" }
        if has("umsatzineur") && has("vorgang") { return "comdirect" }
        if has("partnername") { return "N26" }
        if has("beguenstigterauftraggeber") && has("soll") { return "Deutsche Bank" }
        if has("namezahlungsbeteiligter") { return "Volksbank" }
        if (has("product") || has("produkt")) && (has("state") || has("status")) { return "Revolut" }
        return ""
    }

    static let BKBADSTATE = BRX("revert|declin|fail|pending|vorgemerkt|vormerkung|cancel|ausstehend|abgelehnt|rueckgaengig|rückgängig|zurueck|zurück|storniert|fehlgeschlagen|zurückerstattet|in bearbeitung", i: true)
    static let BKBADTYPE = BRX("exchange|umtausch|wechsel|top.?up|aufladung|aufgeladen|einzahlung|^atm$|geldautomat|bargeld|barauszahlung|auszahlung gaa|cashback|bancomat", i: true)
    static let BKBADPROD = BRX("saving|sparen|spar|deposit|pocket|vault|tresor|invest|crypto|krypto", i: true)

    // MARK: bankKind

    static let rxKindCard1 = BRX("kauf dienstleistung|karten nr|kartennr|kartenzahlung|card payment|\\bpos\\b")
    static let rxKindDD = BRX("lastschrift|\\blsv\\b|direct debit|directdebit|e rechnung|erechnung|\\bebill\\b|e bill|\\beinzug\\b|basislastschrift|debit direct")
    static let rxKindSO = BRX("dauerauftrag|standing order|\\bstanding\\b|\\bstdo\\b")
    static let rxKindCard2 = BRX("karte|card|visa|mastercard|maestro|\\bpos\\b|debit mc|kartenzahlung|card payment|\\btwint\\b")
    static let rxKindTR = BRX("ueberweisung|uberweisung|zahlungsauftrag|transfer|giro|e banking|zahlung an")

    /// Zahlungsart: "dd" Lastschrift/eBill, "so" Dauerauftrag, "card" Karte, "tr" Überweisung, "" unbekannt.
    /// `gvc` = MT940-Geschäftsvorfallcode (DK-Liste), sonst Stichwörter aus Typ-Spalte/Buchungstext (Web `bankKind`).
    static func kind(_ gvc: String, _ txt: String) -> String {
        if !gvc.isEmpty {
            let g = BU.num(gvc)
            if (g >= 104 && g <= 107 && g != 106) || g == 109 || g == 5 || g == 4 { return "dd" }
            if g == 117 || g == 152 || g == 8 { return "so" }
            if g == 106 || g == 83 || g == 84 { return "card" }
            if g == 116 || g == 20 || g == 166 { return "tr" }
        }
        let t = Partners.lnorm(txt)
        if t.isEmpty { return "" }
        // eindeutige Kartenkäufe zuerst: PostFinance führt sie als Typ «Lastschrift» («KAUF/DIENSTLEISTUNG … KARTEN NR»)
        if rxKindCard1.test(t) { return "card" }
        if rxKindDD.test(t) { return "dd" }
        if rxKindSO.test(t) { return "so" }
        if rxKindCard2.test(t) { return "card" }
        if rxKindTR.test(t) { return "tr" }
        return ""
    }

    static let rxCamtDD1 = BRX("IDDT|RDDT")
    static let rxCamtDD2 = BRX("ESDD|BBDD|PMDD|UPDD|OODD")
    static let rxCamtSO = BRX("STDO")
    static let rxCamtCard1 = BRX("CCRD|MCRD|DCRD")
    static let rxCamtCard2 = BRX("POSD|CWDL|SMRT|POSP")
    static let rxCamtTR = BRX("ICDT|RCDT")

    /// camt BkTxCd: Domn/Fmly/SubFmly (ISO 20022) oder proprietärer Code (Web `bankKindCamt`).
    static func kindCamt(_ bt: XNode?) -> String {
        guard let bt = bt else { return "" }
        func txt(_ el: XNode?) -> String { el.map { BU.trim($0.textContent).uppercased() } ?? "" }
        let dm = bt.first("Domn")
        let fmE = dm?.first("Fmly")
        let fm = txt(fmE?.first("Cd"))
        let sf = txt(fmE?.first("SubFmlyCd"))
        if rxCamtDD1.test(fm) || rxCamtDD2.test(sf) { return "dd" }
        if rxCamtSO.test(sf) { return "so" }
        if rxCamtCard1.test(fm) || rxCamtCard2.test(sf) { return "card" }
        if rxCamtTR.test(fm) { return "tr" }
        return kind("", txt(bt.first("Prtry")?.first("Cd")))
    }

    // MARK: bankCsv

    static let rxDecComma = BRX(",\\d{1,2}(\\D*)$")
    static let rxDecDot = BRX("\\.\\d{1,3}(\\D*)$")
    static let rxSH = BRX("^(S|H)$", i: true)
    static let rxCollective = BRX("sammel|zahlungen|collective", i: true)
    static let rxCollective2 = BRX("sammel|collective", i: true)
    static let rxSHNeg = BRX("^(s|d|dr|debit|soll|belastung|-)", i: true)
    static let rxSHPos = BRX("^(h|c|cr|credit|haben|gutschrift|\\+)", i: true)
    static let rxCur3 = BRX("[A-Z]{3}")
    static let rxCardPay = BRX("zahlung|payment|dank|thank|gutschrift|ausgleich|lastschrift|einzug|erhalten", i: true)
    static let rxHeadCHF = BRX("\\bCHF\\b", i: true)
    static let rxHeadEUR = BRX("EUR|€", i: true)
    static let rxBodyCHF = BRX("\\bCHF\\b")
    static let rxBodyEUR = BRX("\\bEUR\\b|€")
    static let rxIbanCH = BRX("\\b(?:CH|LI)\\d{2}[ \\d]{4}")
    static let rxIbanEU = BRX("\\b(?:DE|AT|LU|NL|FR|IT|ES|BE|IE)\\d{2}[ \\dA-Z]{4}")

    /// Zelle ohne umschliessende Anführungszeichen, getrimmt (Web `g`).
    static func cell(_ row: [String], _ i: Int) -> String {
        i >= 0 && i < row.count ? BU.trim(rxQuotesEnds.replaceAll(row[i], "")) : ""
    }

    /// Ergebnis von `csv`: Buchungen und Bank, oder `head` (erste Zeile) wenn nicht erkannt.
    struct CsvResult {
        var tx: [BRawTx]
        var bank: String
        var head: String
        var ok: Bool
    }

    /// Letzte Buchung, die selbst kein Einzelposten ist (Web `bankParent`).
    static func parent(_ tx: [BRawTx]) -> Int? {
        var i = tx.count - 1
        while i >= 0 {
            if !tx[i].sub { return i }
            i -= 1
        }
        return nil
    }

    static func csv(_ txt0: String) -> CsvResult {
        let body = txt0.hasPrefix("\u{FEFF}") ? String(txt0.dropFirst()) : txt0
        // Trennzeichen über die ersten Zeilen bestimmen (Vorspann kann kürzer sein)
        var cnt: [String: Int] = [";": 0, ",": 0, "\t": 0]
        for l in BU.lines(body).prefix(60) {
            var q = false
            var c: [String: Int] = [";": 0, ",": 0, "\t": 0]
            for u in l.unicodeScalars {
                let ch = String(u)
                if ch == "\"" { q.toggle() } else if !q, c[ch] != nil { c[ch]! += 1 }
            }
            for (k, v) in c { cnt[k] = Swift.max(cnt[k] ?? 0, v) }
        }
        // jedes Trennzeichen probieren (häufigstes zuerst), das erste mit erkannter Kopfzeile gewinnt
        let dls = BU.sorted([";", "\t", ","]) { a, b in Double((cnt[b] ?? 0) - (cnt[a] ?? 0)) }
        var rows: [[String]]? = nil
        var hi = -1
        var found: BCol? = nil
        for dl in dls where hi < 0 {
            let rs = CSV.parse("sep=" + dl + "\n" + body)
            if rows == nil { rows = rs }
            for r in 0..<Swift.min(rs.count, 60) {
                var c = head(rs[r])
                if c.ok {
                    hi = r
                    c.head = rs[r]
                    found = c
                    rows = rs
                    break
                }
            }
        }
        if hi < 0 {
            found = guessCols(dls, body)
            if let c = found {
                rows = c.rows
                hi = -1
            }
        }
        guard var col = found else {
            let fr = (rows ?? []).first { !BU.trim($0.joined()).isEmpty } ?? []
            return CsvResult(tx: [], bank: "", head: BU.slice(fr.prefix(10).joined(separator: " · "), 0, 160), ok: false)
        }
        let allRows = rows ?? []
        let data = Array(allRows.dropFirst(hi + 1))
        func g(_ row: [String], _ i: Int) -> String { cell(row, i) }
        // Dezimaltrennzeichen aus den Beträgen der Datei
        var dc = 0, ddot = 0
        for row in data.prefix(300) {
            for i in [col.amt, col.deb, col.cre, col.sub] {
                let v = g(row, i)
                if rxDecComma.test(v) { dc += 1 } else if rxDecDot.test(v) { ddot += 1 }
            }
        }
        let dec = dc > ddot ? "," : (ddot > 0 ? "." : "")
        // Soll/Haben-Spalte ohne Namen (alte VR/Fiducia: Kopf « ») über die Werte erkennen
        if col.sh < 0 {
            let w = (hi >= 0 && hi < allRows.count ? allRows[hi] : (data.first ?? [])).count
            var ci = 0
            while ci < w && col.sh < 0 {
                if ci != col.date && ci != col.amt {
                    let vs = data.prefix(200).map { g($0, ci) }.filter { !$0.isEmpty }
                    if vs.count > 5 && vs.allSatisfy({ rxSH.test($0) }) { col.sh = ci }
                }
                ci += 1
            }
        }
        // zwei Namensspalten (Auftraggeber/Empfänger): die mit wechselnden Werten ist der Vertragspartner, die konstante bist du
        var nmCol = col.name
        if col.name2 >= 0 && col.name >= 0 {
            func ds(_ i: Int) -> Int { Set(data.prefix(300).map { g($0, i) }.filter { !$0.isEmpty }).count }
            if ds(col.name2) > ds(col.name) { nmCol = col.name2 }
        }
        var tx: [BRawTx] = []
        var pos = 0, neg = 0
        for row in data {
            let ty = g(row, col.type)
            let text = col.text.map { g(row, $0) }.filter { !$0.isEmpty }.joined(separator: " · ")
            guard let d = date(g(row, col.date)) else {
                // Einzelposten einer Sammelbuchung (UBS «Einzelbetrag», ZKB «Betrag Detail», TKB «Betrag Einzelzahlung», LUKB ohne Datum)
                let last = parent(tx)
                var sv = num(g(row, col.sub), dec)
                if sv == nil { sv = num(g(row, col.deb), dec) }
                if sv == nil { sv = num(g(row, col.amt), dec) }
                if let li = last, BU.truthy(sv), !g(row, col.sub).isEmpty || rxCollective.test(tx[li].text + " " + tx[li].name),
                   !BU.trim(row.joined()).isEmpty {
                    tx[li].coll = true
                    let p = tx[li]
                    tx.append(BRawTx(d: p.d, a: (p.a < 0 ? -1 : 1) * Swift.abs(sv ?? 0), cur: p.cur, name: g(row, nmCol), text: text,
                                     type: "", cred: "", mref: "", kind: p.kind, sub: true))
                }
                continue   // sonst Fusszeilen wie «Kontostand;…»
            }
            // Revolut & Co.: nur abgeschlossene Buchungen vom Hauptkonto, kein Umtausch/Aufladen
            if BKBADSTATE.test(g(row, col.state)) || BKBADTYPE.test(ty) || BKBADPROD.test(g(row, col.prod)) { continue }
            var a: Double? = nil
            let de = num(g(row, col.deb), dec), cr = num(g(row, col.cre), dec)
            if let de = de, de != 0 { a = -Swift.abs(de) } else if let cr = cr, cr != 0 { a = col.guess ? cr : Swift.abs(cr) }
            if a == nil { a = num(g(row, col.amt), dec) }
            guard var amount = a, amount != 0 else {
                // Einzelposten mit Datum (UBS alt): gehört zur vorherigen Sammelbuchung
                let sv2 = num(g(row, col.sub), dec)
                if BU.truthy(sv2), let li = parent(tx),
                   tx[li].coll || rxCollective2.test(tx[li].text + " " + tx[li].name + " " + tx[li].type) {
                    tx[li].coll = true
                    let p = tx[li]
                    tx.append(BRawTx(d: d, a: (p.a < 0 ? -1 : 1) * Swift.abs(sv2 ?? 0), cur: p.cur, name: g(row, nmCol), text: text,
                                     type: ty, cred: "", mref: "", kind: kind("", ty + " " + text), sub: true))
                }
                continue
            }
            let shv = g(row, col.sh)
            if !shv.isEmpty {
                if rxSHNeg.test(shv) { amount = -Swift.abs(amount) } else if rxSHPos.test(shv) { amount = Swift.abs(amount) }
            }
            if amount > 0 { pos += 1 } else { neg += 1 }
            var nm = g(row, nmCol)
            if col.payee >= 0 || col.payer >= 0 {
                let pe = g(row, col.payee), pr = g(row, col.payer)
                let first = amount < 0 ? pe : pr
                nm = !first.isEmpty ? first : (!nm.isEmpty ? nm : (amount < 0 ? pr : pe))
            }
            let cu = rxCur3.match(g(row, col.cur).uppercased())?.s(0) ?? ""
            tx.append(BRawTx(d: d, a: amount, cur: cu, name: nm, text: text, type: ty, cred: g(row, col.cred), mref: g(row, col.mref),
                             kind: kind("", ty + " " + text)))
        }
        // Sammelbuchung mit Einzelposten: nur die Einzelposten zählen
        let subDays = Set(tx.filter { $0.sub }.map { $0.d })
        tx = tx.filter { !($0.coll && subDays.contains($0.d)) }
        // Kreditkarten-Abrechnungen führen Einkäufe positiv: fast alles positiv und die wenigen Belastungen sind Zahlungen an die Karte
        let negs = tx.filter { $0.a < 0 }
        if pos > neg * 3 && !negs.isEmpty
            && Double(negs.filter { rxCardPay.test($0.name + " " + $0.text) }.count) >= Double(negs.count) * 0.6 {
            for i in tx.indices { tx[i].a = -tx[i].a }
        } else if col.card && col.deb < 0 && pos > neg * 4 {
            for i in tx.indices { tx[i].a = -tx[i].a }
        }
        let hc = col.head.joined(separator: "|")
        var cur = rxHeadCHF.test(hc) ? "CHF" : (rxHeadEUR.test(hc) ? "EUR" : "")
        if cur.isEmpty {
            let nC = rxBodyCHF.count(body), nE = rxBodyEUR.count(body)
            if nC != nE {
                cur = nC > nE ? "CHF" : "EUR"
            } else {
                let iC = rxIbanCH.count(body), iE = rxIbanEU.count(body)
                if iC != iE { cur = iC > iE ? "CHF" : "EUR" }
            }
        }
        if !cur.isEmpty { for i in tx.indices where tx[i].cur.isEmpty { tx[i].cur = cur } }
        return CsvResult(tx: tx, bank: col.guess ? "" : bankOf(col.head), head: "", ok: true)
    }

    static let rxLetters2 = BRX("[A-Za-z]{2}")

    /// Datei ohne Kopfzeile (Targobank u.a.): Spalten über die Werte bestimmen – Datum, Betrag(e), längster Text (Web `bankGuessCols`).
    static func guessCols(_ dls: [String], _ body: String) -> BCol? {
        for dl in dls {
            let rs = CSV.parse("sep=" + dl + "\n" + body).filter { $0.count >= 3 }
            if rs.count < 5 { continue }
            let w = rs.prefix(50).map { $0.count }.max() ?? 0
            let S = Array(rs.prefix(200))
            func cell(_ r: [String], _ i: Int) -> String { i < r.count ? BU.trim(r[i]) : "" }
            var dcol = -1
            for i in 0..<w where Double(S.filter({ date(cell($0, i)) != nil }).count) >= Double(S.count) * 0.7 {
                dcol = i
                break
            }
            if dcol < 0 { continue }
            var nums: [Int] = []
            var tcol = -1
            var tl = 0.0
            for k in 0..<w where k != dcol {
                let ne = S.filter { !cell($0, k).isEmpty }
                if ne.isEmpty { continue }
                let nn = ne.filter { r in
                    let v = cell(r, k)
                    return num(v) != nil && rxDigit.test(v) && !rxLetters2.test(v)
                }.count
                if Double(nn) >= Double(ne.count) * 0.9 && Double(ne.count) >= Double(S.count) * 0.2 {
                    nums.append(k)
                } else {
                    let al = Double(ne.reduce(0) { $0 + BU.len(cell($1, k)) }) / Double(ne.count)
                    if al > tl {
                        tl = al
                        tcol = k
                    }
                }
            }
            if nums.isEmpty || tcol < 0 { continue }
            // Saldo-Spalte (fast immer gefüllt) weglassen, wenn es andere Betragsspalten gibt
            if nums.count > 1 {
                let nf = nums.filter { k in Double(S.filter { !cell($0, k).isEmpty }.count) < Double(S.count) * 0.95 }
                if !nf.isEmpty { nums = nf }
            }
            var c = BCol()
            c.date = dcol
            c.text = [tcol]
            c.ok = true
            c.guess = true
            c.rows = rs
            if nums.count == 1 {
                c.amt = nums[0]
            } else {
                c.deb = nums[0]
                c.cre = nums[1]
                // Belastungsspalte mit negativen Werten: Vorzeichen übernehmen
                if S.contains(where: { r in (num(cell(r, nums[0])) ?? 0) < 0 }) {
                    c.amt = nums[0]
                    c.deb = -1
                }
            }
            c.head = []
            return c
        }
        return nil
    }

    // MARK: camt.052/053/054

    static let rxCamtPending = BRX("PDNG|INFO")
    static let rxTrue = BRX("true", i: true)
    static let rxCamtVer = BRX("camt\\.05[234]")
    static let rxXMLEnc = BRX("^(\\s*<\\?xml[^>]*?)encoding\\s*=\\s*[\"'][^\"']*[\"']")

    static func camt(_ txt: String) -> (tx: [BRawTx], fmt: String)? {
        // Text ist schon dekodiert: Kodierungsangabe im Kopf auf UTF-8 setzen (DOMParser ignoriert sie ebenso)
        let fixed = rxXMLEnc.replaceFirst(txt, "$1encoding=\"UTF-8\"")
        guard let doc = XNode.parse(Data(fixed.utf8)) else { return nil }
        var tx: [BRawTx] = []
        let acur = doc.first("Acct")?.first("Ccy")?.textContent ?? ""
        for n in doc.all("Ntry") {
            if let st = n.kid("Sts"), rxCamtPending.test(st.textContent) { continue }
            if rxTrue.test(n.kid("RvslInd")?.textContent ?? "") { continue }   // Storno
            let amt = n.kid("Amt")
            let ind = n.kid("CdtDbtInd")?.textContent
            let sg: Double = ind == "DBIT" ? -1 : 1
            let bd = n.kid("BookgDt") ?? n.kid("ValDt")
            guard let d = date((bd?.first("Dt") ?? bd?.first("DtTm"))?.textContent ?? "") else { continue }
            var cur = acur
            if let a = amt, let c = a.attrs["Ccy"], !c.isEmpty { cur = c }
            let info = n.kid("AddtlNtryInf")?.textContent ?? ""
            let tds = n.all("TxDtls")
            let nk = kindCamt(n.kid("BkTxCd"))
            let amtV = BU.num(amt?.textContent ?? "")
            if tds.isEmpty {
                tx.append(BRawTx(d: d, a: sg * amtV, cur: cur, name: "", text: info, cred: "", kind: !nk.isEmpty ? nk : kind("", info)))
                continue
            }
            for t in tds {
                let ta = t.kid("Amt") ?? t.first("TxAmt")?.first("Amt")
                let v: Double = tds.count > 1 ? (ta.map { BU.num($0.textContent) } ?? BU.r2(amtV / Double(tds.count))) : amtV
                let ti = t.kid("CdtDbtInd")?.textContent ?? ""
                let s2: Double = !ti.isEmpty ? (ti == "DBIT" ? -1 : 1) : sg
                let rp = t.first("RltdPties")
                let party = s2 < 0 ? rp?.kid("Cdtr") : rp?.kid("Dbtr")
                var nm = party?.first("Nm")?.textContent ?? ""
                if nm.isEmpty {
                    let up = s2 < 0 ? rp?.kid("UltmtCdtr") : rp?.kid("UltmtDbtr")
                    nm = up?.first("Nm")?.textContent ?? ""
                }
                let us = t.all("Ustrd").map { $0.textContent }.joined(separator: " ")
                let ad = t.first("AddtlTxInf")?.textContent ?? ""
                let cred = t.first("CdtrSchmeId")?.first("Id")?.textContent ?? ""
                let mref = BU.trim(t.first("MndtId")?.textContent ?? "")
                let tk0 = kindCamt(t.kid("BkTxCd"))
                let tk = !tk0.isEmpty ? tk0 : nk
                let ttx = BU.trim([us, ad, tds.count > 1 ? "" : info].filter { !$0.isEmpty }.joined(separator: " · "))
                var k = tk
                if k.isEmpty { k = !cred.isEmpty ? "dd" : "" }
                if k.isEmpty { k = kind("", info + " " + ttx) }
                tx.append(BRawTx(d: d, a: s2 * v, cur: cur, name: BU.trim(nm), text: ttx, cred: BU.trim(cred), mref: mref, kind: k))
            }
        }
        return (tx, rxCamtVer.match(txt)?.s(0) ?? "camt")
    }

    // MARK: MT940

    static let rxMtSplit = BRX("\\n(?=:61:)")
    static let rxMt60 = BRX(":60[FM]:[CD]\\d{6}([A-Z]{3})")
    static let rxMt61 = BRX("^:61:(\\d{6})(\\d{4})?(R?[CD])[A-Z]?([\\d,]+)")
    static let rxMt86 = BRX("\\n:86:")
    static let rxMtNext = BRX("\\n:\\d\\d[A-Z]?:")
    static let rxMtSub = BRX("\\?\\d\\d")
    static let rxMtField = BRX("\\?(\\d\\d)([^?]*)")
    static let rxSpaces = BRX("\\s+")
    static let rxMtCred = BRX("CRED\\+(\\S{8,35}?)(?=[A-Z]{4}\\+|$|\\s)")
    static let rxMtSvwz = BRX("SVWZ\\+(.*)$")
    static let rxMtTag = BRX("[A-Z]{4}\\+\\S*")
    static let rxMtMref = BRX("MREF\\+(\\S{1,35}?)(?=[A-Z]{4}\\+|$|\\s)")
    static let rxMtGvc = BRX("^(\\d{3})")

    static func mt940(_ txt: String) -> [BRawTx] {
        var cur = ""
        var tx: [BRawTx] = []
        let parts = rxMtSplit.split(txt.replacingOccurrences(of: "\r", with: ""))
        for (pi, p) in parts.enumerated() {
            // Währung je Auszug (mehrere Konten in einer Datei); ein nachfolgender Auszug gilt erst ab der nächsten Buchung
            let cm = rxMt60.matches(p)
            let nextCur = cm.last.map { BU.slice($0.s(0), -3) } ?? cur
            if pi == 0 {
                cur = nextCur
                continue
            }
            guard let m = rxMt61.match(p) else {
                cur = nextCur
                continue
            }
            let ymd = m.s(1)
            let d = date("20" + ymd)
            var raw4 = m.s(4)
            if let r = raw4.range(of: ",") { raw4.replaceSubrange(r, with: ".") }
            let v = BU.num(raw4)
            let code = m.s(3)
            let sg: Double = code.contains("D") != code.hasPrefix("R") ? -1 : 1
            let seg = rxMt86.split(p)
            let after = seg.count > 1 ? seg[1] : ""
            let k86 = (rxMtNext.split(after).first ?? "").replacingOccurrences(of: "\n", with: "")
            guard let day = d else {
                // JS: ungültiges Datum ergibt "" und bleibt drin; hier übersprungen (kommt bei gültigen Dateien nicht vor)
                cur = nextCur
                continue
            }
            if !rxMtSub.test(k86) {
                // unstrukturiertes :86: (CH-Banken)
                let ft = BU.trim(rxSpaces.replaceAll(k86, " "))
                tx.append(BRawTx(d: day, a: sg * v, cur: cur, name: "", text: ft, cred: "", kind: kind("", ft)))
                cur = nextCur
                continue
            }
            var f: [String: String] = [:]
            for fm in rxMtField.matches(k86) { f[fm.s(1), default: ""] += fm.s(2) }
            let purp = ["20", "21", "22", "23", "24", "25", "26", "27", "28", "29", "60", "61", "62", "63"].map { f[$0] ?? "" }.joined()
            let cred = rxMtCred.match(purp)?.s(1) ?? ""
            let sv = rxMtSvwz.match(purp)?.s(1) ?? ""
            let svwz = !sv.isEmpty ? sv : rxMtTag.replaceAll(purp, " ")
            let mref = rxMtMref.match(purp)?.s(1) ?? ""
            let gvc = rxMtGvc.match(k86)?.s(1) ?? ""
            var k = kind(gvc, (f["00"] ?? "") + " " + svwz)
            if k.isEmpty && !cred.isEmpty { k = "dd" }
            tx.append(BRawTx(d: day, a: sg * v, cur: cur, name: BU.trim((f["32"] ?? "") + (f["33"] ?? "")), text: BU.trim(svwz),
                             cred: cred, mref: mref, kind: k))
            cur = nextCur
        }
        return tx
    }

    // MARK: bankRead

    static let rxIsCamt = BRX("<\\s*(\\w+:)?Document[\\s>]")
    static let rxIsMt1 = BRX("(^|\\n):20:")
    static let rxIsMt2 = BRX("\\n:61:")

    static func read(_ data: Data) throws -> BankFile {
        if data.count > maxBytes { throw BankReadError.tooBig }
        if data.isEmpty { throw BankReadError.empty }
        return try read(text: decode(data))
    }

    static func read(text txt: String) throws -> BankFile {
        var raw: [BRawTx]
        var fmt = ""
        var bank = ""
        if rxIsCamt.test(txt) && rxCamtVer.test(txt) {
            guard let r = camt(txt) else { throw BankReadError.notRecognized(firstLine: "") }
            raw = r.tx
            fmt = r.fmt
        } else if rxIsMt1.test(txt) && rxIsMt2.test(txt) {
            raw = mt940(txt)
            fmt = "MT940"
        } else {
            let r = csv(txt)
            if !r.ok { throw BankReadError.notRecognized(firstLine: r.head) }
            raw = r.tx
            bank = r.bank
            fmt = "CSV"
        }
        if raw.isEmpty { throw BankReadError.empty }
        let tx = BU.sorted(raw.map { $0.tx }) { a, b in a.date < b.date ? -1 : (b.date < a.date ? 1 : 0) }
        return BankFile(bank: bank, tx: tx, from: tx.first?.date, to: tx.last?.date, format: fmt)
    }

    // MARK: bankMerge

    /// Mehrere Dateien (Konto, Kreditkarte, zweites Konto …) → eine Buchungsliste; gleiche Buchung in zwei Exporten
    /// desselben Kontos (überlappende Zeiträume) nur einmal.
    static func merge(_ rs: [BankFile]) -> BankFile {
        if rs.count == 1 { return rs[0] }
        var tx: [BankTx] = []
        var seen: [String: Int] = [:]
        for (fi, r) in rs.enumerated() {
            for t in r.tx {
                let src = !r.bank.isEmpty ? r.bank : r.format
                let k = src + "|" + t.date.iso + "|" + String(t.amount) + "|" + BU.slice(Partners.lnorm(t.name + " " + t.text), 0, 60)
                if let s = seen[k], s != fi { continue }
                seen[k] = fi
                tx.append(t)
            }
        }
        tx = BU.sorted(tx) { a, b in a.date < b.date ? -1 : (b.date < a.date ? 1 : 0) }
        return BankFile(bank: "", tx: tx, from: tx.first?.date, to: tx.last?.date, format: rs.map { $0.format }.joined(separator: ", "), files: rs.count)
    }
}

// MARK: - Kleines XML-DOM für camt (wie DOMParser: lokale Namen, textContent)

final class XNode {
    let name: String
    var attrs: [String: String]
    private(set) var children: [XNode] = []
    private var parts: [Part] = []

    private enum Part {
        case text(String)
        case node(XNode)
    }

    init(name: String, attrs: [String: String]) {
        self.name = name
        self.attrs = attrs
    }

    func appendText(_ s: String) {
        if case .text(let t)? = parts.last {
            parts[parts.count - 1] = .text(t + s)
        } else {
            parts.append(.text(s))
        }
    }

    func append(_ n: XNode) {
        children.append(n)
        parts.append(.node(n))
    }

    /// JS `textContent`: aller Text darunter in Dokumentreihenfolge.
    var textContent: String {
        var out = ""
        for p in parts {
            switch p {
            case .text(let t): out += t
            case .node(let n): out += n.textContent
            }
        }
        return out
    }

    /// JS `getElementsByTagNameNS("*", n)`: alle Nachfahren mit diesem lokalen Namen.
    func all(_ n: String) -> [XNode] {
        var out: [XNode] = []
        func walk(_ x: XNode) {
            for c in x.children {
                if c.name == n { out.append(c) }
                walk(c)
            }
        }
        walk(self)
        return out
    }

    /// Erster Nachfahre mit diesem Namen (Web `one`).
    func first(_ n: String) -> XNode? {
        for c in children {
            if c.name == n { return c }
            if let f = c.first(n) { return f }
        }
        return nil
    }

    /// Direktes Kind mit diesem Namen (Web `kid`).
    func kid(_ n: String) -> XNode? { children.first { $0.name == n } }

    /// XML lesen; Fehler → nil. Wurzel ist ein künstlicher Dokumentknoten.
    static func parse(_ data: Data) -> XNode? {
        let p = XMLParser(data: data)
        let d = Builder()
        p.delegate = d
        p.shouldProcessNamespaces = false
        p.shouldResolveExternalEntities = false
        guard p.parse(), !d.failed else { return nil }
        return d.root
    }

    private final class Builder: NSObject, XMLParserDelegate {
        let root = XNode(name: "#document", attrs: [:])
        var stack: [XNode] = []
        var failed = false

        override init() {
            super.init()
            stack = [root]
        }

        static func local(_ q: String) -> String {
            if let i = q.lastIndex(of: ":") { return String(q[q.index(after: i)...]) }
            return q
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?,
                    attributes attributeDict: [String: String] = [:]) {
            var at: [String: String] = [:]
            for (k, v) in attributeDict { at[Builder.local(k)] = v }
            let n = XNode(name: Builder.local(elementName), attrs: at)
            stack.last?.append(n)
            stack.append(n)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if stack.count > 1 { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if stack.count > 1 { stack.last?.appendText(string) }
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            if stack.count > 1 { stack.last?.appendText(String(decoding: CDATABlock, as: UTF8.self)) }
        }

        func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
            failed = true
        }
    }
}
