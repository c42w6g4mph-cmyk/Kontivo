import SwiftUI
import KontivoCore

/// Intro beim Öffnen der App (wie `#splash` der Web-App, 83141ec/d11e068/5347844):
/// Papierhintergrund, Logo (96 pt) federt mit leichter Drehung ein, zwei Ringe pulsieren nach aussen,
/// «Kontivo» erscheint Buchstabe für Buchstabe, der Slogan nach ~1 s; ab 2.0 s blendet alles aus (Logo zoomt leicht).
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
        if AppModel.isUITestLaunch { return ProcessInfo.processInfo.arguments.contains("-uiSplash") }
        #endif
        return true
    }

    /// Ende der Animation (s) – danach wird das Overlay entfernt
    private var total: Double { reduceMotion ? 1.7 : 2.5 }

    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSince(SplashView.launch)
            scene(t)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task {
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
        return ZStack {
            if !reduceMotion {
                ring(Self.clamp((t - 0.35) / 1.1))
                ring(Self.clamp((t - 0.6) / 1.1))
            }
            Image("Logo")
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color(red: 14 / 255, green: 90 / 255, blue: 94 / 255).opacity(0.3), radius: 17, y: 14)
                .scaleEffect(scale)
                .rotationEffect(.degrees(rot))
                .opacity(alpha)
        }
        .frame(width: 96, height: 96)
    }

    /// Pulsierender Ring (splRing: Deckkraft .55 → 0, Grösse .9 → 1.9, ease-out)
    @ViewBuilder private func ring(_ p: Double) -> some View {
        if p > 0 && p < 1 {
            let q = Self.easeOut(p)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(KColor.teal, lineWidth: 2)
                .frame(width: 96, height: 96)
                .scaleEffect(0.9 + 1.0 * q)
                .opacity(0.55 * (1 - q))
        }
    }

    /// «Kontivo»: K aus dem Logo + Buchstaben, die nacheinander von unten erscheinen (Abstand 0.06 s)
    private func wordmark(_ t: Double) -> some View {
        let size: CGFloat = 36
        let letters = Array("ontivo")
        func p(_ i: Int) -> Double {
            reduceMotion ? 1 : Self.easeOutBack(Self.clamp((t - (0.45 + Double(i) * 0.06)) / 0.45))
        }
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            OnbKGlyph()
                .frame(width: size * 0.72 * 357.5 / 440, height: size * 0.72)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
                .padding(.trailing, -size * 0.055)
                .modifier(SplashUp(p: p(-1)))
            ForEach(letters.indices, id: \.self) { i in
                Text(verbatim: String(letters[i]))
                    .font(.system(size: size, weight: .bold))
                    .modifier(SplashUp(p: p(i)))
            }
        }
        .tracking(-size * 0.01)
        .foregroundStyle(KColor.ink)
    }

    // MARK: Zeitkurven

    static func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
    /// ease (CSS «ease», angenähert)
    static func ease(_ x: Double) -> Double { let c = clamp(x); return c * c * (3 - 2 * c) }
    static func easeOut(_ x: Double) -> Double { let c = clamp(x); return 1 - pow(1 - c, 3) }
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
