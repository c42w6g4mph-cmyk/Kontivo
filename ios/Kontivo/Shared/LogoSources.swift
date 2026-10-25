import SwiftUI
import UIKit
import KontivoCore

// MARK: - Quellen App Store, Website-Symbol, Profilbild, Favicon (Port von logoCands, siteCand, socialCands, faviconCand)

extension LogoFinder {
    // MARK: App Store

    static func str(_ r: [String: Any], _ k: String) -> String {
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

    static func pixelSize(_ im: UIImage) -> (w: CGFloat, h: CGFloat) {
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

}
