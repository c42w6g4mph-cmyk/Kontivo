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
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }
}

extension Color {
    /// «#RRGGBB» (oder #RGB). Ungültig → Grau der Web-App.
    init(hex: String?) {
        var s = (hex ?? "").trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt32(s.prefix(6), radix: 16) ?? 0x5F666E
        self = Color(UIColor(rgb: s.count >= 6 ? v : 0x5F666E))
    }
}

/// Symbole: Schlüssel der Web-App (Kategoriename der Vorbelegung, «tag», Einnahmenart) → SF Symbol
enum KIcon {
    static func symbol(forKey key: String) -> String {
        switch key {
        case "Wohnen": return "house"
        case "Energie & Wasser": return "bolt"
        case "Versicherung": return "checkmark.shield"
        case "Gesundheit": return "heart"
        case "Mobilfunk & Internet": return "iphone"
        case "Abos & Medien": return "play.rectangle"
        case "Mobilität": return "car"
        case "Familie & Bildung": return "person.2"
        case "Freizeit & Sport": return "dumbbell"
        case "Steuern & Gebühren": return "doc.text"
        case "Finanzen": return "building.columns"
        case "Sonstiges": return "square.grid.2x2"
        case "Lohn": return "briefcase"
        case "Nebeneinkommen": return "plus.circle"
        case "Bonus": return "gift"
        case "Kapitalerträge": return "chart.line.uptrend.xyaxis"
        case "Vermietung": return "key"
        case "Rente": return "hourglass"
        case "Zulagen": return "person.badge.plus"
        case "Unterstützung": return "heart"
        case "Rückerstattung": return "arrow.uturn.backward.circle"
        default: return "tag"
        }
    }

    static func symbol(for category: KontivoCore.Category?) -> String {
        guard let c = category else { return symbol(forKey: "Sonstiges") }
        return symbol(forKey: c.icon)
    }

    /// Auswahl für eigene Kategorien (Verwalten → Kategorie → Symbol)
    static let choices: [String] = KontivoCore.Category.iconKeys
}

/// Abstände und Radien wie in der Web-App
enum KMetric {
    static let radius: CGFloat = 13
    static let markRadius: CGFloat = 10
    static let gutter: CGFloat = 16
    /// Max. Inhaltsbreite auf dem iPad
    static let maxContent: CGFloat = 600
}


/// Schriften der Web-App. CSS-px = iOS-pt.
/// - Text: `-apple-system` (SF Pro) → `.system(size:weight:)`
/// - Überschriften (v176): SF Pro Semibold 600, Laufweite −0.015em → `KFont.title`
/// - Grosse Beträge (v164, Web `--serif` = ui-serif/New York) → `KFont.serif`, Tabellenziffern
/// - Beträge in Listen (`.cmain .n`, `.mn`, `.dcv`): ui-rounded → `KFont.rounded`
enum KFont {
    static func serif(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
    static func title(_ size: CGFloat) -> Font { .system(size: size, weight: .semibold) }
    /// Laufweite in pt aus em (z.B. −0.015em bei 30 px → −0.45)
    static func tracking(_ em: CGFloat, _ size: CGFloat) -> CGFloat { em * size }
}
