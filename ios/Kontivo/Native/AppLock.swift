import SwiftUI
import UIKit
import LocalAuthentication
import KontivoCore

/// «App-Sperre»: Face ID / Touch ID / Gerätecode (`.deviceOwnerAuthentication`) beim Start und nach mehr als
/// 30 Sekunden im Hintergrund; Datenschutz-Abdeckung (Papier mit Unschärfe + Logo) im App-Umschalter.
/// Sperre und Abdeckung liegen in einem eigenen Fenster über allem (auch über offenen Fenstern und Alerts).
@MainActor
@Observable
final class AppLock {
    static let shared = AppLock()

    /// Nach so vielen Sekunden im Hintergrund wird wieder entsperrt
    static let graceSeconds: TimeInterval = 30

    /// Sperrbildschirm sichtbar
    private(set) var locked = false
    /// Nur Abdeckung (App-Umschalter, inaktiv)
    private(set) var covered = false
    /// Systemabfrage Face ID/Code läuft
    private(set) var authenticating = false
    /// Letzter Versuch abgebrochen/fehlgeschlagen: Knopf «Entsperren» zeigen
    private(set) var failed = false

    /// Eigene Systemabfragen (Mitteilungen, Kalender, Face ID beim Einschalten): App wird kurz inaktiv, keine Abdeckung
    @ObservationIgnored var suppressCover = false
    @ObservationIgnored private var backgroundAt: Date?
    @ObservationIgnored private var started = false
    /// Beim nächsten Aktivwerden automatisch Face ID/Code anfragen (Start, Rückkehr nach > 30 s).
    /// Nach Abbrechen nicht erneut automatisch (sonst Endlosschleife), dann Knopf «Entsperren».
    @ObservationIgnored private var autoAuth = false
    @ObservationIgnored private var window: UIWindow?

    var enabled: Bool { NativePrefs.lockOn }

    // MARK: Lebenszyklus (aus NativeHooks)

    /// Erster Auftritt der App: bei eingeschalteter Sperre sofort sperren.
    func appStarted(phase: ScenePhase) {
        guard !started else { return }
        started = true
        guard enabled else { return }
        locked = true
        autoAuth = true
        updateWindow()
        if phase == .active {
            autoAuth = false
            authenticate()
        }
    }

    func phaseChanged(_ phase: ScenePhase) {
        switch phase {
        case .background:
            backgroundAt = Date()
            if enabled {
                covered = true
                updateWindow()
            }
        case .inactive:
            if enabled && !authenticating && !suppressCover {
                covered = true
                updateWindow()
            }
        case .active:
            if let t = backgroundAt, enabled, Date().timeIntervalSince(t) > AppLock.graceSeconds {
                locked = true
                autoAuth = true
            }
            backgroundAt = nil
            if !enabled { locked = false }
            if locked && autoAuth && !authenticating {
                autoAuth = false
                authenticate()
            }
            covered = false
            updateWindow()
        @unknown default:
            break
        }
    }

    // MARK: Entsperren

    func authenticate() {
        guard locked, !authenticating else { return }
        if NativePrefs.stub {
            unlock()
            return
        }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // Kein Gerätecode mehr eingerichtet: Sperre ist wirkungslos → entsperren statt aussperren
            unlock()
            return
        }
        authenticating = true
        failed = false
        Task { @MainActor in
            let ok: Bool
            do {
                ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Kontivo entsperren")
            } catch {
                ok = false
            }
            self.authenticating = false
            if ok { self.unlock() } else { self.failed = true }
            self.updateWindow()
        }
    }

    private func unlock() {
        locked = false
        failed = false
        covered = false
        updateWindow()
    }

    /// Einschalten: Gerätecode muss eingerichtet sein, einmal bestätigen. Rückgabe: Fehlermeldung oder nil.
    func enable() async -> String? {
        if NativePrefs.stub {
            NativePrefs.lockOn = true
            return nil
        }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            return "Auf diesem Gerät ist kein Code eingerichtet. Richte in den Einstellungen einen Code (und Face ID) ein, um Kontivo zu sperren."
        }
        suppressCover = true
        defer { suppressCover = false }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "App-Sperre für Kontivo einschalten")
            if ok { NativePrefs.lockOn = true }
            return nil
        } catch {
            return nil
        }
    }

    func disable() {
        NativePrefs.lockOn = false
        locked = false
        covered = false
        failed = false
        updateWindow()
    }

    /// «Face ID», «Touch ID», «Optic ID» bzw. «Code»
    static var methodName: String {
        let ctx = LAContext()
        var err: NSError?
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        switch ctx.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Code"
        }
    }

    static var methodSymbol: String {
        switch methodName {
        case "Face ID": return "faceid"
        case "Touch ID": return "touchid"
        case "Optic ID": return "opticid"
        default: return "lock.fill"
        }
    }

    // MARK: Fenster über allem

    private func updateWindow() {
        let show = locked || covered
        if show {
            if window == nil {
                let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else { return }
                let w = UIWindow(windowScene: scene)
                w.windowLevel = .alert + 1
                w.backgroundColor = .clear
                let host = UIHostingController(rootView: AppLockCoverView())
                host.view.backgroundColor = .clear
                w.rootViewController = host
                // Darstellung wie das Hauptfenster (Hell/Dunkel aus «Darstellung»)
                if let main = scene.windows.first(where: { $0 !== w }) {
                    w.overrideUserInterfaceStyle = main.overrideUserInterfaceStyle
                }
                window = w
            }
            // nicht zum Schlüsselfenster machen (Fenster der App bleiben für Tastatur und Präsentationen zuständig)
            window?.isHidden = false
        } else {
            window?.isHidden = true
        }
    }
}

/// Sperrbildschirm bzw. Abdeckung: Papier mit Unschärfe, Logo, bei Sperre Knopf «Entsperren».
struct AppLockCoverView: View {
    private var lock: AppLock { AppLock.shared }

    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial).ignoresSafeArea()
            KColor.paper.opacity(0.78).ignoresSafeArea()
            VStack(spacing: 14) {
                Image("Logo")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 76, height: 76)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityHidden(true)
                Text("Kontivo")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .foregroundStyle(KColor.ink)
                if lock.locked {
                    Text("Gesperrt")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                    if !lock.authenticating {
                        Button {
                            lock.authenticate()
                        } label: {
                            Label("Entsperren", systemImage: AppLock.methodSymbol)
                                .font(.headline)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(KColor.teal)
                        .padding(.top, 8)
                        .accessibilityIdentifier("lock.unlock")
                    }
                }
            }
            .padding(32)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("lock.cover")
    }
}
