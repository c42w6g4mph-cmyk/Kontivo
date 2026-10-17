import SwiftUI
import UIKit
import Network
import KontivoCore

// MARK: - Netz und Links (gemeinsam für Logo-, Adress- und Kurssuche)

/// Netzstatus wie `navigator.onLine` der Web-App: kurzer Blick auf den aktuellen Pfad (NWPathMonitor).
enum NetCheck {
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false
        private let cont: CheckedContinuation<Bool, Never>
        init(_ c: CheckedContinuation<Bool, Never>) { cont = c }
        func finish(_ v: Bool) {
            lock.lock(); defer { lock.unlock() }
            if done { return }
            done = true
            cont.resume(returning: v)
        }
    }

    /// true, wenn eine Verbindung besteht (im Zweifel nach 1.5 s true, damit nichts blockiert)
    static func isOnline() async -> Bool {
        await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in
            let once = Once(c)
            let m = NWPathMonitor()
            let q = DispatchQueue(label: "ch.kontivo.netcheck")
            m.pathUpdateHandler = { p in
                once.finish(p.status == .satisfied)
                m.cancel()
            }
            m.start(queue: q)
            q.asyncAfter(deadline: .now() + 1.5) {
                once.finish(true)
                m.cancel()
            }
        }
    }
}

/// Externe Links an einer Stelle (A10)
enum WebLinks {
    /// Google-Bildersuche «<Name> logo» (logoSearch der Web-App); öffnet in Safari
    static func googleImages(_ name: String) -> URL? {
        URL(string: "https://www.google.com/search?tbm=isch&q=" + LogoFinder.enc(name.trimmingCharacters(in: .whitespacesAndNewlines) + " logo"))
    }
}

// MARK: - Kandidaten

/// Quelle eines Logo-Vorschlags (LSRC der Web-App)
enum LogoSource: String, Hashable, Sendable {
    case wiki, store, site, social, web

    var label: String {
        switch self {
        case .wiki: return "Wikipedia"
        case .web: return "Website"
        case .site: return "Website-Symbol"
        case .social: return "Profilbild"
        case .store: return "App Store"
        }
    }
}

/// Ein Logo-Vorschlag
struct LogoCandidate: Identifiable, Hashable, Sendable {
    var url: String
    var thumb: String
    var title: String
    var seller: String
    var score: Double
    var src: LogoSource
    var id: String { url }
}

/// Übernommenes Logo: PNG 512×512 und Hintergrund (Hex)
struct LogoImage: Sendable {
    var png: Data
    var background: String
}

/// Fehler bei der Übernahme (LERR)
enum LogoError: Error, Sendable {
    case small, empty, load, storage, failed

    var message: String {
        switch self {
        case .small: return "Bild zu klein oder nicht quadratisch"
        case .empty: return "Bild wirkt leer oder einfarbig"
        case .load: return "Bild konnte nicht geladen werden"
        case .storage: return "Speichern nicht möglich"
        case .failed: return "Übernahme fehlgeschlagen"
        }
    }
}

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

    private static let urlSafe = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

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

    /// Bild laden (Zeitlimit wie im Inventar: ca. 10 s)
    static func loadImage(_ urlString: String, timeout: TimeInterval = 10) async -> UIImage? {
        guard let d = await fetchData(urlString, timeout: timeout) else { return nil }
        return UIImage(data: d)
    }

    // MARK: Wikidata / Commons

    struct WikiResult {
        var cands: [LogoCandidate] = []
        var dom = ""
        var social: [(p: String, h: String)] = []
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

    private static func langValue(_ any: Any?) -> String? {
        guard let m = any as? [String: Any] else { return nil }
        for l in ["de", "en"] {
            if let o = m[l] as? [String: Any], let v = o["value"] as? String, !v.isEmpty { return v }
        }
        return nil
    }

    private static func names(of en: [String: Any]) -> [String] {
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

    private static func num(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private struct WikiRaw {
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
            if exact && isOrg && social.isEmpty {
                for (p, prop) in [("x", "P2002"), ("instagram", "P2003")] {
                    if let h = claims(en, prop).first, !h.isEmpty { social.append((p: p, h: h)) }
                }
            }
            guard let f = file, !f.isEmpty else { continue }
            let domOk = !dom.isEmpty && sites.contains { Partners.regDom($0) == Partners.regDom(dom) }
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

    // MARK: App Store

    private static func str(_ r: [String: Any], _ k: String) -> String {
        (r[k] as? String) ?? ""
    }

    /// Punkte für einen App-Store-Treffer (lscore)
    static func lscore(_ name: String, _ r: [String: Any], _ dom: String) -> Int {
        let want = Partners.ltok(name)
        if !Partners.lusable(name) { return 0 }
        let genre = str(r, "primaryGenreName").lowercased()
        if genre.contains("game") || genre.contains("spiel") { return 0 }
        let sellerName = str(r, "sellerName")
        let seller = sellerName.isEmpty ? str(r, "artistName") : sellerName
        let track = str(r, "trackName")
        let sellerUrl = str(r, "sellerUrl")
        let byDom = !dom.isEmpty && !sellerUrl.isEmpty && Partners.regDom(Format.domain(of: sellerUrl)) == Partners.regDom(dom)
        var sc = 0
        if Partners.nameEq(want, seller) || byDom {
            sc = 3
            if Partners.nameEq(want, track) { sc += 2 } else if Partners.nameHas(want, track) { sc += 1 }
            if byDom { sc += 2 }
        } else if Partners.nameEq(want, track) {
            sc = 2
        } else if Partners.nameHas(want, track) || Partners.nameHas(want, seller) {
            sc = 1
        }
        return sc
    }

    /// iTunes Search API (logoCands), Länder je Währung; Abbruch, sobald ein Treffer ≥ 3 Punkte hat
    static func storeCands(_ name: String, currency: Currency, dom: String) async -> [LogoCandidate] {
        let countries: [String]
        switch currency {
        case .EUR: countries = ["de", "ch"]
        case .USD: countries = ["us", "ch"]
        case .GBP: countries = ["gb", "ch"]
        case .TRY: countries = ["tr", "de"]
        default: countries = ["ch", "de"]
        }
        let tk = Partners.ltok(name).joined(separator: " ")
        let term = tk.isEmpty ? name.trimmingCharacters(in: .whitespacesAndNewlines) : tk
        if term.isEmpty { return [] }
        var seen = Set<String>()
        var out: [LogoCandidate] = []
        for cc in countries {
            let j = await fetchJSON("https://itunes.apple.com/search?entity=software&limit=20&country=" + cc + "&term=" + enc(term), timeout: 9)
            for r in (j?["results"] as? [[String: Any]]) ?? [] {
                let a512 = str(r, "artworkUrl512")
                let a100 = str(r, "artworkUrl100")
                let u = a512.isEmpty ? a100 : a512
                if u.isEmpty { continue }
                let tid = (r["trackId"] as? NSNumber)?.stringValue ?? "?"
                if seen.contains(tid) { continue }
                seen.insert(tid)
                let sc = lscore(name, r, dom)
                if sc > 0 {
                    let sn = str(r, "sellerName")
                    out.append(LogoCandidate(url: u, thumb: a100.isEmpty ? u : a100, title: str(r, "trackName"),
                                             seller: sn.isEmpty ? str(r, "artistName") : sn, score: Double(sc), src: .store))
                }
            }
            if out.contains(where: { $0.score >= 3 }) { break }
        }
        return stableSorted(out) { $0.score > $1.score }
    }

    // MARK: Website, Profilbild, Favicon

    private static func pixelSize(_ im: UIImage) -> (w: CGFloat, h: CGFloat) {
        (im.size.width * im.scale, im.size.height * im.scale)
    }

    /// App-Symbol der Website (siteCand): gstatic faviconV2 256 px, /apple-touch-icon.png, www.-Variante; ab 120 px, fast quadratisch
    static func siteCand(_ domain: String, score: Double) async -> LogoCandidate? {
        let d = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return nil }
        let bare = d.lowercased().hasPrefix("www.") ? String(d.dropFirst(4)) : d
        let srcs = ["https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&size=256&url=https://" + d,
                    "https://" + d + "/apple-touch-icon.png",
                    "https://www." + bare + "/apple-touch-icon.png"]
        for s in srcs {
            guard let im = await loadImage(s) else { continue }
            let (w, h) = pixelSize(im)
            if w >= 120 && h >= 120 && w / h > 0.9 && w / h < 1.1 {
                return LogoCandidate(url: s, thumb: s, title: d, seller: "", score: score, src: .site)
            }
        }
        return nil
    }

    /// Profilbild auf X/Instagram (socialCands, nur manuell, höchstens 2)
    static func socialCands(_ list: [(p: String, h: String)]) async -> [LogoCandidate] {
        var out: [LogoCandidate] = []
        for s in list.prefix(2) {
            let u = "https://unavatar.io/" + s.p + "/" + enc(s.h) + "?fallback=false"
            if let im = await loadImage(u), pixelSize(im).w >= 150 {
                out.append(LogoCandidate(url: u, thumb: u, title: "@" + s.h, seller: "", score: 4, src: .social))
            }
        }
        return out
    }

    /// Website-Symbol über Google (faviconCand, nur manuell, Punkte 0)
    static func faviconCand(_ domain: String) -> LogoCandidate? {
        let d = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return nil }
        let u = "https://www.google.com/s2/favicons?sz=256&domain=" + enc(d)
        return LogoCandidate(url: u, thumb: u, title: d, seller: "", score: 0, src: .web)
    }

    // MARK: Alle Quellen

    /// Reihenfolge nach Punkten; bei Gleichstand Wikipedia vor anderen (candSort)
    static func candLess(_ a: LogoCandidate, _ b: LogoCandidate) -> Bool {
        if a.score != b.score { return a.score > b.score }
        return a.src == .wiki && b.src != .wiki
    }

    /// Alle Vorschläge (allCands). `alt` = Bezeichnung (nur Vorschläge, höchstens 2.5 Punkte). Liefert auch die bekannte Domain.
    static func allCandidates(name: String, currency: Currency, alt: String?, web: String, manual: Bool) async -> (cands: [LogoCandidate], dom: String) {
        let dom = Format.domain(of: web)
        async let w = wikiCands(name, dom: dom)
        async let s = storeCands(name, currency: currency, dom: dom)
        let wr = await w
        let sr = await s
        var all = wr.cands + sr
        if !all.contains(where: { $0.score >= 3 }), let alt, Partners.lusable(alt), Partners.lnorm(alt) != Partners.lnorm(name) {
            async let w2 = wikiCands(alt, dom: "")
            async let s2 = storeCands(alt, currency: currency, dom: "")
            let more = (await w2).cands + (await s2)
            for var c in more {
                c.score = Swift.min(c.score, 2.5)
                all.append(c)
            }
        }
        let d2 = dom.isEmpty ? wr.dom : dom
        if let ic = await siteCand(d2, score: dom.isEmpty ? 5.5 : 6) { all.append(ic) }
        if manual && d2.isEmpty {
            let base = Partners.ltok(name).filter { !Partners.LGEN.contains($0) }.joined()
            let tl = currency == .EUR ? ["de", "com", "ch"] : ["ch", "com", "de"]
            if !base.isEmpty {
                for t in tl {
                    if let g = await siteCand(base + "." + t, score: 2.5) {
                        all.append(g)
                        break
                    }
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

    // MARK: Übernahme

    /// Logo übernehmen (takeLogo): Wikipedia eingepasst, Website/Profilbild füllend, App Store/Favicon geprüft
    static func take(_ c: LogoCandidate) async -> Result<LogoImage, LogoError> {
        switch c.src {
        case .wiki: return await padBlob(c.url, minPx: 200, full: false)
        case .site, .social: return await padBlob(c.url, minPx: 120, full: true)
        case .store: return await logoBlob(c.url, minSide: 256)
        case .web: return await logoBlob(c.url, minSide: 16)
        }
    }

    /// 512×512 deckend mit Hintergrund rendern
    static func render512(_ bg: UIColor, _ draw: (CGRect) -> Void) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let full = CGRect(x: 0, y: 0, width: 512, height: 512)
        return UIGraphicsImageRenderer(size: full.size, format: fmt).image { ctx in
            bg.setFill()
            ctx.fill(full)
            ctx.cgContext.interpolationQuality = .high
            draw(full)
        }
    }

    /// Helligkeit: Standardabweichung und Anteil deckender Pixel (Alpha > 200) einer Probe w×h
    static func lumaStats(_ im: UIImage, side: Int) -> (sd: Double, opaque: Double)? {
        guard let px = LogoPixels.rgba(im, width: side, height: side) else { return nil }
        var n = 0.0, sum = 0.0, sq = 0.0, op = 0.0
        var i = 0
        while i + 3 < px.count {
            let l = 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
            sum += l
            sq += l * l
            n += 1
            if px[i + 3] > 200 { op += 1 }
            i += 4
        }
        if n == 0 { return nil }
        let mean = sum / n
        return (sqrt(Swift.max(0, sq / n - mean * mean)), op / n)
    }

    /// App-Store-Bilder und Favicons (logoBlob): Mindestkante, Seitenverhältnis 0.8–1.25, nicht leer, 512×512;
    /// Kachel mit Rand/Glas-Saum (Web v181/v184/v185 `tileFix`/`tileDraw`): Rand und Ecken in Kachelfarbe übermalt, kein Zoom
    static func logoBlob(_ url: String, minSide: CGFloat) async -> Result<LogoImage, LogoError> {
        let big = url.replacingOccurrences(of: "/\\d+x\\d+bb\\.(jpg|jpeg|png|webp)$", with: "/512x512bb.png",
                                           options: [.regularExpression, .caseInsensitive])
        let srcs = big == url ? [url] : [big, url]
        for s in srcs {
            guard let im = await loadImage(s) else { continue }
            let (w, h) = pixelSize(im)
            if w < minSide || h < minSide || w / h < 0.8 || w / h > 1.25 { return .failure(.small) }
            guard let st = lumaStats(im, side: 32) else { continue }
            if st.sd < 6 || st.opaque < 0.6 { return .failure(.empty) }
            let tf = LogoTile.fix(im)
            if let out = LogoTile.draw(im, tf), let png = out.pngData() {
                return .success(LogoImage(png: png, background: tf.bg.isEmpty ? "#FFFFFF" : tf.bg))
            }
        }
        return .failure(.load)
    }

    /// Wikipedia-, Website- und Profilbilder (padBlob): eingepasst in ein 420er-Feld (bzw. füllend), weiss;
    /// wirkt das Ergebnis leer, auf dunklem Grund #1C1C1E
    static func padBlob(_ url: String, minPx: CGFloat, full: Bool) async -> Result<LogoImage, LogoError> {
        guard let im = await loadImage(url) else { return .failure(.load) }
        let (w, h) = pixelSize(im)
        if w <= 0 || h <= 0 { return .failure(.load) }
        if Swift.max(w, h) < minPx { return .failure(.small) }
        // Kachel (App-Symbol, Website-Symbol mit Saum): wie gespeichert zeichnen (Web v185)
        let tf0 = LogoTile.fix(im)
        if tf0.tile && tf0.sw >= 120, let out = LogoTile.draw(im, tf0), let png = out.pngData() {
            return .success(LogoImage(png: png, background: tf0.bg))
        }
        for hex in ["#FFFFFF", "#1C1C1E"] {
            let bg = hex == "#FFFFFF" ? UIColor.white : UIColor(red: 0x1C / 255.0, green: 0x1C / 255.0, blue: 0x1E / 255.0, alpha: 1)
            let k = full ? Swift.max(512 / w, 512 / h) : Swift.min(420 / w, 420 / h)
            let dw = w * k, dh = h * k
            let out = render512(bg) { _ in im.draw(in: CGRect(x: (512 - dw) / 2, y: (512 - dh) / 2, width: dw, height: dh)) }
            guard let st = lumaStats(out, side: 48) else { continue }
            if st.sd < 8 { continue }
            if let png = out.pngData() { return .success(LogoImage(png: png, background: hex)) }
        }
        return .failure(.empty)
    }

    static func stableSorted(_ a: [LogoCandidate], by less: (LogoCandidate, LogoCandidate) -> Bool) -> [LogoCandidate] {
        a.enumerated().sorted { x, y in
            if less(x.element, y.element) { return true }
            if less(y.element, x.element) { return false }
            return x.offset < y.offset
        }.map { $0.element }
    }
}

// MARK: - Kachel aufbereiten (Web tileFix/tileDraw, 1:1)

/// App-Symbole und Kacheln mit Rand (weisse Ecken, Rahmen, feiner Saum): Kachelfarbe aus den Seitenmitten, Ausschnitt auf die
/// Kachel begrenzen (kein Zoom); Saum und Ecken übermalt `draw` in Kachelfarbe.
enum LogoTile {
    struct Fix {
        var sx: CGFloat, sy: CGFloat, sw: CGFloat, sh: CGFloat
        /// Kachelfarbe «#RRGGBB», "" = keine Kachel
        var bg: String = ""
        var tile = false
        var rgb: [Int] = [255, 255, 255]
        var rad: CGFloat = 0
        var band: CGFloat = 0.045
    }

    /// JS `Math.round`
    private static func jr(_ v: CGFloat) -> Int { Int((v + 0.5).rounded(.down)) }

    static func fix(_ im: UIImage) -> Fix {
        let w = im.size.width * im.scale, h = im.size.height * im.scale
        let full = Fix(sx: 0, sy: 0, sw: w, sh: h)
        let N = 160
        guard let d = LogoPixels.rgba(im, width: N, height: N) else { return full }
        func P(_ x0: CGFloat, _ y0: CGFloat) -> [Int] {
            let x = Swift.max(0, Swift.min(N - 1, jr(x0))), y = Swift.max(0, Swift.min(N - 1, jr(y0)))
            let i = (y * N + x) * 4
            return [Int(d[i]), Int(d[i + 1]), Int(d[i + 2]), Int(d[i + 3])]
        }
        func dist(_ a: [Int], _ b: [Int]) -> Int {
            if a[3] < 40 && b[3] < 40 { return 0 }
            if (a[3] < 40) != (b[3] < 40) { return 999 }
            return Swift.abs(a[0] - b[0]) + Swift.abs(a[1] - b[1]) + Swift.abs(a[2] - b[2])
        }
        let C = P(1, 1)
        func bg(_ p: [Int]) -> Bool { p[3] < 40 || dist(p, C) < 36 }
        var x0 = N, y0 = N, x1 = -1, y1 = -1
        for y in 0..<N {
            for x in 0..<N where !bg(P(CGFloat(x), CGFloat(y))) {
                if x < x0 { x0 = x }
                if x > x1 { x1 = x }
                if y < y0 { y0 = y }
                if y > y1 { y1 = y }
            }
        }
        if x1 < 0 { return full }
        let bw = CGFloat(x1 - x0 + 1), bh = CGFloat(y1 - y0 + 1)
        if bw / bh < 0.85 || bw / bh > 1.18 { return full }
        // Kachelfarbe 10 % innerhalb der Seitenmitten; Kachel nur, wenn alle vier gleich und auch die Ecken (14 % diagonal) Kachel sind
        let cx = CGFloat(x0 + x1) / 2, cy = CGFloat(y0 + y1) / 2
        let fx0 = CGFloat(x0), fy0 = CGFloat(y0), fx1 = CGFloat(x1), fy1 = CGFloat(y1)
        let E = [P(cx, fy0 + bh * 0.1), P(cx, fy1 - bh * 0.1), P(fx0 + bw * 0.1, cy), P(fx1 - bw * 0.1, cy)]
        if E.contains(where: bg) { return full }
        for a in 1..<4 where dist(E[0], E[a]) > 60 { return full }
        let T = (0..<3).map { k in jr(CGFloat(E[0][k] + E[1][k] + E[2][k] + E[3][k]) / 4) } + [255]
        func near(_ p: [Int]) -> Bool { dist(p, T) < 54 }
        let corners: [(CGFloat, CGFloat)] = [(0.14, 0.14), (0.86, 0.14), (0.14, 0.86), (0.86, 0.86)]
        for f in corners where !near(P(fx0 + bw * f.0, fy0 + bh * f.1)) { return full }
        // Saum: von jeder Seitenmitte nach innen bis zur Kachelfarbe
        var rim = 0
        let lim = jr(bw * 0.08)
        for v in [(0, 1), (0, -1), (1, 0), (-1, 0)] {
            let sx0: CGFloat = v.0 != 0 ? (v.0 > 0 ? fx0 : fx1) : cx
            let sy0: CGFloat = v.1 != 0 ? (v.1 > 0 ? fy0 : fy1) : cy
            var k = 0
            while k < lim && !near(P(sx0 + CGFloat(v.0 * k), sy0 + CGFloat(v.1 * k))) { k += 1 }
            rim = Swift.max(rim, k)
        }
        // Eckenradius: entlang der Diagonale bis zur Kachelfarbe (Abstand ≈ 0,29 × Radius)
        var dg = 0
        while CGFloat(dg) < bw * 0.2 && !near(P(fx0 + CGFloat(dg), fy0 + CGFloat(dg))) { dg += 1 }
        let rad = Swift.min(bw * 0.3, Swift.max(0, CGFloat(dg - rim) / 0.29))
        let hex = "#" + T.prefix(3).map { String(format: "%02X", $0) }.joined()
        let fx = w / CGFloat(N), fy = h / CGFloat(N)
        return Fix(sx: fx0 * fx, sy: fy0 * fy, sw: bw * fx, sh: bh * fy, bg: hex, tile: true, rgb: Array(T.prefix(3)),
                   rad: Swift.max(0.2237, rad / bw), band: Swift.min(0.08, Swift.max(0.045, (CGFloat(rim) + 1.5) / bw)))
    }

    /// Kachel 512×512 zeichnen; Saum (`band`) und alles ausserhalb der runden Kachel in Kachelfarbe übermalen
    static func draw(_ im: UIImage, _ tf: Fix) -> UIImage? {
        let S = 512
        var buf = [UInt8](repeating: 0, count: S * S * 4)
        let w = im.size.width * im.scale, h = im.size.height * im.scale
        guard tf.sw > 0, tf.sh > 0, w > 0, h > 0 else { return nil }
        let cg: CGImage? = buf.withUnsafeMutableBytes { raw -> CGImage? in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            ctx.translateBy(x: 0, y: CGFloat(S))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            UIColor(Color(hex: tf.bg.isEmpty ? "#FFFFFF" : tf.bg)).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
            ctx.interpolationQuality = .high
            // Ausschnitt (sx, sy, sw, sh) auf 512×512 abbilden
            let kx = CGFloat(S) / tf.sw, ky = CGFloat(S) / tf.sh
            im.draw(in: CGRect(x: -tf.sx * kx, y: -tf.sy * ky, width: w * kx, height: h * ky))
            UIGraphicsPopContext()
            if tf.tile {
                let b = jr(tf.band * CGFloat(S))
                let R = Swift.max(0, tf.rad * CGFloat(S) - CGFloat(b))
                let lo = b, hi = S - 1 - b
                let px = base.assumingMemoryBound(to: UInt8.self)
                for y in 0..<S {
                    for x in 0..<S {
                        var out = x < lo || x > hi || y < lo || y > hi
                        if !out && R > 0 {
                            let fx = CGFloat(x), fy = CGFloat(y), flo = CGFloat(lo), fhi = CGFloat(hi)
                            let cx = fx < flo + R ? flo + R : (fx > fhi - R ? fhi - R : fx)
                            let cy = fy < flo + R ? flo + R : (fy > fhi - R ? fhi - R : fy)
                            if cx != fx && cy != fy {
                                let dx = fx - cx, dy = fy - cy
                                out = dx * dx + dy * dy > R * R
                            }
                        }
                        if out {
                            let i = (y * S + x) * 4
                            px[i] = UInt8(tf.rgb[0])
                            px[i + 1] = UInt8(tf.rgb[1])
                            px[i + 2] = UInt8(tf.rgb[2])
                            px[i + 3] = 255
                        }
                    }
                }
            }
            return ctx.makeImage()
        }
        return cg.map { UIImage(cgImage: $0) }
    }
}

// MARK: - Pixel

/// RGBA-Pixel eines Bildes (nicht vormultipliziert, Zeile 0 = oben), für Bildprüfung und Zuschneiden
enum LogoPixels {
    static func rgba(_ img: UIImage, width w: Int, height h: Int) -> [UInt8]? {
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw -> Bool in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            img.draw(in: CGRect(x: 0, y: 0, width: w, height: h))
            UIGraphicsPopContext()
            return true
        }
        guard ok else { return nil }
        var i = 0
        while i + 3 < buf.count {
            let a = Int(buf[i + 3])
            if a > 0 && a < 255 {
                buf[i] = UInt8(Swift.min(255, Int(buf[i]) * 255 / a))
                buf[i + 1] = UInt8(Swift.min(255, Int(buf[i + 1]) * 255 / a))
                buf[i + 2] = UInt8(Swift.min(255, Int(buf[i + 2]) * 255 / a))
            }
            i += 4
        }
        return buf
    }
}

// MARK: - Zwischenspeicher (Web LC_CACHE, LOGO_TAKEN)

/// Letzte Suchen (gleicher Name/Währung/Website, 20 Minuten) und übernommene Bilder je Adresse: erneutes Öffnen zeigt sofort
/// dieselbe Auswahl samt Markierung, erneutes Antippen lädt nicht neu (Web v184).
@MainActor
final class LogoCache {
    static let shared = LogoCache()
    private var lists: [String: (t: Date, cs: [LogoCandidate])] = [:]
    private var selected: [String: String] = [:]
    private var images: [String: LogoImage] = [:]
    /// Übernommen und gespeichert (Import): Adresse → Datei-ID und Hintergrund
    private var stored: [String: (id: String, bg: String)] = [:]

    static func key(_ name: String, _ cur: Currency, _ web: String) -> String {
        Partners.lnorm(name) + "|" + cur.rawValue + "|" + Format.domain(of: web)
    }

    func list(_ key: String) -> [LogoCandidate]? {
        guard let h = lists[key], Date().timeIntervalSince(h.t) < 20 * 60 else { return nil }
        return h.cs
    }

    func setList(_ key: String, _ cs: [LogoCandidate]) { if !cs.isEmpty { lists[key] = (Date(), cs) } }
    func selection(_ key: String) -> String? { selected[key] }
    func select(_ key: String, _ url: String) { selected[key] = url }
    func image(_ url: String) -> LogoImage? { images[url] }
    func setImage(_ url: String, _ img: LogoImage) { images[url] = img }
    func storedLogo(_ url: String, model: AppModel) -> (id: String, bg: String)? {
        guard let h = stored[url], model.files.has(h.id) else { return nil }
        return h
    }
    func setStored(_ url: String, _ v: (id: String, bg: String)) { stored[url] = v }
}

// MARK: - Ansicht

/// Logo-Suche mit Vorschlägen (Wikidata/Commons, App Store, Website-Symbol, Profilbild). Übernahme nur nach Antippen.
/// onPick liefert PNG-Daten (512×512) und die Hintergrundfarbe (Hex); danach schliesst sich das Fenster. Die Auswahl bleibt
/// 20 Minuten gespeichert (erneutes Öffnen zeigt sie sofort, das gewählte Logo markiert, Web v184).
/// Den Toast nach der Übernahme («Logo übernommen» bzw. «Logo gespeichert») zeigt der Aufrufer.
struct LogoSearchSheet: View {
    let name: String
    let currency: Currency
    let web: String
    let onPick: (Data, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LogoCandidatesView(name: name, currency: currency, web: web) { png, bg in
                    onPick(png, bg)
                    dismiss()
                }
                .padding(KMetric.gutter)
                .frame(maxWidth: KMetric.maxContent)
                .frame(maxWidth: .infinity)
            }
            .background(KColor.paper.ignoresSafeArea())
            .navigationTitle("Logo suchen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
    }
}

/// Vorschlagsliste wie im Web (`.lcands`, `paintCands`): Hinweis, Kacheln nebeneinander (64 pt breit, Bild 52 pt), Quelle darunter.
/// Für Formulare auch direkt einbettbar (Web zeigt die Liste unter dem Logo).
struct LogoCandidatesView: View {
    let name: String
    let currency: Currency
    let web: String
    var alt: String = ""
    let onPick: (Data, String) -> Void

    @State private var phase: Phase = .idle
    @State private var cands: [LogoCandidate] = []
    @State private var busyID: String?
    @State private var selected: String?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    private enum Phase { case idle, searching, done, noName, offline }

    private var primary: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? alt.trimmingCharacters(in: .whitespacesAndNewlines) : n
    }

    private var cacheKey: String { LogoCache.key(primary, currency, web) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { noticeView }
            .task { await search() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle, .searching:
            message("Suche Logos…")
        case .noName:
            message("Zuerst den Namen eintragen")
        case .offline:
            message("Keine Internetverbindung")
        case .done:
            if cands.isEmpty {
                message("Nichts gefunden. Tipp: Vertragspartner oder Bezeichnung so schreiben, wie die Firma heisst, eine Website eintragen, oder «Logo im Web suchen».")
            } else {
                results
            }
        }
    }

    /// `.lcmsg`: 12.5 pt, ink3, volle Breite
    private func message(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12.5))
            .foregroundStyle(KColor.ink3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var results: some View {
        let list = Array(cands.prefix(10))
        return VStack(alignment: .leading, spacing: 10) {
            message((list.first?.score ?? 0) >= 3 ? "Tippe auf das passende Logo:" : "Keine eindeutige Übereinstimmung – passt eines davon?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64, maximum: 64), spacing: 10, alignment: .top)], alignment: .leading, spacing: 10) {
                ForEach(list) { c in
                    LogoCandidateTile(c: c, busy: busyID == c.id, selected: selected == c.url) {
                        Task { await pick(c) }
                    }
                    .disabled(busyID != nil)
                }
            }
        }
    }

    @ViewBuilder private var noticeView: some View {
        if let t = notice {
            Text(t)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.horizontal, 24)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func show(_ t: String, seconds: Double = 2.4) {
        noticeTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { notice = t }
        noticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.2)) { notice = nil }
        }
    }

    private func search() async {
        guard phase == .idle else { return }
        if primary.isEmpty && Format.domain(of: web).isEmpty {
            phase = .noName
            return
        }
        // letzte Suche (20 min) sofort zeigen
        if let hit = LogoCache.shared.list(cacheKey) {
            cands = hit
            selected = LogoCache.shared.selection(cacheKey)
            phase = .done
            return
        }
        phase = .searching
        if !(await NetCheck.isOnline()) {
            phase = .offline
            return
        }
        let cs = primary.isEmpty ? [] : await LogoFinder.manualCandidates(name: primary, currency: currency, web: web)
        var all = cs
        if cs.isEmpty, let fc = LogoFinder.faviconCand(Format.domain(of: web)) { all = [fc] }
        LogoCache.shared.setList(cacheKey, all)
        cands = all
        phase = .done
    }

    private func pick(_ c: LogoCandidate) async {
        guard busyID == nil else { return }
        if let img = LogoCache.shared.image(c.url) {
            choose(c, img)
            return
        }
        busyID = c.id
        show("Übernehme Logo…", seconds: 30)
        let r = await LogoFinder.take(c)
        busyID = nil
        switch r {
        case .success(let img):
            noticeTask?.cancel()
            notice = nil
            LogoCache.shared.setImage(c.url, img)
            choose(c, img)
        case .failure(let e):
            show(e.message)
        }
    }

    private func choose(_ c: LogoCandidate, _ img: LogoImage) {
        selected = c.url
        LogoCache.shared.select(cacheKey, c.url)
        onPick(img.png, img.background)
    }
}

/// Eine Kachel (`.lcand`): Bild 52 pt (weiss, Ring), Titel 10.5 pt, Quelle 9.5 pt; schwach = Bild halb durchsichtig,
/// Wikipedia-Schriftzug eingepasst mit Rand; App-Symbole in der Vorschau schon wie gespeichert (Saum übermalt, Web v186).
struct LogoCandidateTile: View {
    let c: LogoCandidate
    let busy: Bool
    let selected: Bool
    let action: () -> Void
    @State private var preview: UIImage?

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    Color.white
                    if let p = preview {
                        Image(uiImage: p).resizable().interpolation(.high).scaledToFill()
                    } else {
                        AsyncImage(url: URL(string: c.thumb)) { ph in
                            if let img = ph.image {
                                if c.src == .wiki {
                                    img.resizable().interpolation(.high).scaledToFit().padding(6)
                                } else {
                                    img.resizable().interpolation(.high).scaledToFill()
                                }
                            } else if ph.error != nil {
                                Image(systemName: "photo").foregroundStyle(Color.gray.opacity(0.5))
                            } else {
                                ProgressView()
                            }
                        }
                    }
                    if busy {
                        Color.black.opacity(0.35)
                        ProgressView().tint(.white)
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .opacity(c.score >= 3 ? 1 : 0.55)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? KColor.brass : KColor.line, lineWidth: selected ? 2 : 1))
                Text(c.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(KColor.ink2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 64)
                Text(c.src.label)
                    .font(.system(size: 9.5))
                    .foregroundStyle(KColor.ink3)
                    .padding(.top, -2)
            }
            .frame(width: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(c.title + ", " + c.src.label)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .task(id: c.url) { await makePreview() }
    }

    /// Vorschau wie beim Speichern (nicht für Profilbild/Website-Symbol)
    private func makePreview() async {
        if c.src == .social || c.src == .site { return }
        let big = c.url.replacingOccurrences(of: "/\\d+x\\d+bb\\.(jpg|jpeg|png|webp)$", with: "/512x512bb.png",
                                             options: [.regularExpression, .caseInsensitive])
        var im = await LogoFinder.loadImage(big)
        if im == nil { im = await LogoFinder.loadImage(c.thumb) }
        guard let img = im else { return }
        let tf = LogoTile.fix(img)
        guard tf.tile, let out = LogoTile.draw(img, tf) else { return }
        preview = out
    }
}
