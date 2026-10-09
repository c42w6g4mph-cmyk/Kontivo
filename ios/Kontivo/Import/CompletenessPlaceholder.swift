import SwiftUI
import KontivoCore

/// Platzhalter für die Route `.completeness(only:)`, bis der Bereich core die Vollständigkeit-Ansicht liefert.
/// Beim Zusammenführen: in `AppSheetView` durch die echte Ansicht ersetzen und diese Datei löschen.
struct CompletenessPlaceholder: View {
    let only: UUID?
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ContentUnavailableView("Vollständigkeit", systemImage: "checklist",
                                   description: Text("Logos, Kündigungsfristen und Absender ergänzen."))
                .navigationTitle("Vollständigkeit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Schliessen") { model.dismissTop() }
                    }
                }
        }
    }
}
