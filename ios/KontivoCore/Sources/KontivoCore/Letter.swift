import Foundation

/// Bausteine des Kündigungsschreibens (Texte wie in der Web-App).
public struct LetterParts: Hashable, Sendable {
    /// Namen der Unterzeichnenden («Vorname Nachname», sonst Personenname)
    public var names: [String]
    public var signers: [UUID]
    /// Absenderblock: je Adressgruppe «Name1 und Name2», danach deren Adresszeilen (höchstens 7 Zeilen, siehe `senderCut`)
    public var sender: [String]
    /// Hinweis, wenn der Absender gekürzt wurde («Absender gekürzt: …»), sonst leer
    public var senderCut: String = ""
    /// Empfänger: Vertragspartner (wenn nicht schon in der ersten Adresszeile) + Adresszeilen
    public var to: [String]
    /// Ort der Datumszeile (Ort des ersten Unterzeichners)
    public var city: String
    public var subject: String
    /// «Kundennummer: …», «Vertragsnummer: …» (bzw. «Rufnummer»/«Policennummer»/«Versichertennummer», `Letter.contractNumberLabel`)
    public var references: [String]
    public var body: String
    /// Kündigungsfrist (muss bis dann beim Vertragspartner sein)
    public var deadline: Day?
    /// Land des Vertragspartners für Anrede, Gruss und Datum («CH», «DE», «X» = anderes), Web v229 `cc`
    public var country: String = "CH"
    /// Land des (ersten) Absenders, Web `scc`
    public var senderCountry: String = "CH"
    /// Länderzeile, die beim Empfänger ergänzt wurde («DEUTSCHLAND»), sonst leer (Web `cLine`)
    public var countryLine: String = ""

    /// Inhalt des Textfelds: Referenzzeilen + Leerzeile + Text (`ltBodyText`).
    public var bodyText: String {
        (references.isEmpty ? "" : references.joined(separator: "\n") + "\n\n") + body
    }
}

public enum Letter {
    /// Miete erkennen wie Web `isRent`: Mitgliedschaften und Gerätemieten («mieterverband», «gerätemiete», «router», «zähler»,
    /// «parkplatz», «garage») ausgeschlossen; sonst Bezeichnung + Vertragspartner enthalten «miete», «mietvertrag», «mietzins»,
    /// «wohnungsmiete», «mietwohnung», «untermiete», «nebenkosten», oder Kategorie Wohnen und «wohnung», «zimmer», «apartment»,
    /// «vermiet», «verwaltung», «immobilien».
    public static func isRentHeuristic(label: String, partner: String, kind: CategoryKind?) -> Bool {
        let t = (label + " " + partner).lowercased()
        if ["mieterverband", "gerätemiete", "geraetemiete", "router", "zähler", "zaehler", "parkplatz", "garage"].contains(where: { t.contains($0) }) { return false }
        if ["miete", "mietvertrag", "mietzins", "wohnungsmiete", "mietwohnung", "untermiete", "nebenkosten"].contains(where: { t.contains($0) }) { return true }
        if kind == .housing && ["wohnung", "zimmer", "apartment", "vermiet", "verwaltung", "immobilien"].contains(where: { t.contains($0) }) { return true }
        return false
    }

    /// Beschriftung der Vertragsnummer (Web `contrLbl`, v145/v153): Krankenkasse/Grundversicherung → «Versichertennummer»,
    /// Kategorie Versicherung oder «versicherung»/«police» → «Policennummer», Handy (nur Bezeichnung/Vertragspartner) →
    /// «Rufnummer», sonst «Vertragsnummer». Gespeichert wird immer in `contractNo`; gleiche Beschriftung in Formular, Ansicht und Brief.
    public static func contractNumberLabel(label: String, partner: String, categoryName: String, categoryKind: CategoryKind?) -> String {
        let t = (label + " " + categoryName).lowercased()
        if RX.test("krankenkasse|krankenversicher|grundversicherung", t) { return "Versichertennummer" }
        if categoryKind == .insurance || RX.test("versicherung|police", t) { return "Policennummer" }
        if RX.test("handy|natel|smartphone|prepaid|sim-?karte|mobilfunk-?abo|mobile abo", (label + " " + partner).lowercased()) { return "Rufnummer" }
        return "Vertragsnummer"
    }

    /// `contractNumberLabel` für einen Vertrag.
    public static func contractNumberLabel(_ c: Contract, data: AppData) -> String {
        let cat = data.category(c.categoryID)
        return contractNumberLabel(label: c.label, partner: data.partnerName(of: c), categoryName: cat?.name ?? "", categoryKind: cat?.kind)
    }

    /// Alle Beschriftungen, die als Referenzzeile vor dem Brieftext stehen können (Web `REF_RE`).
    public static let referenceLabels = ["Kundennummer", "Vertragsnummer", "Rufnummer", "Policennummer", "Versichertennummer"]

    /// Hinweis Grundversicherung (Web `#ltKvg`, v156): nur bei CHF und Krankenkasse/Grundversicherung/KVG in Bezeichnung,
    /// Vertragspartner oder Kategorie.
    public static let kvgHint = "Grundversicherung (KVG): Die Kündigung wird erst gültig, wenn die neue Krankenkasse deine Aufnahme bestätigt hat – sonst bleibst du beim bisherigen Versicherer."

    public static func showsKvgHint(_ c: Contract, data: AppData) -> Bool {
        c.currency == .CHF && RX.test("krankenkass|grundversich|kvg", [c.label, data.partnerName(of: c), data.category(c.categoryID)?.name ?? ""].joined(separator: " "), ignoreCase: true)
    }

    /// «Fehlt noch — wird beim Vertrag gespeichert» erst zeigen, wenn Kunden- UND Vertragsnummer fehlen (Web v156);
    /// darin dann die Felder, die leer sind.
    public static func showsMissingNumbers(_ c: Contract) -> Bool {
        c.customerNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && c.contractNo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Standard-Unterzeichnende: Inhaber des Vertrags; ohne Inhaber bei genau einer Person diese, sonst niemand.
    public static func defaultSigners(_ c: Contract, data: AppData) -> [UUID] {
        let all = data.persons.map { $0.id }
        let own = c.holderIDs.filter { all.contains($0) }
        if !own.isEmpty { return own }
        return all.count == 1 ? all : []
    }

    /// Bausteine des Briefs.
    public static func parts(_ c: Contract, signers: [UUID]? = nil, calc: Calc) -> LetterParts {
        let data = calc.data
        let sg = signers ?? defaultSigners(c, data: data)
        let partner = data.partner(c.partnerID)
        let pn = (partner?.name ?? "").trimmingCharacters(in: .whitespaces)
        let al = partner?.address.lines ?? []
        let rcc = recipientCountry(c, lines: al, data: data)
        struct P { var name: String; var addr: [String]; var addrNoCountry: [String]; var city: String; var cc: String }
        let ps: [P] = sg.map { h in
            var o = data.resolvedSender(h)
            let sc = senderCountry(o, home: data.settings.homeCurrency)
            // Absender in anderem Land als der Vertragspartner: Land beim Absender ergänzen (fehlt es)
            if o.country.trimmingCharacters(in: .whitespaces).isEmpty && (sc == "CH" || sc == "DE") && sc != rcc { o.country = countryName[sc] ?? "" }
            let n = o.fullName
            var nc = o
            nc.country = ""
            return P(name: n.isEmpty ? (data.person(h)?.name ?? "") : n, addr: o.addressLines, addrNoCountry: nc.addressLines, city: o.city, cc: sc)
        }
        // Absender nach gleicher Adresse gruppiert; mehr als 7 Zeilen: zuerst ohne Land, dann eine Zeile pro Person
        func block(_ noCountry: Bool) -> [String] {
            var groups: [(key: String, names: [String], addr: [String])] = []
            for p in ps {
                let a = noCountry ? p.addrNoCountry : p.addr
                let k = a.joined(separator: "|")
                if let i = groups.firstIndex(where: { $0.key == k }) {
                    groups[i].names.append(p.name)
                } else {
                    groups.append((key: k, names: [p.name], addr: a))
                }
            }
            var out: [String] = []
            for g in groups {
                out.append(g.names.joined(separator: " und "))
                out += g.addr
            }
            return out
        }
        var sender = block(false)
        var sCut = ""
        if sender.count > 7 {
            sender = block(true)
            sCut = "Absender gekürzt: Land weggelassen."
        }
        if sender.count > 7 {
            sender = ps.map { ([$0.name] + $0.addrNoCountry).joined(separator: ", ") }
            sCut = "Absender gekürzt: eine Zeile pro Person."
        }
        if sender.count > 7 {
            sender = Array(sender.prefix(7))
            sCut = "Absender gekürzt: Nicht alle Personen passen in den Absender (höchstens 7 Zeilen)."
        }
        var to: [String] = []
        let firstHasName: Bool = al.first.map { $0.lowercased().contains(pn.lowercased()) } ?? false
        if !pn.isEmpty && !firstHasName { to.append(pn) }
        to += al
        // Auslandsbrief: Bestimmungsland als letzte Zeile in Grossbuchstaben (Post CH/DE), nur wenn noch keine Länderzeile da ist
        let scc = ps.first?.cc ?? senderCountry(SenderAddress(), home: data.settings.homeCurrency)
        var cLine = ""
        if !al.isEmpty, scc != rcc, let up = countryUpper[rcc], let lastLine = to.last, countryOf(line: lastLine).isEmpty, !RX.test("^[A-ZÄÖÜ ]{4,}$", lastLine) {
            cLine = up
            to.append(up)
        }
        var refs: [String] = []
        if !c.customerNo.isEmpty { refs.append("Kundennummer: " + c.customerNo) }
        if !c.contractNo.isEmpty { refs.append(contractNumberLabel(c, data: data) + ": " + c.contractNo) }
        let e = calc.termEnd(c)
        let d = calc.noticeDeadline(c)
        let we = ps.count > 1
        // Anrede, Gruss nach Land des Vertragspartners (Web v229): CH ohne Komma, danach gross; sonst mit Komma, danach klein
        let deL = rcc != "CH"
        let body = "Sehr geehrte Damen und Herren" + (deL ? "," : "") + "\n\n" + (deL ? "hiermit " : "Hiermit ") + (we ? "kündigen wir" : "kündige ich") + " den oben genannten Vertrag ordentlich zum nächstmöglichen Termin"
            + (e != nil ? ", nach " + (we ? "unserer" : "meiner") + " Berechnung zum " + Format.fmtD(e) : "") + ".\n\n"
            + "Bitte bestätigen Sie " + (we ? "uns" : "mir") + " die Kündigung und das Vertragsende schriftlich.\n\n" + (deL ? "Mit freundlichen Grüßen" : "Freundliche Grüsse")
        var lp = LetterParts(names: ps.map { $0.name }, signers: sg, sender: sender, senderCut: sCut, to: to, city: ps.first?.city ?? "",
                             subject: subject(c, data: data), references: refs, body: body, deadline: d)
        lp.country = rcc
        lp.senderCountry = scc
        lp.countryLine = cLine
        return lp
    }

    // MARK: Land für Brief-Konventionen (Web v229)

    static let countryName = ["CH": "Schweiz", "DE": "Deutschland"]
    static let countryUpper = ["CH": "SCHWEIZ", "DE": "DEUTSCHLAND"]

    /// Länderzeile → «CH»/«DE», sonst "" (Web `ccLine`)
    public static func countryOf(line l: String) -> String {
        let t = l.trimmingCharacters(in: .whitespaces)
        if RX.test("^(schweiz|suisse|svizzera|switzerland|ch)$", t, ignoreCase: true) { return "CH" }
        if RX.test("^(deutschland|germany|allemagne|de|brd)$", t, ignoreCase: true) { return "DE" }
        return ""
    }

    /// Land aus Adresszeilen (Web `ccFromLines`): Länderzeile, sonst «X» bei anderer Länderzeile nach PLZ-Zeile, sonst PLZ (4 Stellen CH, 5 DE)
    public static func countryOf(lines: [String]) -> String {
        let L = lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let last = L.last else { return "" }
        let cl = countryOf(line: last)
        if !cl.isEmpty { return cl }
        // letzte Zeile ohne Ziffern nach einer PLZ-Zeile = anderes Land (z.B. «Niederlande»)
        if L.count > 1 && !RX.test("\\d", last) && RX.test("\\d", L[L.count - 2]) { return "X" }
        for l in L.reversed() {
            if let m = RX.match("^(?:(CH|D|DE)[-\\s])?(\\d{4,5})\\s+\\S", l, ignoreCase: true) {
                if m.count > 1, let p = m[1], !p.isEmpty { return p.lowercased() == "ch" ? "CH" : "DE" }
                return (m.count > 2 ? (m[2] ?? "") : "").count == 5 ? "DE" : "CH"
            }
        }
        return ""
    }

    /// Land des Vertragspartners (Web `ltRecvCC`): Adresse > Katalog > Währung > Hauptwährung
    public static func recipientCountry(_ c: Contract, lines: [String], data: AppData) -> String {
        let cc = countryOf(lines: lines)
        if !cc.isEmpty { return cc }
        if let t = Catalog.match(names: [data.partnerName(of: c), c.label], currency: c.currency), t.country == "CH" || t.country == "DE" { return t.country }
        if c.currency == .EUR { return "DE" }
        if c.currency == .CHF { return "CH" }
        return data.settings.homeCurrency == .EUR ? "DE" : "CH"
    }

    /// Land eines Absenders (Web `ltSendCC`): Länderzeile, sonst PLZ, sonst Hauptwährung
    public static func senderCountry(_ o: SenderAddress, home: Currency) -> String {
        let cl = countryOf(line: o.country)
        if !cl.isEmpty { return cl }
        if !o.country.trimmingCharacters(in: .whitespaces).isEmpty { return "X" }
        let z = o.zip.trimmingCharacters(in: .whitespaces)
        if RX.test("^\\d{5}$", z) { return "DE" }
        if RX.test("^\\d{4}$", z) { return "CH" }
        return home == .EUR ? "DE" : "CH"
    }

    static let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember"]

    /// Ort und Datum (Web `ltDate`): Schweiz «Kreuzlingen, 24. Oktober 2026», sonst «Konstanz, 24.10.2026»
    public static func dateLine(country: String, city: String, today d: Day) -> String {
        (city.isEmpty ? "" : city + ", ")
            + (country == "CH" ? "\(d.day). \(monthNames[d.month - 1]) \(d.year)" : String(format: "%02d.%02d.%d", d.day, d.month, d.year))
    }

    /// Anrede (Web v156/v229): ausserhalb der Schweiz mit Komma und danach klein («hiermit»), Schweiz ohne Komma, danach gross.
    public static func salutation(_ currency: Currency) -> String {
        "Sehr geehrte Damen und Herren" + (currency == .EUR ? "," : "")
    }

    /// Betreff «Kündigung <Bezeichnung oder Vertragspartner>[ bei <Vertragspartner>]»;
    /// « bei …» entfällt, wenn die Bezeichnung den Vertragspartner schon enthält (Fix F14).
    public static func subject(_ c: Contract, data: AppData) -> String {
        let pn = data.partnerName(of: c)
        let main = c.label.isEmpty ? pn : c.label
        var s = "Kündigung " + main
        if !c.label.isEmpty && !pn.isEmpty && !c.label.lowercased().contains(pn.lowercased()) { s += " bei " + pn }
        return s
    }

    /// Hinweise unter dem Brief (Sätze in dieser Reihenfolge).
    public static func hints(_ c: Contract, parts: LetterParts, calc: Calc) -> [String] {
        var h: [String] = []
        // Fix F4: Frist = Zugang beim Vertragspartner, nicht Absendetermin
        if let d = parts.deadline {
            h.append("Muss spätestens am " + Format.fmtD(d) + " beim Vertragspartner sein. Per Post einige Werktage vorher absenden, am besten eingeschrieben.")
        }
        if !parts.senderCut.isEmpty && !parts.signers.isEmpty { h.append(parts.senderCut) }
        if c.holderIDs.count > 1 && parts.signers.count < c.holderIDs.count {
            h.append("Gemeinsamer Vertrag: In der Regel müssen alle Vertragsparteien kündigen.")
        }
        if calc.isRent(c) {
            h.append("Mietverträge verlangen Schriftform mit eigenhändiger Unterschrift (CH Art. 266l OR, DE § 568 BGB).")
            if parts.signers.count < 2 {
                h.append("Familienwohnung in der Schweiz: Ehe- oder eingetragene Partner müssen ausdrücklich zustimmen, am besten mitunterschreiben (Art. 266m OR).")
            }
        }
        h.append("Vorlage ohne Gewähr. Prüf Adresse, Frist und die im Vertrag verlangte Form.")
        return h
    }

    /// Hinweiskasten statt Unterschriften bei Miete.
    public static func rentSignatureNote(signerCount: Int) -> String {
        "Mietvertrag: PDF ausdrucken, von Hand unterschreiben" + (signerCount > 1 ? " (alle Mieter)" : "") +
            " und per Post senden, am besten eingeschrieben. Eine eingefügte Unterschrift oder eine E-Mail genügt hier nicht."
    }

    /// Unterzeichnende ohne vollständigen Absender (`sndOk`).
    public static func signersMissingAddress(_ signers: [UUID], data: AppData) -> [UUID] {
        signers.filter { !data.resolvedSender($0).isComplete }
    }

    /// Absenderzeile im Brief-Fenster: «Absender: …» bzw. «Wer kündigt? Bitte oben wählen.» (fett: erster Teil).
    public static func senderLine(_ parts: LetterParts) -> (bold: String, text: String) {
        if parts.signers.isEmpty { return ("Wer kündigt?", " Bitte oben wählen.") }
        return ("Absender:", " " + parts.sender.joined(separator: ", "))
    }

    /// Text der Rückfrage bei unvollständigem Absender.
    public static func missingSenderText(_ names: [String]) -> String {
        "Bei " + names.joined(separator: " und ") + " fehlt die Adresse. Der Vertragspartner kann die Kündigung so schlechter zuordnen."
    }

    /// Mailtext («Als E-Mail-Text»): Referenzen, Text, Namen (+ Absenderzeilen ab der zweiten).
    public static func mailText(references: [String], body: String, names: [String], sender: [String]) -> String {
        let namesBlock = names.joined(separator: "\n") + (sender.count > 1 ? "\n" + sender.dropFirst().joined(separator: "\n") : "")
        return [references.joined(separator: "\n"), body, namesBlock].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Mailtext für «Per E-Mail kündigen» aus dem Detail (Web v143): Referenzen, Text, Namen und – mit Unterzeichnenden –
    /// die Adresszeilen des Absenders (ab der zweiten Zeile).
    public static func directMailText(_ parts: LetterParts) -> String {
        let names = parts.names.joined(separator: "\n") + (parts.sender.count > 1 && !parts.signers.isEmpty ? "\n" + parts.sender.dropFirst().joined(separator: "\n") : "")
        return [parts.references.joined(separator: "\n"), parts.body, names].filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// Prüfung vor «Per E-Mail kündigen» (Web v143, gleiche Regeln wie beim Brief), in dieser Reihenfolge.
    public enum MailCheck: Equatable, Sendable {
        /// Keine Person beim Vertrag: «Wer kündigt?» – «Person eintragen» / «Trotzdem senden»
        case noSigner
        /// Absender ohne Adresse: «Absender unvollständig» – «Adresse ergänzen» (erste Person) / «Trotzdem senden»
        case senderIncomplete([UUID])
        /// Weder Kunden- noch Vertragsnummer: «Kundennummer fehlt» – «Nummer eintragen» / «Ohne senden»
        case numberMissing
    }

    /// Offene Rückfragen vor dem Mailversand (Web: nacheinander, «Trotzdem/Ohne senden» geht zur nächsten).
    public static func mailChecks(_ c: Contract, data: AppData) -> [MailCheck] {
        var out: [MailCheck] = []
        let sg = defaultSigners(c, data: data)
        if sg.isEmpty {
            out.append(.noSigner)
        } else {
            let miss = signersMissingAddress(sg, data: data)
            if !miss.isEmpty { out.append(.senderIncomplete(miss)) }
        }
        if c.customerNo.isEmpty && c.contractNo.isEmpty { out.append(.numberMissing) }
        return out
    }

    /// Titel, Text und Knöpfe der Rückfragen (Web v143).
    public static func mailCheckTexts(_ check: MailCheck, data: AppData) -> (title: String, text: String, ok: String, no: String) {
        switch check {
        case .noSigner:
            return ("Wer kündigt?", "Beim Vertrag ist keine Person hinterlegt. Ohne Namen und Adresse kann der Vertragspartner die Kündigung schlecht zuordnen.",
                    "Person eintragen", "Trotzdem senden")
        case .senderIncomplete(let ids):
            return ("Absender unvollständig", missingSenderText(ids.compactMap { data.person($0)?.name }), "Adresse ergänzen", "Trotzdem senden")
        case .numberMissing:
            return ("Kundennummer fehlt", "Mit Kunden- oder Vertragsnummer kann der Vertragspartner die Kündigung sicher zuordnen.", "Nummer eintragen", "Ohne senden")
        }
    }

    /// Referenzzeilen am Anfang eines bearbeiteten Texts abtrennen («Kundennummer: », «Vertragsnummer: », «Rufnummer: » …, Web `REF_RE`).
    public static func splitReferences(_ text: String) -> (references: [String], body: String) {
        var lines = text.components(separatedBy: "\n")
        var refs: [String] = []
        while let f = lines.first, referenceLabels.contains(where: { f.hasPrefix($0 + ": ") }) {
            refs.append(f)
            lines.removeFirst()
        }
        return (refs, lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Dateiname «Kuendigung-<Vertragspartner|Bezeichnung|Vertrag>-<JJJJ-MM-TT>.pdf»; Umlaute umschreiben (Fix F14), sonst «_».
    public static func pdfFileName(_ c: Contract, data: AppData, today: Day) -> String {
        let pn = data.partnerName(of: c)
        let base = !pn.isEmpty ? pn : (!c.label.isEmpty ? c.label : "Vertrag")
        return "Kuendigung-" + fileSafe(base) + "-" + today.iso + ".pdf"
    }

    /// Titel des Viewers «Kündigung · <Vertragspartner|Bezeichnung|Vertrag>».
    public static func viewerTitle(_ c: Contract, data: AppData) -> String {
        let pn = data.partnerName(of: c)
        return "Kündigung · " + (!pn.isEmpty ? pn : (!c.label.isEmpty ? c.label : "Vertrag"))
    }

    static func fileSafe(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe").replacingOccurrences(of: "ü", with: "ue")
            .replacingOccurrences(of: "Ä", with: "Ae").replacingOccurrences(of: "Ö", with: "Oe").replacingOccurrences(of: "Ü", with: "Ue")
            .replacingOccurrences(of: "ß", with: "ss")
        var stripped = String.UnicodeScalarView()
        for u in t.decomposedStringWithCanonicalMapping.unicodeScalars where !(u.value >= 0x300 && u.value <= 0x36F) { stripped.append(u) }
        t = String(stripped)
        var out = ""
        var lastUnderscore = false
        for u in t.unicodeScalars {
            let v = u.value
            let ok = (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || v == 0x5F || v == 0x2D
            if ok {
                out.unicodeScalars.append(u)
                lastUnderscore = v == 0x5F
            } else if !lastUnderscore {
                out += "_"
                lastUnderscore = true
            }
        }
        return out
    }
}
