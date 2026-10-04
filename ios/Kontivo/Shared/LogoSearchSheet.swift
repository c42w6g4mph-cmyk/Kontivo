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
        if manual && !wr.social.isEmpty {
            all += await socialCands(wr.social)
        }
        var seen = Set<String>()
        all = all.filter { seen.insert($0.url).inserted }
        return (stableSorted(all, by: candLess), d2)
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

    /// App-Store-Bilder und Favicons (logoBlob): Mindestkante, Seitenverhältnis 0.8–1.25, nicht leer, 512×512 auf weiss
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
            let out = render512(.white) { r in im.draw(in: r) }
            if let png = out.pngData() { return .success(LogoImage(png: png, background: "#FFFFFF")) }
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

// MARK: - Ansicht

/// Logo-Suche mit Vorschlägen (Wikidata/Commons, App Store, Website-Symbol). Übernahme nur nach Antippen.
/// onPick liefert PNG-Daten (512×512) und die Hintergrundfarbe (Hex); danach schliesst sich das Fenster.
/// Den Toast nach der Übernahme («Logo übernommen» bzw. «Logo gespeichert») zeigt der Aufrufer.
struct LogoSearchSheet: View {
    let name: String
    let currency: Currency
    let web: String
    let onPick: (Data, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .idle
    @State private var cands: [LogoCandidate] = []
    @State private var busyID: String?
    @State private var notice: String?
    @State private var noticeTask: Task<Void, Never>?

    private enum Phase { case idle, searching, done, noName, offline }

    var body: some View {
        NavigationStack {
            ScrollView {
                content
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
            .overlay(alignment: .bottom) { noticeView }
        }
        .task { await search() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .idle, .searching:
            HStack(spacing: 10) {
                ProgressView()
                Text("Suche Logos…").font(.subheadline).foregroundStyle(KColor.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
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

    private func message(_ t: String) -> some View {
        Text(t)
            .font(.subheadline)
            .foregroundStyle(KColor.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var results: some View {
        let list = Array(cands.prefix(10))
        return VStack(alignment: .leading, spacing: 12) {
            message((list.first?.score ?? 0) >= 3 ? "Tippe auf das passende Logo:" : "Keine eindeutige Übereinstimmung – passt eines davon?")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                ForEach(list) { c in
                    tile(c)
                }
            }
        }
    }

    private func tile(_ c: LogoCandidate) -> some View {
        let busy = busyID == c.id
        return Button {
            Task { await pick(c) }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
                    AsyncImage(url: URL(string: c.thumb)) { ph in
                        if let img = ph.image {
                            img.resizable().interpolation(.high).scaledToFit()
                        } else if ph.error != nil {
                            Image(systemName: "photo").foregroundStyle(Color.gray.opacity(0.5))
                        } else {
                            ProgressView()
                        }
                    }
                    .padding(6)
                    if busy {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.35))
                        ProgressView().tint(.white)
                    }
                }
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(c.title.isEmpty ? " " : c.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(KColor.ink)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Text(c.src.label)
                    .font(.caption2)
                    .foregroundStyle(KColor.ink2)
            }
            .padding(8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
            .opacity(c.score >= 3 ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(busyID != nil)
        .accessibilityLabel(c.title + ", " + c.src.label)
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
                .padding(.bottom, 24)
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
        let primary = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if primary.isEmpty && Format.domain(of: web).isEmpty {
            phase = .noName
            return
        }
        phase = .searching
        if !(await NetCheck.isOnline()) {
            phase = .offline
            return
        }
        let cs = await LogoFinder.manualCandidates(name: primary, currency: currency, web: web)
        cands = cs
        phase = .done
    }

    private func pick(_ c: LogoCandidate) async {
        guard busyID == nil else { return }
        busyID = c.id
        show("Übernehme Logo…", seconds: 30)
        let r = await LogoFinder.take(c)
        busyID = nil
        switch r {
        case .success(let img):
            noticeTask?.cancel()
            notice = nil
            onPick(img.png, img.background)
            dismiss()
        case .failure(let e):
            show(e.message)
        }
    }
}
