import UIKit
import KontivoCore

/// Fixkosten-Bericht als PDF (Web v220 `reportPdf`, Design V3 «App-Look»): A4 595 × 842 pt, Seite 1 Zusammenfassung, ab Seite 2
/// Vertragsblätter (2 × 5 je Seite). Alle Masse 1:1 aus der Web-App; dort liegt der Ursprung unten links (PDF), hier wird mit
/// `Y = 842 − y` umgerechnet. Schriften wie im Web-PDF: Helvetica, Helvetica-Bold, Times (Zahlen).
enum FixReportPDF {
    static let W: CGFloat = 595
    static let H: CGFloat = 842
    static let LM: CGFloat = 42
    static let RM: CGFloat = 595 - 42

    enum F { case regular, bold, times }

    static func font(_ f: F, _ pt: CGFloat) -> UIFont {
        switch f {
        case .regular: return UIFont(name: "Helvetica", size: pt) ?? .systemFont(ofSize: pt)
        case .bold: return UIFont(name: "Helvetica-Bold", size: pt) ?? .boldSystemFont(ofSize: pt)
        case .times: return UIFont(name: "TimesNewRomanPSMT", size: pt) ?? UIFont(name: "Times-Roman", size: pt) ?? .systemFont(ofSize: pt)
        }
    }

    static func color(_ hex: String) -> UIColor {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        return UIColor(rgb: UInt32(s, radix: 16) ?? 0x6B7280)
    }

    static func width(_ s: String, _ f: F, _ pt: CGFloat) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font(f, pt)]).width
    }

    /// Text kürzen mit «…» (`repFit`)
    static func fit(_ s0: String, _ f: F, _ pt: CGFloat, _ w: CGFloat) -> String {
        var s = s0
        if width(s, f, pt) <= w { return s }
        while s.count > 1 && width(s + "…", f, pt) > w { s.removeLast() }
        return s.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Zeichenfläche mit den Bausteinen der Web-App (rr, rect, hl, tx, lab, logo)
    struct Canvas {
        let ctx: CGContext

        func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, _ c: String) {
            let rect = CGRect(x: x, y: FixReportPDF.H - y - h, width: w, height: h)
            ctx.setFillColor(FixReportPDF.color(c).cgColor)
            ctx.addPath(UIBezierPath(roundedRect: rect, cornerRadius: min(r, min(w, h) / 2)).cgPath)
            ctx.fillPath()
        }

        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ c: String) {
            ctx.setFillColor(FixReportPDF.color(c).cgColor)
            ctx.fill(CGRect(x: x, y: FixReportPDF.H - y - h, width: w, height: h))
        }

        func hl(_ x1: CGFloat, _ x2: CGFloat, _ y: CGFloat, _ c: String, _ lw: CGFloat = 0.6) {
            ctx.saveGState()
            ctx.setLineWidth(lw)
            ctx.setStrokeColor(FixReportPDF.color(c).cgColor)
            ctx.move(to: CGPoint(x: x1, y: FixReportPDF.H - y))
            ctx.addLine(to: CGPoint(x: x2, y: FixReportPDF.H - y))
            ctx.strokePath()
            ctx.restoreGState()
        }

        enum Align { case left, right, center }

        /// Text mit Grundlinie bei y; gibt die Breite zurück
        @discardableResult
        func tx(_ s: String, _ x0: CGFloat, _ y: CGFloat, f: F = .regular, pt: CGFloat = 9, c: String = "#121314", al: Align = .left) -> CGFloat {
            let fo = FixReportPDF.font(f, pt)
            let w = (s as NSString).size(withAttributes: [.font: fo]).width
            var x = x0
            if al == .right { x -= w } else if al == .center { x -= w / 2 }
            UIGraphicsPushContext(ctx)
            (s as NSString).draw(at: CGPoint(x: x, y: FixReportPDF.H - y - fo.ascender),
                                 withAttributes: [.font: fo, .foregroundColor: FixReportPDF.color(c)])
            UIGraphicsPopContext()
            return w
        }

        func lab(_ s: String, _ x: CGFloat, _ y: CGFloat, _ c: String = "#6A6C70") {
            tx(s.uppercased(), x, y, f: .bold, pt: 6.6, c: c)
        }

        /// App-Symbol «K im Zeitring» (Web `logo`), s = Kantenlänge
        func logo(_ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
            let u = s / 1024
            func X(_ v: CGFloat) -> CGFloat { x + v * u }
            func Y(_ v: CGFloat) -> CGFloat { FixReportPDF.H - (y + s - v * u) }
            rr(x, y, s, s, 228 * u, "#111113")
            let cx = X(512), cy = Y(512), r = 382 * u
            // Bogen hell von 90° bis 330°, Messing von −30° bis 90° (PDF-Winkel gegen den Uhrzeigersinn → hier gespiegelt)
            func arc(_ a0: CGFloat, _ a1: CGFloat, _ col: String) {
                ctx.saveGState()
                ctx.setLineWidth(64 * u)
                ctx.setStrokeColor(FixReportPDF.color(col).cgColor)
                ctx.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: -a0, endAngle: -a1, clockwise: true)
                ctx.strokePath()
                ctx.restoreGState()
            }
            arc(.pi / 2, .pi * 11 / 6, "#ECEAE6")
            arc(-.pi / 6, .pi / 2, "#C6AB78")
            let sc: CGFloat = 0.88
            func tr(_ px: CGFloat, _ py: CGFloat) -> (CGFloat, CGFloat) { (512 + (px - 516.4) * sc, 512 + (py - 512) * sc) }
            let p = [(339.78, 292.0), (393.78, 292.0), (439.78, 349.5), (439.78, 732.0), (339.78, 732.0)].map { tr($0.0, $0.1) }
            ctx.setFillColor(FixReportPDF.color("#ECEAE6").cgColor)
            ctx.move(to: CGPoint(x: X(p[0].0), y: Y(p[0].1)))
            for q in p.dropFirst() { ctx.addLine(to: CGPoint(x: X(q.0), y: Y(q.1))) }
            ctx.closePath()
            ctx.fillPath()
            let a = tr(693, 792), b = tr(469, 512), c2 = tr(693, 232), ca = tr(0, 292), cb = tr(1024, 732)
            ctx.saveGState()
            ctx.clip(to: CGRect(x: X(ca.0), y: Y(ca.1), width: (cb.0 - ca.0) * u, height: (cb.1 - ca.1) * u))
            func chevron(_ lw: CGFloat, _ col: String) {
                ctx.setLineWidth(lw)
                ctx.setStrokeColor(FixReportPDF.color(col).cgColor)
                ctx.setLineCap(.butt)
                ctx.setLineJoin(.miter)
                ctx.move(to: CGPoint(x: X(a.0), y: Y(a.1)))
                ctx.addLine(to: CGPoint(x: X(b.0), y: Y(b.1)))
                ctx.addLine(to: CGPoint(x: X(c2.0), y: Y(c2.1)))
                ctx.strokePath()
            }
            chevron(144 * sc * u, "#111113")
            chevron(80 * sc * u, "#ECEAE6")
            ctx.restoreGState()
        }
    }

    // MARK: Erzeugen

    static func render(_ R: FixReport, calc: Calc, categoryColor: (String) -> String) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "Kontivo Fixkosten-Bericht", kCGPDFContextCreator as String: "Kontivo"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: W, height: H), format: format)
        let data = calc.data
        let home = R.home.rawValue
        let N = R.pageCount
        func num(_ v: Double) -> String { Format.money0(Format.jsRound(v)) }
        func title(_ id: UUID) -> String { data.contract(id).map { data.title(of: $0) } ?? "" }
        let foreign = R.rows.contains { data.contract($0.contractID)?.currency != R.home }
        return renderer.pdfData { pc in
            func foot(_ cv: Canvas, _ p: Int) {
                cv.hl(LM, RM, 40, "#E6E6E3", 0.6)
                cv.tx("Kontivo · Deine Verträge, ganz entspannt", LM, 28, pt: 6.8, c: "#9C9B97")
                cv.tx("Stand " + Format.fmtShort(R.today) + " · Beträge in " + home
                      + (foreign ? " · Fremdwährungen zum Kurs vom " + Format.fmtShort(R.today) : ""), W / 2, 28, pt: 6.8, c: "#9C9B97", al: .center)
                cv.tx("Seite \(p) von \(N)", RM, 28, pt: 6.8, c: "#9C9B97", al: .right)
            }
            func head(_ cv: Canvas, _ sub: String) {
                cv.logo(LM, H - 70, 26)
                cv.tx("KONTIVO", LM + 34, H - 53, f: .bold, pt: 10.5)
                cv.tx(sub, LM + 34, H - 65, pt: 7.5, c: "#6A6C70")
                if !R.who.isEmpty { cv.tx(R.who, RM, H - 53, pt: 7.8, c: "#6A6C70", al: .right) }
                cv.tx("Stand \(R.today.day). " + Format.monthNames[R.today.month - 1] + " \(R.today.year)", RM, H - 64, pt: 7.8, c: "#6A6C70", al: .right)
            }

            // ---------- Seite 1 ----------
            pc.beginPage()
            var cv = Canvas(ctx: pc.cgContext)
            head(cv, "Fixkosten-Bericht")
            let top = H - 92, gap: CGFloat = 8, bw = RM - LM - gap * 2, c1 = bw * 0.42, c2 = (bw - c1) / 2, th: CGFloat = 54
            cv.rr(LM, top - th * 2 - gap, c1, th * 2 + gap, 12, "#F4F4F2")
            cv.lab("Fixkosten pro Monat", LM + 14, top - 20)
            let nw = cv.tx(num(R.total), LM + 14, top - 58, f: .times, pt: 34)
            cv.tx(home, LM + 18 + nw, top - 58, pt: 9, c: "#6A6C70")
            if R.income > 0 {
                let q = Int(Format.jsRound(R.total / R.income * 100)), bx = LM + 14, bwid = c1 - 28
                cv.rr(bx, top - th * 2 - gap + 30, bwid, 4.5, 2.2, "#E6E6E3")
                cv.rr(bx, top - th * 2 - gap + 30, max(4.5, bwid * min(1, R.total / R.income)), 4.5, 2.2, "#A88437")
                cv.tx("\(q) % der Einnahmen · " + num(max(0, R.income - R.total)) + " " + home + " bleiben", bx, top - th * 2 - gap + 16, pt: 7.2, c: "#6A6C70")
            }
            let diffText = (R.diff >= 0.5 ? "+" : (R.diff <= -0.5 ? "-" : "±")) + num(abs(R.diff))
            let tiles: [(String, String, String)] = [
                ("pro Jahr", num(R.year), "#121314"),
                ("Verträge", String(R.rows.count), "#121314"),
                ("Fristen in 90 Tagen", String(R.deadlines.count), R.deadlines.isEmpty ? "#121314" : "#A93227"),
                ("Teurer seit Vorjahr", diffText, "#121314"),
            ]
            for (i, tl) in tiles.enumerated() {
                let x = LM + c1 + gap + CGFloat(i % 2) * (c2 + gap), y = top - (i < 2 ? th : th * 2 + gap)
                cv.rr(x, y, c2, th, 12, "#F4F4F2")
                cv.lab(tl.0, x + 12, y + th - 17)
                cv.tx(tl.1, x + 12, y + 12, f: .times, pt: 19, c: tl.2)
            }
            // Kategorien + Grösste Posten / Handlungsbedarf
            let y2 = top - th * 2 - gap - 14, hw = (RM - LM - gap) / 2, bh: CGFloat = 230
            cv.rr(LM, y2 - bh, hw, bh, 12, "#F9F9F7")
            cv.rr(LM + hw + gap, y2 - bh, hw, bh, 12, "#F9F9F7")
            cv.tx("Nach Kategorie", LM + 12, y2 - 20, f: .bold, pt: 9.2)
            cv.tx(home + " / Monat", LM + hw - 12, y2 - 20, pt: 7.5, c: "#6A6C70", al: .right)
            var cy = y2 - 42
            let maxC = min(9, R.categories.count)
            for e in R.categories.prefix(maxC) {
                let cc = categoryColor(e.name)
                cv.rr(LM + 12, cy - 4, 13, 13, 3.5, cc)
                cv.tx(String(e.name.prefix(1)).uppercased(), LM + 18.5, cy - 0.5, f: .bold, pt: 7, c: "#FFFFFF", al: .center)
                cv.tx(fit(e.name, .regular, 8.4, hw - 110), LM + 31, cy, pt: 8.4)
                cv.tx(num(e.value), LM + hw - 12, cy, pt: 8.4, al: .right)
                let bx = LM + 31, bwd = hw - 43
                cv.rr(bx, cy - 9, bwd, 2.6, 1.3, "#ECEBE7")
                cv.rr(bx, cy - 9, max(2.6, bwd * CGFloat(e.value / (R.total == 0 ? 1 : R.total))), 2.6, 1.3, cc)
                cy -= 21
            }
            if R.categories.count > maxC { cv.tx("+ \(R.categories.count - maxC) weitere", LM + 31, cy, pt: 7.2, c: "#6A6C70") }
            let rx = LM + hw + gap + 12, rw = hw - 24
            var ry = y2 - 20
            cv.tx("Grösste Posten", rx, ry, f: .bold, pt: 9.2)
            cv.tx("Anteil", rx + rw, ry, pt: 7.5, c: "#6A6C70", al: .right)
            ry -= 18
            for r in R.top {
                guard let c = data.contract(r.contractID) else { continue }
                cv.tx(fit(data.title(of: c), .bold, 8.2, rw - 110), rx, ry, f: .bold, pt: 8.2)
                cv.tx(fit(calc.reportTopSub(c), .regular, 6.8, rw - 110), rx, ry - 9, pt: 6.8, c: "#6A6C70")
                cv.tx(Format.money(r.monthly, R.home), rx + rw - 34, ry, pt: 8.2, al: .right)
                cv.tx("\(Int(Format.jsRound(r.monthly / (R.total == 0 ? 1 : R.total) * 100))) %", rx + rw, ry, pt: 7.5, c: "#6A6C70", al: .right)
                cv.hl(rx, rx + rw, ry - 14, "#EFEEEA")
                ry -= 22
            }
            ry -= 6
            cv.tx("Handlungsbedarf", rx, ry, f: .bold, pt: 9.2)
            cv.tx("nächste 90 Tage", rx + rw, ry, pt: 7.5, c: "#6A6C70", al: .right)
            ry -= 18
            if R.deadlines.isEmpty { cv.tx("Keine Kündigungsfristen in den nächsten 90 Tagen.", rx, ry, pt: 7.8, c: "#6A6C70") }
            for f in R.deadlines {
                let red = f.days <= 30
                let ptx = "bis " + String(format: "%02d.%02d.", f.date.day, f.date.month)
                let pw = width(ptx, .bold, 6.8) + 12
                cv.tx(fit(title(f.contractID), .bold, 8.2, rw - pw - 8), rx, ry, f: .bold, pt: 8.2)
                cv.tx(fit(f.sub, .regular, 6.8, rw - pw - 8), rx, ry - 9, pt: 6.8, c: "#6A6C70")
                cv.rr(rx + rw - pw, ry - 3, pw, 11, 5.5, red ? "#F6E1DE" : "#F3EAD7")
                cv.tx(ptx, rx + rw - pw / 2, ry, f: .bold, pt: 6.8, c: red ? "#A93227" : "#86671F", al: .center)
                cv.hl(rx, rx + rw, ry - 14, "#EFEEEA")
                ry -= 22
            }
            // 12-Monats-Vorschau
            let y3 = y2 - bh - gap, ch: CGFloat = 200
            cv.rr(LM, y3 - ch, RM - LM, ch, 12, "#F9F9F7")
            cv.tx("Fixkosten der nächsten 12 Monate", LM + 12, y3 - 20, f: .bold, pt: 9.2)
            cv.tx("inkl. Jahreszahlungen und angekündigter Preise", RM - 12, y3 - 20, pt: 7.5, c: "#6A6C70", al: .right)
            var mx = R.months.map(\.value).max() ?? 0
            if mx == 0 { mx = 1 }
            let gx = LM + 12, gw = RM - LM - 24, slot = gw / 12, bwd2 = slot - 8, base = y3 - ch + 44, maxH: CGFloat = 110
            // jeder Balken mit Wert (Summe der Zahlungen im Monat); Jahr beim ersten Monat und im Januar (Web v228)
            for (i, m) in R.months.enumerated() {
                let hgt = max(1.5, CGFloat(m.value / mx) * maxH), x = gx + CGFloat(i) * slot + 4
                cv.rr(x, base, bwd2, hgt, 3, m.high ? "#A88437" : "#E3D7BC")
                let yr = (i == 0 || m.date.month == 1) ? " " + String(String(m.date.year).suffix(2)) : ""
                cv.tx(String(Format.monthNames[m.date.month - 1].prefix(3)) + yr, x + bwd2 / 2, base - 11, pt: 6.8, c: "#6A6C70", al: .center)
                if m.high {
                    cv.tx(num(m.value), x + bwd2 / 2, base + hgt + 4, f: .bold, pt: 6.6, c: "#86671F", al: .center)
                } else {
                    cv.tx(num(m.value), x + bwd2 / 2, base + hgt + 4, pt: 6.4, c: "#4A4C50", al: .center)
                }
            }
            let ly = y3 - ch + 14
            var lx = LM + 12
            cv.rr(lx, ly, 7, 7, 1.5, "#E3D7BC")
            lx += 11 + cv.tx("Monat mit den regelmässigen Zahlungen", lx + 11, ly + 0.5, pt: 7, c: "#6A6C70") + 14
            let pk = R.months.filter(\.high).map { String(Format.monthNames[$0.date.month - 1].prefix(3)) + " " + ($0.bigName ?? "") }
            if !pk.isEmpty {
                cv.rr(lx, ly, 7, 7, 1.5, "#A88437")
                cv.tx(fit("Höher wegen Jahres- oder Sonderzahlung: " + pk.joined(separator: " · "), .regular, 7, RM - 12 - lx - 11), lx + 11, ly + 0.5, pt: 7, c: "#6A6C70")
            }
            if !R.rows.isEmpty {
                cv.tx("Ab Seite 2: alle Verträge mit Kündigungsregel" + (R.showIDs ? ", Kunden-Nr." : "") + " und Kontakt – zum Ablegen oder Weitergeben.",
                      LM, y3 - ch - 18, pt: 7.5, c: "#6A6C70")
            }
            foot(cv, 1)

            // ---------- Vertragsblätter: 2 Spalten × 5 Zeilen pro Seite ----------
            let S = R.sheetRows
            for p in 0..<(N - 1) {
                pc.beginPage()
                cv = Canvas(ctx: pc.cgContext)
                let py = H - 60
                cv.tx("Vertragsblätter", LM, py, f: .bold, pt: 13)
                cv.tx("Seite \(p + 2) von \(N) · \(min(S.count, (p + 1) * 10)) von \(S.count) Verträgen", RM, py, pt: 7.5, c: "#6A6C70", al: .right)
                cv.hl(LM, RM, py - 8, "#121314", 1)
                let cw = (RM - LM - 10) / 2, chh: CGFloat = 126, y0 = py - 20
                let slice = S.dropFirst(p * 10).prefix(10)
                for (i, r) in slice.enumerated() {
                    guard let c = data.contract(r.contractID) else { continue }
                    let x = LM + CGFloat(i % 2) * (cw + 10), y = y0 - CGFloat(i / 2) * (chh + 9) - chh, cc = categoryColor(r.category)
                    cv.rr(x, y, cw, chh, 11, "#F4F4F2")
                    cv.rr(x + 11, y + chh - 36, 22, 22, 6, cc)
                    let pn = calc.partnerName(c)
                    let initial = String((pn.isEmpty ? data.title(of: c) : pn).prefix(1)).uppercased()
                    cv.tx(initial.isEmpty ? "?" : initial, x + 22, y + chh - 28.5, f: .bold, pt: 9.5, c: "#FFFFFF", al: .center)
                    let am = Format.money(r.monthly, R.home)
                    let aw = width(am, .times, 12.5) + width(" /Mt.", .regular, 6.8)
                    cv.tx(fit(data.title(of: c), .bold, 9, cw - 56 - aw), x + 40, y + chh - 21, f: .bold, pt: 9)
                    cv.tx(fit(calc.reportSheetSub(r), .regular, 6.8, cw - 56 - aw), x + 40, y + chh - 31, pt: 6.8, c: "#6A6C70")
                    let ex = cv.tx(" /Mt.", x + cw - 11, y + chh - 22, pt: 6.8, c: "#6A6C70", al: .right)
                    cv.tx(am, x + cw - 11 - ex, y + chh - 22, f: .times, pt: 12.5, al: .right)
                    cv.hl(x + 11, x + cw - 11, y + chh - 44, "#E6E6E3")
                    var ry2 = y + chh - 56
                    for line in calc.reportSheetLines(r, showIDs: R.showIDs) {
                        cv.tx(line.label, x + 11, ry2, pt: 6.9, c: "#8A8B8F")
                        cv.tx(fit(line.value, .regular, 6.9, cw - 82), x + 70, ry2, pt: 6.9)
                        ry2 -= 10.2
                    }
                }
                foot(cv, p + 2)
            }
        }
    }
}
