import SwiftUI
import KontivoCore

/// Plus oben rechts in «Verträge» (Web 17862f0/fe70531, v143, v156): Menü
/// «Vertrag erfassen» (Einzeln, mit Vorlagen-Katalog) | «Aus Kontoauszug» (Web v201: Fixkosten automatisch finden –
/// die Datei bleibt auf deinem Gerät) mit der Wahl der Quelle: Datei, Foto aufnehmen, Fotos | «Einnahme erfassen»
/// (Lohn, Rente, Stipendium …).
struct AddMenuButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Button {
                model.present(.contractForm(.new(prefill: nil)))
            } label: {
                Label {
                    Text("Vertrag erfassen")
                    Text("Einzeln, mit Vorlagen-Katalog")
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
                    Text("Fixkosten automatisch finden – die Datei bleibt auf deinem Gerät")
                } icon: {
                    Image(systemName: "building.columns")
                }
            }
            .accessibilityIdentifier("addBank")
            Button {
                model.present(.incomeForm(nil))
            } label: {
                Label {
                    Text("Einnahme erfassen")
                    Text("Lohn, Rente, Stipendium …")
                } icon: {
                    Image(systemName: "arrow.down.to.line")
                }
            }
            .accessibilityIdentifier("addIncome")
        } label: {
            Image(systemName: "plus")
                .fontWeight(.semibold)
        }
        .accessibilityLabel("Hinzufügen")
        .accessibilityIdentifier("addMenu")
    }
}
