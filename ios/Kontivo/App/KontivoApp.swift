import SwiftUI
import KontivoCore

@main
struct KontivoApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    /// Bereich native: Empfänger für Mitteilungen vor dem Ende des Starts setzen (Tippen auf eine Erinnerung)
    init() { NativeBoot.start() }

    var body: some Scene {
        WindowGroup {
            RootView()
                // Bereich native: Erinnerungen planen, Erinnerung öffnet Vertrag, App-Sperre (Native/NativeHooks.swift)
                .kontivoNative()
                .environment(model)
                // Darstellung über das UIKit-Fenster (preferredColorScheme(nil) hebt «Dunkel» unter iOS 17 nicht zuverlässig auf)
                .onAppear { KontivoApp.applyInterfaceStyle(model.interfaceStyle) }
                .onChange(of: model.data.settings.theme) { _, _ in KontivoApp.applyInterfaceStyle(model.interfaceStyle) }
                // Daten, Zahlen und Datumsauswahl immer Schweizer Format (wie die Web-App), unabhängig von der Gerätesprache
                .environment(\.locale, Locale(identifier: "de_CH"))
                .tint(KColor.teal)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                KontivoApp.applyInterfaceStyle(model.interfaceStyle)
                model.sceneBecameActive()
            case .background: model.saveNow()
            default: break
            }
        }
    }

    /// Hell/Dunkel/Automatisch für alle Fenster der App (inkl. offener Fenster und Alerts)
    @MainActor
    static func applyInterfaceStyle(_ style: UIUserInterfaceStyle) {
        for scene in UIApplication.shared.connectedScenes {
            guard let ws = scene as? UIWindowScene else { continue }
            for w in ws.windows where w.overrideUserInterfaceStyle != style {
                w.overrideUserInterfaceStyle = style
            }
        }
    }
}
