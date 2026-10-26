import Foundation

// MARK: - Kontoauszug: Vereine (Web BKCLUBW, BKCLUBA, bankClub, BKCLUBL, bankClubLabel; Web v331 ff.)
// Sport-, Musik-, Kultur- und andere Vereine CH/DE/AT. Wörter überall im Text; Kürzel nur am Namensanfang
// («FC Paradies», «TV Konstanz», «AS Calcio») und ohne Firmenform (AG/GmbH), damit «TV Media AG» oder Kantonskürzel nicht treffen.

enum BankClub {
    static let BKCLUBW = BRX("\\b(verein|vereins|club|klub|turnverein|turngemeinde|turnerschaft|turnerbund|sportverein|sportclub|sportgemeinschaft|spielvereinigung|fussballclub|fussballverein|fussball club|calcio|futbol|tennisclub|tennis club|tischtennis|schwimmclub|schwimmverein|skiclub|ski club|eishockey|handballclub|handball|volleyball|basketball|unihockey|floorball|leichtathletik|judo|karate|taekwondo|ringerclub|boxclub|reitverein|reitclub|golfclub|golf club|schutzenverein|schuetzenverein|schutzengesellschaft|schuetzengesellschaft|ruderclub|segelclub|yachtclub|kanuclub|wassersport|radsport|veloclub|velo club|radfahrverein|alpenverein|alpenclub|bergsteiger|samariterverein|lebensrettung|slrg|dlrg|musikverein|musikgesellschaft|stadtmusik|feldmusik|harmonie|blasmusik|brass band|guggenmusik|chor|mannerchor|maennerchor|frauenchor|kirchenchor|gesangverein|jodlerklub|jodlerclub|theaterverein|trachtenverein|narrenzunft|fasnachtsgesellschaft|zunft|kulturverein|forderverein|foerderverein|elternverein|quartierverein|dorfverein|frauenverein|pfadi|pfadfinder|jungwacht|blauring|cevi|tierschutzverein|kleingartenverein|gartenverein|imkerverein|kynologisch|hundesportverein|modellflug|schachclub|schachverein|jassclub)\\b")
    static let BKCLUBA = BRX("^(fc|sc|sv|sg|spvgg|tsv|tus|tsg|tv|vfb|vfl|vfr|mtv|esv|psv|bsc|bsv|ssv|fsv|djk|asv|atsv|ksv|ttc|ttv|tc|thc|hc|ehc|uhc|ihc|rc|rsc|rsv|bc|vc|bbc|stv|dtv|etv|ktv|btv|mtv|lc|lg|lac|sac|dav|oav|ssc|skc|kc|fv|ffc|jfv|sfv|satus|cevi)\\s+[a-z]")
    static let rxNoClub = BRX("\\b(bank|store|shop|online|versand|hotel|resort|reise|reisen|ferien|urlaub|travel)\\b|club med")
    static let rxFirm = BRX("\\b(ag|gmbh|sa|sarl|ltd|inc|kg|ug|ohg|se)\\b")
    static let rxClubWord = BRX("verein|club|klub")

    /// Verein? (Web `bankClub(name, hay)`): `hay` = Name plus Mitteilung bzw. Buchungstext, leer → Name
    static func isClub(_ name: String, _ hay: String) -> Bool {
        let n = Partners.lnorm(name)
        if BankCatalog.BKRETAIL.test(n) || rxNoClub.test(n) { return false }
        let h = Partners.lnorm(hay.isEmpty ? n : hay)
        if rxFirm.test(n) { return BKCLUBW.test(h) && rxClubWord.test(n) }
        return BKCLUBA.test(n) || BKCLUBW.test(h)
    }

    /// Bezeichnung aus der Vereinsart; sonst «Mitgliedschaft» (Web `BKCLUBL`)
    static let BKCLUBL: [(BRX, String)] = [
        (BRX("fussball|calcio|futbol|^(fc|fv|ffc|jfv|sfv)\\s"), "Fussball"), (BRX("tischtennis|^(ttc|ttv)\\s"), "Tischtennis"), (BRX("tennis|^tc\\s"), "Tennis"),
        (BRX("eishockey|^(ehc|ihc)\\s"), "Eishockey"), (BRX("unihockey|floorball|^uhc\\s"), "Unihockey"), (BRX("handball"), "Handball"),
        (BRX("volleyball|^vc\\s"), "Volleyball"), (BRX("basketball|^bbc\\s"), "Basketball"), (BRX("turn|^(tv|stv|dtv|etv|ktv|btv|mtv|satus)\\s"), "Turnverein"),
        (BRX("schwimm|wassersport|lebensrettung|slrg|dlrg"), "Schwimmen"), (BRX("ski"), "Skiclub"), (BRX("leichtathletik|^(lc|lg|lac)\\s"), "Leichtathletik"),
        (BRX("reit"), "Reiten"), (BRX("golf"), "Golf"), (BRX("schutzen|schuetzen"), "Schützenverein"), (BRX("ruder|segel|yacht|kanu"), "Wassersport"),
        (BRX("radsport|velo|radfahr"), "Radsport"), (BRX("alpen|bergsteiger|^(sac|dav|oav)\\s"), "Alpenverein"), (BRX("judo|karate|taekwondo|ringer|box"), "Kampfsport"),
        (BRX("chor|gesang|jodler"), "Chor"), (BRX("musik|harmonie|blasmusik|brass band|gugge"), "Musikverein"), (BRX("theater"), "Theaterverein"),
        (BRX("pfadi|pfadfinder|jungwacht|blauring|cevi"), "Pfadi / Jugendverband"), (BRX("schach"), "Schachclub"), (BRX("narren|fasnacht|zunft"), "Fasnacht"),
        (BRX("samariter"), "Samariterverein"),
    ]

    /// Bezeichnung eines Vereins (Web `bankClubLabel`): "" = kein Verein
    static func label(_ name: String, _ hay: String) -> String {
        if !isClub(name, hay) { return "" }
        let n = Partners.lnorm(name), h = n + " " + Partners.lnorm(hay)
        for (r, l) in BKCLUBL where r.test(n) || r.test(h) { return l }
        return "Mitgliedschaft"
    }
}
