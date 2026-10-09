import Foundation

// MARK: - Kontoauszug: Katalog-Treffer, Ausschlüsse und Kategorie
// 1:1 nach Web BKALIAS, bankTpl, BKSKIP, BKSHOP, BKRETAIL, BKVIA, BKCAT, bankCat.

enum BankCatalog {
    /// Katalogeinträge mit Sonderregel (Web `BKALIAS`): Treffer über Stichwort statt über die Namenswörter.
    static let BKALIAS: [String: BRX] = [
        "Rundfunkbeitrag": BRX("rundfunk|beitragsservice"),
        "Serafe": BRX("\\bserafe\\b"),
        "SBB Halbtax": BRX("halbtax"),
        "Deutschlandticket": BRX("deutschlandticket|d ticket"),
        "Die Mobiliar": BRX("\\bmobiliar\\b"),
        "Amazon Prime": BRX("amazon prime|prime video|amzn prime"),
        "Zurich": BRX("zurich (versicherung|insurance|schweiz|lebens)"),
    ]

    /// Katalog mit vorberechneten Wörtern (TPL-Reihenfolge).
    struct Item {
        let entry: CatalogEntry
        /// `ltok(t[0])`
        let tok: [String]
        /// Länder, in denen es einen anderen Eintrag mit gleichem ersten Wort gibt (AXA / AXA Deutschland)
        let otherIn: Set<String>
    }

    static let items: [Item] = {
        let es = Catalog.entries
        let toks = es.map { Partners.ltok($0.name) }
        return es.indices.map { (i: Int) -> Item in
            var other = Set<String>()
            if let f = toks[i].first {
                for j in es.indices where j != i && toks[j].first == f { other.insert(es[j].country) }
            }
            return Item(entry: es[i], tok: toks[i], otherIn: other)
        }
    }()

    /// Eintrag zu einem Katalognamen (Namen sind eindeutig).
    static func entry(named n: String) -> CatalogEntry? {
        items.first { $0.entry.name == n }?.entry
    }

    static let rxFiller = BRX("^(lastschrift|zahlung|erechnung|ebill|dauerauftrag|gutschrift|belastung|einkauf|kauf|abo|abonnement|rechnung)$")

    /// Katalog: alle markanten Wörter des Namens müssen vorkommen; kurze Namen (CSS, O2) nur im Namen, nicht im Freitext (Web `bankTpl`).
    static func tpl(_ name: String, _ text: String, _ cur: String) -> CatalogEntry? {
        let nn = " " + Partners.lnorm(name) + " "
        let nt = " " + Partners.lnorm(name + " " + text) + " "
        let cc = cur == "EUR" ? "DE" : (cur == "CHF" ? "CH" : "")
        let via = BKVIA.test(nn)
        var best: CatalogEntry? = nil
        var inN = 0
        let nt2 = BankName.tok(name)
        func better(_ t: CatalogEntry, _ n: Bool) -> Bool {
            guard let b = best else { return true }
            let d = (n ? 1 : 0) - inN
            if d != 0 { return d > 0 }
            let c = (t.country == cc ? 1 : 0) - (b.country == cc ? 1 : 0)
            if c != 0 { return c > 0 }
            return BU.len(t.name) - BU.len(b.name) > 0
        }
        for it in items {
            let t = it.entry
            if let al = BKALIAS[t.name] {
                if al.test(nt) {
                    let n1 = al.test(nn)
                    if better(t, n1) {
                        best = t
                        inN = n1 ? 1 : 0
                    }
                }
                continue
            }
            let tk = it.tok
            if tk.isEmpty || (!t.country.isEmpty && !cc.isEmpty && t.country != cc && it.otherIn.contains(cc)) { continue }
            // ein Wort (CSS, Zurich, Netflix): nur im Namen, sonst Fehltreffer über Ortsnamen; bei PayPal & Co. auch im Freitext
            let hay = tk.count == 1 && !via ? nn : nt
            // ein Wort: muss vorne im Namen stehen (davor nur Allerweltswörter) – «Garten Center Spiegel» ist nicht «Der Spiegel»
            if tk.count == 1 && !via, let ix = nt2.firstIndex(of: tk[0]), ix > 0,
               nt2[0..<ix].contains(where: { w in w.count > 3 && !Partners.LGEN.contains(w) && !rxFiller.test(w) }) {
                continue
            }
            if tk.allSatisfy({ hay.contains(" " + $0 + " ") }) {
                let n2 = tk.allSatisfy { nn.contains(" " + $0 + " ") }
                if better(t, n2) {
                    best = t
                    inN = n2 ? 1 : 0
                }
            }
        }
        return best
    }

    static let BKSKIP = BRX("bancomat|geldautomat|bargeld|barauszahlung|\\batm\\b|\\bcash\\b|auszahlung gaa|\\bgaa\\b|\\bga \\d{4,}|^ga\\b|umbuchung|uebertrag (auf|von|an) (konto|sparkonto|eigen)|kontouebertrag|eigene?s? konto|sparkonto|kreditkartenabrechnung|kartenabrechnung|twint an|\\bzinsen\\b|\\babschluss\\b")
    /// Gastronomie und Läden: nie ein Vertrag, auch wenn ein Katalogname drinsteckt (NZZ Café, Coop Restaurant)
    static let BKSHOP = BRX("\\b(cafe|caffe|caffe|coffee|kaffee|espresso|bar|restaurant|ristorante|trattoria|osteria|bistro|pizzeria|pizza|burger|kebab|doener|sushi|imbiss|take ?away|kantine|mensa|lounge|baeckerei|backerei|baeckerei|beck|confiserie|konditorei|kiosk|shop|store|boutique|markt|supermarkt|hotel|tankstelle|apotheke|drogerie|tabak|bakery|gartencenter|garten ?center|gaertnerei|blumen|baumarkt)\\b")
    /// Alltagseinkäufe (Detailhandel, Tankstellen, Fast Food): nie ein Vertrag, ausser ein Katalogeintrag passt (Migros Bank, Coop Mobile)
    static let BKRETAIL = BRX("\\b(migros|migrolino|coop|denner|aldi|lidl|rewe|edeka|kaufland|netto|penny|spar|volg|landi|manor|globus|jumbo|obi|bauhaus|hornbach|ikea|dm|rossmann|mueller|douglas|zalando|galaxus|digitec|interdiscount|mediamarkt|media markt|saturn|fust|brack|shell|bp|avia|aral|esso|tamoil|agrola|socar|jet|starbucks|mcdonald s?|mcdonalds|burger king|subway|k kiosk|valora|avec|tchibo|decathlon|h und m|zara|c und a|tk maxx|primark)\\b")
    static let BKVIA = BRX("paypal|klarna|amazon|apple com bill|google|stripe|adyen|sumup|wero|twint")

    /// Kategorie: Stichwörter → Standardkategorie (Web `BKCAT`)
    static let BKCAT: [(BRX, String)] = [
        (BRX("steuer|finanzamt|steueramt|serafe|rundfunk|gebuehr|kfz steuer"), "Steuern & Gebühren"),
        (BRX("miete|mietzins|immobilien|hausverwaltung|liegenschaft|wohnbau|wohnung|nebenkosten"), "Wohnen"),
        (BRX("kita|krippe|schule|kindergarten|musikschule|hort"), "Familie & Bildung"),
        (BRX("leasing|sbb|halbtax|deutschlandticket|bahn|bvg|parking|parkplatz|garage|tankstelle"), "Mobilität"),
        (BRX("fitness|sport|verein|club|gym|mcfit|yoga"), "Freizeit & Sport"),
        (BRX("versicherung|praemie|police|krankenkasse|kranken"), "Versicherung"),
        (BRX("strom|energie|gas|wasser|stadtwerke|abschlag|akonto"), "Energie & Wasser"),
        (BRX("swisscom|sunrise|salt|telekom|vodafone|mobilfunk|internet|festnetz"), "Mobilfunk & Internet"),
        (BRX("netflix|spotify|abo|zeitung|streaming|disney|apple com bill|youtube"), "Abos & Medien"),
    ]

    /// Aktueller Name der Standardkategorie `key` (Web `catByKey`), nur wenn es sie gibt (`allCats().indexOf(k) >= 0`).
    static func categoryName(key: String, in data: AppData) -> String? {
        if key.isEmpty { return nil }
        if let kind = Category.standardKinds[key], let c = data.categories.first(where: { $0.kind == kind }) { return c.name }
        return data.categories.contains(where: { $0.name == key }) ? key : nil
    }

    /// Kategorie: Katalog, sonst Stichwörter, sonst Sonstiges (Web `bankCat`).
    static func category(catalog: CatalogEntry?, name: String, text: String, data: AppData) -> String {
        if let t = catalog, let c = categoryName(key: t.category, in: data) { return c }
        let s = Partners.lnorm(name + " " + text)
        for (r, k) in BKCAT where r.test(s) {
            if let c = categoryName(key: k, in: data) { return c }
        }
        return "Sonstiges"
    }
}
