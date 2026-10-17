import Foundation

/// Anzeigefarben der Kategorien (Web v190 «kräftigere Kategoriefarben», `catColor` mit `CAT_OLD`/`CAT_COLOR`, und Design
/// 13.10.2026 `OLD_COL`): gespeicherte alte Standardfarben werden beim Anzeigen ersetzt, eigene Farben bleiben. Daten unverändert.
public enum CategoryPalette {
    /// Altes Petrol/Türkis → neutrale Töne (Web `OLD_COL`)
    public static let oldTeal: [String: String] = ["#0e5a5e": "#4A5A66", "#2f86a6": "#3F6E9A", "#2b7a7d": "#4A5A66", "#5fb3b5": "#4A5A66"]
    /// Frühere Standardfarben je Standardkategorie (Web `CAT_OLD`)
    public static let previous: [String: String] = [
        "Wohnen": "#6b4e9e", "Energie & Wasser": "#b0562a", "Versicherung": "#4a5a66", "Gesundheit": "#b03a5b",
        "Mobilfunk & Internet": "#1f4e8c", "Abos & Medien": "#a93227", "Mobilität": "#3f4a55", "Familie & Bildung": "#3f6e9a",
        "Freizeit & Sport": "#2e6a4e", "Steuern & Gebühren": "#6e7b3a", "Finanzen": "#8a6a1f", "Sonstiges": "#5f666e",
    ]
    /// Aktuelle Standardfarben (Web `CAT_COLOR`, v190)
    public static let current: [String: String] = [
        "Wohnen": "#6A4FB3", "Energie & Wasser": "#D0692B", "Versicherung": "#2F7F7A", "Gesundheit": "#C2416B",
        "Mobilfunk & Internet": "#2563B8", "Abos & Medien": "#C0392B", "Mobilität": "#8B5A3C", "Familie & Bildung": "#3B8BC9",
        "Freizeit & Sport": "#2E8B57", "Steuern & Gebühren": "#7E8F25", "Finanzen": "#B08A1E", "Sonstiges": "#6B7280",
        "Lohn": "#2E6A4E", "Nebeneinkommen": "#4A5A66", "Bonus": "#8A6A1F", "Kapitalerträge": "#1F4E8C", "Vermietung": "#6B4E9E",
        "Rente": "#B0562A", "Zulagen": "#B23A6F", "Unterstützung": "#3D6FA8", "Rückerstattung": "#5F7A2E",
    ]

    /// Anzeigefarbe: `hex` = gespeicherte Farbe, `key` = Standardschlüssel (Name der Vorbelegung) oder Name.
    public static func display(_ hex: String?, key: String) -> String {
        let raw = (hex ?? "").trimmingCharacters(in: .whitespaces)
        let valid = raw.range(of: "^#[0-9a-fA-F]{3,8}$", options: .regularExpression) != nil
        let c = valid ? (oldTeal[raw.lowercased()] ?? raw) : ""
        if !c.isEmpty, let o = previous[key], c.lowercased() == o, let n = current[key] { return n }
        if !c.isEmpty { return c }
        return current[key] ?? "#6B7280"
    }
}

extension AppData {
    /// Anzeigefarbe einer Kategorie nach Name (Web `catColor(name)`)
    public func categoryDisplayColor(named name: String) -> String {
        guard let cat = category(named: name) else { return CategoryPalette.current[name] ?? "#6B7280" }
        let key = Category.standardNames.contains(cat.icon) ? cat.icon : cat.name
        return CategoryPalette.display(cat.colorHex, key: key)
    }
}
