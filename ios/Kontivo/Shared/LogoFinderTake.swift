import SwiftUI
import UIKit
import KontivoCore

// MARK: - Logo übernehmen (Port von takeLogo, padBlob, logoBlob)

extension LogoFinder {

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
