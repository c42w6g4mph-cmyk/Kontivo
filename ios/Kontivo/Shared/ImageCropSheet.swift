import SwiftUI
import UIKit
import KontivoCore

/// Vorbereitetes Bild für das Zuschneiden (openCrop): höchstens 1600 px, erkannte Hintergrundfarbe und Inhaltsrahmen
struct CropPrep: @unchecked Sendable {
    let img: UIImage
    let w: CGFloat
    let h: CGFloat
    let bgR: Int
    let bgG: Int
    let bgB: Int
    let box: CGRect
}

/// Bildanalyse für das Zuschneiden (analyze der Web-App)
enum CropMath {
    static func prepare(_ src: UIImage) -> CropPrep {
        var w = src.size.width * src.scale
        var h = src.size.height * src.scale
        if !(w > 0 && h > 0) {
            w = 512
            h = 512
        }
        let sc = Swift.min(1, 1600 / Swift.max(w, h))
        let W = Swift.max(1, (w * sc).rounded())
        let H = Swift.max(1, (h * sc).rounded())
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: CGSize(width: W, height: H), format: fmt).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            src.draw(in: CGRect(x: 0, y: 0, width: W, height: H))
        }
        // Analysekopie mit höchstens 500 px
        let ss = Swift.min(1, 500 / Swift.max(W, H))
        let aw = Swift.max(1, Int((W * ss).rounded()))
        let ah = Swift.max(1, Int((H * ss).rounded()))
        var bg = [255, 255, 255]
        var box = CGRect(x: 0, y: 0, width: W, height: H)
        if let px = LogoPixels.rgba(img, width: aw, height: ah) {
            func at(_ x: Int, _ y: Int) -> [Int] {
                let i = (y * aw + x) * 4
                return [Int(px[i]), Int(px[i + 1]), Int(px[i + 2]), Int(px[i + 3])]
            }
            let corners = [at(0, 0), at(aw - 1, 0), at(0, ah - 1), at(aw - 1, ah - 1)]
            let transparent = corners.filter { $0[3] < 30 }.count >= 2
            if !transparent {
                for k in 0..<3 {
                    let s = corners.reduce(0) { $0 + $1[k] }
                    bg[k] = Int((Double(s) / 4).rounded())
                }
            }
            var minX = aw, minY = ah, maxX = -1, maxY = -1
            for y in 0..<ah {
                for x in 0..<aw {
                    let i = (y * aw + x) * 4
                    let a = Int(px[i + 3])
                    let hit: Bool
                    if transparent {
                        hit = a > 30
                    } else {
                        let d = abs(Int(px[i]) - bg[0]) + abs(Int(px[i + 1]) - bg[1]) + abs(Int(px[i + 2]) - bg[2])
                        hit = a > 30 && d > 48
                    }
                    if hit {
                        if x < minX { minX = x }
                        if x > maxX { maxX = x }
                        if y < minY { minY = y }
                        if y > maxY { maxY = y }
                    }
                }
            }
            if maxX >= 0 {
                box = CGRect(x: CGFloat(minX) / ss, y: CGFloat(minY) / ss,
                             width: CGFloat(maxX - minX + 1) / ss, height: CGFloat(maxY - minY + 1) / ss)
            }
        }
        return CropPrep(img: img, w: W, h: H, bgR: bg[0], bgG: bg[1], bgB: bg[2], box: box)
    }
}

/// Bild zuschneiden (quadratisch, Zoom, Hintergrund). onDone liefert PNG-Daten (512×512) und Hintergrundfarbe (Hex).
/// Das Fenster schliesst sich nach «Übernehmen»; den Toast («Logo gesetzt» / «Bild gesetzt») zeigt der Aufrufer.
struct ImageCropSheet: View {
    let image: UIImage
    let title: String
    let onDone: (Data, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var prep: CropPrep?
    /// Zoom relativ zur Kachelbreite (Kachelbreiten pro Bildpunkt); Anzeige-Massstab = z × Kachelbreite
    @State private var z: CGFloat = 1
    @State private var zAuto: CGFloat = 1
    /// Bildpunkt in der Kachelmitte
    @State private var cx: CGFloat = 0
    @State private var cy: CGFloat = 0
    @State private var bgMode: BgMode = .auto
    @State private var containerW: CGFloat = 340
    @State private var dragLast: CGSize = .zero
    @State private var pinchBase: CGFloat?
    @State private var errorText: String?

    private enum BgMode: Hashable { case auto, white, black }

    var body: some View {
        NavigationStack {
            ScrollView {
                form
            }
            .background(KColor.paper.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    private var form: some View {
        VStack(spacing: 16) {
            Text("Mit einem Finger verschieben, mit zwei Fingern oder dem Regler zoomen. So sieht die Kachel später aus.")
                .font(.footnote)
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            preview
            zoomRow
            bgSection
            if let e = errorText {
                Text(e).font(.footnote).foregroundStyle(KColor.alert)
            }
            Button { export() } label: {
                Text("Übernehmen").font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(prep == nil)
            Button { autoFit() } label: {
                Text("Automatisch einpassen").frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .disabled(prep == nil)
        }
        .padding(KMetric.gutter)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { g in
                Color.clear
                    .onAppear { containerW = g.size.width }
                    .onChange(of: g.size.width) { _, w in containerW = w }
            }
        )
    }

    // MARK: Ansicht

    private var side: CGFloat { Swift.max(120, Swift.min(280, containerW * 0.74)) }

    private var bgColor: Color {
        switch bgMode {
        case .white: return .white
        case .black: return .black
        case .auto: return autoColor
        }
    }

    private var autoColor: Color {
        guard let p = prep else { return .white }
        return Color(red: Double(p.bgR) / 255, green: Double(p.bgG) / 255, blue: Double(p.bgB) / 255)
    }

    private var preview: some View {
        let s = side
        return ZStack {
            bgColor
            if let p = prep {
                let k = z * s
                Image(uiImage: p.img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: p.w * k, height: p.h * k)
                    .position(x: s / 2 + (p.w / 2 - cx) * k, y: s / 2 + (p.h / 2 - cy) * k)
            } else {
                ProgressView()
            }
        }
        .frame(width: s, height: s)
        .clipShape(RoundedRectangle(cornerRadius: s * 0.22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: s * 0.22, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
        .contentShape(Rectangle())
        .highPriorityGesture(dragGesture.simultaneously(with: pinchGesture))
        .accessibilityLabel("Vorschau der Kachel")
    }

    private var zoomRow: some View {
        HStack(spacing: 12) {
            Text("−").font(.title3).foregroundStyle(KColor.ink2).accessibilityHidden(true)
            Slider(value: Binding(get: { zoomToSlider(z) }, set: { z = sliderToZoom($0) }), in: 0...100, step: 1)
                .accessibilityLabel("Zoom")
                .disabled(prep == nil)
            Text("+").font(.title3).foregroundStyle(KColor.ink2).accessibilityHidden(true)
        }
    }

    private var bgSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hintergrund")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KColor.ink2)
            HStack(spacing: 8) {
                bgChip(.auto, "Automatisch", autoColor)
                bgChip(.white, "Weiss", .white)
                bgChip(.black, "Schwarz", .black)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bgChip(_ mode: BgMode, _ title: String, _ dot: Color) -> some View {
        let on = bgMode == mode
        return Button { bgMode = mode } label: {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(KColor.line, lineWidth: 1))
                Text(title).font(.subheadline.weight(on ? .semibold : .regular)).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .foregroundStyle(on ? Color.white : KColor.ink)
            .background(Capsule().fill(on ? KColor.teal : KColor.field))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Gesten

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                guard prep != nil else { return }
                let k = z * side
                guard k > 0 else { return }
                let dx = v.translation.width - dragLast.width
                let dy = v.translation.height - dragLast.height
                dragLast = v.translation
                cx -= dx / k
                cy -= dy / k
            }
            .onEnded { _ in dragLast = .zero }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                guard prep != nil else { return }
                if pinchBase == nil { pinchBase = z }
                z = clampZoom((pinchBase ?? z) * v.magnification)
            }
            .onEnded { _ in pinchBase = nil }
    }

    // MARK: Zoom (Regler 0…100, Mitte = automatisch eingepasst, Bereich ÷4 … ×4)

    private func zoomToSlider(_ k: CGFloat) -> Double {
        guard zAuto > 0, k > 0 else { return 50 }
        return Swift.max(0, Swift.min(100, 50 + 25 * log2(Double(k / zAuto))))
    }

    private func sliderToZoom(_ v: Double) -> CGFloat {
        zAuto * CGFloat(pow(2, (v - 50) / 25))
    }

    private func clampZoom(_ k: CGFloat) -> CGFloat {
        Swift.max(sliderToZoom(0), Swift.min(sliderToZoom(100), k))
    }

    // MARK: Ablauf

    private func load() async {
        guard prep == nil else { return }
        let src = image
        let p = await Task.detached(priority: .userInitiated) { CropMath.prepare(src) }.value
        prep = p
        autoFit()
    }

    /// Automatisch einpassen (cropAutoFit): Inhalt füllt 74 % der Kachel, Mitte = Inhaltsmitte
    private func autoFit() {
        guard let p = prep else { return }
        let m = Swift.max(p.box.width, p.box.height)
        zAuto = m > 0 ? 0.74 / m : 1
        z = zAuto
        cx = p.box.midX
        cy = p.box.midY
    }

    private var bgHex: String {
        switch bgMode {
        case .white: return "#FFFFFF"
        case .black: return "#000000"
        case .auto:
            guard let p = prep else { return "#FFFFFF" }
            return String(format: "#%02X%02X%02X", p.bgR, p.bgG, p.bgB)
        }
    }

    /// Übernehmen (cropOk): 512×512 PNG mit gewähltem Hintergrund
    private func export() {
        guard let p = prep else { return }
        let S: CGFloat = 512
        let bg: UIColor
        switch bgMode {
        case .white: bg = .white
        case .black: bg = .black
        case .auto: bg = UIColor(red: CGFloat(p.bgR) / 255, green: CGFloat(p.bgG) / 255, blue: CGFloat(p.bgB) / 255, alpha: 1)
        }
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = true
        let k = z * S
        let out = UIGraphicsImageRenderer(size: CGSize(width: S, height: S), format: fmt).image { ctx in
            bg.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
            ctx.cgContext.interpolationQuality = .high
            p.img.draw(in: CGRect(x: S / 2 - cx * k, y: S / 2 - cy * k, width: p.w * k, height: p.h * k))
        }
        guard let png = out.pngData() else {
            errorText = "Bild konnte nicht erzeugt werden"
            return
        }
        onDone(png, bgHex)
        dismiss()
    }
}
