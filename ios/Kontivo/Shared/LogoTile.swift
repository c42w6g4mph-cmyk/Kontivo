import SwiftUI
import UIKit
import KontivoCore

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
        var T: [Int] = []
        for k in 0..<3 {
            let sum: Int = E[0][k] + E[1][k] + E[2][k] + E[3][k]
            T.append(jr(CGFloat(sum) / 4))
        }
        T.append(255)
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
