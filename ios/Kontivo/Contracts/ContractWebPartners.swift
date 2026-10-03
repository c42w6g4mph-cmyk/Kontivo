import Foundation
import UIKit
import KontivoCore

/// Vertragspartner-Vorschläge aus dem Internet (webPartners der Web-App): Wikidata-Suche mit Zeitlimit 8 s.
enum CTWebPartners {
    static let wd = "https://www.wikidata.org/w/api.php?format=json&origin=*"

    /// P31-Werte, die keine Firmen sind (Personen, Figuren, Werke, Orte, Ereignisse …)
    static let wnot: Set<String> = ["Q5", "Q95074", "Q15632617", "Q15773317", "Q11424", "Q5398426", "Q7889", "Q482994", "Q134556", "Q7725634",
                                    "Q571", "Q515", "Q70208", "Q262166", "Q1549591", "Q5119", "Q42744322", "Q486972", "Q3957", "Q532",
                                    "Q15284", "Q747074", "Q4022", "Q23397", "Q8502", "Q1656682", "Q13406463", "Q4167410", "Q17537576",
                                    "Q3305213", "Q1004", "Q11032"]

    static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 8
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpAdditionalHeaders = ["User-Agent": "Kontivo/0.1 (iOS-App; Vertragsverwaltung)"]
        return URLSession(configuration: cfg)
    }()

    /// Bilder: Zeitlimit 10 s
    static let imageSession: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 10
        cfg.timeoutIntervalForResource = 10
        cfg.httpAdditionalHeaders = ["User-Agent": "Kontivo/0.1 (iOS-App; Vertragsverwaltung)"]
        return URLSession(configuration: cfg)
    }()

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    /// Wert für eine URL-Abfrage kodieren
    static func enc(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }

    /// GET als JSON-Objekt; Fehler oder Zeitüberschreitung → nil
    static func json(_ s: String) async -> [String: Any]? {
        guard let url = URL(string: s) else { return nil }
        do {
            let (d, r) = try await session.data(from: url)
            guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { return nil }
            return try JSONSerialization.jsonObject(with: d) as? [String: Any]
        } catch {
            return nil
        }
    }

    /// Werte einer Eigenschaft ohne Rang «deprecated» (wclaims): Entitäten als ID, sonst Rohwert
    static func claims(_ en: [String: Any], _ p: String) -> [Any] {
        guard let cl = en["claims"] as? [String: Any], let arr = cl[p] as? [[String: Any]] else { return [] }
        var out: [Any] = []
        for c in arr {
            if (c["rank"] as? String) == "deprecated" { continue }
            guard let ms = c["mainsnak"] as? [String: Any], let dv = ms["datavalue"] as? [String: Any], let v = dv["value"] else { continue }
            if let o = v as? [String: Any], let id = o["id"] as? String {
                out.append(id)
            } else if let s = v as? String {
                if !s.isEmpty { out.append(s) }
            } else {
                out.append(v)
            }
        }
        return out
    }

    static func strings(_ en: [String: Any], _ p: String) -> [String] {
        claims(en, p).compactMap { $0 as? String }
    }

    private static func text(_ en: [String: Any], _ key: String, _ lang: String) -> String {
        guard let m = en[key] as? [String: Any], let l = m[lang] as? [String: Any] else { return "" }
        return (l["value"] as? String) ?? ""
    }

    /// Internet-Suche (mindestens 3 Zeichen, brauchbarer Name). Höchstens 4 Treffer.
    static func search(_ query: String) async -> [WebPartnerHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 3, Partners.lusable(q) else { return [] }
        guard let r = await json(wd + "&action=wbsearchentities&type=item&limit=8&language=de&uselang=de&search=" + enc(q)) else { return [] }
        let ids = ((r["search"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String }
        if ids.isEmpty { return [] }
        guard let e = await json(wd + "&action=wbgetentities&props=" + enc("claims|labels|descriptions") + "&languages=" + enc("de|en")
                                 + "&ids=" + enc(ids.joined(separator: "|"))) else { return [] }
        let ents = (e["entities"] as? [String: Any]) ?? [:]
        let nq = Partners.lnorm(q)
        var out: [WebPartnerHit] = []
        var seen = Set<String>()
        for id in ids {
            guard let en = ents[id] as? [String: Any], en["claims"] != nil else { continue }
            if strings(en, "P31").contains(where: { wnot.contains($0) }) { continue }
            let sites = strings(en, "P856").map { Format.domain(of: $0) }.filter { !$0.isEmpty }
            guard let dom = sites.first else { continue }
            var lab = text(en, "labels", "de")
            if lab.isEmpty { lab = text(en, "labels", "en") }
            if lab.isEmpty { continue }
            if !Partners.lnorm(lab).contains(nq) { continue }
            let k = Partners.regDom(dom)
            if seen.contains(k) { continue }
            seen.insert(k)
            let file = strings(en, "P8972").first ?? strings(en, "P2910").first ?? strings(en, "P154").first ?? ""
            let tel = strings(en, "P1329").first ?? ""
            var mail = strings(en, "P968").first ?? ""
            if mail.lowercased().hasPrefix("mailto:") { mail = String(mail.dropFirst(7)) }
            let p17 = strings(en, "P17")
            let cc = p17.contains("Q39") ? "CH" : (p17.contains("Q183") ? "DE" : (dom.hasSuffix(".ch") ? "CH" : (dom.hasSuffix(".de") ? "DE" : "")))
            let dde = text(en, "descriptions", "de")
            let den = text(en, "descriptions", "en")
            out.append(WebPartnerHit(name: lab, desc: dde.isEmpty ? den : dde, descAll: dde + " " + den, dom: dom, cc: cc,
                                     tel: tel, mail: mail, file: file))
        }
        return Array(out.prefix(4))
    }

    /// Vorschaubild eines Treffers: Logo-Datei aus Commons, sonst Website-Symbol
    static func thumbURL(_ w: WebPartnerHit) -> URL? {
        if !w.file.isEmpty {
            return URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/" + enc(w.file) + "?width=96")
        }
        if w.dom.isEmpty { return nil }
        return URL(string: "https://www.google.com/s2/favicons?sz=64&domain=" + enc(w.dom))
    }
}

/// Logo zu einem Internet-Treffer laden (Commons-Logo, sonst Website-Symbol) und als 512×512-PNG aufbereiten.
enum CTLogoFetch {
    static func logo(file: String, domain: String) async -> (png: Data, bg: String)? {
        if !file.isEmpty, let u = await commonsThumb(file), let img = await image(u), let r = pad(img, minPx: 200, full: false) {
            return r
        }
        if !domain.isEmpty, let r = await siteIcon(Partners.regDom(domain)) {
            return r
        }
        return nil
    }

    static func commonsThumb(_ file: String) async -> URL? {
        let s = "https://commons.wikimedia.org/w/api.php?format=json&origin=*&action=query&prop=imageinfo&iiprop=" + CTWebPartners.enc("url|size")
            + "&iiurlwidth=512&titles=" + CTWebPartners.enc("File:" + file)
        guard let j = await CTWebPartners.json(s), let q = j["query"] as? [String: Any], let pages = q["pages"] as? [String: Any] else { return nil }
        for (_, v) in pages {
            guard let pg = v as? [String: Any], let ii = (pg["imageinfo"] as? [[String: Any]])?.first else { continue }
            if let u = (ii["thumburl"] as? String) ?? (ii["url"] as? String), let url = URL(string: u) { return url }
        }
        return nil
    }

    static func image(_ url: URL) async -> UIImage? {
        do {
            let (d, r) = try await CTWebPartners.imageSession.data(from: url)
            guard let h = r as? HTTPURLResponse, (200..<300).contains(h.statusCode) else { return nil }
            return UIImage(data: d)
        } catch {
            return nil
        }
    }

    /// App-Symbol der Website (Google-Symboldienst bzw. apple-touch-icon), nur quadratisch ab 120 px
    static func siteIcon(_ domain: String) async -> (png: Data, bg: String)? {
        let bare = domain.lowercased().hasPrefix("www.") ? String(domain.dropFirst(4)) : domain
        let srcs = ["https://t2.gstatic.com/faviconV2?client=SOCIAL&type=FAVICON&fallback_opts=TYPE,SIZE,URL&size=256&url=https://" + bare,
                    "https://" + bare + "/apple-touch-icon.png",
                    "https://www." + bare + "/apple-touch-icon.png"]
        for s in srcs {
            guard let u = URL(string: s), let img = await image(u), let cg = img.cgImage else { continue }
            let w = CGFloat(cg.width)
            let h = CGFloat(cg.height)
            if w >= 120 && h >= 120 && w / h > 0.9 && w / h < 1.1, let r = pad(img, minPx: 120, full: true) { return r }
        }
        return nil
    }

    /// Auf ein Quadrat 512×512 setzen (weiss, bei hellem Logo dunkel). Leere Bilder → nil.
    static func pad(_ img: UIImage, minPx: CGFloat, full: Bool) -> (png: Data, bg: String)? {
        guard let cg = img.cgImage else { return nil }
        let w = CGFloat(cg.width)
        let h = CGFloat(cg.height)
        if max(w, h) < minPx || w <= 0 || h <= 0 { return nil }
        let tries: [(String, UIColor)] = [("#FFFFFF", UIColor.white), ("#1C1C1E", UIColor(rgb: 0x1C1C1E))]
        for (hex, color) in tries {
            let fmt = UIGraphicsImageRendererFormat()
            fmt.scale = 1
            fmt.opaque = true
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512), format: fmt)
            let out = renderer.image { ctx in
                color.setFill()
                ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
                let k = full ? max(512 / w, 512 / h) : min(420 / w, 420 / h)
                let dw = w * k
                let dh = h * k
                img.draw(in: CGRect(x: (512 - dw) / 2, y: (512 - dh) / 2, width: dw, height: dh))
            }
            if luminanceSD(out) < 8 { continue }
            if let d = out.pngData() { return (d, hex) }
        }
        return nil
    }

    /// Standardabweichung der Helligkeit auf 48×48 (leere Bilder erkennen)
    static func luminanceSD(_ img: UIImage) -> Double {
        guard let cg = img.cgImage else { return 0 }
        let n = 48
        var px = [UInt8](repeating: 0, count: n * n * 4)
        let ok: Bool = px.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
            return true
        }
        if !ok { return 0 }
        var sum = 0.0
        var sq = 0.0
        var i = 0
        while i < px.count {
            let l = 0.2126 * Double(px[i]) + 0.7152 * Double(px[i + 1]) + 0.0722 * Double(px[i + 2])
            sum += l
            sq += l * l
            i += 4
        }
        let c = Double(n * n)
        let m = sum / c
        return sqrt(max(0, sq / c - m * m))
    }
}
