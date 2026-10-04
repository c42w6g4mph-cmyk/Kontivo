import Foundation

/// Eintrag des Anbieterkatalogs Schweiz / Deutschland (Resources/catalog.json, erzeugt aus TPL der Web-App).
public struct CatalogEntry: Codable, Hashable, Sendable, Identifiable {
    public var name: String
    /// «CH», «DE» oder "" (international)
    public var country: String
    /// Name der Standardkategorie (Vorbelegung), "" = keine
    public var category: String
    /// Vorschlag für die Bezeichnung
    public var label: String
    /// Domain ohne Protokoll
    public var web: String
    /// Kündigungsfrist (0 = unbekannt bzw. keine)
    public var notice: Int
    public var noticeUnit: NoticeUnit
    public var cancelTerm: CancelTerm
    public var cancelChannel: CancelChannel?
    public var mandatory: Bool
    public var hint: String

    public var id: String { name }

    public init(name: String, country: String, category: String, label: String, web: String, notice: Int, noticeUnit: NoticeUnit,
                cancelTerm: CancelTerm, cancelChannel: CancelChannel?, mandatory: Bool, hint: String) {
        self.name = name
        self.country = country
        self.category = category
        self.label = label
        self.web = web
        self.notice = notice
        self.noticeUnit = noticeUnit
        self.cancelTerm = cancelTerm
        self.cancelChannel = cancelChannel
        self.mandatory = mandatory
        self.hint = hint
    }

    /// Land für die Anzeige (`tplFlag`): «CH», «DE» oder «CH · DE».
    public var flag: String { country.isEmpty ? "CH · DE" : country }

    /// Art der vorbelegten Kategorie.
    public var categoryKind: CategoryKind? { Category.defaultKind(forName: category) }

    /// Währung beim Übernehmen (nur wenn noch kein Betrag eingetragen ist): DE → EUR, CH → CHF.
    public var suggestedCurrency: Currency? {
        if country == "DE" { return .EUR }
        if country == "CH" { return .CHF }
        return nil
    }
}

/// Treffer der Internet-Suche (Wikidata) für `standardRule`.
public struct WebPartnerHit: Hashable, Sendable {
    public var name: String
    public var desc: String
    public var descAll: String
    public var dom: String
    public var cc: String
    public var tel: String
    public var mail: String
    public var file: String

    public init(name: String, desc: String = "", descAll: String = "", dom: String = "", cc: String = "", tel: String = "", mail: String = "", file: String = "") {
        self.name = name
        self.desc = desc
        self.descAll = descAll
        self.dom = dom
        self.cc = cc
        self.tel = tel
        self.mail = mail
        self.file = file
    }
}

public enum Catalog {
    /// Alle Einträge (Reihenfolge wie in der Web-App).
    public static let entries: [CatalogEntry] = load()

    static func load() -> [CatalogEntry] {
        let url = Bundle.module.url(forResource: "catalog", withExtension: "json")
            ?? Bundle.module.url(forResource: "catalog", withExtension: "json", subdirectory: "Resources")
        guard let u = url, let d = try? Data(contentsOf: u), let list = try? JSONDecoder().decode([CatalogEntry].self, from: d) else { return [] }
        return list
    }

    /// Eintrag mit genau diesem Namen (ohne Gross/Klein, getrimmt) (`tplFind`).
    public static func find(_ name: String) -> CatalogEntry? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n.isEmpty { return nil }
        return entries.first { $0.name.lowercased() == n }
    }

    /// Katalog-Fenster: Land «CH»/«DE» (internationale immer dabei) oder alle, Suche in Name, Bezeichnung, Kategorie; alphabetisch.
    public static func search(_ query: String, country: String = "") -> [CatalogEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { t in
            (country.isEmpty || t.country.isEmpty || t.country == country)
                && (q.isEmpty || (t.name + " " + t.label + " " + t.category).lowercased().contains(q))
        }.stableSorted { $0.name.compare($1.name, options: [], range: nil, locale: Locale(identifier: "de")) == .orderedAscending }
    }

    /// Vorlage-Chips unter dem Vertragspartner (höchstens 5): «Name Bezeichnung» enthält den Text.
    public static func suggestions(_ query: String, limit: Int = 5) -> [CatalogEntry] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.count < 2 { return [] }
        return Array(entries.filter { ($0.name + " " + $0.label).lowercased().contains(q) }.prefix(limit))
    }

    /// Erster Eintrag mit derselben registrierbaren Domain.
    public static func entry(forDomain dom: String) -> CatalogEntry? {
        let r = Partners.regDom(dom)
        if r.isEmpty { return nil }
        return entries.first { !$0.web.isEmpty && Partners.regDom($0.web) == r }
    }

    // MARK: Übliche Fristen (STD_RULES / stdFor)

    public enum Hints {
        public static let kvg = "Grundversicherung: per 31.12. kündbar, Kündigung muss bis 30.11. eingetroffen sein. Mit Mindestfranchise und Standardmodell (freie Arztwahl) zusätzlich per 30.06., Kündigung bis 31.03. Zusatzversicherungen haben eigene Fristen."
        public static let vvg = "Nach 3 Jahren per Ende Versicherungsjahr kündbar (VVG). Genaue Frist in der Police prüfen."
        public static let telecomCH = "60 Tage auf Monatsende, frühestens auf Ende der Mindestlaufzeit."
        public static let telecomDE = "Nach der Mindestlaufzeit monatlich mit 1 Monat Frist kündbar (TKG)."
        public static let streaming = "Jederzeit kündbar, gilt ab der nächsten Abrechnungsperiode."
        public static let bank = "Konto jederzeit kündbar. Guthaben vorher übertragen."
        public static let fitness = "Abos laufen meist 12 Monate. Verlängerung und Frist im Vertrag prüfen."
        public static let energyCH = "Grundversorgung: Haushalte können den Stromanbieter nicht wechseln."
        public static let energyDE = "Sondervertrag: nach Mindestlaufzeit meist 1 Monat Frist. Grundversorgung: 2 Wochen."
        public static let gkv = "Gesetzliche Krankenkasse: 2 Monate zum Monatsende, nach mindestens 12 Monaten Mitgliedschaft."
        public static let insuranceDE = "Meist 3 Monate zum Ende des Versicherungsjahres, neuere Verträge oft 1 Monat. Police prüfen."
        public static let check = "Frist im Vertrag prüfen."
    }

    struct RuleValues {
        var notice: Int
        var unit: NoticeUnit
        var term: CancelTerm
        var channel: CancelChannel?
        var mandatory: Bool
        var hint: String
    }

    struct Rule {
        var pattern: String
        var category: String
        var label: String
        var ch: RuleValues?
        var de: RuleValues?
        var any: RuleValues?
        var dePattern: String?
    }

    static let rules: [Rule] = [
        Rule(pattern: "krankenkasse|krankenversicher|health insur", category: "Versicherung", label: "Krankenkasse",
             ch: RuleValues(notice: 1, unit: .months, term: .yearEnd, channel: .registered, mandatory: true, hint: Hints.kvg),
             de: RuleValues(notice: 2, unit: .months, term: .monthEnd, channel: nil, mandatory: true, hint: Hints.gkv),
             any: nil, dePattern: "gesetzlich|krankenkasse"),
        Rule(pattern: "versicher|insurance", category: "Versicherung", label: "Versicherung",
             ch: RuleValues(notice: 3, unit: .months, term: .contractYear, channel: .letter, mandatory: false, hint: Hints.vvg),
             de: RuleValues(notice: 3, unit: .months, term: .contractYear, channel: .letter, mandatory: false, hint: Hints.insuranceDE),
             any: nil, dePattern: nil),
        Rule(pattern: "telekom|telecom|mobilfunk|mobile (network|operator)|internetdienst|internet service|kabelnetz", category: "Mobilfunk & Internet", label: "Handy / Internet",
             ch: RuleValues(notice: 60, unit: .days, term: .monthEnd, channel: nil, mandatory: false, hint: Hints.telecomCH),
             de: RuleValues(notice: 1, unit: .months, term: .anytime, channel: nil, mandatory: false, hint: Hints.telecomDE),
             any: nil, dePattern: nil),
        Rule(pattern: "energieversorg|stromanbieter|stadtwerk|elektrizit|electric utility|energy (company|supplier)", category: "Energie & Wasser", label: "Strom",
             ch: RuleValues(notice: 0, unit: .months, term: .anytime, channel: nil, mandatory: true, hint: Hints.energyCH),
             de: RuleValues(notice: 1, unit: .months, term: .anytime, channel: nil, mandatory: false, hint: Hints.energyDE),
             any: nil, dePattern: nil),
        Rule(pattern: "streaming|video.on.demand|musikdienst|music service", category: "Abos & Medien", label: "Streaming",
             ch: nil, de: nil, any: RuleValues(notice: 0, unit: .months, term: .period, channel: .online, mandatory: false, hint: Hints.streaming), dePattern: nil),
        Rule(pattern: "fitness", category: "Freizeit & Sport", label: "Fitnessabo",
             ch: nil, de: nil, any: RuleValues(notice: 0, unit: .months, term: .contractYear, channel: nil, mandatory: false, hint: Hints.fitness), dePattern: nil),
        Rule(pattern: "\\bbank\\b|kreditinstitut|neobank|sparkasse", category: "Finanzen", label: "Konto",
             ch: nil, de: nil, any: RuleValues(notice: 0, unit: .months, term: .monthEnd, channel: nil, mandatory: false, hint: Hints.bank), dePattern: nil),
    ]

    /// Übliche Frist für einen beliebigen Anbieter aus Branche (Beschreibung) und Land (`stdFor`). Nur Vorschlag.
    /// Kategorie nur, wenn es sie in `categoryNames` gibt.
    public static func standardRule(for w: WebPartnerHit, categoryNames: [String]) -> CatalogEntry? {
        let descText = !w.descAll.isEmpty ? w.descAll : w.desc
        let d = Partners.lnorm(descText) + " " + Partners.lnorm(w.name)
        for r in rules {
            if !RX.test(r.pattern, d) { continue }
            var v: RuleValues? = r.any
            if v == nil {
                if w.cc == "CH" { v = r.ch } else if w.cc == "DE" { v = r.de }
            }
            if let dp = r.dePattern, w.cc == "DE", !RX.test(dp, d) { continue }
            let cat = categoryNames.contains(r.category) ? r.category : ""
            guard let val = v else {
                if cat.isEmpty { return nil }
                return CatalogEntry(name: w.name, country: w.cc, category: cat, label: r.label, web: w.dom, notice: 0, noticeUnit: .months,
                                    cancelTerm: .anytime, cancelChannel: nil, mandatory: false, hint: "")
            }
            return CatalogEntry(name: w.name, country: w.cc, category: cat, label: r.label, web: w.dom, notice: val.notice, noticeUnit: val.unit,
                                cancelTerm: val.term, cancelChannel: val.channel, mandatory: val.mandatory, hint: val.hint)
        }
        return nil
    }

    /// Vorlage für einen Internet-Treffer: Katalogeintrag mit gleicher Domain (Name ersetzt), sonst `standardRule`.
    /// Ohne Hinweistext → nil (wie `pickWebPartner`).
    public static func template(for w: WebPartnerHit, categoryNames: [String]) -> CatalogEntry? {
        var t: CatalogEntry?
        if var k = entry(forDomain: w.dom) {
            k.name = w.name
            t = k
        } else {
            t = standardRule(for: w, categoryNames: categoryNames)
        }
        if let x = t, x.hint.isEmpty { return nil }
        return t
    }
}

// MARK: - Reguläre Ausdrücke (NSRegularExpression, ICU-Syntax)

enum RX {
    static func make(_ pattern: String, ignoreCase: Bool) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }

    static func test(_ pattern: String, _ s: String, ignoreCase: Bool = false) -> Bool {
        guard let re = make(pattern, ignoreCase: ignoreCase) else { return false }
        return re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)) != nil
    }

    /// Erster Treffer mit allen Gruppen (Gruppe 0 = ganzer Treffer, nicht beteiligte Gruppen nil).
    static func match(_ pattern: String, _ s: String, ignoreCase: Bool = false) -> [String?]? {
        guard let re = make(pattern, ignoreCase: ignoreCase),
              let m = re.firstMatch(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)) else { return nil }
        return groups(m, s)
    }

    /// Alle Treffer.
    static func matches(_ pattern: String, _ s: String, ignoreCase: Bool = false) -> [[String?]] {
        guard let re = make(pattern, ignoreCase: ignoreCase) else { return [] }
        return re.matches(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s)).map { groups($0, s) }
    }

    static func groups(_ m: NSTextCheckingResult, _ s: String) -> [String?] {
        var out: [String?] = []
        for i in 0..<m.numberOfRanges {
            let r = m.range(at: i)
            if r.location == NSNotFound {
                out.append(nil)
            } else if let rr = Range(r, in: s) {
                out.append(String(s[rr]))
            } else {
                out.append(nil)
            }
        }
        return out
    }

    /// Alle Treffer ersetzen (Vorlage mit $1 …).
    static func replace(_ pattern: String, in s: String, with template: String, ignoreCase: Bool = false) -> String {
        guard let re = make(pattern, ignoreCase: ignoreCase) else { return s }
        return re.stringByReplacingMatches(in: s, options: [], range: NSRange(s.startIndex..<s.endIndex, in: s), withTemplate: template)
    }
}
