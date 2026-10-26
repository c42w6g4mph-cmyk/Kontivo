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
    /// Rechtsform am Anfang («Genossenschaft Migros Ostschweiz») ist Teil des Namens: nur abschneiden, wenn davor schon ein Name steht (Web v223)
    static let rxLegal = BRX("^(.+?\\s(?:AG|GmbH|SA|Sàrl|KG|SE|Ltd|Inc|B\\.V\\.|e\\.\\s?V\\.|Genossenschaft))(?:\\s|$)", i: true)
    static let rxCoopStart = BRX("^Genossenschaft\\s+(?=\\S)", i: true)
    static let rxEllipsis = BRX("\\s*(?:\\.{2,}|…)$")
    static let rxFxTail = BRX("\\s+(?:EUR|USD|GBP|CHF|SEK|NOK|DKK|PLN|CZK|HUF|TRY)\\s*[\\d.,]+$", i: true)
    static let rxEllipsisEnd = BRX("(?:\\.{2,}|…)$")
    static let rxCutWord = BRX("\\S\\s+\\S+(?:\\.{2,}|…)$")
    static let rxCutWordTail = BRX("\\s+\\S+(?:\\.{2,}|…)$")

    /// Leerzeichen zusammenfassen (JS `.replace(/\s+/g," ").trim()`).
    static func squash(_ s: String) -> String { BU.trim(rxSpaces.replaceAll(s, " ")) }

    /// Name kürzen: bis vor Mitteilung/Referenz/IBAN/PLZ Ort, bis zur Rechtsform, höchstens 5 Wörter (Web `bankNameClean`).
    static func clean(_ raw: String) -> String {
        // Originalbetrag in Fremdwährung am Ende weg; von der Bank abgeschnitten («Raiffeisen Pensionskasse Genosse...»):
        // das angeschnittene letzte Wort weglassen (Web v331 ff.)
        var n = rxFxTail.replaceFirst(squash(raw), "")
        if rxEllipsisEnd.test(n) { n = rxCutWord.test(n) ? rxCutWordTail.replaceFirst(n, "") : rxEllipsis.replaceFirst(n, "") }
        if let m = rxCleanCut.match(n) { n = BU.slice(n, 0, m.index) }
        if let lg = rxLegal.match(n) { n = lg.s(1) }
        n = rxCoopStart.replaceFirst(n, "")
        return BU.trim(n.split(separator: " ", omittingEmptySubsequences: false).prefix(5).joined(separator: " "))
    }

    static let rxNameLabel = BRX("(?:Empf(?:ä|ae)nger|Auftraggeber|Beg(?:ü|ue)nstigter|Bezugsort|Zahlungsempf(?:ä|ae)nger)\\s*:\\s*(.+?)(?=\\s+(?:Kto/IBAN|IBAN|Konto|BLZ|Buchungstext|Verwendungszweck|Transaktionsdatum|Karten-?Nr|Referenz)\\b|\\s*,|$)", i: true)
    static let rxNameTo = BRX("(?:issued by|sent money to|received money from|payment to|\\bzahlung an|ebill-zahlung an|e-bill-zahlung an)\\s+(.+?)(?=\\s+with reference|\\s*,|$)", i: true)
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

    static let rxMitteilung = BRX("\\s*,\\s*Mitteilung\\b", i: true)
    static let rxPLZLine = BRX("^(?:[A-Z]{1,2}-?)?\\d{4,5}\\s+[A-Za-zÄÖÜäöü]")
    static let rxHeadLine = BRX("ref\\.?-?\\s?nr|e-?banking|e-?rechnung|^(belastung|gutschrift|zahlungsauftrag|dauerauftrag|lastschrift|vergutung|verguetung)\\b", i: true)
    static let BKDEPT = BRX("^(postfach|case postale|casella postale|po box|c/o|contact ?cent(er|re)|kundendienst|kundenservice|kundencenter|service ?cent(er|re)|customer (care|service)|finanzabteilung|finanzen|abteilung|buchhaltung|debitoren|debitorenbuchhaltung|inkasso|ordnungsbussen|steueramt|zentrale|hauptsitz|miete|mietzins|nebenkosten|prämie|praemie|rechnung)\\b", i: true)
    static let rxColonEnd = BRX(":\\s*$")

    /// Land als ganze Zeile (Web `BKLAND`)
    static let BKLAND = BRX("^(schweiz|suisse|svizzera|switzerland|deutschland|germany|osterreich|oesterreich|austria|liechtenstein|frankreich|france|italien|italia|litauen|niederlande)$")
    static let rxStreetEnd = BRX("(strasse|str\\.|gasse|weg|platz|allee|quai)$", i: true)

    /// Strasse oder Hausnummer (Web `bankStreet`)
    static func street(_ x: String) -> Bool { rxDigit.test(x) || rxStreetEnd.test(x) }

    static let rxMitteilungColon = BRX("mitteilung\\s*:", i: true)
    static let rxLegalEnd = BRX("\\b(ag|gmbh|sa|sarl|kg|ohg|ug|genossenschaft|verein|stiftung|e ?v)\\.?$", i: true)
    static let rxPLZStart = BRX("^\\d{4,5}\\s")
    static let rxLetters3 = BRX("[A-Za-zÄÖÜäöü]{3}")
    static let rxColon = BRX(":")

    /// Einzelposten im Sammelauftrag (Web v272 `bankSubMemo`, TKB): «Vollkasko Audi / Schweizerische Mobiliar …» = Mitteilung, dann Empfänger.
    /// Nur wenn die 2. Zeile ein Name ist (keine Strasse, PLZ, Land) und die 1. Zeile kein Firmenname.
    static func subMemo(_ text: String) -> (memo: String, name: String)? {
        let tl = rxNewlines.split(text.replacingOccurrences(of: "\r", with: "")).map { squash($0) }.filter { !$0.isEmpty }
        if tl.count < 2 || rxMitteilungColon.test(text) { return nil }
        let a = tl[0], b = tl[1]
        if rxLegalEnd.test(a) { return nil }
        if street(b) || rxPLZStart.test(b) || BKLAND.test(Partners.lnorm(b)) || !rxLetters3.test(b) || rxColon.test(a) { return nil }
        // 2. Zeile setzt den Namen fort («Strassenverkehrsamt / des Kantons Thurgau»): keine Mitteilung (Web v331 ff.)
        if rxContinue.test(b) { return nil }
        return (BU.slice(a, 0, 60), b)
    }

    /// Name einer Buchung (Kosten und Einnahmen gleich, Web v272 `bankTxName`): Empfänger/Auftraggeber, sonst aus dem Buchungstext;
    /// nur der erste Teil vor «;» / « · »
    static let rxContinue = BRX("^(des|der|die|den|dem|von|vom|zur|zum|für|fur|du|de|des|di|del|della|of|for|and|und)\\s", i: true)

    static func txName(_ t: BankTx, home: String = "CHF") -> String {
        let nm0 = !t.name.isEmpty && !isType(t.name) ? clean(rxComma.split(t.name)[0]) : from(t.text)
        var nm = BU.trim(rxNameCut.split(nm0)[0])
        // Kürzel vor dem Komma («SC, SwissCaution SA»): der eigentliche Name kommt danach (Web v329)
        if rxShort.test(nm), BankCatalog.tpl(nm, "", home) == nil, let m = BRX("(?:^|\\n)\\s*" + nm + "\\s*,\\s*([^,\\n]{4,})").match(!t.name.isEmpty ? t.name : t.text),
           !isType(m.s(1)) {
            let c = clean(m.s(1))
            if !c.isEmpty { nm = c }
        }
        return nm
    }

    static let rxShort = BRX("^[A-Za-z]{1,3}$")

    static let rxNameCut = BRX(";|\\s·\\s")

    /// Vertragspartner aus dem Buchungstext (Web `bankNameFrom`).
    static func from(_ t: String) -> String {
        let full = rxNewlines.split(t.replacingOccurrences(of: "\r", with: "")).map { squash($0) }.filter { !$0.isEmpty }.joined(separator: " , ")
        // ausdrückliche Bezeichnungen
        if let m = rxNameLabel.match(full), !isType(m.s(1)) { return clean(m.s(1)) }
        if let m = rxNameTo.match(rxMitteilung.split(full)[0]) { return clean(m.s(1)) }
        // Kartenzahlung «… 12.09.2026 03:14 NETFLIX.COM …»: Händler steht nach Datum und Uhrzeit
        if let m = rxNameAfterTime.match(full) {
            let mm = clean(rxComma.split(m.s(1))[0])
            if !mm.isEmpty && !isType(mm) { return mm }
        }
        // Adressblock (Web v272): Name = erste Zeile zwischen Kopfzeile (Ref.-Nr.) und «PLZ Ort». Strasse, Postfach, Abteilung
        // («Contact Center», «Finanzabteilung») und Zweckwörter («Miete») davor werden übersprungen: «Sunrise GmbH / Postfach / 8050 Zürich» → Sunrise GmbH
        let ln = rxNewlines.split(t.replacingOccurrences(of: "\r", with: "")).map { squash($0) }.filter { !$0.isEmpty }
        var pli = -1
        var li = 1
        while li < ln.count {
            if rxPLZLine.test(ln[li]) {
                pli = li
                break
            }
            li += 1
        }
        if pli > 0 {
            var st0 = 0
            for hi in 0..<pli where rxHeadLine.test(ln[hi]) { st0 = hi + 1 }
            var bi = st0
            while bi < pli {
                let cand = ln[bi]
                if street(cand) || BKDEPT.test(cand) || rxColonEnd.test(cand) || isType(cand) {
                    bi += 1
                    continue
                }
                let cn = clean(cand)
                if !cn.isEmpty && !isType(cn) && BU.len(cn) > 2 { return cn }
                break
            }
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
