import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signatur beibehalten)
/// Logo-Suche mit Vorschlägen (Wikidata/Commons, App Store, Website-Symbol). Übernahme nur nach Antippen.
/// onPick liefert PNG-Daten (512×512) und die Hintergrundfarbe (Hex).
struct LogoSearchSheet: View {
    let name: String
    let currency: Currency
    let web: String
    let onPick: (Data, String) -> Void
    var body: some View { Text("Logo suchen") }
}
