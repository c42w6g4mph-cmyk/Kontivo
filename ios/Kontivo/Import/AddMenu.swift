import SwiftUI
import KontivoCore

/// Plus oben rechts in «Verträge» (Web 17862f0/fe70531): Menü
/// «Vertrag erfassen» (Einzeln, mit Anbieter-Katalog) | «Aus Kontoauszug» (Fixkosten in Bank-Dateien finden –
/// Konto und Kreditkarte auf einmal) mit der Wahl der Quelle: Datei, Foto aufnehmen, Fotos.
struct AddMenuButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button {
                model.present(.contractForm(.new(prefill: nil)))
            } label: {
                Label {
                    Text("Vertrag erfassen")
                    Text("Einzeln, mit Anbieter-Katalog")
                } icon: {
                    Image(systemName: "square.and.pencil")
                }
            }
            .accessibilityIdentifier("addContract")
            Menu {
                ForEach(BankPickSource.available, id: \.self) { s in
                    Button {
                        BankImportCenter.shared.pick(s, model: model)
                    } label: {
                        Label {
                            Text(s.title)
                            Text(s.subtitle)
                        } icon: {
                            Image(systemName: s.symbol)
                        }
                    }
                }
            } label: {
                Label {
                    Text("Aus Kontoauszug")
                    Text("Fixkosten in Bank-Dateien finden – Konto und Kreditkarte auf einmal")
                } icon: {
                    Image(systemName: "building.columns")
                }
            }
            .accessibilityIdentifier("addBank")
        } label: {
            Image(systemName: "plus")
                .fontWeight(.semibold)
        }
        .accessibilityLabel("Hinzufügen")
        .accessibilityIdentifier("addMenu")
    }
}
