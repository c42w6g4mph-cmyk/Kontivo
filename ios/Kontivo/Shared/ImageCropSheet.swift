import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signatur beibehalten)
/// Bild zuschneiden (quadratisch, Zoom, Hintergrund). onDone liefert PNG-Daten und Hintergrundfarbe (Hex).
struct ImageCropSheet: View {
    let image: UIImage
    let title: String
    let onDone: (Data, String) -> Void
    var body: some View { Text(title) }
}
