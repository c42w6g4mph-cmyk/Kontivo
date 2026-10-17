import Foundation

/// Wann die Wechselkurse automatisch neu geladen werden (Web `autoRate`, v162).
///
/// Die EZB veröffentlicht werktags gegen 16 Uhr. Solange der Stand nicht von heute ist, wird alle 3 Stunden erneut geprüft
/// (vorher nur einmal pro Tag → am Morgen geprüft = Vortageskurs bis zum nächsten Tag). Bei offener App zusätzlich stündlich
/// (`foregroundInterval`, Web `setInterval(…, 3600e3)`), sonst beim Zurückkehren in die App.
public enum RatePolicy {
    /// Mindestabstand zwischen zwei Abrufen, solange der Kurs nicht von heute ist (Web `3*3600e3`).
    public static let recheckInterval: TimeInterval = 3 * 3600
    /// Prüftakt bei offener App (Web `setInterval(…, 3600e3)`).
    public static let foregroundInterval: TimeInterval = 3600

    /// Abruf nötig? (ohne `force`): USD fehlt → ja; Kursdatum = heute → nein; letzter Abruf vor weniger als 3 h → nein.
    public static func needsFetch(_ s: Settings, today: Day, now: Date = Date()) -> Bool {
        guard (s.rates["USD"] ?? 0) > 0 else { return true }
        if s.rateDate == today { return false }
        if let at = s.rateCheckedAt, now.timeIntervalSince(at) < recheckInterval { return false }
        return true
    }

    /// Nach erfolgreichem Abruf (Web: `rateChecked = heute`, `rateCheckedAt = Date.now()`).
    public static func markChecked(_ s: inout Settings, today: Day, now: Date = Date()) {
        s.rateChecked = today
        s.rateCheckedAt = now
    }
}
