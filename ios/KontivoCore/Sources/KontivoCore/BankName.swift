import Foundation

// MARK: - Kontoauszug: Vertragspartner aus Name und Buchungstext
// 1:1 nach Web BKPRE, BKTYPEW, bankIsType, bankNameClean, bankNameFrom, BKPROC, bankDesc, bankPretty, BKSTOP, bankTok.

enum BankName {
    static let BKPRE = BRX("^(?:KAUF/DIENSTLEISTUNG|KAUF/ONLINE[- ]SHOPPING|ONLINE[- ]SHOPPING|EINKAUF(?: ZKB)?(?: VISA)?(?: DEBIT)?(?: CARD)?|LASTSCHRIFT|LSV:?|BELASTUNG|E-?RECHNUNG|E-?BILL:?|GIRO (?:AN|AUSLAND|POST|BANK|INTERN)|ZAHLUNG:?|DAUERAUFTRAG:?|SEPA[- ](?:BASIS)?LASTSCHRIFT|FOLGELASTSCHRIFT|ERSTLASTSCHRIFT|KARTENZAHLUNG|DEBITKARTE|UEBERWEISUNG|ÜBERWEISUNG|ZAHLUNGSAUFTRAG|PURCHASE|PAYMENT|VISA-UMSATZ|E-BANKING-AUFTRAG|TO|PAYMENT FROM|TRANSFER TO|TRANSFER FROM|ZAHLUNG VON|AN|VON)\\b[\\s:,.-]*", i: true)

    /// Wörter, aus denen nur die Buchungsart besteht («Belastung e-banking / Ref.-Nr. 123», «QR-Rechnung», «Zahlung Debitkarte»)
    static let BKTYPEW: Set<String> = Set(("belastung gutschrift zahlung zahlungen einkauf warenbezug und dienstleistung dienstleistungen dauerauftrag lsv lastschrift e banking ebanking " +
        "verguetungsauftrag verguetung qr rechnung ebill bill debitkarte kreditkarte karte mastercard visa maestro debit card twint bezug kartenzahlung " +
        "ueberweisung uberweisung sammelauftrag auftrag zahlungsauftrag ref nr referenz purchase payment einzahlung auftragsart finance post giro buchung " +
        "online shopping kauf sepa basislastschrift folgelastschrift erstlastschrift transfer direct transaction issued by of an die der das im per vom " +
        "kartennummer kartenverfuegung verfuegung verfugung vergutungsauftrag vergutung lastschriftverfahren standing order ihr ihre karten xxxx xx x")
        .split(separator: " ").map(String.init))

    static let rxAllDigits = BRX("^\\d+$")

    /// Nur Buchungsart, kein Name (Web `bankIsType`).
    static func isType(_ p: String) -> Bool {
        let w = Partners.lnorm(p).split(separator: " ").map(String.init).filter { !$0.isEmpty }
        if w.isEmpty { return true }
        return w.allSatisfy { x in rxAllDigits.test(x) || (x.count < 2 && w.count > 1) || BKTYPEW.contains(x) }
    }

    static let rxSpaces = BRX("\\s+")
    static let rxCleanCut = BRX("\\s(?:MITTEILUNGEN?|Mitteilungen?:|REFERENZ|Referenz(?:-Nr\\.?)?:?|QR-Referenz|Transaktions(?:-Nr\\.?|datum)|Karten?-?Nr\\.?|Kartennummer|IBAN|Kto/IBAN|Kto|BLZ|Konto-Nr\\.?|CH\\d{2}\\s?\\d|DE\\d{2}\\s?\\d|\\d{4,5}\\s+[A-ZÄÖÜa-zäöü]{2}|Ref\\.|Buchungstext:|Verwendungszweck)")
    static let rxLegal = BRX("^(.*?\\b(?:AG|GmbH|SA|Sàrl|KG|SE|Ltd|Inc|B\\.V\\.|e\\.\\s?V\\.|Genossenschaft))(?:\\s|$)", i: true)

    /// Leerzeichen zusammenfassen (JS `.replace(/\s+/g," ").trim()`).
    static func squash(_ s: String) -> String { BU.trim(rxSpaces.replaceAll(s, " ")) }

    /// Name kürzen: bis vor Mitteilung/Referenz/IBAN/PLZ Ort, bis zur Rechtsform, höchstens 5 Wörter (Web `bankNameClean`).
    static func clean(_ raw: String) -> String {
        var n = squash(raw)
        if let m = rxCleanCut.match(n) { n = BU.slice(n, 0, m.index) }
        if let lg = rxLegal.match(n) { n = lg.s(1) }
        return BU.trim(n.split(separator: " ", omittingEmptySubsequences: false).prefix(5).joined(separator: " "))
    }

    static let rxNameLabel = BRX("(?:Empf(?:ä|ae)nger|Auftraggeber|Beg(?:ü|ue)nstigter|Bezugsort|Zahlungsempf(?:ä|ae)nger)\\s*:\\s*(.+?)(?=\\s+(?:Kto/IBAN|IBAN|Konto|BLZ|Buchungstext|Verwendungszweck|Transaktionsdatum|Karten-?Nr|Referenz)\\b|\\s*,|$)", i: true)
    static let rxNameTo = BRX("(?:issued by|sent money to|received money from|payment to|zahlung an|ebill-zahlung an|e-bill-zahlung an)\\s+(.+?)(?=\\s+with reference|\\s*,|$)", i: true)
    static let rxNameAfterTime = BRX("\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}[ \\t]*/?[ \\t]*\\d{1,2}:\\d{2}(?::\\d{2})?[ \\t]+([A-Za-zÄÖÜäöü][^,]+)")
    static let rxComma = BRX("\\s*,\\s*")
    static let rxParts = BRX("\\s*,\\s*|\\s+/\\s+|\\s·\\s")
    static let rxNewlines = BRX("\\n+")
    static let rxPreText = BRX("^Buchungstext:\\s*", i: true)
    static let rxPreVom = BRX("^VOM \\d{1,2}\\.\\d{1,2}\\.\\d{2,4}\\s*", i: true)
    static let rxPreCard = BRX("^KARTEN?\\s*NR\\.?\\s*[X\\d* ]+?(?=\\s[A-Za-z])\\s*", i: true)
    static let rxPreNr = BRX("^Nr\\.\\s*[x\\d ]+,?\\s*", i: true)
    static let rxPreRef = BRX("^Ref\\.?-?Nr\\.?\\s*[\\d ]+", i: true)
    static let rxPreDigits = BRX("^\\d{6,}\\s*")
    static let rxPreDate = BRX("^\\d{1,2}\\.\\d{1,2}\\.\\d{2,4}(\\s+\\d{1,2}:\\d{2}(:\\d{2})?)?\\s*")

    /// Vertragspartner aus dem Buchungstext (Web `bankNameFrom`).
    static func from(_ t: String) -> String {
        let full = rxNewlines.split(t.replacingOccurrences(of: "\r", with: "")).map { squash($0) }.filter { !$0.isEmpty }.joined(separator: " , ")
        // ausdrückliche Bezeichnungen
        if let m = rxNameLabel.match(full), !isType(m.s(1)) { return clean(m.s(1)) }
        if let m = rxNameTo.match(full) { return clean(m.s(1)) }
        // Kartenzahlung «… 12.09.2026 03:14 NETFLIX.COM …»: Händler steht nach Datum und Uhrzeit
        if let m = rxNameAfterTime.match(full) {
            let mm = clean(rxComma.split(m.s(1))[0])
            if !mm.isEmpty && !isType(mm) { return mm }
        }
        for part in rxParts.split(full) {
            var x = part
            for _ in 0..<6 {
                let o = x
                x = BKPRE.replaceFirst(x, "")
                x = rxPreText.replaceFirst(x, "")
                x = rxPreVom.replaceFirst(x, "")
                x = rxPreCard.replaceFirst(x, "")
                x = rxPreNr.replaceFirst(x, "")
                x = rxPreRef.replaceFirst(x, "")
                x = rxPreDigits.replaceFirst(x, "")
                x = BU.trim(rxPreDate.replaceFirst(x, ""))
                if o == x { break }
            }
            // führende Buchungsart-Wörter weg: «E-Banking Dauerauftrag Immo Seeblick AG» → «Immo Seeblick AG»
            var xw = x.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            while xw.count > 1 && isType(xw[0]) { xw.removeFirst() }
            x = xw.joined(separator: " ")
            if x.isEmpty || isType(x) { continue }
            let c = clean(x)
            if !c.isEmpty && !isType(c) { return c }
        }
        return ""
    }

    /// Kartenbezeichnungen der Zahlungsdienste: «SQ *Muster Bar», «PAYPAL *SPOTIFY», «GOOGLE *YouTube», «PADDLE.NET* NOTION»
    static let BKPROC = BRX("^(?:SQ|SP|SUMUP|SUM UP|PAYPAL|PP|GOOGLE|GOOGLE PAY|STRIPE|PADDLE(?:\\.NET)?|IZ|ZTL|TST|FS|2CO|FASTSPRING|LEMSQZY|LS|DRI|CKO|ADY|ADYEN|NYX|WL|PAYU|MOLLIE|KLARNA|APPLE PAY|WWW)\\s?\\*\\s?(.+)$", i: true)
    static let rxApple = BRX("^apple\\.com/bill|^apple com bill|^itunes\\.com", i: true)
    static let rxAmazon = BRX("^amzn\\s*(mktp|marketplace)|^amazon\\s*(mktp|marketplace|\\.de|\\.ch|eu)", i: true)
    static let rxPrime = BRX("^amzn\\s*prime|^amazon\\s*prime|^prime video", i: true)
    static let rxDescTel = BRX("\\s+(?:\\+?\\d[\\d\\- /]{6,}\\d)(?=\\s|$).*$")
    static let rxDescBranch = BRX("\\s+#?\\d{3,}\\b.*$")
    static let rxDescDomain = BRX("(\\S{3,})\\.(?:com|de|ch|net|io|eu|co\\.uk|tv|app)\\b.*$", i: true)
    static let rxDescCountry = BRX("\\s+\\b(?:CH|DE|AT|NL|IE|LU|GB|US|SE|CHE|DEU|NLD|IRL|LUX|USA)\\b$")

    /// Händlername einer Kartenzahlung aufbereiten (Web `bankDesc`).
    static func desc(_ raw: String) -> String {
        var n = squash(raw).components(separatedBy: "//")[0]
        if let m = BKPROC.match(n) { n = BU.trim(m.s(1)) }
        if rxApple.test(n) { return "Apple" }
        if rxAmazon.test(n) { return "Amazon" }
        if rxPrime.test(n) { return "Amazon Prime" }
        n = rxDescTel.replaceFirst(n, "")              // Telefonnummer und alles danach
        n = rxDescBranch.replaceFirst(n, "")           // Filialnummer
        n = rxDescDomain.replaceFirst(n, "$1")         // NETFLIX.COM LOS GATOS → NETFLIX
        n = BU.trim(rxDescCountry.replaceFirst(n, ""))
        return n
    }

    static let rxUpper3 = BRX("[A-Z]{3}")
    static let rxWordStart = BRX("(^|[\\s\\-/(])([a-zäöü])")
    static let rxDotCom = BRX("\\.com$", i: true)
    static let legalFix: [(BRX, String)] = [(BRX("\\bAg\\b"), "AG"), (BRX("\\bGmbh\\b"), "GmbH"), (BRX("\\bSa\\b"), "SA"),
                                            (BRX("\\bKg\\b"), "KG"), (BRX("\\bSe\\b"), "SE"), (BRX("\\bEv\\b"), "eV")]

    /// GROSSSCHRIFT in Namensschreibweise, Rechtsformen korrekt, «.com» weg (Web `bankPretty`).
    static func pretty(_ raw: String) -> String {
        var s = BU.trim(raw)
        if !s.isEmpty && s == s.uppercased() && rxUpper3.test(s) {
            s = rxWordStart.replaceAll(s.lowercased()) { m in m.s(1) + m.s(2).uppercased() }
        }
        for (r, v) in legalFix { s = r.replaceAll(s, v) }
        return rxDotCom.replaceFirst(s, "")
    }

    static let BKSTOP: Set<String> = ["com", "www", "net", "online", "payment", "payments", "europe", "international", "sca", "bv", "debit", "card", "karte", "nr", "los", "gatos", "stockholm"]

    /// Markante Wörter ohne Ziffern und Füllwörter (Web `bankTok`).
    static func tok(_ s: String) -> [String] {
        Partners.ltok(s).filter { !rxDigit.test($0) && !BKSTOP.contains($0) }
    }

    static let rxDigit = BRX("\\d")
}
