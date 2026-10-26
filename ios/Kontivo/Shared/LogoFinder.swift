import SwiftUI
import UIKit
import KontivoCore

// MARK: - Suche (Port von wikiCands, logoCands, siteCand, socialCands, faviconCand, allCands, padBlob, logoBlob, takeLogo)

enum LogoFinder {
    static let wd = "https://www.wikidata.org/w/api.php?format=json&origin=*"

    /// Keine Firmen: Personen, Figuren, Werke, Orte, Sportereignisse … (WNOT)
    static let wnot: Set<String> = ["Q5", "Q95074", "Q15632617", "Q15773317", "Q11424", "Q5398426", "Q7889", "Q482994", "Q134556", "Q7725634",
                                    "Q571", "Q515", "Q70208", "Q262166", "Q1549591", "Q5119", "Q42744322", "Q486972", "Q3957", "Q532", "Q15284",
                                    "Q747074", "Q4022", "Q23397", "Q8502", "Q1656682", "Q13406463", "Q4167410", "Q17537576", "Q3305213", "Q1004", "Q11032"]

    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 20
        c.httpAdditionalHeaders = ["User-Agent": "Kontivo-iOS/1.0 (Vertragsverwaltung; Logo-Suche)"]
        return URLSession(configuration: c)
    }()

    static let urlSafe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Prozentkodierung für Abfrageparameter (streng, auch «+», «&», «|»)
    static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: urlSafe) ?? ""
    }

    // MARK: Netz

    static func fetchData(_ urlString: String, timeout: TimeInterval) async -> Data? {
        guard let u = URL(string: urlString) else { return nil }
        var req = URLRequest(url: u, cachePolicy: .useProtocolCachePolicy, timeoutInterval: timeout)
        req.setValue("application/json, image/*;q=0.9, */*;q=0.5", forHTTPHeaderField: "Accept")
        do {
            let (d, resp) = try await session.data(for: req)
            if let h = resp as? HTTPURLResponse, !(200..<300).contains(h.statusCode) { return nil }
            return d
        } catch {
            return nil
        }
    }

    /// JSON-Objekt (Wikidata/Commons 8 s, iTunes 9 s)
    static func fetchJSON(_ urlString: String, timeout: TimeInterval = 8) async -> [String: Any]? {
        guard let d = await fetchData(urlString, timeout: timeout) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    /// Bild laden (Web B02 `loadImg`: Zeitlimit 8 s, ein hängender Abruf hält sonst die ganze Logo-Suche auf)
    static func loadImage(_ urlString: String, timeout: TimeInterval = 8) async -> UIImage? {
        guard let d = await fetchData(urlString, timeout: timeout) else { return nil }
        return UIImage(data: d)
    }

    // MARK: Wikidata / Commons

    struct WikiResult {
        var cands: [LogoCandidate] = []
        var dom = ""
        var social: [(p: String, h: String)] = []
        /// Profilbild stammt vom Eintrag mit der bekannten Website (Web v292 `social.domOk`)
        var socialDomOk = false
    }

    /// Claims einer Eigenschaft ohne Rang «deprecated» (wclaims): Entitäten als ID, sonst Text
    static func claims(_ en: [String: Any], _ p: String) -> [String] {
        guard let cl = en["claims"] as? [String: Any], let arr = cl[p] as? [[String: Any]] else { return [] }
        var out: [String] = []
        for c in arr {
            if (c["rank"] as? String) == "deprecated" { continue }
            guard let ms = c["mainsnak"] as? [String: Any], let dv = ms["datavalue"] as? [String: Any], let v = dv["value"] else { continue }
            if let d = v as? [String: Any] {
                if let id = d["id"] as? String, !id.isEmpty { out.append(id) }
            } else if let s = v as? String, !s.isEmpty {
                out.append(s)
            }
        }
        return out
    }

    static func langValue(_ any: Any?) -> String? {
        guard let m = any as? [String: Any] else { return nil }
        for l in ["de", "en"] {
            if let o = m[l] as? [String: Any], let v = o["value"] as? String, !v.isEmpty { return v }
        }
        return nil
    }

    static func names(of en: [String: Any]) -> [String] {
        var out: [String] = []
        for k in ["labels", "aliases"] {
            guard let m = en[k] as? [String: Any] else { continue }
            for (_, v) in m {
                if let one = v as? [String: Any], let s = one["value"] as? String {
                    out.append(s)
                } else if let many = v as? [[String: Any]] {
                    for x in many { if let s = x["value"] as? String { out.append(s) } }
                }
            }
        }
        return out
    }

    static func num(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    struct WikiRaw {
        var file: String
        var title: String
        var desc: String
        var score: Double
        var exact: Bool
        var domOk: Bool
        var site: String
    }

    static func wikiCands(_ rawName: String, dom: String) async -> WikiResult {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        var res = WikiResult()
        guard Partners.lusable(name) else { return res }
        let want = Partners.ltok(name)
        let q1 = wd + "&action=query&list=search&srnamespace=0&srlimit=10&srsearch=" + enc(name + " haswbstatement:P154")
        let q2 = wd + "&action=wbsearchentities&type=item&limit=10&language=de&uselang=de&search=" + enc(name)
        async let r1 = fetchJSON(q1)
        async let r2 = fetchJSON(q2)
        let j1 = await r1
        let j2 = await r2
        var ids: [String] = []
        func add(_ id: String?) {
            if let id, !id.isEmpty, !ids.contains(id) { ids.append(id) }
        }
        if let q = j1?["query"] as? [String: Any], let s = q["search"] as? [[String: Any]] {
            for h in s { add(h["title"] as? String) }
        }
        if let s = j2?["search"] as? [[String: Any]] {
            for h in s { add(h["id"] as? String) }
        }
        if ids.isEmpty { return res }
        let top = Array(ids.prefix(20))
        let e = await fetchJSON(wd + "&action=wbgetentities&props=claims%7Clabels%7Caliases%7Cdescriptions&languages=de%7Cen%7Cfr%7Cit&ids="
                                + top.map { enc($0) }.joined(separator: "%7C"))
        let ents = e?["entities"] as? [String: Any] ?? [:]
        var out: [WikiRaw] = []
        var orgSites: [String] = []
        var social: [(p: String, h: String)] = []
        var socialDomOk = false
        for (rank, id) in top.enumerated() {
            guard let en = ents[id] as? [String: Any], en["claims"] is [String: Any] else { continue }
            let file = claims(en, "P8972").first ?? claims(en, "P2910").first ?? claims(en, "P154").first
            let ns = names(of: en)
            let exact = ns.contains { Partners.nameEq(want, $0) }
            let part = !exact && ns.contains { Partners.nameHas(want, $0) }
            if !exact && !part { continue }
            let notOrg = claims(en, "P31").contains { wnot.contains($0) }
            let hasOrgProp = ["P856", "P452", "P159", "P1454", "P749"].contains { !claims(en, $0).isEmpty }
            let isOrg = !notOrg && hasOrgProp
            let sites = claims(en, "P856").map { Format.domain(of: $0) }.filter { !$0.isEmpty }
            if exact && isOrg, let s0 = sites.first, !orgSites.contains(Partners.regDom(s0)) { orgSites.append(Partners.regDom(s0)) }
            let domOk = !dom.isEmpty && sites.contains { Partners.regDom($0) == Partners.regDom(dom) }
            // Profilbild nur vom richtigen Eintrag (Web v292): Website bekannt → nur der Eintrag mit dieser Website,
            // sonst der erste exakte Firmentreffer (bei Mehrdeutigkeit unten verworfen)
            var sh: [(p: String, h: String)] = []
            for (p, prop) in [("x", "P2002"), ("instagram", "P2003")] {
                if let h = claims(en, prop).first, !h.isEmpty { sh.append((p: p, h: h)) }
            }
            if LogoQuery.takeSocial(hasCurrent: !social.isEmpty, currentDomOk: socialDomOk, handles: sh.count, exactOrg: exact && isOrg,
                                    domOk: domOk, domKnown: !dom.isEmpty) {
                social = sh
                socialDomOk = domOk
            }
            guard let f = file, !f.isEmpty else { continue }
            let domBad = !dom.isEmpty && !sites.isEmpty && !domOk
            var sc: Double = (exact && isOrg) ? 3 : (exact ? 1.5 : 1)
            if domOk { sc = Swift.max(sc, 3) + 1 } else if domBad { sc = Swift.min(sc, 2) }
            let desc = langValue(en["descriptions"]) ?? ""
            let lab = langValue(en["labels"]) ?? f
            out.append(WikiRaw(file: f, title: lab, desc: desc, score: sc - Double(rank) * 0.001, exact: exact && isOrg, domOk: domOk, site: sites.first ?? ""))
        }
        // Mehrdeutig: mehrere passende Firmen mit verschiedenen Websites und keine passende Website
        let ex = out.filter { $0.exact }
        var exSites: [String] = []
        for o in ex {
            let d = Partners.regDom(o.site)
            if !d.isEmpty && !exSites.contains(d) { exSites.append(d) }
        }
        let ambiguous = !out.contains { $0.domOk } && ex.count > 1 && exSites.count != 1
        if ambiguous {
            for i in out.indices { out[i].score = Swift.min(out[i].score, 2.5) }
        }
        let best = out.first { $0.score >= 3 }
        let domain: String
        if let b = best, !b.site.isEmpty {
            domain = b.site
        } else {
            domain = (orgSites.count == 1 && !ambiguous) ? orgSites[0] : ""
        }
        res.dom = domain
        res.social = ambiguous ? [] : social
        res.socialDomOk = socialDomOk
        if out.isEmpty { return res }
        let first12 = Array(out.prefix(12))
        let titles = first12.map { enc("File:" + $0.file) }.joined(separator: "%7C")
        let q = await fetchJSON("https://commons.wikimedia.org/w/api.php?format=json&origin=*&action=query&prop=imageinfo&iiprop=url%7Csize&iiurlwidth=512&titles=" + titles)
        var norm: [String: String] = [:]
        var byT: [String: [String: Any]] = [:]
        if let qq = q?["query"] as? [String: Any] {
            for n in (qq["normalized"] as? [[String: Any]]) ?? [] {
                if let f = n["from"] as? String, let t = n["to"] as? String { norm[f] = t }
            }
            if let pages = qq["pages"] as? [String: Any] {
                for (_, pv) in pages {
                    if let pg = pv as? [String: Any], let t = pg["title"] as? String,
                       let ii = (pg["imageinfo"] as? [[String: Any]])?.first { byT[t] = ii }
                }
            }
        }
        for o in first12 {
            let t = "File:" + o.file
            guard let ii = byT[norm[t] ?? t] ?? byT[t.replacingOccurrences(of: "_", with: " ")] else { continue }
            let w = num(ii["thumbwidth"]) ?? num(ii["width"]) ?? 0
            let h = num(ii["thumbheight"]) ?? num(ii["height"]) ?? 0
            guard let u = (ii["thumburl"] as? String) ?? (ii["url"] as? String), !u.isEmpty else { continue }
            var sc = o.score
            let ar = (w > 0 && h > 0) ? Swift.max(w / h, h / w) : 1
            if ar > 3.2 { sc = Swift.min(sc, 2) } else if sc >= 3 && ar <= 1.6 { sc += 0.5 }
            res.cands.append(LogoCandidate(url: u, thumb: u, title: o.title, seller: o.desc, score: sc, src: .wiki))
        }
        return res
    }

    // MARK: Alle Quellen

    /// Reihenfolge nach Punkten; bei Gleichstand Wikipedia vor anderen (candSort)
    static func candLess(_ a: LogoCandidate, _ b: LogoCandidate) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return a.src == .wiki && b.src != .wiki
    }

    /// Festes Logo (Web `logoPin`, baab11e): Apple immer mit dem Wikipedia-Logo von Apple Inc.
    static func pinCand(_ name: String, web: String = "") -> LogoCandidate? {
        guard let p = LogoQuery.pin(name: name, web: web) else { return nil }
        return LogoCandidate(url: p.url, thumb: p.url, title: p.title, seller: "", score: p.score, src: .wiki)
    }

    /// Alle Vorschläge (allCands). `alt` = Bezeichnung (nur Vorschläge, höchstens 2.5 Punkte). Liefert auch die bekannte Domain.
    /// Ohne eindeutigen Treffer wird kürzer gesucht (v294) und – ohne bekannte Website – die Adresse geraten (d6fc9de).
    static func allCandidates(name: String, currency: Currency, alt: String?, web: String, manual: Bool) async -> (cands: [LogoCandidate], dom: String) {
        let dom = Format.domain(of: web)
        let pin = pinCand(name, web: web) ?? pinCand(alt ?? "")
        if let pin, !manual { return ([pin], dom) }
        async let w = wikiCands(name, dom: dom)
        async let s = storeCands(name, currency: currency, dom: dom)
        let wr = await w
        let sr = await s
        var all = wr.cands + sr
        func good() -> Bool { all.contains { $0.score >= 3 } }
        if !good(), let alt, Partners.lusable(alt), Partners.lnorm(alt) != Partners.lnorm(name) {
            async let w2 = wikiCands(alt, dom: "")
            async let s2 = storeCands(alt, currency: currency, dom: "")
            let more = (await w2).cands + (await s2)
            for var c in more {
                c.score = Swift.min(c.score, 2.5)
                all.append(c)
            }
        }
        // Nichts Brauchbares mit dem vollen Namen: kürzer suchen, nur eindeutige Firmentreffer (≥ 3) zählen (Web v294)
        var wdom = wr.dom
        var shortening: LogoShortening?
        if !good() {
            let sh = LogoQuery.shorten(name)
            shortening = sh
            for v in sh.variants {
                async let w3 = wikiCands(v, dom: dom)
                async let s3 = storeCands(v, currency: currency, dom: dom)
                let wr3 = await w3
                let gd = (wr3.cands + (await s3)).filter { $0.score >= 3 }
                if !gd.isEmpty {
                    for var c in gd {
                        c.score = Swift.min(c.score, LogoQuery.shortenedMaxScore)
                        all.append(c)
                    }
                    if dom.isEmpty && !wr3.dom.isEmpty && wdom.isEmpty { wdom = wr3.dom }
                    break
                }
            }
        }
        let d2 = dom.isEmpty ? wdom : dom
        if let ic = await siteCand(d2, score: dom.isEmpty ? 5.5 : 6) { all.append(ic) }
        // Keine Website bekannt und nichts Eindeutiges: Adresse raten, zuerst mit dem Markenwort (nur Vorschlag, 2.5 Punkte)
        if LogoQuery.shouldGuess(knownDomain: d2, manual: manual, bestScore: all.map { $0.score }.max() ?? 0) {
            for g in LogoQuery.guessDomains(name, currency: currency, shortening: shortening) {
                if let c = await siteCand(g, score: 2.5) {
                    all.append(c)
                    break
                }
            }
        }
        // Profilbild (X/Instagram) ist meist am saubersten → bevorzugt, auch bei der automatischen Suche (Web v186/v187)
        if !wr.social.isEmpty {
            for var c in await socialCands(wr.social) {
                c.score = 6.5
                all.append(c)
            }
        }
        if let pin { all.append(pin) }
        var seen = Set<String>()
        all = all.filter { seen.insert($0.url).inserted }
        return (stableSorted(all, by: candLess), d2)
    }

    /// Automatisch übernehmen (autoLogo): Vertragspartner, sonst Bezeichnung; die ersten bis zu drei guten Treffer (≥ 3 Punkte)
    /// der Reihe nach übernehmen. Liefert das erste brauchbare Bild samt Kandidat (für den Zwischenspeicher).
    static func autoLogo(name: String, currency: Currency, alt: String?, web: String) async -> (LogoCandidate, LogoImage)? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = n.isEmpty ? (alt ?? "") : n
        if primary.isEmpty || !Partners.lusable(primary) { return nil }
        let cs = await allCandidates(name: primary, currency: currency, alt: nil, web: web, manual: false).cands
        for c in cs.filter({ $0.score >= 3 }).prefix(3) {
            if case .success(let img) = await take(c) { return (c, img) }
        }
        return nil
    }

    /// Vorschläge wie «Logo automatisch finden» (runCands): ohne Website-Symbol kommt das Google-Favicon dazu
    static func manualCandidates(name: String, currency: Currency, web: String) async -> [LogoCandidate] {
        let primary = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let dom = Format.domain(of: web)
        var cs: [LogoCandidate] = []
        var d2 = dom
        if !primary.isEmpty {
            let r = await allCandidates(name: primary, currency: currency, alt: nil, web: web, manual: true)
            cs = r.cands
            if d2.isEmpty { d2 = r.dom }
        }
        if !cs.contains(where: { $0.src == .site }), let fc = faviconCand(d2) { cs.append(fc) }
        return cs
    }

}
