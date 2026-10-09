import Foundation
import UIKit
import PDFKit
import Vision

/// Text aus Kontoauszügen als PDF oder Foto – alles auf dem Gerät (nativ, nicht in der Web-App).
/// PDF: Text je Seite über PDFKit; Seiten ohne Text (eingescannt) und Fotos über Vision (Texterkennung, genau).
/// Erkannte Wörter werden nach ihrer Höhe zu Zeilen zusammengesetzt, damit Datum und Betrag einer Buchung
/// in einer Zeile stehen (Eingabe für `BankImport.readStatementText`).
enum StatementText {
    /// Gewünschte Sprachen der Texterkennung (nur die vom Gerät unterstützten werden gesetzt)
    static let languages = ["de-DE", "de-CH", "en-US", "fr-FR"]

    /// Text eines PDFs; nil = keine lesbare PDF-Datei (oder mit Passwort geschützt)
    static func pdf(_ data: Data) -> String? {
        guard let doc = PDFDocument(data: data), !doc.isLocked else { return nil }
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let t = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if t.count >= 20 {
                pages.append(t)
            } else {
                // eingescannte Seite: als Bild rendern und erkennen
                let b = page.bounds(for: .mediaBox)
                let scale = min(3, 2400 / max(1, max(b.width, b.height)))
                let img = page.thumbnail(of: CGSize(width: b.width * scale, height: b.height * scale), for: .mediaBox)
                pages.append(recognize(img))
            }
        }
        return pages.joined(separator: "\n")
    }

    /// Text mehrerer Fotos (Seiten eines Auszugs, in Reihenfolge)
    static func images(_ images: [UIImage]) -> String {
        images.map { recognize($0) }.joined(separator: "\n")
    }

    /// Texterkennung eines Bildes, Zeilen von oben nach unten
    static func recognize(_ image: UIImage) -> String {
        guard let cg = image.cgImage else { return "" }
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        // Beträge und Daten nicht «korrigieren» lassen
        req.usesLanguageCorrection = false
        let supported = (try? req.supportedRecognitionLanguages()) ?? []
        let langs = languages.filter { supported.contains($0) }
        req.recognitionLanguages = langs.isEmpty ? ["de-DE", "en-US"] : langs
        let handler = VNImageRequestHandler(cgImage: cg, orientation: orientation(image.imageOrientation), options: [:])
        do { try handler.perform([req]) } catch { return "" }
        let words: [OCRWord] = (req.results ?? []).compactMap { o in
            guard let c = o.topCandidates(1).first else { return nil }
            return OCRWord(text: c.string, box: o.boundingBox)
        }
        return lines(words).joined(separator: "\n")
    }

    /// Erkanntes Textstück mit Rahmen (Vision: 0…1, Ursprung unten links)
    struct OCRWord {
        var text: String
        var box: CGRect
    }

    /// Zeilen nach Höhe bilden: Stücke, deren Mitte innerhalb einer halben Zeilenhöhe liegt, gehören zusammen;
    /// innerhalb der Zeile von links nach rechts, mit zwei Leerzeichen getrennt (Spalten bleiben erkennbar).
    static func lines(_ words: [OCRWord]) -> [String] {
        let ws = words.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !ws.isEmpty else { return [] }
        let heights = ws.map { $0.box.height }.sorted()
        let typical = heights[heights.count / 2]
        let tol = max(0.004, typical * 0.5)
        var rows: [(mid: CGFloat, items: [OCRWord])] = []
        for w in ws.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.indices.last, abs(rows[last].mid - w.box.midY) <= tol {
                rows[last].items.append(w)
                let n = CGFloat(rows[last].items.count)
                rows[last].mid += (w.box.midY - rows[last].mid) / n
            } else {
                rows.append((mid: w.box.midY, items: [w]))
            }
        }
        return rows.map { r in
            r.items.sorted { $0.box.minX < $1.box.minX }.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: "  ")
        }
    }

    static func orientation(_ o: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch o {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
