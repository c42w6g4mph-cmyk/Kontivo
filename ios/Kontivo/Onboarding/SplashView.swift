import SwiftUI
import KontivoCore

/// Intro beim Öffnen der App (wie `#splash` der Web-App v172–v174): Papierhintergrund, App-Symbol als Vektor (96 pt)
/// federt mit leichter Drehung ein, das Messing-Segment dreht 1.5 Umdrehungen um das K (splSpin), «Kontivo» (Wortmarke mit
/// O als Kreisdiagramm, v171) erscheint Teil für Teil, das Messing-Drittel des O zeichnet sich ab 1 s, der Slogan nach ~1 s;
/// ab 2.0 s blendet alles aus (Logo zoomt leicht). Keine pulsierenden Ringe mehr (v173).
/// Reduzierte Bewegung: alles sofort sichtbar, kürzer (Ausblenden ab 1.2 s).
///
/// Blockiert keine Tipps (`allowsHitTesting(false)`) und ist für VoiceOver unsichtbar.
/// Alle Phasen werden aus der Zeit seit dem Start (`SplashView.launch`) berechnet: Liegt eine zweite Kopie über
/// der Einführung (fullScreenCover beim Erststart), zeigen beide exakt dasselbe Bild – das Hochfahren der Einführung fällt nicht auf.
struct SplashView: View {
    /// Aufruf, wenn das Intro fertig ausgeblendet ist (Overlay entfernen)
    var onDone: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Startzeitpunkt (erster Zugriff = App-Start, RootView fragt `enabled` beim Erzeugen ab)
    static let launch = Date()

    /// Beim Kaltstart zeigen; in UI-Tests nur mit `-uiSplash` (sonst stören 2.5 s Animation die Abläufe)
    static var enabled: Bool {
        _ = launch
        #if DEBUG
        if AppModel.isUITestLaunch {
            let args = ProcessInfo.processInfo.arguments
            return args.contains("-uiSplash") || args.contains("-uiSplashHold")
        }
        #endif
        return true
    }

    /// Ende der Animation (s) – danach wird das Overlay entfernt
    private var total: Double { reduceMotion ? 1.7 : 2.5 }

    /// Bildschirmfoto: «-uiSplashHold» hält das Intro bei 1.7 s an (nur Debug)
    static var holdTime: Double? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiSplashHold") { return 1.7 }
        #endif
        return nil
    }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = SplashView.holdTime ?? ctx.date.timeIntervalSince(SplashView.launch)
            scene(t)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
            if SplashView.holdTime != nil { return }
            let left = max(0, total - Date().timeIntervalSince(SplashView.launch))
            try? await Task.sleep(nanoseconds: UInt64(left * 1_000_000_000))
            onDone()
        }
    }

    // MARK: Bild zu einem Zeitpunkt

    @ViewBuilder private func scene(_ t: Double) -> some View {
        let fadeStart = reduceMotion ? 1.2 : 2.0
        let out = Self.clamp((t - fadeStart) / 0.5)
        ZStack {
            KColor.paper
            VStack(spacing: 14) {
                logo(t)
                    .scaleEffect(reduceMotion ? 1 : 1 + 0.12 * Self.ease(out))
                wordmark(t)
                Text(verbatim: "Deine Verträge, ganz entspannt.")
                    .font(.system(size: 14))
                    .foregroundStyle(KColor.ink2)
                    .modifier(SplashUp(p: reduceMotion ? 1 : Self.ease(Self.clamp((t - 1.0) / 0.5))))
            }
        }
        .opacity(1 - Self.ease(out))
    }

    private func logo(_ t: Double) -> some View {
        let pop = reduceMotion ? 1.0 : Self.clamp(t / 0.7)
        // splPop: 0 % scale .5 / −10°, 60 % scale 1.07 / 2°, 100 % scale 1 / 0° (federnd)
        let (scale, rot, alpha): (Double, Double, Double) = {
            if pop >= 1 { return (1, 0, 1) }
            if pop < 0.6 {
                let q = Self.easeOut(pop / 0.6)
                return (0.5 + 0.57 * q, -10 + 12 * q, q)
            }
            let q = Self.ease((pop - 0.6) / 0.4)
            return (1.07 - 0.07 * q, 2 - 2 * q, 1)
        }()
        // splSpin: Segment von −540° auf 0° in 1.5 s ab 0.3 s, cubic-bezier(.25,.6,.15,1)
        let spin = reduceMotion ? 1.0 : Self.bezier(Self.clamp((t - 0.3) / 1.5), 0.25, 0.6, 0.15, 1)
        return KAppLogo(size: 96, segmentAngle: .degrees(-540 * (1 - spin)))
            .shadow(color: Color.black.opacity(0.28), radius: 17, y: 14)
            .scaleEffect(scale)
            .rotationEffect(.degrees(rot))
            .opacity(alpha)
            .frame(width: 96, height: 96)
    }

    /// «Kontivo» (36 pt): K, O und die Buchstaben erscheinen nacheinander von unten (Abstand 0.06 s, ab 0.39 s für das K);
    /// das Messing-Drittel des O zeichnet sich ab 1.0 s in 0.6 s (wlDraw).
    private func wordmark(_ t: Double) -> some View {
        KWordmark(size: 36, progress: { i in
            reduceMotion ? 1 : Self.easeOutBack(Self.clamp((t - (0.45 + Double(i - 1) * 0.06)) / 0.45))
        }, brass: reduceMotion ? 1 : Self.bezier(Self.clamp((t - 1.0) / 0.6), 0.3, 0.7, 0.3, 1))
    }

    // MARK: Zeitkurven

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    /// ease (CSS «ease», angenähert)
    static func ease(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }
    static func easeOut(_ x: Double) -> Double { let c = clamp(x); return 1 - pow(1 - c, 3) }
    /// CSS cubic-bezier(x1,y1,x2,y2) für Fortschritt x (Newton-Verfahren)
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        let c = clamp(x)
        func bx(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * x1 + 3 * (1 - u) * u * u * x2 + u * u * u }
        func by(_ u: Double) -> Double { 3 * (1 - u) * (1 - u) * u * y1 + 3 * (1 - u) * u * u * y2 + u * u * u }
        var u = c
        for _ in 0..<8 {
            let d = (bx(u + 1e-4) - bx(u - 1e-4)) / 2e-4
            if abs(d) < 1e-6 { break }
            u = min(1, max(0, u - (bx(u) - c) / d))
        }
        return by(u)
    }
    /// Leichtes Überschwingen wie cubic-bezier(.2,1.2,.4,1)
    static func easeOutBack(_ x: Double) -> Double {
        let c = clamp(x), k = 1.2
        return 1 + (k + 1) * pow(c - 1, 3) + k * pow(c - 1, 2)
    }
}

/// splUp: von 10 pt unten einblenden (p = Fortschritt 0…1, darf leicht überschwingen)
private struct SplashUp: ViewModifier {
    let p: Double
    func body(content: Content) -> some View {
        content
            .opacity(SplashView.clamp(p))
            .offset(y: 10 * (1 - p))
    }
}
