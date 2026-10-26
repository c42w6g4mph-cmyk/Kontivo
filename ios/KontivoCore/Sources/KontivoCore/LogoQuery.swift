import Foundation

// MARK: - Logo-Suche: reine Regeln ohne Netz (Web allCands, logoPin, wikiCands-Profilbild; v292, v294, d6fc9de, baab11e)

/// Festes Logo für sehr häufige Vertragspartner (Web `LOGO_PIN`, baab11e): Apple immer mit dem Wikipedia-Logo von Apple Inc.
public struct LogoPin: Hashable, Sendable {
    public var url: String
    public var title: String
    public var domain: String
    /// Punkte (vor allen anderen Quellen)
    public var score: Double { 9 }
}

/// Kürzere Suchbegriffe, wenn der volle Name nichts Eindeutiges liefert (Web v294)
public struct LogoShortening: Hashable, Sendable {
    /// Wörter ohne Rechtsform, Allerweltswörter und Adjektive («Raiffeisen Pensionskasse AG» → [Raiffeisen, Pensionskasse])
    public var words: [String]
    /// Amt, Ortsname oder Marke nicht vorne: nie kürzen
    public var amt: Bool
    /// Suchbegriffe der Reihe nach (erst ohne Allerweltswörter, dann nur das Markenwort)
    public var variants: [String]
}

public enum LogoQuery {
    static let pins: [(pattern: String, url: String, title: String, domain: String)] = [
        ("^(apple|apple inc|apple services|apple one|apple music|apple tv|apple arcade|apple fitness|icloud|itunes|app store|apple com bill|apple com)\\b",
         "https://upload.wikimedia.org/wikipedia/commons/thumb/f/fa/Apple_logo_black.svg/500px-Apple_logo_black.svg.png", "Apple Inc.", "apple.com"),
    ]

    /// Festes Logo zu Name oder Website (Web `logoPin`)
    public static func pin(name: String, web: String = "") -> LogoPin? {
        let n = Partners.lnorm(name)
        var d = Format.domain(of: web)
        if d.lowercased().hasPrefix("www.") { d.removeFirst(4) }
        for p in pins {
            let hit = n.range(of: p.pattern, options: .regularExpression) != nil || (!d.isEmpty && d == p.domain)
            if hit { return LogoPin(url: p.url, title: p.title, domain: p.domain) }
        }
        return nil
    }

    /// Wörter, die allein nie als Markenwort taugen (Web v294: Kita, Praxis, Garage …)
    static let notBrand: Set<String> = ["kita", "krippe", "schule", "praxis", "garage", "immobilien", "immo", "wohnbau", "hausverwaltung", "fitness",
                                        "studio", "zahnarzt", "arzt", "apotheke", "physio", "physiotherapie", "kanzlei", "treuhand", "stiftung",
                                        "pensionskasse", "reinigung", "hauswart", "elektro", "sanitar", "maler", "transport", "taxi", "autohaus",
                                        "carrosserie", "restaurant", "hotel", "camping", "musikschule", "sport", "verein"]

    private static func rawWords(_ name: String) -> [String] {
        name.replacingOccurrences(of: "[.,()]", with: " ", options: .regularExpression)
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).map(String.init)
    }

    /// Kürzere Suche (Web allCands v294): nur eindeutige Firmentreffer zählen; Ämter («Stadtverwaltung …») werden nie gekürzt
    public static func shorten(_ name: String) -> LogoShortening {
        let raw = rawWords(name)
        let words = raw.filter { w in
            let t = Partners.lnorm(w)
            return !t.isEmpty && !Partners.LSTOP.contains(t) && !Partners.LGEN.contains(t) && !Partners.LADJ.contains(t)
        }
        var amt = words.contains { w in
            let t = Partners.lnorm(w)
            return Partners.LPLACE.contains { pl in t == pl || t.hasPrefix(pl) || t.hasSuffix(pl) }
        }
        // Marke steht vorne: erstes Wort (nach «Schweizerische» & Co.) muss erhalten bleiben
        let w1 = raw.first { w in
            let t = Partners.lnorm(w)
            return !t.isEmpty && !Partners.LADJ.contains(t) && !Partners.LSTOP.contains(t)
        } ?? ""
        if words.isEmpty || Partners.lnorm(words[0]) != Partners.lnorm(w1) { amt = true }
        var vars: [String] = []
        if !amt && !words.isEmpty {
            let v1 = words.joined(separator: " ")
            if Partners.lnorm(v1) != Partners.lnorm(name) { vars.append(v1) }
            let w0 = Partners.lnorm(words[0])
            if words.count > 1 && w0.count >= 5 && Partners.lusable(words[0]) && !notBrand.contains(w0) { vars.append(words[0]) }
        }
        return LogoShortening(words: words, amt: amt, variants: vars)
    }

    /// Kürzer gefundene Treffer zählen höchstens 4.5 Punkte (Web v294)
    public static let shortenedMaxScore = 4.5

    /// Website raten, wenn keine bekannt ist (Web d6fc9de): zuerst das Markenwort («protekta»), dann der ganze Name ohne
    /// Allerweltswörter. `shortening` nur, wenn kürzer gesucht wurde. Endungen je Währung: EUR de/com/ch, sonst ch/com/de.
    public static func guessDomains(_ name: String, currency: Currency, shortening: LogoShortening?) -> [String] {
        var bases: [String] = []
        if let s = shortening, !s.words.isEmpty, !s.amt {
            let gw = Partners.lnorm(s.words[0]).replacingOccurrences(of: "[^a-z0-9]", with: "", options: .regularExpression)
            if gw.count >= 4 && Partners.lusable(gw) { bases.append(gw) }
        }
        let base = Partners.ltok(name).filter { !Partners.LGEN.contains($0) }.joined()
        if !base.isEmpty && !bases.contains(base) { bases.append(base) }
        let tl = currency == .EUR ? ["de", "com", "ch"] : ["ch", "com", "de"]
        return bases.flatMap { b in tl.map { b + "." + $0 } }
    }

    /// Wann eine Website geraten wird: keine Website bekannt und (manuelle Suche oder nichts Eindeutiges ≥ 3 Punkte)
    public static func shouldGuess(knownDomain: String, manual: Bool, bestScore: Double) -> Bool {
        knownDomain.isEmpty && (manual || bestScore < 3)
    }

    /// Profilbild (X/Instagram) aus einem Wikidata-Eintrag übernehmen? (Web v292: «Sunrise» traf das Anime-Studio)
    /// Website bekannt → nur der Eintrag mit dieser Website; sonst der erste exakte Firmentreffer. Ein Eintrag mit passender
    /// Website ersetzt einen früheren ohne. Rückgabe: true = `handles` übernehmen.
    public static func takeSocial(hasCurrent: Bool, currentDomOk: Bool, handles: Int, exactOrg: Bool, domOk: Bool, domKnown: Bool) -> Bool {
        guard exactOrg, domOk || !domKnown, handles > 0 else { return false }
        return !hasCurrent || (domOk && !currentDomOk)
    }
}
