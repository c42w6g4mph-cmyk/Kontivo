import Foundation

/// Ein Vertrag aus dem CSV-Import (Vertragspartner, Kategorie und Inhaber noch als Namen; IDs setzt `CSV.apply`).
public struct CSVImportItem: Hashable, Sendable {
    public var contract: Contract
    public var partnerName: String
    public var categoryName: String
    public var holderNames: [String]
    /// Adresse des Vertragspartners (mehrzeilig)
    public var address: String
    /// Website des Vertragspartners
    public var web: String
}

/// Vorschau des CSV-Imports. Es wird noch nichts gespeichert (auch keine Kategorien oder Inhaber).
public struct CSVImportPreview: Sendable {
    public var items: [CSVImportItem]
    /// Zeilen ohne Namen
    public var skipped: Int
    /// bereits vorhanden (oder doppelt in der Datei)
    public var duplicates: Int
    /// abgelaufene Verträge, die ins Archiv kommen
    public var archived: Int
    public var newHolderNames: [String]
    public var newCategoryNames: [String]
    /// Anzahl erkannter Spalten
    public var columnCount: Int
    public var hasAmount: Bool
    public var hasName: Bool
    /// Turnus-Zahlen ausserhalb 1/2/3/6/12/24, auf den nächsten erlaubten Turnus gerundet (`cycAdj`)
    public var adjustedCycles: Int
    /// Ungültige Daten (Fälligkeit, Beginn, Ende), ignoriert (`badDates`)
    public var badDates: Int

    /// Mindestens Name und Betrag erkannt?
    public var isUsable: Bool { hasAmount && hasName }

    public static let noColumnsTitle = "Keine passenden Spalten"
    public static let noColumnsText = "Nötig sind mindestens eine Spalte für den Namen (z.B. «Name» oder «Vertragspartner») und eine für den Betrag (z.B. «Kosten»). Am einfachsten: einmal «CSV exportieren» und die Datei als Vorlage nutzen."
    public static let nothingTitle = "Nichts zu importieren"
    public static let confirmButton = "Importieren"
    public static let readError = "Die Datei konnte nicht gelesen werden"

    var skipInfo: [String] {
        var info: [String] = []
        if duplicates > 0 { info.append("\(duplicates) bereits vorhanden") }
        if skipped > 0 { info.append("\(skipped) ohne Namen") }
        return info
    }

    /// Text, wenn nichts übrig bleibt.
    public var nothingText: String {
        skipInfo.isEmpty ? "Die Datei enthält keine Verträge." : "Übersprungen: " + skipInfo.joined(separator: ", ") + "."
    }

    /// «3 Verträge gefunden»
    public var confirmTitle: String {
        "\(items.count)" + (items.count == 1 ? " Vertrag gefunden" : " Verträge gefunden")
    }

    /// Text der Bestätigung.
    public var confirmText: String {
        var t = ""
        if archived > 0 { t += "\(archived) davon sind bereits beendet und kommen ins Archiv.\n" }
        if !skipInfo.isEmpty { t += "Übersprungen: " + skipInfo.joined(separator: ", ") + ".\n" }
        if !newHolderNames.isEmpty { t += "Neue Inhaber: " + newHolderNames.joined(separator: ", ") + ".\n" }
        if !newCategoryNames.isEmpty { t += "Neue Kategorien: " + newCategoryNames.joined(separator: ", ") + ".\n" }
        if adjustedCycles > 0 { t += Format.count(adjustedCycles, "Zahlungsrhythmus", "Zahlungsrhythmen") + " angepasst.\n" }
        if badDates > 0 { t += (badDates == 1 ? "1 ungültiges Datum" : "\(badDates) ungültige Daten") + " ignoriert.\n" }
        return t + "\nBestehende Verträge bleiben unverändert."
    }

    /// Meldung nach dem Import.
    public var doneText: String {
        "\(items.count)" + (items.count == 1 ? " Vertrag importiert — bitte kurz prüfen" : " Verträge importiert — bitte kurz prüfen")
    }
}

/// CSV-Export und -Import (Trennzeichen «;», RFC 4180, UTF-8 mit BOM, Zeilenende CRLF).
public enum CSV {
    // MARK: Export

    /// Dateiname «kontivo-export-JJJJ-MM-TT.csv».
    public static func fileName(today: Day) -> String {
        "kontivo-export-" + today.iso + ".csv"
    }

    /// Spaltennamen (ProMonat_ mit Hauptwährung).
    public static func header(home: Currency) -> [String] {
        ["Vertragspartner", "Bezeichnung", "Kategorie", "Betrag", "Waehrung", "Turnus_Monate", "ProMonat_" + home.rawValue,
         "NaechsteZahlung", "Beginn", "Ende", "Kuendigungsfrist", "Einheit", "Verlaengerung", "KuendigenBis", "Preisverlauf",
         "Kundennummer", "Vertragsnummer", "Inhaber", "Zahlungsart", "BelastetUeber", "KuendigungPer", "Website", "Telefon", "EMail",
         "Status", "KuendbarPer", "Pflichtvertrag", "Notiz", "Sonderzahlungen", "Adresse", "KuendigungsLink"]
    }

    /// Alle Verträge als CSV-Text (mit BOM, CRLF).
    public static func export(_ data: AppData, today: Day) -> String {
        let calc = Calc(data: data, today: today)
        var rows: [String] = [header(home: data.settings.homeCurrency).map { quote($0) }.joined(separator: ";")]
        for c in data.contracts {
            let p = data.partner(c.partnerID)
            let prices = (["Anfang:" + Format.fixed2(c.amount)] + calc.pricesOf(c).map { $0.from.iso + ":" + Format.fixed2($0.amount) }).joined(separator: " | ")
            let extras = calc.extrasOf(c).map { x -> String in
                let note = x.note.replacingOccurrences(of: "|", with: " ").replacingOccurrences(of: ":", with: " ")
                return x.date.iso + ":" + Format.fixed2(x.amount) + (x.note.isEmpty ? "" : ":" + note)
            }.joined(separator: " | ")
            let fields: [String] = [
                p?.name ?? "", c.label, data.category(c.categoryID)?.name ?? "", Format.fixed2(calc.curPrice(c)), c.currency.rawValue, String(c.cycle),
                Format.fixed2(calc.monthlyCost(c)), calc.nextDue(c)?.iso ?? "", c.start?.iso ?? "", calc.effEnd(c)?.iso ?? "",
                String(c.notice), c.noticeUnit.rawValue, c.renewMonths == 0 ? "" : String(c.renewMonths),
                calc.urgency(c).date?.iso ?? "", prices, c.customerNo, c.contractNo, data.holderNames(of: c).joined(separator: ", "),
                c.payMethod, c.payAccount, c.cancelChannel?.webText ?? "", p?.web ?? "", c.tel, c.mail, c.status.rawValue,
                // Frist 0 und «jederzeit» ausdrücklich, damit der Import keine Katalogwerte einsetzt (wie Web)
                c.cancelTerm == .anytime ? (c.end == nil ? "jederzeit" : "") : c.cancelTerm.rawValue,
                c.mandatory ? "ja" : "", c.note, extras, p?.address.text ?? "", c.cancelURL,
            ]
            rows.append(fields.map { quote($0) }.joined(separator: ";"))
        }
        return "\u{FEFF}" + rows.joined(separator: "\r\n")
    }

    /// Export als UTF-8-Daten.
    public static func exportData(_ data: AppData, today: Day) -> Data {
        Data(export(data, today: today).utf8)
    }

    /// Feld nach RFC 4180 quoten, wenn es Trennzeichen, Anführungszeichen oder Zeilenumbrüche enthält.
    public static func quote(_ s: String, delimiter: Character = ";") -> String {
        if s.contains(delimiter) || s.contains("\"") || s.contains("\n") || s.contains("\r") || s.contains("\r\n") {
            return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return s
    }

    // MARK: Lesen

    /// Text einer Datei: UTF-8, sonst Windows-1252 (Excel «CSV (Trennzeichen-getrennt)»), sonst MacRoman.
    public static func decodeText(_ data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        if let s = String(data: data, encoding: .macOSRoman) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    /// Zeilen und Felder. Trennzeichen: Zeile «sep=X» oder das häufigste von «;», «,», Tab in der ersten Zeile (ausserhalb von
    /// Anführungszeichen). `"` öffnet ein Zitat nur am Feldanfang (Fix H1). Leere Zeilen entfallen.
    public static func parse(_ text: String) -> [[String]] {
        var sc = Array(text.unicodeScalars)
        if let f = sc.first, f.value == 0xFEFF { sc.removeFirst() }
        let quoteU: Unicode.Scalar = "\""
        let lf: Unicode.Scalar = "\n"
        let cr: Unicode.Scalar = "\r"
        // erste Zeile
        var firstEnd = 0
        var inQ = false
        while firstEnd < sc.count {
            let ch = sc[firstEnd]
            if ch == quoteU { inQ.toggle() } else if !inQ && (ch == lf || ch == cr) { break }
            firstEnd += 1
        }
        var start = 0
        var delim: Unicode.Scalar = ";"
        let firstLine = String(String.UnicodeScalarView(sc[0..<firstEnd]))
        if firstLine.lowercased().hasPrefix("sep="), firstLine.unicodeScalars.count >= 5 {
            delim = Array(firstLine.unicodeScalars)[4]
            start = firstEnd
            if start < sc.count && sc[start] == cr { start += 1 }
            if start < sc.count && sc[start] == lf { start += 1 }
        } else {
            var counts: [Unicode.Scalar: Int] = [";": 0, ",": 0, "\t": 0]
            var q = false
            for ch in sc[0..<firstEnd] {
                if ch == quoteU { q.toggle(); continue }
                if !q, counts[ch] != nil { counts[ch]! += 1 }
            }
            var best: Unicode.Scalar = ";"
            for cand in [";", ",", "\t"] as [Unicode.Scalar] where (counts[cand] ?? 0) > (counts[best] ?? 0) { best = cand }
            delim = best
        }
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var q = false
        func pushRow() {
            row.append(String(field))
            field = String.UnicodeScalarView()
            if row.contains(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) { rows.append(row) }
            row = []
        }
        var i = start
        while i < sc.count {
            let ch = sc[i]
            if q {
                if ch == quoteU {
                    if i + 1 < sc.count && sc[i + 1] == quoteU {
                        field.append(quoteU)
                        i += 1
                    } else {
                        q = false
                    }
                } else {
                    field.append(ch)
                }
            } else if ch == quoteU && field.isEmpty {
                q = true
            } else if ch == delim {
                row.append(String(field))
                field = String.UnicodeScalarView()
            } else if ch == lf || ch == cr {
                if ch == cr && i + 1 < sc.count && sc[i + 1] == lf { i += 1 }
                pushRow()
            } else {
                field.append(ch)
            }
            i += 1
        }
        pushRow()
        return rows
    }

    // MARK: Werte

    /// Normalisieren für Spaltennamen: klein, ä→ae, ö→oe, ü→ue, ß→ss, nur a–z/0–9.
    public static func norm(_ x: String) -> String {
        let t = x.lowercased().replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
        var out = String.UnicodeScalarView()
        for u in t.unicodeScalars where (u.value >= 0x61 && u.value <= 0x7A) || (u.value >= 0x30 && u.value <= 0x39) { out.append(u) }
        return String(out)
    }

    /// Zahl lesen: «1’234.50», «1.234,50», «12,90», «CHF 12.-», «1.000» (Tausender, Fix L1).
    public static func number(_ x: String) -> Double? {
        var t = String(String.UnicodeScalarView(x.unicodeScalars.filter { u in
            (u.value >= 0x30 && u.value <= 0x39) || u == "," || u == "." || u == "-" || u == "'"
        }))
        t = t.replacingOccurrences(of: "'", with: "")
        if t.isEmpty { return nil }
        let hasComma = t.contains(",")
        let hasDot = t.contains(".")
        if hasComma && hasDot {
            let lc = t.lastIndex(of: ",")!
            let ld = t.lastIndex(of: ".")!
            if lc > ld {
                t = t.replacingOccurrences(of: ".", with: "")
                if let r = t.range(of: ",") { t.replaceSubrange(r, with: ".") }
            } else {
                t = t.replacingOccurrences(of: ",", with: "")
            }
        } else if hasComma || hasDot {
            let sep: Character = hasComma ? "," : "."
            let parts = t.split(separator: sep, omittingEmptySubsequences: false)
            var thousands = false
            if parts.count > 2 {
                thousands = parts.dropFirst().allSatisfy { $0.count == 3 }
            } else if parts.count == 2 {
                let before = parts[0].replacingOccurrences(of: "-", with: "")
                thousands = parts[1].count == 3 && parts[1].allSatisfy({ $0.isNumber }) && (1...3).contains(before.count) && before != "0"
            }
            if thousands {
                t = t.replacingOccurrences(of: String(sep), with: "")
            } else if hasComma, let r = t.range(of: ",") {
                t.replaceSubrange(r, with: ".")
            }
        }
        guard let m = RX.match("^-?(\\d+\\.?\\d*|\\.\\d+)", t), let s = m[0], let v = Double(s), v.isFinite else { return nil }
        return v
    }

    /// Datum lesen: «JJJJ-MM-TT» bzw. «JJJJ/MM/TT» oder «TT.MM.JJ(JJ)» bzw. «TT/MM/JJJJ». Ungültige Tage → nil; zweistellige Jahre > 50 → 19xx;
    /// Monat > 12 und Tag ≤ 12 → US-Format (Fix L2).
    public static func date(_ x: String) -> Day? {
        let t = x.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let m = RX.match("^(\\d{4})[-/](\\d{1,2})[-/](\\d{1,2})", t), let y = Int(m[1] ?? ""), let mo = Int(m[2] ?? ""), let d = Int(m[3] ?? "") {
            return valid(y, mo, d)
        }
        if let m = RX.match("^(\\d{1,2})[./](\\d{1,2})[./](\\d{2,4})", t), var d = Int(m[1] ?? ""), var mo = Int(m[2] ?? ""), var y = Int(m[3] ?? "") {
            if y < 100 { y += y > 50 ? 1900 : 2000 }
            if mo > 12 && d <= 12 { swap(&mo, &d) }
            return valid(y, mo, d)
        }
        return nil
    }

    static func valid(_ y: Int, _ m: Int, _ d: Int) -> Day? {
        guard m >= 1 && m <= 12 && d >= 1 && d <= Day.daysIn(y, m) else { return nil }
        return Day(y, m, d)
    }

    /// Turnus aus Text.
    public enum CycleValue: Hashable, Sendable {
        case months(Int)
        /// alle n Wochen (Betrag wird auf monatlich umgerechnet)
        case weeks(Int)
        /// Zahl ausserhalb 1/2/3/6/12/24 → auf den nächsten erlaubten Turnus gerundet (wird gezählt)
        case adjusted(Int)
    }

    /// Nächster erlaubter Turnus (bei Gleichstand der kleinere, wie Web `csvCycle`).
    static func nearestCycle(_ n: Int) -> CycleValue {
        let ok = [1, 2, 3, 6, 12, 24]
        if ok.contains(n) { return .months(n) }
        var best = 1
        for v in ok where Swift.abs(v - n) < Swift.abs(best - n) { best = v }
        return .adjusted(best)
    }

    /// Turnus lesen: zuerst Zahl + Einheit («12 Monate», «1 Jahr», «2 Wochen», Fix M2), dann Wortregeln.
    public static func cycle(_ x: String) -> CycleValue {
        let t = norm(x)
        if t.isEmpty { return .months(1) }
        if t.allSatisfy({ $0.isNumber }) {
            return nearestCycle(Int(t) ?? 1)
        }
        if let m = RX.match("(\\d+)(monat|month)", t), let n = Int(m[1] ?? "") {
            return nearestCycle(n)
        }
        if let m = RX.match("(\\d+)(jahr|jaehr|year)", t), let n = Int(m[1] ?? "") {
            return nearestCycle(n * 12)
        }
        if let m = RX.match("(\\d+)(woche|week)", t), let n = Int(m[1] ?? ""), n > 0 {
            return .weeks(n)
        }
        if RX.test("woech|week", t) { return .weeks(1) }
        if RX.test("2jahr|zweijaehr|biennial", t) { return .months(24) }
        if RX.test("halbjaehr|halfyear|semiannual|6monat", t) { return .months(6) }
        if RX.test("quartal|quarter|viertel|3monat", t) { return .months(3) }
        if RX.test("2monat|zweimonat|bimonth", t) { return .months(2) }
        if RX.test("jaehr|jahr|year|annual", t) { return .months(12) }
        return .months(1)
    }

    /// Kündbar per lesen.
    public static func term(_ x: String) -> CancelTerm? {
        let t = norm(x)
        if t.isEmpty || RX.test("jederzeit|anytime", t) { return nil }
        if let v = CancelTerm(rawValue: t), v != .anytime { return v }
        if t.contains("periode") { return .period }
        if t.contains("monatsende") || t.contains("monat") { return .monthEnd }
        if t.contains("quartal") { return .quarterEnd }
        if t.contains("halbjahr") { return .halfYearEnd }
        if t.contains("vertragsjahr") { return .contractYear }
        if t.contains("jahresende") || t.contains("jahr") { return .yearEnd }
        return nil
    }

    /// Kategorie aus Stichworten (Standardname) oder "".
    public static func categoryGuess(_ x: String) -> String {
        let t = norm(x)
        if t.isEmpty { return "" }
        let rules: [(String, String)] = [
            ("Gesundheit", "gesund|arzt|zahn|apothek|optik|brille|health"),
            ("Versicherung", "versich|police|haftpflicht|krankenkass|insurance"),
            ("Abos & Medien", "stream|entertain|musik|music|video|software|app|cloud|zeitschrift|zeitung|abo|medien"),
            ("Mobilfunk & Internet", "handy|mobilfunk|internet|telefon|dsl|glasfaser|phone|tv"),
            ("Energie & Wasser", "strom|gas|energie|heiz|wasser|energy"),
            ("Wohnen", "miete|wohn|haus|immobil|nebenkost|rent"),
            ("Freizeit & Sport", "fitness|sport|verein|freizeit|gym"),
            ("Familie & Bildung", "kind|kita|hort|schule|bildung|familie|betreuung|kurs|studium"),
            ("Steuern & Gebühren", "steuer|gebuehr|abgabe|serafe|billag|tax"),
            ("Mobilität", "auto|kfz|bahn|mobilit|leasing|oev|transport|car|parkplatz"),
            ("Finanzen", "bank|konto|kredit|finanz|spar|depot|vorsorge|saeule|finance"),
        ]
        for (name, re) in rules where RX.test(re, t) { return name }
        if RX.test("^(andere|sonstig|other|misc)", t) { return "Sonstiges" }
        return ""
    }

    struct HistEntry {
        var from: Day
        var to: Day
        var amount: Double
    }

    /// Preisverlauf im Format der App «Contract»: «17.02.2025 bis 17.02.2026 404,1 CHF, …».
    static func history(_ txt: String) -> [HistEntry] {
        var out: [HistEntry] = []
        for m in RX.matches("(\\d{1,2}\\.\\d{1,2}\\.\\d{2,4})\\s*bis\\s*(\\d{1,2}\\.\\d{1,2}\\.\\d{2,4})\\s*([\\d'.,]+)", txt) {
            guard let a = number(m[3] ?? ""), let f = date(m[1] ?? ""), let t = date(m[2] ?? "") else { continue }
            out.append(HistEntry(from: f, to: t, amount: a))
        }
        return out.stableSorted { $0.from < $1.from }
    }

    /// Inhaber aus Text (wie Web `csvHolders`): Ganzer Text gleich einem bestehenden Inhaber (z.B. «Anna & Ben») → dieser.
    /// Mit Komma oder aus dem eigenen Export (`ownExport`): nur am Komma trennen, Namen wörtlich. Sonst Trennung an «&», «/», «+»,
    /// «und» mit Nachnamen-Regel («Anna und Ben Müller») und Abgleich auch über den Vornamen.
    public static func holders(_ txt: String, existing: [String], ownExport: Bool = false) -> [String] {
        let whole = txt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let w = existing.first(where: { $0.lowercased() == whole }) { return [w] }
        let kom = ownExport || txt.contains(",")
        let pattern = kom ? "\\s*,\\s*" : "\\s*(?:&|/|\\+|\\bund\\b)\\s*"
        var parts = RX.replace(pattern, in: txt, with: "\u{1F}").components(separatedBy: "\u{1F}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if parts.isEmpty { return [] }
        if !kom {
            let last = parts[parts.count - 1].split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if last.count > 1 {
                let sur = last.dropFirst().joined(separator: " ")
                parts = parts.map { $0.contains(" ") ? $0 : $0 + " " + sur }
            }
        }
        return parts.map { p in
            let lo = p.lowercased()
            let first = lo.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? lo
            return existing.first { h in let hl = h.lowercased(); return hl == lo || (!kom && hl == first) } ?? p
        }
    }

    // MARK: Import

    /// Zielfelder und Spaltennamen (normalisiert, in Reihenfolge).
    static let columnMap: [(String, [String])] = [
        ("partner", ["partner", "anbieter", "vertragspartner", "firma", "unternehmen", "provider", "company", "merchant", "name", "vertragsname"]),
        ("label", ["bezeichnung", "vertrag", "titel", "label", "beschreibung", "abo", "service", "produkt", "abonnement", "name"]),
        ("cat", ["kategorie", "category", "art"]),
        ("amount", ["betrag", "preis", "kosten", "amount", "price", "cost", "costs", "beitrag", "monatsbetrag", "zahlung", "payment"]),
        ("cur", ["waehrung", "wahrung", "currency"]),
        ("cycle", ["turnusmonate", "turnus", "abrechnungsperiode", "abrechnungszeitraum", "zahlungsperiode", "intervall", "zyklus", "rhythmus", "zahlungsintervall", "zahlungsrhythmus", "billingperiod", "frequency", "billingcycle", "interval", "period"]),
        ("due", ["naechstezahlung", "naechsteabbuchung", "naechstefaelligkeit", "faellig", "faelligam", "faelligkeit", "nextpayment", "nextbilling", "nextdue", "zahltag", "abbuchungsdatum"]),
        ("start", ["beginn", "vertragsbeginn", "startdatum", "start", "startdate", "abschlussdatum", "seit"]),
        ("end", ["ende", "vertragsende", "enddatum", "laufzeitende", "laufzeitbis", "enddate"]),
        ("notice", ["kuendigungsfrist", "frist", "notice", "noticeperiod", "cancellationperiod"]),
        ("noticeU", ["einheit"]),
        ("renew", ["verlaengerung", "verlaengerungmonate"]),
        ("cancTerm", ["kuendbarper"]),
        ("mand", ["pflichtvertrag", "pflicht"]),
        ("custNo", ["kundennummer", "kundennr", "customernumber"]),
        ("contrNo", ["vertragsnummer", "vertragsnr", "contractnumber", "policennummer"]),
        ("holders", ["inhaber", "vertragsinhaber", "person", "owner", "holder"]),
        ("payM", ["zahlungsart", "zahlungsmethode", "zahlungsmittel", "paymentmethod"]),
        ("payA", ["belastetueber", "konto", "karte"]),
        ("cancF", ["kuendigungper"]),
        ("cancUrl", ["kuendigungslink", "kuendigungsurl", "cancellink", "cancelurl"]),
        ("web", ["website", "web", "url"]),
        ("tel", ["telefon", "phone"]),
        ("mail", ["email", "mail"]),
        ("note", ["notiz", "notizen", "notes", "note", "bemerkung", "kommentar"]),
        ("addr", ["kuendigungsadresse", "adresse", "address", "anschrift"]),
        ("prices", ["preisverlauf", "kostenhistorien", "kostenhistorie", "preishistorie"]),
        ("tags", ["tags", "schlagworte"]),
        ("contact", ["kontaktdaten", "kontakt", "ansprechpartner"]),
        ("dueDay", ["abbuchungstag", "zahltagimmonat"]),
        ("status", ["status"]),
        ("extras", ["sonderzahlungen", "einmalzahlungen"]),
    ]

    /// Duplikat-Schlüssel: Vertragspartner, Bezeichnung, Betrag, Turnus, Beginn.
    static func dupKey(partner: String, label: String, amount: Double, cycle: Int, start: Day?) -> String {
        [norm(partner), norm(label), Format.fixed2(amount), String(cycle), start?.iso ?? ""].joined(separator: "|")
    }

    /// Vorschau aus einer Datei (Text-Erkennung UTF-8 / Windows-1252).
    public static func preview(csv: Data, data: AppData, today: Day, now: Date = Date()) -> CSVImportPreview {
        preview(rows: parse(decodeText(csv)), data: data, today: today, now: now)
    }

    /// Vorschau aus Zeilen: Verträge erkennen, Duplikate überspringen. Ändert nichts an den Daten.
    public static func preview(rows: [[String]], data: AppData, today: Day, now: Date = Date()) -> CSVImportPreview {
        var res = CSVImportPreview(items: [], skipped: 0, duplicates: 0, archived: 0, newHolderNames: [], newCategoryNames: [],
                                   columnCount: 0, hasAmount: false, hasName: false, adjustedCycles: 0, badDates: 0)
        if rows.count < 2 { return res }
        let head = rows[0].map { norm($0) }
        // eigener Export (Spalten «Turnus_Monate» und «KuendbarPer»): Inhaber nur am Komma trennen
        let ownExport = head.contains("turnusmonate") && head.contains("kuendbarper")
        var col: [String: Int] = [:]
        var taken = Set<Int>()
        for (field, aliases) in columnMap {
            for a in aliases where col[field] == nil {
                if let i = head.firstIndex(of: a), !taken.contains(i) {
                    col[field] = i
                    taken.insert(i)
                }
            }
        }
        res.columnCount = col.count
        res.hasAmount = col["amount"] != nil
        res.hasName = col["partner"] != nil || col["label"] != nil
        func g(_ r: [String], _ k: String) -> String {
            guard let i = col[k], i < r.count else { return "" }
            return r[i].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var have = Set<String>()
        for c in data.contracts {
            have.insert(dupKey(partner: data.partnerName(of: c), label: c.label, amount: c.amount, cycle: c.cycle, start: c.start))
        }
        let home = data.settings.homeCurrency
        let personNames = data.persons.map { $0.name }
        let defaultHolder = personNames.first ?? "Ich"
        var catNames = data.categories.map { $0.name }
        var newCats: [String] = []
        var newHolders: [String] = []

        for r in rows.dropFirst() {
            let partner = g(r, "partner")
            let label = g(r, "label")
            if partner.isEmpty && label.isEmpty {
                res.skipped += 1
                continue
            }
            var amt = number(g(r, "amount")) ?? 0
            let tpl = Catalog.find(partner) ?? Catalog.find(label)
            var cy = 1
            switch cycle(g(r, "cycle")) {
            case .months(let n): cy = n
            case .weeks(let n):
                amt = n == 1 ? Format.round2(amt * 52 / 12) : Format.round2(amt * 52 / 12 / Double(n))
                cy = 1
            case .adjusted(let n):
                cy = n
                res.adjustedCycles += 1
            }
            let curRaw = (g(r, "cur") + " " + g(r, "amount")).uppercased()
            let cur: Currency
            if RX.test("EUR|€", curRaw) { cur = .EUR }
            else if RX.test("USD|US\\$|\\$", curRaw) { cur = .USD }
            else if RX.test("GBP|£", curRaw) { cur = .GBP }
            else if RX.test("TRY|₺|\\bTL\\b", curRaw) { cur = .TRY }
            else if RX.test("CHF|FR", curRaw) { cur = .CHF }
            else { cur = home }

            // Kategorie (neue erst nach Bestätigung, Fix L3)
            var catRaw = g(r, "cat")
            var cat = catNames.first { $0.lowercased() == catRaw.lowercased() && !catRaw.isEmpty } ?? ""
            if cat.isEmpty { cat = categoryGuess(catRaw) }
            if cat.isEmpty, let t = tpl { cat = t.category }
            if !cat.isEmpty && !catNames.contains(cat) {
                catRaw = cat
                cat = ""
            }
            if cat.isEmpty && !catRaw.isEmpty {
                if let ex = catNames.first(where: { $0.lowercased() == catRaw.lowercased() }) {
                    cat = ex
                } else {
                    catNames.append(catRaw)
                    newCats.append(catRaw)
                    cat = catRaw
                }
            }
            if cat.isEmpty { cat = "Sonstiges" }

            // Kündigungsfrist «3 Monate», «1 Jahr», «1 Woche», «1 Tag»
            let nRaw = g(r, "notice")
            var nNum = number(nRaw)
            let unitSrc = g(r, "noticeU").isEmpty ? RX.replace("[\\d\\s.,]", in: nRaw, with: "") : g(r, "noticeU")
            let uRaw = norm(unitSrc)
            var nu: NoticeUnit = .months
            var years = false
            if RX.test("^k|tagimmonat", uRaw) { nu = .dayOfMonth }
            else if RX.test("^w|woche|week", uRaw) { nu = .weeks }
            else if RX.test("jahr|year", uRaw) { years = true }
            else if RX.test("^d|^t|tag|day", uRaw) { nu = .days }
            if years {
                nNum = (nNum ?? 0) * 12
                nu = .months
            }

            // Preisverlauf: eigenes Format «Anfang:… | Datum:…» oder «Contract» («von bis Betrag»)
            var prices: [PriceChange] = []
            var base = amt
            let pv = g(r, "prices")
            let hist = pv.isEmpty ? [] : history(pv)
            if !hist.isEmpty {
                for (i, p) in hist.enumerated() {
                    prices.append(PriceChange(from: p.from, amount: p.amount))
                    let after = p.to.addingDays(1)
                    if i + 1 >= hist.count || hist[i + 1].from > after { prices.append(PriceChange(from: after, amount: amt)) }
                }
                if let st0 = date(g(r, "start")), let f = prices.first, f.from <= st0 {
                    base = f.amount
                    prices.removeFirst()
                }
                var seen = Set<Day>()
                prices = prices.filter { seen.insert($0.from).inserted }
            } else if !pv.isEmpty {
                for part in pv.components(separatedBy: "|") {
                    guard let m = RX.match("^(.+?):\\s*(.+)$", part.trimmingCharacters(in: .whitespacesAndNewlines)),
                          let k = m[1], let vs = m[2], let v = number(vs) else { continue }
                    if RX.test("anfang", k, ignoreCase: true) { base = v } else if let d = date(k) { prices.append(PriceChange(from: d, amount: v)) }
                }
            }

            let tags = g(r, "tags")
            let st = norm(g(r, "status"))
            let mRaw = norm(g(r, "mand"))
            // Katalog nur ohne Spalte (leer ist eine bewusste Angabe)
            let mand = (!mRaw.isEmpty || col["mand"] != nil) ? RX.test("^(ja|yes|1|true|x)$", mRaw) : (RX.test("pflicht", tags, ignoreCase: true) || (tpl?.mandatory ?? false))
            let restTags = tags.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !RX.test("pflicht", $0, ignoreCase: true) }.joined(separator: ", ")
            let hs = g(r, "holders").isEmpty ? [defaultHolder] : holders(g(r, "holders"), existing: personNames, ownExport: ownExport)
            for h in hs where !personNames.contains(h) && !newHolders.contains(h) { newHolders.append(h) }

            var c = Contract(createdAt: now)
            c.label = label
            c.amount = Format.round2(base)
            c.currency = cur
            c.cycle = cy
            // ungültige Daten zählen (Web `bad.n`)
            func dateCounted(_ k: String) -> Day? {
                let raw = g(r, k)
                if raw.isEmpty { return nil }
                let d = date(raw)
                if d == nil { res.badDates += 1 }
                return d
            }
            c.due = dateCounted("due")
            c.start = dateCounted("start")
            c.end = dateCounted("end")
            // Katalogwerte für Frist / Kündbar per nur, wenn die Spalte fehlt (leer, 0 oder «jederzeit» sind bewusste Angaben)
            if let n = nNum {
                c.notice = Int(n)
                c.noticeUnit = nu
            } else if let t = tpl, col["notice"] == nil {
                c.notice = t.notice
                c.noticeUnit = t.noticeUnit
            }
            if let rn = number(g(r, "renew")), rn != 0, Swift.abs(rn) < 1e6 { c.renewMonths = Int(rn) }
            if col["cancTerm"] != nil {
                c.cancelTerm = term(g(r, "cancTerm")) ?? .anytime
            } else if let t = tpl, g(r, "end").isEmpty {
                c.cancelTerm = t.cancelTerm
            }
            if c.end != nil { c.cancelTerm = .anytime }
            c.mandatory = mand
            c.customerNo = g(r, "custNo")
            c.contractNo = g(r, "contrNo")
            c.payMethod = g(r, "payM")
            c.payAccount = g(r, "payA")
            c.cancelChannel = CancelChannel(webText: g(r, "cancF")) ?? tpl?.cancelChannel
            c.cancelURL = g(r, "cancUrl")
            c.tel = g(r, "tel")
            c.mail = g(r, "mail")
            var noteLines: [String] = [g(r, "note")]
            if !g(r, "contact").isEmpty { noteLines.append("Kontakt: " + g(r, "contact")) }
            if !restTags.isEmpty { noteLines.append("Tags: " + restTags) }
            if amt == 0 && g(r, "amount").isEmpty { noteLines.append("Kein Betrag im Import") }
            c.note = noteLines.filter { !$0.isEmpty }.joined(separator: "\n")
            c.prices = prices
            c.extras = g(r, "extras").components(separatedBy: "|").compactMap { p -> ExtraPayment? in
                guard let m = RX.match("^(\\d{4}-\\d{2}-\\d{2}):(-?[\\d.]+):?(.*)$", p.trimmingCharacters(in: .whitespacesAndNewlines)),
                      let d = Day(iso: m[1] ?? ""), let a = Double(m[2] ?? ""), a.isFinite, a != 0 else { return nil }
                return ExtraPayment(date: d, amount: a, note: (m[3] ?? "").trimmingCharacters(in: .whitespaces))
            }
            if RX.test("cancel|gekuend|archiv", st) {
                c.status = .cancelled
                c.cancelledAt = today
            }
            // Nächste Zahlung aus Beginn, Turnus und Abbuchungstag
            if c.due == nil {
                var s0 = c.start ?? today
                var dayN = 0
                if let m = RX.match("^\\s*(\\d+)", g(r, "dueDay")), let ds = m[1], let n = Int(ds) { dayN = n }
                if dayN >= 1 && dayN <= 31 { s0 = Day(s0.year, s0.month, Swift.min(dayN, s0.daysInMonth)) }
                var dd = s0
                var gg = 0
                while dd < today && gg < 600 {
                    gg += 1
                    dd = s0.addingMonths(c.cycleForCalc * gg)
                }
                c.due = dd
            }
            // Abgelaufene Verträge direkt ins Archiv
            if let e = c.end, e < today, c.status != .cancelled {
                c.status = .cancelled
                c.cancelledAt = e
                res.archived += 1
            }
            let key = dupKey(partner: partner, label: label, amount: c.amount, cycle: c.cycle, start: c.start)
            if have.contains(key) {
                res.duplicates += 1
                continue
            }
            have.insert(key)
            let web = g(r, "web").isEmpty ? (tpl?.web ?? "") : g(r, "web")
            // Adresse: mehrzeilig wie im Formular; einzeilig «Firma, Strasse, PLZ Ort» → Zeilen
            let adRaw = g(r, "addr").replacingOccurrences(of: "\r\n", with: "\n")
            let adParts = adRaw.contains("\n") ? adRaw.components(separatedBy: "\n") : adRaw.components(separatedBy: ",")
            let ad = adParts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n")
            res.items.append(CSVImportItem(contract: c, partnerName: partner, categoryName: cat, holderNames: hs, address: ad, web: web))
        }
        res.newCategoryNames = newCats
        res.newHolderNames = newHolders
        return res
    }

    /// Vorschau übernehmen: neue Inhaber und Kategorien anlegen, Vertragspartner finden oder anlegen, Verträge anhängen.
    /// Rückgabe: IDs der neuen Verträge.
    @discardableResult
    public static func apply(_ preview: CSVImportPreview, to data: inout AppData) -> [UUID] {
        for h in preview.newHolderNames where data.person(named: h) == nil {
            data.persons.append(Person(name: h))
        }
        for n in preview.newCategoryNames where !data.categories.contains(where: { $0.name.lowercased() == n.lowercased() }) {
            let col = Category.newColor(existingCount: data.categories.count)
            data.categories.append(Category(name: n, colorHex: col, icon: "tag", kind: Category.kind(forName: n, among: data.categories)))
        }
        var ids: [UUID] = []
        for item in preview.items {
            var c = item.contract
            var pn = item.partnerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let addrText = item.address.replacingOccurrences(of: "\r\n", with: "\n")
            if pn.isEmpty && !addrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // ohne Vertragspartner: Firma aus der Adresse (einzelne Zeile ohne Ziffer vor «PLZ Ort»), sonst Bezeichnung, sonst erste Zeile
                let L = WebImport.lines(addrText)
                let firm = WebImport.addrSplit(addrText, partnerName: L.first).company
                pn = !firm.isEmpty ? firm : (!c.label.isEmpty ? c.label : (L.first ?? ""))
            }
            if !pn.isEmpty {
                if let existing = Partners.find(pn, in: data), let pi = data.partnerIndex(existing.id) {
                    if data.partners[pi].web.isEmpty && !item.web.isEmpty { data.partners[pi].web = item.web }
                    if data.partners[pi].address.isEmpty && !addrText.isEmpty { data.partners[pi].address = WebImport.addrSplit(addrText, partnerName: pn) }
                    c.partnerID = existing.id
                } else {
                    let p = Partner(name: pn, web: item.web, address: addrText.isEmpty ? PostalAddress() : WebImport.addrSplit(addrText, partnerName: pn))
                    data.partners.append(p)
                    c.partnerID = p.id
                }
            }
            if item.categoryName == "Sonstiges" {
                c.categoryID = (data.category(named: "Sonstiges") ?? data.otherCategory)?.id
            } else {
                c.categoryID = (data.category(named: item.categoryName) ?? data.categories.first { $0.name.lowercased() == item.categoryName.lowercased() })?.id
            }
            c.holderIDs = []
            for h in item.holderNames {
                if let p = data.person(named: h) ?? data.persons.first(where: { $0.name.lowercased() == h.lowercased() }), !c.holderIDs.contains(p.id) {
                    c.holderIDs.append(p.id)
                }
            }
            c.id = UUID()
            data.contracts.append(c)
            ids.append(c.id)
        }
        return ids
    }
}
