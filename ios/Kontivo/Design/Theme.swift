import SwiftUI
import UIKit
import KontivoCore

/// Farben der Web-App (CSS-Variablen), hell/dunkel automatisch.
enum KColor {
    // Web v224 «Graphit & Messing» (berechnete CSS-Variablen, hell / dunkel G2)
    static let paper   = dyn(0xF4F4F2, 0x2C2D30)
    static let surface = dyn(0xFFFFFF, 0x36373B)
    static let sunken  = dyn(0xEEEEEC, 0x414246)
    static let field   = dyn(0xF1F1EF, 0x414246)
    static let ink     = dyn(0x121314, 0xE8E6E2)
    static let ink2    = dyn(0x5E6064, 0xA8A7A3)
    static let ink3    = dyn(0x6A6C70, 0x9C9B97)
    static let line    = dyn(0xE6E6E3, 0x45464A)
    /// Akzent (Web `--teal`, heute Messing). Name bleibt aus Kompatibilität.
    static let teal    = dyn(0x86671F, 0xC6AB78)
    /// Gefüllte Knöpfe/Chips (Web `--tealFill`)
    static let tealFill = dyn(0x86671F, 0xC6AB78)
    static let ok      = dyn(0x2E6A4E, 0x7DBF98)
    static let warn    = dyn(0x86671F, 0xC6AB78)
    static let alert   = dyn(0xA93227, 0xE8837A)
    /// Gefüllte Warnflächen (Web `--alertFill`)
    static let alertFill = dyn(0xA93227, 0xC0473B)
    /// Messing (Web `--brass`): Striche, Ringsegment, Haken
    static let brass   = dyn(0xA88437, 0xC6AB78)
    /// Plus-Knopf, Badge (Web `--brassFab`)
    static let brassFab = dyn(0x8F6E22, 0xC6AB78)
    /// Schrift auf Messing (Web `--onBrass`)
    static let onBrass = dyn(0xFFFFFF, 0x1E1D1A)
    /// Glasfläche Tabbar (Web `--glass`, `--glassEdge`, `--glassShade`)
    static let glass      = dynA((0xFAFAF8, 0.70), (0x36373B, 0.72))
    static let glassEdge  = dynA((0xFFFFFF, 0.75), (0xFFFFFF, 0.14))
    static let glassShade = dynA((0x141E23, 0.14), (0x000000, 0.45))
    /// Web `--lift`: Aufhellung der Kategoriefarbe im Dunkelmodus (0 % / 26 %)
    static func lift(_ scheme: ColorScheme) -> Double { scheme == .dark ? 0.26 : 0 }
    /// Bezahlt/offen in Diagrammen
    static let barPaid = teal
    static let barOpen = ink

    /// Leichte Messingfläche (Web `color-mix(in srgb, var(--brass) 18%, var(--surface))`, z.B. `.mgi.i4.w`)
    static let brassSoft = mixDyn(brassRGB, surfaceRGB, 0.18)
    /// Akzent mit 14 % Deckkraft (Plaketten «5 offen», Web `color-mix(--teal 14%, transparent)`)
    static let tealTint = dynA((0x86671F, 0.14), (0xC6AB78, 0.14))

    // MARK: Kategoriefarben (Web v166 «Kategorien in Pastell»)

    /// Fläche einer Kategorie-Marke: Kategoriefarbe 20 % (hell) bzw. 30 % (dunkel) über `--surface`.
    static func categoryFill(_ hex: String?) -> Color {
        let c = rgb(hex)
        return Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(rgb: mix(c, 0x36373B, 0.30)) : UIColor(rgb: mix(c, 0xFFFFFF, 0.20))
        })
    }

    /// Symbol einer Kategorie-Marke: Kategoriefarbe (hell) bzw. 45 % Farbe + Weiss (dunkel).
    static func categoryInk(_ hex: String?) -> Color {
        let c = rgb(hex)
        return Color(UIColor { tc in
            tc.userInterfaceStyle == .dark ? UIColor(rgb: mix(c, 0xFFFFFF, 0.45)) : UIColor(rgb: c)
        })
    }

    /// Altes Petrol/Türkis aus gespeicherten Farben beim Anzeigen ersetzen (Web `newCol`/`OLD_COL`, v165).
    static func displayHex(_ hex: String?) -> String {
        let h = (hex ?? "").trimmingCharacters(in: .whitespaces)
        return oldColors[h.lowercased()] ?? h
    }

    static let oldColors: [String: String] = ["#0e5a5e": "#4A5A66", "#2f86a6": "#3F6E9A", "#2b7a7d": "#4A5A66", "#5fb3b5": "#4A5A66"]

    /// «#RRGGBB»/«#RGB» → 0xRRGGBB (ungültig → #5F666E, Web `--c` Ersatz)
    static func rgb(_ hex: String?) -> UInt32 {
        var s = displayHex(hex)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count >= 6, let v = UInt32(s.prefix(6), radix: 16) else { return 0x5F666E }
        return v
    }

    /// `color-mix(in srgb, a p, b)`
    static func mix(_ a: UInt32, _ b: UInt32, _ p: Double) -> UInt32 {
        func ch(_ v: UInt32, _ s: UInt32) -> Double { Double((v >> s) & 0xFF) }
        func m(_ s: UInt32) -> UInt32 { UInt32((ch(a, s) * p + ch(b, s) * (1 - p)).rounded()) & 0xFF }
        return (m(16) << 16) | (m(8) << 8) | m(0)
    }

    private static let brassRGB: (UInt32, UInt32) = (0xA88437, 0xC6AB78)
    private static let surfaceRGB: (UInt32, UInt32) = (0xFFFFFF, 0x36373B)

    private static func mixDyn(_ a: (UInt32, UInt32), _ b: (UInt32, UInt32), _ p: Double) -> Color {
        dyn(mix(a.0, b.0, p), mix(a.1, b.1, p))
    }

    private static func dynA(_ light: (UInt32, CGFloat), _ dark: (UInt32, CGFloat)) -> Color {
        Color(UIColor { tc in
            let v = tc.userInterfaceStyle == .dark ? dark : light
            return UIColor(rgb: v.0, alpha: v.1)
        })
    }

    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { tc in
            UIColor(rgb: tc.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// UIKit-Farbe hell/dunkel (Navigationsleisten, Tabbar)
    static func ui(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor { tc in UIColor(rgb: tc.userInterfaceStyle == .dark ? dark : light, alpha: alpha) }
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// «#RRGGBB» (oder #RGB). Ungültig → Grau der Web-App. Alte Türkis-Töne werden wie im Web ersetzt (`newCol`).
    init(hex: String?) {
        self = Color(UIColor(rgb: KColor.rgb(hex)))
    }
}

/// Symbole der Web-App als Vektor-Vorlagen im Asset-Katalog (`Assets.xcassets/Icons/ic.<name>`, Pfade 1:1 aus index.html v224).
/// Kategorie-Symbole: Schlüssel der Web-App (Kategoriename der Vorbelegung, «tag», Einnahmenart) → `ic.cat.<slug>`.
/// Anzeige immer über `KIcon.image(_:)` (kann auch SF-Symbol-Namen anzeigen).
enum KIcon {
    /// Asset-Name des Kategorie-Symbols (Web `CAT_ICON`/`TAG_ICON`)
    static func symbol(forKey key: String) -> String {
        if let s = catSlug[key] { return "ic.cat." + s }
        return "ic.cat.tag"
    }

    static func symbol(for category: KontivoCore.Category?) -> String {
        guard let c = category else { return symbol(forKey: "Sonstiges") }
        return symbol(forKey: c.icon)
    }

    /// Auswahl für eigene Kategorien (Verwalten → Kategorie → Symbol)
    static let choices: [String] = KontivoCore.Category.iconKeys

    /// Bild zu einem Namen: «ic.…» = Web-Symbol aus dem Asset-Katalog (Vorlage, Farbe über foregroundStyle), sonst SF Symbol.
    static func image(_ name: String) -> Image {
        name.hasPrefix("ic.") ? Image(name) : Image(systemName: name)
    }

    /// Web-Symbol in fester Grösse (CSS `width/height`), z.B. `KIcon.view("ic.search", 17)`
    static func view(_ name: String, _ size: CGFloat) -> some View {
        image(name).resizable().renderingMode(.template).scaledToFit().frame(width: size, height: size)
    }

    static let catSlug: [String: String] = [
        "Wohnen": "wohnen", "Energie & Wasser": "energie", "Versicherung": "versicherung", "Gesundheit": "gesundheit",
        "Mobilfunk & Internet": "mobilfunk", "Abos & Medien": "abos", "Mobilität": "mobilitaet", "Familie & Bildung": "familie",
        "Freizeit & Sport": "freizeit", "Steuern & Gebühren": "steuern", "Finanzen": "finanzen", "Sonstiges": "sonstiges",
        "Lohn": "lohn", "Nebeneinkommen": "nebeneinkommen", "Bonus": "bonus", "Kapitalerträge": "kapital", "Vermietung": "vermietung",
        "Rente": "rente", "Zulagen": "zulagen", "Unterstützung": "unterstuetzung", "Rückerstattung": "rueckerstattung", "tag": "tag",
    ]
}

/// Abstände und Radien wie in der Web-App
enum KMetric {
    /// `.sgroup`, Formulargruppen, `--r` (13 px)
    static let radius: CGFloat = 13
    static let markRadius: CGFloat = 10
    /// Seitenrand (`.wrap` padding 0 17px)
    static let gutter: CGFloat = 17
    /// Gruppierte Listen (Verträge, Detail, Kosten): Radius 16 (v164)
    static let groupRadius: CGFloat = 16
    /// Steuerelemente (Suche, Filter, Segmente): Radius 10 (v164)
    static let controlRadius: CGFloat = 10
    /// Trennlinie in Listen mit Marke beginnt bei 62 px (v164 `.bkr+.bkr:before`)
    static let rowDividerInset: CGFloat = 62
    /// Titelzeile der Tabs (v184 `.top` min-height 57)
    static let titleBarHeight: CGFloat = 57
    /// Max. Seitenbreite auf dem iPad inkl. Seitenrand 17 (Web `.wrap` max-width 580 → Inhalt 546)
    static let maxContent: CGFloat = 580
    /// Unterer Inhaltsabstand einer Tab-Seite: Web `.wrap` padding-bottom 138 ab Bildschirmrand, abzüglich des
    /// Sicherheitsabstands der Tabbar (iPhone 17 Pro) → Abstand am Ende des ScrollView-Inhalts (gemessen am Simulatorfoto)
    static let tabPageBottom: CGFloat = 56

    /// Eckenradius einer Marke je Grösse (Web `.mark` je Ort: 50→12, 44→11, 40→10, 38→9, 36→10, 34→9, 32→8, 30→8, 28→7)
    static func markRadius(_ size: CGFloat) -> CGFloat {
        switch size {
        case ..<29: return 7
        case ..<33: return 8
        case ..<35: return 9
        case ..<37: return 10
        case ..<39: return 9
        case 70..<80: return 17   // Formular-Kopf 76 (Web `.mark.lg`)
        default: return (size * 0.24).rounded()
        }
    }
}


/// Schriften der Web-App. CSS-px = iOS-pt.
/// - Text: `-apple-system` (SF Pro) → `.system(size:weight:)` bzw. `KFont.text`
/// - Überschriften (v176): SF Pro Semibold 600, Laufweite −0.015em → `KFont.title`
/// - Grosse Beträge (v164, Web `--serif` = ui-serif/New York) → `KFont.serif`, Tabellenziffern
/// - Beträge in Listen (`.cmain .n`, `.mn`, `.dcv`): ui-rounded → `KFont.rounded`
/// - Wortmarke (v171): Inter Display Bold → `KFont.wordmark`
enum KFont {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    static func text(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
    /// Wortmarke «Kontivo» (Inter Display Bold, OFL; Datei Resources/Fonts/InterDisplay-Bold.ttf)
    static func wordmark(_ size: CGFloat) -> Font { .custom("InterDisplay-Bold", fixedSize: size) }
    /// Laufweite in pt aus em (z.B. −0.015em bei 30 px → −0.45)
    static func tracking(_ em: CGFloat, _ size: CGFloat) -> CGFloat { em * size }
    /// Natürliche Zeilenhöhe von SF Pro (Ascender + Descender ≈ 1.193 × Grösse)
    static func naturalLineHeight(_ size: CGFloat) -> CGFloat { (size * 1.193).rounded(.up) }
}

extension View {
    /// CSS-Zeilenhöhe nachbilden: Zeilenabstand innerhalb mehrzeiliger Texte plus halber Durchschuss oben und unten
    /// (wie `line-height` im Web). Beispiel `.kLineHeight(12.5, 19.375)`.
    func kLineHeight(_ size: CGFloat, _ lineHeight: CGFloat) -> some View {
        let extra = max(0, lineHeight - KFont.naturalLineHeight(size))
        return self.lineSpacing(extra).padding(.vertical, extra / 2)
    }
}
