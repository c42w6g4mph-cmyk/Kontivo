import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signatur beibehalten)
/// Unterschrift zeichnen (PencilKit). onDone liefert JPEG-Daten (zugeschnitten, Tintenblau auf weiss).
struct SignaturePadSheet: View {
    let title: String
    let onDone: (Data) -> Void
    var body: some View { Text(title) }
}

/// Namenszug-Vorschläge (6 Handschriften aus dem Bundle). onPick liefert JPEG-Daten.
struct SignatureSuggestionsSheet: View {
    let first: String
    let last: String
    let onPick: (Data) -> Void
    var body: some View { Text("Vorschläge") }
}
