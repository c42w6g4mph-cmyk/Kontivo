import SwiftUI
import UIKit
import PencilKit
import KontivoCore

// MARK: - Bildhilfen (gemeinsam für Zeichnen und Namenszüge)

/// Zuschnitt und JPEG wie `sigFromCanvas` der Web-App: Bereich aller Pixel mit Rotanteil < 200, plus 12 px Rand,
/// weisser Grund, JPEG-Qualität 0.85.
enum SignatureImaging {
    /// Tintenblau #1c2a52
    static let ink = UIColor(red: 0x1C / 255.0, green: 0x2A / 255.0, blue: 0x52 / 255.0, alpha: 1)

    /// Zuschneiden auf den gezeichneten Bereich. nil, wenn nichts gezeichnet ist.
    static func cropToJPEG(_ image: CGImage, padding: Int = 12, quality: CGFloat = 0.85) -> Data? {
        let w = image.width
        let h = image.height
        guard w > 0, h > 0 else { return nil }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        // Weisser Grund, dann das Bild (transparente Bereiche werden weiss)
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let flat = ctx.makeImage(), let raw = ctx.data else { return nil }
        let rowBytes = ctx.bytesPerRow
        let px = raw.bindMemory(to: UInt8.self, capacity: rowBytes * h)
        var x0 = w, y0 = h, x1 = -1, y1 = -1
        for y in 0..<h {
            let row = y * rowBytes
            var x = 0
            while x < w {
                if px[row + x * 4] < 200 {
                    if x < x0 { x0 = x }
                    if x > x1 { x1 = x }
                    if y < y0 { y0 = y }
                    if y > y1 { y1 = y }
                }
                x += 1
            }
        }
        guard x1 >= 0 else { return nil }
        x0 = max(0, x0 - padding)
        y0 = max(0, y0 - padding)
        x1 = min(w - 1, x1 + padding)
        y1 = min(h - 1, y1 + padding)
        let rect = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
        guard let cropped = flat.cropping(to: rect) else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: quality)
    }
}

// MARK: - Unterschrift zeichnen

/// Unterschrift zeichnen (PencilKit). onDone liefert JPEG-Daten (zugeschnitten, Tintenblau auf weiss).
/// Das Fenster schliesst sich nach «Übernehmen» selbst und meldet «Unterschrift gespeichert».
struct SignaturePadSheet: View {
    let title: String
    let onDone: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model: AppModel?
    @State private var holder = SignatureCanvasHolder()
    @State private var message: String?
    @State private var messageTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Mit dem Finger auf der Linie unterschreiben, am besten im Querformat.")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                SignaturePadArea(holder: holder)
                    .frame(height: 200)
                Button {
                    holder.clear()
                } label: {
                    Text("Löschen").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(KColor.ink2)
                Spacer(minLength: 0)
            }
            .padding(KMetric.gutter)
            .kContentWidth()
            .kPageBackground()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { accept() }.fontWeight(.semibold)
                }
            }
            .overlay(alignment: .bottom) { localMessage }
        }
    }

    @ViewBuilder private var localMessage: some View {
        if let m = message {
            Text(m)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Capsule().fill(Color.black.opacity(0.82)))
                .padding(.bottom, 40)
                .transition(.opacity)
                .allowsHitTesting(false)
        }
    }

    private func show(_ text: String) {
        messageTask?.cancel()
        withAnimation { message = text }
        messageTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { message = nil }
        }
    }

    private func accept() {
        guard holder.hasStrokes else {
            show("Bitte zuerst unterschreiben")
            return
        }
        guard let jpeg = holder.exportJPEG() else {
            show("Nichts gezeichnet")
            return
        }
        onDone(jpeg)
        dismiss()
        model?.toast("Unterschrift gespeichert")
    }
}

/// Hält die PencilKit-Fläche, damit «Löschen» und «Übernehmen» auf die Zeichnung zugreifen können.
@MainActor
final class SignatureCanvasHolder {
    let canvas: PKCanvasView

    init() {
        let c = PKCanvasView()
        c.drawingPolicy = .anyInput
        c.tool = PKInkingTool(.pen, color: SignatureImaging.ink, width: 2.6)
        c.backgroundColor = .clear
        c.isOpaque = false
        c.isScrollEnabled = false
        c.minimumZoomScale = 1
        c.maximumZoomScale = 1
        c.bouncesZoom = false
        c.showsVerticalScrollIndicator = false
        c.showsHorizontalScrollIndicator = false
        // Tinte nicht für den Dunkelmodus umfärben (weisses Feld)
        c.overrideUserInterfaceStyle = .light
        c.accessibilityLabel = "Unterschriftfeld"
        canvas = c
    }

    var hasStrokes: Bool { !canvas.drawing.strokes.isEmpty }

    func clear() { canvas.drawing = PKDrawing() }

    /// Zeichnung über die ganze Fläche (Auflösung × 2) auf weiss, zugeschnitten, JPEG.
    func exportJPEG() -> Data? {
        let size = canvas.bounds.size
        guard size.width > 1, size.height > 1 else { return nil }
        let drawing = canvas.drawing
        var image: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: CGRect(origin: .zero, size: size), scale: 2)
        }
        guard let cg = image?.cgImage else { return nil }
        return SignatureImaging.cropToJPEG(cg)
    }
}

/// Weisses Feld (Radius 14, Rand) mit gestrichelter Hilfslinie 48 pt über der Unterkante und der Zeichenfläche darüber.
private struct SignaturePadArea: View {
    let holder: SignatureCanvasHolder

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white)
            GeometryReader { geo in
                Path { p in
                    let y = geo.size.height - 48
                    p.move(to: CGPoint(x: 24, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width - 24, y: y))
                }
                .stroke(Color(red: 0xB9 / 255.0, green: 0xB9 / 255.0, blue: 0xB9 / 255.0),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .allowsHitTesting(false)
            SignatureCanvasView(canvas: holder.canvas)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
    }
}

private struct SignatureCanvasView: UIViewRepresentable {
    let canvas: PKCanvasView

    func makeUIView(context: Context) -> PKCanvasView { canvas }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {}
}

// MARK: - Namenszug-Vorschläge

/// Namenszug-Vorschläge (6 Handschriften aus dem Bundle). onPick liefert JPEG-Daten.
/// Das Fenster schliesst sich nach der Wahl selbst und meldet «Namenszug übernommen».
struct SignatureSuggestionsSheet: View {
    let first: String
    let last: String
    let onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model: AppModel?
    @State private var variants: [SignatureVariantImage]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tippe auf einen Vorschlag. Üblich sind voller Name, Initial mit Nachname oder nur der Nachname.")
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    content
                }
                .padding(KMetric.gutter)
                .kContentWidth()
            }
            .kPageBackground()
            .navigationTitle("Namenszug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task { await build() }
    }

    @ViewBuilder private var content: some View {
        if let vs = variants {
            if vs.isEmpty {
                Text("Zuerst den Namen beim Absender erfassen")
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
            } else {
                ForEach(vs) { v in
                    Button { pick(v) } label: { SignatureVariantTile(variant: v) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(v.text), \(v.label)")
                }
                Text("Am echtesten ist «Zeichnen» mit dem Finger. Für Mietverträge gilt nur die Unterschrift von Hand auf Papier.")
                    .font(.footnote)
                    .foregroundStyle(KColor.ink2)
                    .padding(.horizontal, 2)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Vorschläge werden erstellt …").font(.footnote).foregroundStyle(KColor.ink2)
            }
            .padding(.vertical, 8)
        }
    }

    private func build() async {
        guard variants == nil else { return }
        // Kurz warten, damit «Vorschläge werden erstellt …» sichtbar wird
        try? await Task.sleep(nanoseconds: 60_000_000)
        variants = SignatureSuggestions.variants(first: first, last: last)
    }

    private func pick(_ v: SignatureVariantImage) {
        onPick(v.jpeg)
        dismiss()
        model?.toast("Namenszug übernommen")
    }
}

/// Ein fertig gezeichneter Vorschlag.
struct SignatureVariantImage: Identifiable {
    let id: Int
    let text: String
    let label: String
    let jpeg: Data
    let image: UIImage
}

private struct SignatureVariantTile: View {
    let variant: SignatureVariantImage

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 12) {
                Image(uiImage: variant.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: geo.size.width * 0.72, maxHeight: 64, alignment: .leading)
                Spacer(minLength: 0)
                Text(variant.label)
                    .font(.caption)
                    .foregroundStyle(Color(white: 0.4))
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 14)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 84)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// Namenszüge wie `renderSig` der Web-App (deterministisch, gleiche Zufallsfolge).
enum SignatureSuggestions {
    struct FontSpec {
        let postScript: String
        let size: CGFloat
        let label: String
        let form: Int
        let swash: Bool
    }

    /// SIG_FONTS – Reihenfolge = Anzeige
    static let fonts: [FontSpec] = [
        FontSpec(postScript: "Hurricane-Regular", size: 120, label: "Voller Name", form: 0, swash: false),
        FontSpec(postScript: "LaBelleAurore", size: 92, label: "Initial + Nachname", form: 1, swash: true),
        FontSpec(postScript: "Licorice-Regular", size: 116, label: "Voller Name", form: 0, swash: false),
        FontSpec(postScript: "Zeyada", size: 110, label: "Nur Nachname", form: 2, swash: false),
        FontSpec(postScript: "Qwigley-Regular", size: 128, label: "Voller Name", form: 0, swash: true),
        FontSpec(postScript: "Bilbo-Regular", size: 112, label: "Initial + Nachname", form: 1, swash: false),
    ]

    /// Formen: 0 voller Name, 1 Initial + Nachname (nur mit beiden), 2 Nachname (sonst Vorname).
    static func forms(first: String, last: String) -> [String] {
        let f = first.trimmingCharacters(in: .whitespaces)
        let l = last.trimmingCharacters(in: .whitespaces)
        let full = (f + " " + l).trimmingCharacters(in: .whitespaces)
        let initial = (!f.isEmpty && !l.isEmpty) ? String(f.prefix(1)) + ". " + l : ""
        let lastOnly = l.isEmpty ? f : l
        return [full, initial, lastOnly]
    }

    @MainActor
    static func variants(first: String, last: String) -> [SignatureVariantImage] {
        let fs = forms(first: first, last: last)
        var out: [SignatureVariantImage] = []
        for (i, spec) in fonts.enumerated() {
            let text = fs[spec.form]
            if text.isEmpty { continue }
            guard let jpeg = render(text: text, spec: spec, seed: i + 1), let img = UIImage(data: jpeg) else { continue }
            out.append(SignatureVariantImage(id: i + 1, text: text, label: spec.label, jpeg: jpeg, image: img))
        }
        return out
    }

    /// `sigRand(seed)`: x = seed·9301 + 49297; je Aufruf x = (x·9301 + 49297) mod 233280, Ergebnis x/233280.
    struct Rand {
        private var x: Int
        init(seed: Int) { x = seed * 9301 + 49297 }
        mutating func next() -> CGFloat {
            x = (x * 9301 + 49297) % 233_280
            return CGFloat(x) / 233_280
        }
    }

    /// Schrift aus dem Bundle; fehlt sie, Systemschrift kursiv.
    static func font(_ name: String, _ size: CGFloat) -> UIFont {
        if let f = UIFont(name: name, size: size) { return f }
        let base = UIFont.systemFont(ofSize: size)
        if let d = base.fontDescriptor.withSymbolicTraits(.traitItalic) { return UIFont(descriptor: d, size: size) }
        return UIFont.italicSystemFont(ofSize: size)
    }

    static func width(_ s: String, _ f: UIFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: f]).width
    }

    /// Leinwand 1000 × 300 px, weiss, Tinte #1c2a52; danach Zuschnitt + JPEG.
    @MainActor
    static func render(text: String, spec: FontSpec, seed: Int) -> Data? {
        let W: CGFloat = 1000
        let H: CGFloat = 300
        var r = Rand(seed: seed)
        var px = spec.size
        var f = font(spec.postScript, px)
        while width(text, f) > W - 140 && px > 40 {
            px -= 6
            f = font(spec.postScript, px)
        }
        let tw = width(text, f)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let ink = SignatureImaging.ink
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: ink]
        let chars = Array(text)
        let rotation = -(0.02 + r.next() * 0.035)
        // Zufallswerte vorab in der Reihenfolge der Web-App ziehen (drei pro Zeichen)
        var jitter: [(dy: CGFloat, sx: CGFloat, sy: CGFloat)] = []
        for _ in 0..<chars.count {
            let dy = (r.next() - 0.5) * px * 0.05
            let sx = 1 + (r.next() - 0.5) * 0.05
            let sy = 1 + (r.next() - 0.5) * 0.07
            jitter.append((dy: dy, sx: sx, sy: sy))
        }
        var prefixWidths: [CGFloat] = []
        for i in 0..<chars.count { prefixWidths.append(width(String(chars[0..<i]), f)) }
        let image = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: format).image { rc in
            let g = rc.cgContext
            UIColor.white.setFill()
            g.fill(CGRect(x: 0, y: 0, width: W, height: H))
            g.saveGState()
            g.translateBy(x: 50, y: H * 0.58)
            g.rotate(by: rotation)
            // Buchstabe für Buchstabe mit leichter Höhen- und Grössenunruhe; Abstand über die Breite des Präfixes
            for i in 0..<chars.count {
                g.saveGState()
                g.translateBy(x: prefixWidths[i], y: jitter[i].dy)
                g.scaleBy(x: jitter[i].sx, y: jitter[i].sy)
                (String(chars[i]) as NSString).draw(at: CGPoint(x: 0, y: -f.ascender), withAttributes: attrs)
                g.restoreGState()
            }
            // Etwas Tintenstärke: zweiter Durchgang minimal versetzt
            g.setAlpha(0.35)
            (text as NSString).draw(at: CGPoint(x: 0.8, y: 0.5 - f.ascender), withAttributes: attrs)
            g.setAlpha(1)
            if spec.swash {
                let y = px * 0.22
                let path = UIBezierPath()
                path.move(to: CGPoint(x: tw * 0.08, y: y + px * 0.06))
                path.addCurve(to: CGPoint(x: tw * 1.04, y: y - px * 0.12),
                              controlPoint1: CGPoint(x: tw * 0.35, y: y + px * 0.16),
                              controlPoint2: CGPoint(x: tw * 0.75, y: y - px * 0.02))
                path.lineWidth = max(2, px * 0.035)
                path.lineCapStyle = .round
                ink.setStroke()
                path.stroke()
            }
            g.restoreGState()
        }
        guard let cg = image.cgImage else { return nil }
        return SignatureImaging.cropToJPEG(cg)
    }
}
