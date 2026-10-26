import Foundation

// MARK: - Kontoauszug: Katalog-Treffer, Ausschlüsse und Kategorie
// 1:1 nach Web BKALIAS, bankTpl, BKSKIP, BKSHOP, BKRETAIL, BKVIA, BKCAT, bankCat.

enum BankCatalog {
    /// Katalogeinträge mit Sonderregel (Web `BKALIAS`): Treffer über Stichwort statt über die Namenswörter.
    static let BKALIAS: [String: BRX] = [
        // CH Serafe und DE Beitragsservice getrennt (Web v331 ff.): Anbieter statt Sammelbegriff «Rundfunkgebühr»
        "Serafe": BRX("\\bserafe\\b|\\bbillag\\b"),
        "Beitragsservice": BRX("rundfunk|beitragsservice|ard zdf"),
        "SBB Halbtax": BRX("halbtax"),
        "Deutschlandticket": BRX("deutschlandticket|d ticket"),
        "Die Mobiliar": BRX("\\bmobiliar\\b"),
        "Amazon Prime": BRX("amazon prime|prime video|amzn prime"),
        // Web v181: O2 auch über Telefónica
        "O2": BRX("\\bo2\\b|telefonica germany|telefonica o2"),
        "Zurich": BRX("zurich (versicherung|insurance|schweiz|lebens)"),
        // Web v210/v211
        "M-net": BRX("\\bm ?net (telekommunikation|gmbh)|\\bmnet\\b"),
        "Migros Mobile": BRX("migros mobile|m ?budget mobile"),
        "SIG": BRX("services industriels de geneve|\\bsig (services|sa|geneve)\\b|^ sig (?!sauer)"),
        "SiL Lausanne": BRX("services industriels de lausanne|\\bsil lausanne\\b"),
    ]

    /// Produkte, deren Nennung im Text den Namen des Anbieters schlägt (Web v181 `BKPROD`; Firmen-Aliase wie Zurich nicht:
    /// «8000 Zürich, Schweiz» in der Adresse)
    static let BKPROD: Set<String> = ["Deutschlandticket", "SBB Halbtax", "Amazon Prime", "O2", "Serafe", "Beitragsservice"]

    /// Gleicher Name, mehrere Verträge (Web v212/v213 `BKLABTPL`): Bezeichnung → Stichwörter im Buchungstext
    static let BKLABTPL: [String: BRX] = [
        "Bausparvertrag": BRX("bauspar"),
        "Reiseversicherung": BRX("reise|\\beti\\b|schutzbrief|travel|annullation"),
        "Rechtsschutz": BRX("rechtsschutz|assista"),
        "Leasing": BRX("leasing"),
        "Säule 3a": BRX("\\b3a\\b|vorsorge|saeule|saule|pillar"),
        "Zusatzversicherung": BRX("zusatz|\\bvvg\\b|spitalvers|ambulant|halbprivat|\\bprivat\\b"),
        "Krankenkasse": BRX("grundvers|\\bkvg\\b|obligatorisch|\\bokp\\b"),
    ]

    /// Namen, die im Katalog mehrfach vorkommen (Web: `TPL.some(o => o !== tp && o[0] === tp[0])`) – Gruppenschlüssel mit «·Bezeichnung»
    static let duplicateNames: Set<String> = {
        var seen = Set<String>(), dup = Set<String>()
        for e in Catalog.entries {
            if seen.contains(e.name) { dup.insert(e.name) } else { seen.insert(e.name) }
        }
        return dup
    }()

    /// Banken schreiben Umlaute als ae/oe/ue (Suedkurier): auf beiden Seiten gleich reduzieren (Katalog und Buchung), nach lnorm (Web v272 `bankDeU`)
    static func deU(_ x: String) -> String {
        x.replacingOccurrences(of: "ae", with: "a").replacingOccurrences(of: "oe", with: "o").replacingOccurrences(of: "ue", with: "u")
    }

    /// Katalog mit vorberechneten Wörtern (TPL-Reihenfolge, Web v272 `tplIdx`).
    struct Item {
        let entry: CatalogEntry
        /// `ltok(t[0]).map(bankDeU)`
        let tok: [String]
        /// Land hat einen Eintrag mit diesem ersten Wort (Web `first[cc][tk[0]]`)
        let firstIn: Set<String>
    }

    static let items: [Item] = {
        let es = Catalog.entries
        let toks = es.map { Partners.ltok($0.name).map(deU) }
        // erstes Wort je Land (Web `first`): nur Einträge mit Land
        var first: [String: Set<String>] = [:]
        for (i, e) in es.enumerated() where !e.country.isEmpty {
            if let f = toks[i].first { first[f, default: []].insert(e.country) }
        }
        return es.indices.map { (i: Int) -> Item in
            Item(entry: es[i], tok: toks[i], firstIn: toks[i].first.flatMap { first[$0] } ?? [])
        }
    }()

    /// Ergebnisse je (Name, Text, Währung) zwischenspeichern (Web `TPLC`, höchstens 5000)
    private static let cacheLock = NSLock()
    private static var cache: [String: CatalogEntry?] = [:]

    /// Eintrag zu einem Katalognamen. Gleicher Name in CH und DE (Rundfunkgebühr, Web v158): Eintrag passend zur Währung
    /// (EUR → DE, CHF → CH), sonst der erste.
    static func entry(named n: String, currency: String = "") -> CatalogEntry? {
        let list = items.filter { $0.entry.name == n }.map { $0.entry }
        if list.count > 1 {
            let cc = currency == "EUR" ? "DE" : (currency == "CHF" ? "CH" : "")
            if let m = list.first(where: { $0.country == cc }) { return m }
        }
        return list.first
    }

    static let rxFiller = BRX("^(lastschrift|zahlung|erechnung|ebill|dauerauftrag|gutschrift|belastung|einkauf|kauf|abo|abonnement|rechnung)$")

    /// Katalog: alle markanten Wörter des Namens müssen vorkommen; kurze Namen (CSS, O2) nur im Namen, nicht im Freitext (Web `bankTpl`).
    static func tpl(_ name: String, _ text: String, _ cur: String) -> CatalogEntry? {
        let ck = name + "\u{1}" + text + "\u{1}" + cur
        cacheLock.lock()
        if let hit = cache[ck] {
            cacheLock.unlock()
            return hit
        }
        if cache.count > 5000 { cache.removeAll() }
        cacheLock.unlock()
        let res = tpl0(name, text, cur)
        cacheLock.lock()
        cache[ck] = .some(res)
        cacheLock.unlock()
        return res
    }

    static let rxFinanzOwner = BRX(" (pensionskasse|vorsorgestiftung|anlagestiftung|stiftung|immobilien|immo|liegenschaft|liegenschaften|verwaltung|wohnbau|baugenossenschaft) ")
    static let rxRentWords = BRX(" (miete|mietzins|nebenkosten) ")

    static func tpl0(_ name: String, _ text: String, _ cur: String) -> CatalogEntry? {
        let nn = " " + deU(Partners.lnorm(name)) + " "
        let nt = " " + deU(Partners.lnorm(name + " " + text)) + " "
        let cc = cur == "EUR" ? "DE" : (cur == "CHF" ? "CH" : "")
        let via = BKVIA.test(nn)
        var best: CatalogEntry? = nil
        var bestTok = 0
        // inN: 2 = Produkt-Alias im Text (Deutschlandticket über Stadtwerke, O2 über Telefónica), 1 = Name, 0 = nur Text
        var inN = 0
        let nt2 = BankName.tok(name).map(deU)
        // spezifischer gewinnt: «Allianz Travel» vor «Allianz Suisse» (Web v213: Anzahl Wörter vor Länge)
        func better(_ t: CatalogEntry, _ tok: Int, _ n: Int) -> Bool {
            guard let b = best else { return true }
            let d = n - inN
            if d != 0 { return d > 0 }
            let c = (t.country == cc ? 1 : 0) - (b.country == cc ? 1 : 0)
            if c != 0 { return c > 0 }
            if tok != bestTok { return tok > bestTok }
            return BU.len(t.name) - BU.len(b.name) > 0
        }
        for it in items {
            let t = it.entry
            if let al = BKALIAS[t.name] {
                if al.test(nt) {
                    let n1 = al.test(nn) ? 1 : (BKPROD.contains(t.name) ? 2 : 0)
                    if better(t, it.tok.count, n1) {
                        best = t
                        bestTok = it.tok.count
                        inN = n1
                    }
                }
                continue
            }
            let tk = it.tok
            if tk.isEmpty || (!t.country.isEmpty && !cc.isEmpty && t.country != cc && it.firstIn.contains(cc)) { continue }
            // ein Wort (CSS, Zurich, Netflix): nur im Namen, sonst Fehltreffer über Ortsnamen; bei PayPal & Co. auch im Freitext
            let hay = tk.count == 1 && !via ? nn : nt
            // ein Wort: muss vorne im Namen stehen (davor nur Allerweltswörter) – «Garten Center Spiegel» ist nicht «Der Spiegel»
            if tk.count == 1 && !via, let ix = nt2.firstIndex(of: tk[0]), ix > 0,
               nt2[0..<ix].contains(where: { w in w.count > 3 && !Partners.LGEN.contains(w) && !rxFiller.test(w) }) {
                continue
            }
            if tk.allSatisfy({ hay.contains(" " + $0 + " ") }) {
                let n2 = tk.allSatisfy { nn.contains(" " + $0 + " ") }
                if better(t, tk.count, n2 ? 1 : 0) {
                    best = t
                    bestTok = tk.count
                    inN = n2 ? 1 : 0
                }
            }
        }
        // gleicher Name, mehrere Verträge (CSS Krankenkasse/Zusatzversicherung, Mainova Strom/Gas): Bezeichnung aus dem Buchungstext wählen
        if let b = best {
            let sib = items.filter { $0.entry.name == b.name && $0.entry.country == b.country }.map { $0.entry }
            if sib.count > 1, let pick = sib.first(where: { o in
                if let r = BKLABTPL[o.label] { return r.test(nt) }
                let lt = Partners.ltok(o.label)
                return !lt.isEmpty && lt.allSatisfy { nt.contains(" " + $0 + " ") }
            }) {
                best = pick
            }
        }
        // «Raiffeisen Pensionskasse» (Vermieterin) ist nicht die Bank Raiffeisen (Web v272)
        if let b = best, b.category == "Finanzen", rxFinanzOwner.test(nn) || rxRentWords.test(nt) { return nil }
        return best
    }

    /// Bussen, Arzt-/Spitalrechnungen (Web v331 ff., Testgenerator): zufällig ähnliche Beträge im Halbjahres-/Jahresabstand sind keine Verträge
    static let BKNOCON = BRX("\\bbusse\\b|bussgeld|ordnungsbusse|parkbusse|verwarnungsgeld|\\bpraxis\\b|arztpraxis|zahnarzt|\\bspital\\b|kantonsspital|\\bklinik\\b|tierarzt|physiotherap|dentalhygiene")
    static let BKSKIP = BRX("u?e?bertrag (auf|von|an)|twint (geld )?(senden|gesendet|an|send)|geld senden|kreditkarten ?abrechnung|aufladung|top ?up\\b|bancomat|geldautomat|bargeld|barauszahlung|\\batm\\b|\\bcash\\b|auszahlung gaa|\\bgaa\\b|\\bga \\d{4,}|^ga\\b|umbuchung|uebertrag (auf|von|an) (konto|sparkonto|eigen)|kontouebertrag|eigene?s? konto|sparkonto|kreditkartenabrechnung|kartenabrechnung|twint an|\\babschluss\\b|kontoubertrag")
    /// Gastronomie und Läden: nie ein Vertrag, auch wenn ein Katalogname drinsteckt (NZZ Café, Coop Restaurant)
    static let BKSHOP = BRX("\\b(gastro|gastronomie|badi beizli|cafe|caffe|caffe|coffee|kaffee|espresso|bar|restaurant|ristorante|trattoria|osteria|bistro|pizzeria|pizza|burger|kebab|doener|doner|sushi|imbiss|take ?away|kantine|mensa|lounge|baeckerei|backerei|baeckerei|beck|confiserie|konditorei|kiosk|shop|store|boutique|markt|supermarkt|hotel|tankstelle|apotheke|drogerie|tabak|bakery|gartencenter|garten ?center|gaertnerei|gartnerei|blumen|baumarkt)\\b")
    /// Alltagseinkäufe (Detailhandel, Tankstellen, Fast Food): nie ein Vertrag, ausser ein Katalogeintrag passt (Migros Bank, Coop Mobile)
    static let BKRETAIL = BRX("\\b(migros|migrolino|coop|denner|aldi|lidl|rewe|edeka|kaufland|netto|penny|spar|volg|landi|manor|globus|jumbo|obi|bauhaus|hornbach|ikea|dm|rossmann|mueller|muller|douglas|zalando|galaxus|digitec|interdiscount|mediamarkt|media markt|saturn|fust|brack|shell|bp|avia|aral|esso|tamoil|agrola|socar|jet|starbucks|mcdonald s?|mcdonalds|burger king|subway|k kiosk|valora|avec|tchibo|decathlon|h und m|zara|c und a|tk maxx|primark)\\b")
    static let BKVIA = BRX("paypal|klarna|amazon|apple com bill|google|stripe|adyen|sumup|wero|twint")
    /// Kontoführung ohne Empfänger (Web v181 `BKFEE`) → Vertragspartner = die Bank
    static let BKFEE = BRX("entgeltabschluss|entgeltabrechnung|kontofuhrung|kontofuehrung|kontopreis|kontoentgelt|kontogebuhr|kontogebuehr|kontoabschluss|abschluss entgelt")

    /// Kategorie: Stichwörter → Standardkategorie (Web `BKCAT`)
    static let BKCAT: [(BRX, String)] = [
        (BRX("strassenverkehrsamt|steuer|finanzamt|steueramt|serafe|rundfunk|gebuehr|kfz steuer"), "Steuern & Gebühren"),
        (BRX("kaution|caution|miete|mietzins|immobilien|hausverwaltung|liegenschaft|wohnbau|wohnung|nebenkosten"), "Wohnen"),
        (BRX("kita|krippe|schule|kindergarten|musikschule|hort"), "Familie & Bildung"),
        (BRX("leasing|sbb|halbtax|deutschlandticket|bahn|bvg|parking|parkplatz|garage|tankstelle"), "Mobilität"),
        (BRX("fitness|sport|verein|club|calcio|gym|mcfit|yoga|\\be v\\b|\\b(sc|fc|tsv|sv|tus|vfb|vfl|djk|sg|turnverein|schwimmverein)\\b"), "Freizeit & Sport"),
        (BRX("versicherung|praemie|police|krankenkasse|kranken"), "Versicherung"),
        (BRX("strom|energie|\\bgas\\b|erdgas|gasversorg|wasser|stadtwerke|abschlag|akonto"), "Energie & Wasser"),
        (BRX("swisscom|sunrise|salt|telekom|vodafone|mobilfunk|internet|festnetz"), "Mobilfunk & Internet"),
        (BRX("netflix|spotify|abo|zeitung|streaming|disney|apple com bill|\\bapple\\b(?! store| retail)|itunes|app store|youtube|dropbox|icloud|google one|onedrive|\\bdomain|hosting|ionos|strato|hostpoint|infomaniak"), "Abos & Medien"),
        (BRX("entgeltabschluss|entgeltabrechnung|kontofuhrung|kontofuehrung|kontopreis|kontoentgelt|darlehen|kreditrate|\\bkredit\\b|hypothek|bausparvertrag|sparplan|depotgebuhr|depotgebuehr"), "Finanzen"),
    ]

    /// Zeitraum im Verwendungszweck → Rhythmus (Web v181 `bankPeriod`): «Rundfunk 07.2026 - 09.2026» = 3, «Jahresgebühr» = 12, sonst 0
    static let rxPeriod = BRX("\\b(\\d{1,2})[./](\\d{4})\\s*(?:-|–|bis)\\s*(\\d{1,2})[./](\\d{4})\\b")
    static let rxPeriodYear = BRX("jahresgebuhr|jahresgebuehr|jahresbeitrag|jahresabo|jahrespramie|jahrespraemie|jahrlich|jaehrlich|annual|yearly")
    static let rxPeriodHalf = BRX("halbjahr|halbjahrlich")
    static let rxPeriodQuarter = BRX("quartal|vierteljahr")

    static func period(_ txt: String) -> Int {
        if let m = rxPeriod.match(txt) {
            let m1: Int = Int(m.s(1)) ?? 0
            let y1: Int = Int(m.s(2)) ?? 0
            let m2: Int = Int(m.s(3)) ?? 0
            let y2: Int = Int(m.s(4)) ?? 0
            let n: Int = (y2 - y1) * 12 + (m2 - m1) + 1
            if [1, 2, 3, 6, 12].contains(n) { return n }
        }
        let l = Partners.lnorm(txt)
        if rxPeriodYear.test(l) { return 12 }
        if rxPeriodHalf.test(l) { return 6 }
        if rxPeriodQuarter.test(l) { return 3 }
        return 0
    }

    /// Aktueller Name der Standardkategorie `key` (Web `catByKey`), nur wenn es sie gibt (`allCats().indexOf(k) >= 0`).
    static func categoryName(key: String, in data: AppData) -> String? {
        if key.isEmpty { return nil }
        if let kind = Category.standardKinds[key], let c = data.categories.first(where: { $0.kind == kind }) { return c.name }
        return data.categories.contains(where: { $0.name == key }) ? key : nil
    }

    /// Kategorie: Katalog, sonst Verein, sonst Stichwörter, sonst Sonstiges (Web `bankCat`; `memo` = Mitteilung des Einzelpostens).
    static func category(catalog: CatalogEntry?, name: String, text: String, memo: String = "", data: AppData) -> String {
        if let t = catalog, let c = categoryName(key: t.category, in: data) { return c }
        if BankClub.isClub(name, name + " " + memo), let c = categoryName(key: "Freizeit & Sport", in: data) { return c }
        let s = Partners.lnorm(name + " " + text)
        for (r, k) in BKCAT where r.test(s) {
            if let c = categoryName(key: k, in: data) { return c }
        }
        return "Sonstiges"
    }
}
