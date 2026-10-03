import SwiftUI
import UIKit
import KontivoCore

/// Farben der Web-App (CSS-Variablen), hell/dunkel automatisch.
enum KColor {
    static let paper   = dyn(0xF3F1EC, 0x15171A)
    static let surface = dyn(0xFBFAF7, 0x1E2125)
    static let sunken  = dyn(0xE9E6DF, 0x272B30)
    static let field   = dyn(0xEFEDE7, 0x272B30)
    static let ink     = dyn(0x1B1E23, 0xE9EAE5)
    static let ink2    = dyn(0x5F666E, 0x9AA1A8)
    static let ink3    = dyn(0x687077, 0x8D949B)
    static let line    = dyn(0xE1DED6, 0x2F343A)
    static let teal    = dyn(0x0E5A5E, 0x5FB3B5)
    static let ok      = dyn(0x2E6A4E, 0x6FB58E)
    static let warn    = dyn(0x9A6710, 0xD9A545)
    static let alert   = dyn(0xA93227, 0xE5776A)
    /// Bezahlt/offen in Diagrammen
    static let barPaid = teal
    static let barOpen = ink

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
