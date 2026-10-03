import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signatur beibehalten)
extension AppModel {
    /// Startet die Kündigung je nach Kündigungsweg (Online → Link, E-Mail → Mail, Brief → Kündigungsschreiben, offen → Auswahl).
    func startCancel(_ contractID: UUID, trial: Bool) {}
    /// Beim Zurückkehren in die App: Rückfrage «Gekündigt?», wenn eine Kündigung über Website/E-Mail gestartet wurde.
    func cancelReturnCheck() {}
}
