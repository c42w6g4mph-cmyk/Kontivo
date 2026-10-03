import UIKit
import KontivoCore

/// Inhalt des PDF-Briefs (`letterPdf` der Web-App).
struct LetterPDFInput {
    /// Absenderblock (höchstens 7 Zeilen)
    var sender: [String]
    /// Anschrift (beliebig viele Zeilen)
    var to: [String]
    /// Ort der Datumszeile (leer = nur Datum)
    var city: String
    var date: Day
    var subject: String
    /// «Kundennummer: …», «Vertragsnummer: …»
    var references: [String]
    /// Text ohne Referenzzeilen
    var body: String
    /// Namen unter den Unterschriften (nebeneinander)
    var names: [String]
    /// Unterschrift je Name (JPEG) oder nil = freie Linie
    var signatures: [Data?]
}

/// PDF-Brief nach DIN 5008 / Schweizer Geschäftsbrief: A4, Rand links 25 mm, Absender ab 20 mm, Anschriftfeld ab 50 mm,
/// Ort/Datum rechts bei 90 mm, Betreff fett ab 105 mm, Referenzen, Text, Unterschriften, Namen. Mehrseitig, Helvetica.
/// Alle Positionen sind Grundlinien, gemessen von der Blattoberkante (Inventar 3, Abschnitt 5).
enum LetterPDF {
    static let pageSize = CGSize(width: 595, height: 842)
    /// Satzspiegel links/rechts (71 pt = 25 mm)
    static let left: CGFloat = 71
    static let right: CGFloat = 524
    static let textWidth: CGFloat = 453
    /// Zeilenschritt 15.5 pt
    static let lineStep: CGFloat = 15.5
    /// Unterste zulässige Grundlinie (70 pt über der Unterkante)
    static let lowestBaseline: CGFloat = 842 - 70
    /// Erste Grundlinie auf Folgeseiten (70 pt unter der Oberkante)
    static let followPageTop: CGFloat = 70

    static func regularFont(_ size: CGFloat) -> UIFont { UIFont(name: "Helvetica", size: size) ?? .systemFont(ofSize: size) }
    static func boldFont(_ size: CGFloat) -> UIFont { UIFont(name: "Helvetica-Bold", size: size) ?? .boldSystemFont(ofSize: size) }

    static func width(_ s: String, _ f: UIFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: f]).width
    }

    /// Zeilenumbruch an Leerzeichen, gierig (`pdfWrap`); überlange Wörter werden zeichenweise getrennt.
    static func wrap(_ str: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        let words = str.components(separatedBy: " ")
        var lines: [String] = []
        var cur = ""
        for w in words {
            let t = cur.isEmpty ? w : cur + " " + w
            if width(t, font) <= maxWidth || cur.isEmpty {
                cur = t
            } else {
                lines.append(cur)
                cur = w
            }
            while cur.count > 1 && width(cur, font) > maxWidth {
                var acc = ""
                for ch in cur {
                    if !acc.isEmpty && width(acc + String(ch), font) > maxWidth { break }
                    acc.append(ch)
                }
                if acc.count >= cur.count { break }
                lines.append(acc)
                cur = String(cur.dropFirst(acc.count))
            }
        }
        if !cur.isEmpty || lines.isEmpty { lines.append(cur) }
        return lines
    }

    /// Absätze an zwei oder mehr aufeinanderfolgenden Zeilenumbrüchen (wie `split(/\n{2,}/)`).
    static func paragraphs(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        var nl = 0
        for ch in s {
            if ch == "\n" {
                nl += 1
                continue
            }
            if nl >= 2 {
                out.append(cur)
                cur = ""
            } else if nl == 1 {
                cur.append("\n")
            }
            nl = 0
            cur.append(ch)
        }
        if nl >= 2 {
            out.append(cur)
            cur = ""
        } else if nl == 1 {
            cur.append("\n")
        }
        out.append(cur)
        return out
    }

    /// PDF erzeugen.
    static func render(_ L: LetterPDFInput) -> Data {
        let regular = regularFont(11)
        let bold = boldFont(11)
        let small = regularFont(9.5)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: L.subject,
            kCGPDFContextCreator as String: "Kontivo",
            kCGPDFContextAuthor as String: L.names.joined(separator: ", "),
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let body = L.body.replacingOccurrences(of: "\r", with: "")
        return renderer.pdfData { ctx in
            var y: CGFloat = 0
            func draw(_ s: String, x: CGFloat, baseline: CGFloat, font: UIFont) {
                (s as NSString).draw(at: CGPoint(x: x, y: baseline - font.ascender),
                                     withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
            func newPage() {
                ctx.beginPage()
                y = followPageTop
            }
            func line(_ s: String, _ f: UIFont) {
                if y > lowestBaseline { newPage() }
                draw(s, x: left, baseline: y, font: f)
                y += lineStep
            }
            func para(_ s: String, _ f: UIFont) {
                for ln in s.components(separatedBy: "\n") {
                    for w in wrap(ln, font: f, maxWidth: textWidth) { line(w, f) }
                }
            }

            ctx.beginPage()
            // Absender (klein) ab 20 mm
            var yy: CGFloat = 57
            for ln in L.sender.prefix(7) {
                draw(ln, x: left, baseline: yy, font: small)
                yy += 12
            }
            // Anschriftfeld ab 50 mm
            yy = 142
            for ln in L.to {
                draw(ln, x: left, baseline: yy, font: regular)
                yy += lineStep
            }
            // Ort und Datum rechts, 90 mm
            let dt = (L.city.isEmpty ? "" : L.city + ", ") + Format.fmtD(L.date)
            draw(dt, x: right - width(dt, regular), baseline: 255, font: regular)
            // Betreff ab 105 mm
            y = 298
            for w in wrap(L.subject, font: bold, maxWidth: textWidth) { line(w, bold) }
            y += lineStep * 0.6
            if !L.references.isEmpty {
                for r in L.references { line(r, regular) }
                y += lineStep * 0.6
            }
            // Text: Absätze durch Leerzeilen
            for p in paragraphs(body) {
                para(p, regular)
                y += lineStep * 0.8
            }
            // Unterschriften nebeneinander: Bild oder freie Linie, darunter der Name
            let names = L.names.isEmpty ? [""] : L.names
            let sigHeight: CGFloat = 46
            let colW = min(220, textWidth / CGFloat(names.count))
            let lw = min(170, colW - 20)
            if y + sigHeight + lineStep * 2 > lowestBaseline { newPage() }
            let g = ctx.cgContext
            for (i, n) in names.enumerated() {
                let x = left + CGFloat(i) * colW
                let sig: UIImage? = i < L.signatures.count ? L.signatures[i].flatMap { UIImage(data: $0) } : nil
                if let img = sig, img.size.width > 0, img.size.height > 0 {
                    var sh = sigHeight
                    var sw = sh * img.size.width / img.size.height
                    if sw > lw {
                        sw = lw
                        sh = sw * img.size.height / img.size.width
                    }
                    // Unterkante 42 pt unter der Grundlinie (unten bündig)
                    img.draw(in: CGRect(x: x, y: y + 42 - sh, width: sw, height: sh))
                } else {
                    g.saveGState()
                    g.setStrokeColor(UIColor(white: 0.45, alpha: 1).cgColor)
                    g.setLineWidth(0.5)
                    g.move(to: CGPoint(x: x, y: y + 44))
                    g.addLine(to: CGPoint(x: x + lw, y: y + 44))
                    g.strokePath()
                    g.restoreGState()
                }
                draw(n, x: x, baseline: y + 57, font: regular)
            }
        }
    }
}

// MARK: - Angaben zum erzeugten Brief (für die Aktionen im Viewer)

/// Was der Viewer für «Per Mail senden» und «Als E-Mail-Text» braucht.
struct LetterDocumentInfo {
    var subject: String
    /// Mailtext (Referenzen, Text, Namen + Absenderzeilen ab der zweiten)
    var mailText: String
    var names: [String]
    /// E-Mail beim Vertrag (darf leer sein)
    var recipient: String
    var isRent: Bool

    static let empty = LetterDocumentInfo(subject: "", mailText: "", names: [], recipient: "", isRent: false)

    /// Kurzer Begleittext für die Mail mit PDF-Anhang.
    var attachmentMailBody: String {
        let we = names.count > 1
        return "Sehr geehrte Damen und Herren\n\nim Anhang " + (we ? "senden wir Ihnen unsere" : "sende ich Ihnen meine")
            + " Kündigung.\n\nFreundliche Grüsse" + (names.isEmpty ? "" : "\n" + names.joined(separator: "\n"))
    }

    /// Ohne gespeicherte Angaben: aus dem Vertrag mit den Standard-Unterzeichnenden.
    static func fallback(_ c: Contract, calc: Calc) -> LetterDocumentInfo {
        let p = Letter.parts(c, calc: calc)
        return LetterDocumentInfo(subject: p.subject,
                                  mailText: Letter.mailText(references: p.references, body: p.body, names: p.names, sender: p.sender),
                                  names: p.names,
                                  recipient: c.mail.trimmingCharacters(in: .whitespacesAndNewlines),
                                  isRent: calc.isRent(c))
    }
}

/// Merkt sich die Angaben zu erzeugten Brief-PDFs (Schlüssel = DocumentRef.id).
@MainActor
enum LetterDocumentStore {
    private static var items: [UUID: LetterDocumentInfo] = [:]
    private static var order: [UUID] = []

    static func put(_ id: UUID, _ info: LetterDocumentInfo) {
        items[id] = info
        order.append(id)
        while order.count > 12 {
            let old = order.removeFirst()
            items[old] = nil
        }
    }

    static func get(_ id: UUID) -> LetterDocumentInfo? { items[id] }
}
