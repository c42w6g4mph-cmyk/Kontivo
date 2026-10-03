import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signatur beibehalten)
struct AddressCandidate: Identifiable, Hashable {
    var id = UUID()
    /// Zeilen: Firma, Strasse, PLZ Ort, ggf. Land
    var lines: [String]
    /// Quelle, z.B. «Wikidata» oder «OpenStreetMap»
    var source: String
}

/// Adresssuche für Vertragspartner (Wikidata + OpenStreetMap/Nominatim wie findAddresses in der Web-App)
enum AddressSearch {
    static func find(name: String, domain: String, currency: Currency) async -> [AddressCandidate] { [] }
}

/// Auswahlliste der gefundenen Adressen
struct AddressPickSheet: View {
    let candidates: [AddressCandidate]
    let onPick: (AddressCandidate) -> Void
    var body: some View { Text("Adressen") }
}
