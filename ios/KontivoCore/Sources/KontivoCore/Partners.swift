import Foundation

/// Namensvergleich (lnorm/ltok/pkey), Vertragspartner-Gruppen und Dubletten.
public enum Partners {
    /// Rechtsformen, Artikel, Länder (zählen nie).
    public static let LSTOP: [String] = ["ag", "gmbh", "sa", "se", "kg", "co", "ltd", "inc", "llc", "plc", "nv", "bv", "spa", "sarl", "sagl", "ug", "ev", "mbh",
                                         "die", "der", "das", "the", "und", "and", "de", "la", "le", "les", "des", "of", "von", "fur", "fuer",
                                         "schweiz", "suisse", "svizzera", "switzerland", "swiss", "deutschland", "germany", "ch", "international"]
    /// Generische Wörter (müssen passen, wenn man sie eingibt; dürfen beim Treffer zusätzlich stehen).
    public static let LGEN: [String] = ["gruppe", "group", "holding", "app", "apps", "mobile", "versicherung", "versicherungen", "versicherungsgesellschaft", "insurance", "assurance", "assurances",
                                        "bank", "krankenkasse", "krankenversicherung", "energie", "strom", "werke", "services", "service", "online", "digital", "genossenschaft", "gesellschaft", "official", "offiziell"]
    /// Adjektive, die beim Treffer zusätzlich stehen dürfen.
    public static let LADJ: [String] = ["schweizerische", "schweizerischen", "schweizer", "deutsche", "deutscher", "allgemeine", "erste", "neue", "grand"]
    /// Ortsbegriffe (allein nie brauchbar).
    public static let LPLACE: [String] = ["stadt", "gemeinde", "kanton", "verwaltung", "landkreis", "kreis", "bezirk", "verein", "club", "amt"]

    /// Normalisieren: klein, ohne Akzente, ß → ss, & → « und », alles ausser a–z/0–9 → ein Leerzeichen, getrimmt.
    public static func lnorm(_ s: String) -> String {
        let nfd = s.lowercased().decomposedStringWithCanonicalMapping
        var stripped = String.UnicodeScalarView()
        for u in nfd.unicodeScalars where !(u.value >= 0x300 && u.value <= 0x36F) {
            stripped.append(u)
        }
        var t = String(stripped)
        t = t.replacingOccurrences(of: "ß", with: "ss")
        t = t.replacingOccurrences(of: "&", with: " und ")
        var out = String.UnicodeScalarView()
        var lastSpace = false
        for u in t.unicodeScalars {
            let ok = (u.value >= 0x61 && u.value <= 0x7A) || (u.value >= 0x30 && u.value <= 0x39)
            if ok {
                out.append(u)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        return String(out).trimmingCharacters(in: .whitespaces)
    }

    /// Wörter ab 2 Zeichen ohne Stoppwörter.
    public static func ltok(_ s: String) -> [String] {
        lnorm(s).split(separator: " ").map(String.init).filter { $0.count >= 2 && !LSTOP.contains($0) }
    }

    /// Vergleichsschlüssel eines Namens (`pkey`).
    public static func pkey(_ s: String) -> String {
        let k = ltok(s).joined(separator: " ")
        return k.isEmpty ? lnorm(s) : k
    }

    /// Name brauchbar für eine Suche: mindestens ein Wort ≥ 3 Zeichen, das weder generisch noch ein Ortsbegriff ist.
    public static func lusable(_ name: String) -> Bool {
        ltok(name).contains { $0.count >= 3 && !LGEN.contains($0) && !LPLACE.contains($0) }
    }

    /// Wortgleichheit inkl. Plural-Endungen s/en ab 6 Zeichen.
    public static func teq(_ a: String, _ b: String) -> Bool {
        a == b || (a.count >= 6 && b.count >= 6 && (a + "s" == b || b + "s" == a || a + "en" == b || b + "en" == a))
    }

    /// Name eines Treffers entspricht genau dem gesuchten (alle Suchwörter vorhanden, sonst nur generische Wörter).
    public static func nameEq(_ want: [String], _ text: String) -> Bool {
        let have = ltok(text)
        if want.isEmpty || have.isEmpty { return false }
        return want.allSatisfy { w in have.contains { teq($0, w) } }
            && have.allSatisfy { t in LGEN.contains(t) || LADJ.contains(t) || want.contains { teq(t, $0) } }
    }

    /// Alle Suchwörter kommen im Text vor.
    public static func nameHas(_ want: [String], _ text: String) -> Bool {
        let have = ltok(text)
        return !want.isEmpty && want.allSatisfy { w in have.contains { teq($0, w) } }
    }

    /// Zweistufige Endungen (`SLD2`): hier zählen drei Teile.
    public static let SLD2: [String] = ["co.uk", "org.uk", "ac.uk", "gov.uk", "me.uk", "com.tr", "gov.tr", "org.tr", "net.tr", "gen.tr",
                                        "co.at", "or.at", "gv.at", "ac.at", "com.au", "net.au", "org.au", "co.jp", "ne.jp", "or.jp",
                                        "co.nz", "com.br", "co.za", "com.mx", "com.cn", "co.in"]

    /// Registrierbare Domain (letzte zwei Teile, bei zweistufigen Endungen wie «co.uk» drei; ohne «www.»).
    public static func regDom(_ d: String) -> String {
        var s = d.lowercased()
        if s.hasPrefix("www.") { s = String(s.dropFirst(4)) }
        let p = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        if p.count > 2 && SLD2.contains(p.suffix(2).joined(separator: ".")) { return p.suffix(3).joined(separator: ".") }
        return p.count > 2 ? p.suffix(2).joined(separator: ".") : s
    }

    /// Schlüssel für die Gruppierung: pkey, ohne Wörter der kleingeschriebene Name.
    public static func groupKey(_ name: String) -> String {
        let k = pkey(name)
        return k.isEmpty ? name.trimmingCharacters(in: .whitespaces).lowercased() : k
    }

    // MARK: Gruppen (native Vertragspartner)

    /// Ein Vertragspartner mit seinen Verträgen.
    public struct Group: Hashable, Sendable {
        public var partner: Partner
        /// Verträge in Speicherreihenfolge (auch gekündigte)
        public var contractIDs: [UUID]
        /// Monatskosten (Hauptwährung) der laufenden, nicht pausierten Verträge
        public var monthlyCost: Double
        /// Vergleichsschlüssel
        public var key: String
        /// Gibt es weitere Vertragspartner mit gleichem Schlüssel?
        public var isDuplicate: Bool
    }

    /// Alle Vertragspartner mit Verträgen, sortiert nach Name (de-CH). `includeEmpty`: auch ohne Verträge.
    public static func groups(_ data: AppData, today: Day, includeEmpty: Bool = false) -> [Group] {
        let calc = Calc(data: data, today: today)
        var list: [Group] = []
        for p in data.partners {
            let cs = data.contracts.filter { $0.partnerID == p.id }
            if cs.isEmpty && !includeEmpty { continue }
            let cost = cs.reduce(0.0) { s, c in s + ((calc.isActive(c) && !calc.isPaused(c)) ? calc.monthlyCost(c) : 0) }
            list.append(Group(partner: p, contractIDs: cs.map { $0.id }, monthlyCost: cost, key: pkey(p.name), isDuplicate: false))
        }
        var cnt: [String: Int] = [:]
        for g in list where !g.key.isEmpty { cnt[g.key, default: 0] += 1 }
        for i in list.indices { list[i].isDuplicate = !list[i].key.isEmpty && (cnt[list[i].key] ?? 0) > 1 }
        return list.stableSorted { Format.lessDE($0.partner.name, $1.partner.name) }
    }

    /// Dubletten: Gruppen mit gleichem Schlüssel (je Schlüssel mindestens 2), in Reihenfolge des ersten Auftretens.
    public static func duplicateSets(_ data: AppData, today: Day) -> [[Group]] {
        var order: [String] = []
        var by: [String: [Group]] = [:]
        for g in groups(data, today: today) where g.isDuplicate {
            if by[g.key] == nil { order.append(g.key) }
            by[g.key, default: []].append(g)
        }
        return order.compactMap { by[$0] }
    }

    /// Ziel beim Zusammenführen: meiste Verträge, dann mit Logo (`mergeTarget`).
    public static func mergeTarget(_ list: [Group]) -> Group? {
        list.stableSorted { a, b in
            if a.contractIDs.count != b.contractIDs.count { return a.contractIDs.count > b.contractIDs.count }
            let la = (a.partner.logoID ?? "").isEmpty ? 0 : 1
            let lb = (b.partner.logoID ?? "").isEmpty ? 0 : 1
            return la > lb
        }.first
    }

    /// Vergleichsform eines Namens für «gleicher Vertragspartner» (Web: `partner.trim().toLowerCase()`),
    /// zusätzlich mehrfache Leerzeichen zusammengefasst.
    public static func sameNameKey(_ name: String) -> String {
        name.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
    }

    /// Bestehender Vertragspartner für einen eingegebenen Namen: nur gleicher Name (ohne Gross/Klein, Leerzeichen getrimmt).
    /// Ähnliche Namen (gleicher Schlüssel `pkey`, z.B. «Swisscom AG» zu «Swisscom») werden wie in der Web-App nicht still
    /// zusammengelegt – dafür gibt es `similar(_:in:)` als Hinweis und das Zusammenführen in der Pflege.
    public static func find(_ name: String, in data: AppData) -> Partner? {
        let lower = sameNameKey(name)
        if lower.isEmpty { return nil }
        return data.partners.first { sameNameKey($0.name) == lower }
    }

    /// Ähnlicher bestehender Vertragspartner (gleicher Schlüssel `pkey`, aber anderer Name) – nur als Hinweis
    /// («Meinst du «Swisscom»?»), nie automatisch.
    public static func similar(_ name: String, in data: AppData) -> Partner? {
        let lower = sameNameKey(name)
        if lower.isEmpty || find(name, in: data) != nil { return nil }
        let key = pkey(name)
        if key.isEmpty { return nil }
        return data.partners.first { pkey($0.name) == key }
    }

    /// Eigene Vertragspartner, deren Name den Text enthält (höchstens `limit`, Vorschläge beim Erfassen).
    public static func matches(_ query: String, in data: AppData, today: Day, limit: Int = 3) -> [Group] {
        let q = query.lowercased()
        return Array(groups(data, today: today).filter { $0.partner.name.lowercased().contains(q) }.prefix(limit))
    }

    /// Mögliches Duplikat beim Erfassen (`paintDup`): gleicher Vertragspartner (Schlüssel) und gleiche Bezeichnung
    /// (normalisiert) oder gleicher aktueller Preis in gleicher Währung. Nur Hinweis, nie blockierend.
    public static func possibleDuplicate(partnerName: String, label: String, amount: Double?, currency: Currency,
                                         in data: AppData, today: Day, excluding: UUID? = nil) -> Contract? {
        let key = pkey(partnerName)
        if key.isEmpty { return nil }
        let lb = lnorm(label)
        let calc = Calc(data: data, today: today)
        return data.contracts.first { c in
            if c.id == excluding { return false }
            guard let p = data.partner(c.partnerID), pkey(p.name) == key else { return false }
            if !lb.isEmpty && lnorm(c.label) == lb { return true }
            if let a = amount, a > 0, calc.curPrice(c) == a, c.currency == currency { return true }
            return false
        }
    }

    /// Text des Duplikat-Hinweises.
    public static func duplicateHint(_ c: Contract, in data: AppData, today: Day) -> String {
        let calc = Calc(data: data, today: today)
        let name = c.label.isEmpty ? data.partnerName(of: c) : c.label
        return "Mögliches Duplikat: «" + name + "» (" + Format.money(calc.curPrice(c)) + " " + c.currency.rawValue + ") existiert bereits. Du kannst trotzdem speichern."
    }
}
