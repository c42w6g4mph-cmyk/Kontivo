import SwiftUI
import KontivoCore

@main
struct KontivoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(model.preferredColorScheme)
                // Daten, Zahlen und Datumsauswahl immer Schweizer Format (wie die Web-App), unabhängig von der Gerätesprache
                .environment(\.locale, Locale(identifier: "de_CH"))
                .tint(KColor.teal)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: model.sceneBecameActive()
            case .background: model.saveNow()
            default: break
            }
        }
    }
}
