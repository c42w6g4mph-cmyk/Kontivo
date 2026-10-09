import Foundation
import KontivoCore

/// Einzige Stelle, an der die Oberfläche die Kontoauszug-Einstellungen des Kerns schreibt
/// (Web `state.settings.bankIgn` / `bankAlias`, Felder liefert der Bereich «bank» in `Settings`).
/// Annahme: `bankIgn: [String]`, `bankAlias: [String: BankAlias]` mit `BankAlias(n:c:)` (Name, Kategoriename) – bei
/// anderer Form nur diese Datei anpassen.
enum BankBridge {
    /// «Nie mehr vorschlagen» (Web: Schlüssel `bankIgnKey` in `bankIgn`)
    static func ignore(_ s: BankSuggestion, in d: inout AppData) {
        let k = BankImport.ignoreKey(s)
        if !d.settings.bankIgn.contains(k) { d.settings.bankIgn.append(k) }
    }

    /// Gelernte Korrektur (Web: beim Anlegen, wenn Name oder Kategorie geändert wurden)
    static func learn(_ s: BankSuggestion, name: String, category: String, in d: inout AppData) {
        d.settings.bankAlias[BankImport.ignoreKey(s)] = BankAlias(n: name, c: category)
    }
}
