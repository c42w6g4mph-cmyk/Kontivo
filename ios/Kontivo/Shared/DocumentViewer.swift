import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signatur beibehalten)
/// Zeigt eine Datei (PDF/Bild) an; bei einem Brief-PDF mit Aktionen (Text ändern, Mail, Drucken, Teilen).
struct DocumentViewer: View {
    let ref: DocumentRef
    var body: some View { Text(ref.title) }
}
