import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signaturen beibehalten)
extension AppModel {
    /// Startet die Kündigung je nach Kündigungsweg (Online → Link, E-Mail → Mail, Brief → Kündigungsschreiben, offen → Auswahl).
    func startCancel(_ contractID: UUID, trial: Bool) {}
    /// Beim Zurückkehren in die App: Rückfrage «Gekündigt?» (setzt cancelQuestion), wenn eine Kündigung über Website/E-Mail gestartet wurde.
    func cancelReturnCheck() {}
    /// Text der Rückfrage «Gekündigt?»
    func cancelQuestionText(_ q: PendingCancel) -> String { "" }
    /// Antwort auf die Rückfrage
    func answerCancelQuestion(_ q: PendingCancel, cancelled: Bool) { cancelQuestion = nil }
}
