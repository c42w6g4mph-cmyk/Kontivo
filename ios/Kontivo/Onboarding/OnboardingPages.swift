import SwiftUI
import UIKit
import KontivoCore

// MARK: - Daten der Einführung (OB_PAGES, OB_TABS, OB_QUICK der Web-App v224)

/// Seiten der Einführung (Web v199/v200: Willkommen, Automatisch erfassen, 4 Tabs, Einrichten, Start – keine Tipps-Seite mehr)
enum OnbPage: Hashable {
    case welcome
    case auto
    case tab(OnbTab)
    case setup
    case start

    /// Erststart: 8 Seiten
    static let firstRun: [OnbPage] = [.welcome, .auto, .tab(.list), .tab(.stat), .tab(.budget), .tab(.term), .setup, .start]
    /// Tour aus «Mehr»: 6 Seiten (ohne Einrichten und Start)
    static let tour: [OnbPage] = [.welcome, .auto, .tab(.list), .tab(.stat), .tab(.budget), .tab(.term)]

    /// Nur beim Erststart (Web `first:true`)
    var firstOnly: Bool { self == .setup || self == .start }
}

/// Tabs (auch für die nachgebildete Tab-Leiste auf den Bildschirmfotos)
enum OnbTab: String, CaseIterable, Hashable {
    case list, stat, budget, term, more

    var name: String {
        switch self {
        case .list: return "Verträge"
        case .stat: return "Kosten"
        case .budget: return "Budget"
        case .term: return "Fristen"
        case .more: return "Mehr"
        }
    }

    /// Symbol wie OB_ICON der Web-App
    var glyph: OnbGlyph {
        switch self {
        case .list: return .list
        case .stat: return .stat
        case .budget: return .budget
        case .term: return .term
        case .more: return .more
        }
    }

    /// Titel = Nutzen als kurze Aussage (Web v199, Linie 15.10.2026)
    var title: String {
        switch self {
        case .list: return "Endlich alles im Blick"
        case .stat: return "Nie mehr überrascht"
        case .budget: return "Wissen, was dir bleibt"
        case .term: return "Nie mehr zu spät kündigen"
        case .more: return ""
        }
    }

    /// Je drei Punkte im gleichen Stil (Web v198/v199)
    var bullets: [String] {
        switch self {
        case .list: return ["Was du monatlich zahlst, auf einen Blick", "CHF und EUR automatisch umgerechnet", "Geordnet nach Kategorie oder Person"]
        case .stat: return ["Du weisst, wann was abgebucht wird", "Bezahlt und offen auf einen Blick", "Du siehst, was teurer geworden ist"]
        case .budget: return ["Einnahmen und Fixkosten verrechnet", "Pro Monat und aufs Jahr gerechnet", "Vergleich mit Richtwerten für CH und DE"]
        case .term: return ["Deine Fristen automatisch berechnet", "Behalten oder kündigen – du entscheidest", "Kündigungsschreiben mit einem Tipp"]
        case .more: return []
        }
    }

    /// Bildschirmfoto im Asset-Katalog (hell/dunkel automatisch, Web onb/<tab>-light|dark.webp v198)
    var asset: String { "onb-" + rawValue }
}

/// Schnellstart-Vorlage: Bezeichnung → Kategorie
struct OnbQuick: Identifiable {
    let id: Int
    let label: String
    let category: KCategory?

    /// Web OB_QUICK v224 (6 Vorlagen)
    static let templates: [(label: String, category: String)] = [
        ("Miete", "Wohnen"), ("Strom", "Energie & Wasser"), ("Handy", "Mobilfunk & Internet"), ("Internet", "Mobilfunk & Internet"),
        ("Streaming", "Abos & Medien"), ("Versicherung", "Versicherung"),
    ]

    /// Kategorie zur Vorlage: gleicher Name, sonst gleiche Standardkategorie (umbenannt), sonst «Sonstiges» (`obCat`).
    static func category(named n: String, in d: AppData) -> KCategory? {
        if let c = d.category(named: n) { return c }
        if let k = KCategory.standardKinds[n], let c = d.categories.first(where: { $0.kind == k }) { return c }
        return d.otherCategory
    }

    static func items(_ d: AppData) -> [OnbQuick] {
        templates.enumerated().map { i, t in OnbQuick(id: i, label: t.label, category: category(named: t.category, in: d)) }
    }
}

/// Masse, die im Web von der Bildschirmgrösse abhängen (`vw`, `vh`, `@media (max-height: …)`)
struct OnbMetrics {
    /// Bildschirmbreite und -höhe inkl. Sicherheitsabstände (CSS-Viewport der Homescreen-App)
    var width: CGFloat = 402
    var height: CGFloat = 874

    var vw: CGFloat { width / 100 }
    var vh: CGFloat { height / 100 }
    /// `@media (max-height: 740px)`
    var short: Bool { height <= 740 }
    /// `@media (max-height: 700px)`
    var veryShort: Bool { height <= 700 }
    /// `#onb .obscr` gap
    var gap: CGFloat { short ? 8 : 10 }
    /// `#onb .obt`: clamp(24px, 7vw, 30px)
    var titleSize: CGFloat { OnbCSS.clamp(24, 7 * vw, 30) }
    /// `#onb .obs`: 15 px, bei max-height 700 14 px
    var textSize: CGFloat { veryShort ? 14 : 15 }
}

private struct OnbMetricsKey: EnvironmentKey {
    static let defaultValue = OnbMetrics()
}

extension EnvironmentValues {
    var onbMetrics: OnbMetrics {
        get { self[OnbMetricsKey.self] }
        set { self[OnbMetricsKey.self] = newValue }
    }
}

// MARK: - Gemeinsame Bausteine

/// Hintergrund: Papier (Web v224: `--glow` transparent, kein Schein mehr)
struct OnbBackground: View {
    var body: some View { KColor.paper }
}

/// Fortschritt (`.obprog`): ein Strich pro Seite (3 px, Radius 2), aktiv bis zur aktuellen Seite
struct OnbProgress: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { j in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(j <= index ? KColor.teal : OnbColor.inkSoft)
                    .frame(height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(index + 1) von \(count)")
    }
}

/// Kopfzeile (`.obtop`, min. 24 px): links Chip, rechts «Überspringen» (15 px, Abstand 4/0/4/12)
struct OnbTopBar<Chip: View>: View {
    var showSkip: Bool = false
    var onSkip: () -> Void = {}
    @ViewBuilder var chip: Chip

    var body: some View {
        HStack(spacing: 0) {
            chip
            Spacer(minLength: 8)
            if showSkip {
                Button(action: onSkip) {
                    Text(verbatim: "Überspringen")
                        .font(.system(size: 15))
                        .foregroundStyle(KColor.ink2)
                        .onbLine(15, 21.75)
                        .padding(.vertical, 4)
                        .padding(.leading, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(minHeight: 24)
    }
}

/// Chip oben links (`.obtab`, Design-Schicht v164: 13 px, 600, ohne Versalien; Symbol 15 px, Strich 2)
struct OnbChip: View {
    var glyph: OnbGlyph? = nil
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            if let g = glyph {
                OnbIcon(glyph: g, size: 15, stroke: 2)
            }
            Text(verbatim: text)
                .font(.system(size: 13, weight: .semibold))
                .onbLine(13, 18.85, .semibold)
        }
        .foregroundStyle(KColor.teal)
        .accessibilityElement(children: .combine)
    }
}

/// Titel (`#onb .obt`): SF Pro 600, clamp(24, 7vw, 30) px, Zeilenhöhe 1.1, Laufweite −0.012em
struct OnbTitle: View {
    let text: String
    @Environment(\.onbMetrics) private var m
    init(_ text: String) { self.text = text }

    var body: some View {
        let s = m.titleSize
        Text(verbatim: text)
            .font(.system(size: s, weight: .semibold))
            .tracking(-0.012 * s)
            .foregroundStyle(KColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .onbLine(s, s * 1.1, .semibold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Untertitel (`#onb .obs`): 15 px, Zeilenhöhe 1.45, ink2
struct OnbSubtitle: View {
    let text: String
    @Environment(\.onbMetrics) private var m
    init(_ text: String) { self.text = text }

    var body: some View {
        let s = m.textSize
        Text(verbatim: text)
            .font(.system(size: s))
            .foregroundStyle(KColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .onbLine(s, s * 1.45)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hauptknopf (`#onb .obbtn`): 17 px 600 weiss auf tealFill, Abstand 15, Radius 15, 6 px über dem Knopf
struct OnbPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .onbLine(17, 24.65, .semibold)
                .frame(maxWidth: .infinity)
                .padding(15)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(KColor.tealFill))
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .padding(.top, 6)
    }
}

/// Zweitknopf (`#onb .obghost`): 32 px hoch, 15 px 500 Teal, Abstand 8 oben / 2 unten
struct OnbGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(KColor.teal)
                .lineLimit(1)
                .frame(height: 22)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Platzhalter in Höhe des Zweitknopfs (Web `OB_PH`), damit «Weiter» auf allen Seiten gleich hoch steht
struct OnbGhostPlaceholder: View {
    var body: some View {
        Color.clear.frame(height: 32).accessibilityHidden(true)
    }
}

/// Weisse Karte mit kleinem Titel (`#onb .obcard`, Einrichten): Radius 16, Abstand 12/13, Lücke 9
struct OnbCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KColor.ink3)
                .onbLine(13, 18.85, .semibold)
            content
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface))
    }
}

/// Hinweis unter einem Feld (`#onb .obhint`): 12.5 px ink3, seitlich 2 px
struct OnbHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 12.5))
            .foregroundStyle(KColor.ink3)
            .fixedSize(horizontal: false, vertical: true)
            .onbLine(12.5, 18.125)
            .padding(.horizontal, 2)
    }
}

// MARK: - Wortmarke

/// Das «K» aus dem Logo (nachgezeichnet aus dem SVG der Web-App): Balken mit ausgesparter Spitze plus Winkel.
/// Wird auch vom Intro (SplashView, Bereich design) genutzt.
struct OnbKGlyph: View {
    var body: some View {
        Canvas { ctx, size in
            let vb = CGRect(x: 339.5, y: 292, width: 357.5, height: 440)
            let s = min(size.width / vb.width, size.height / vb.height)
            ctx.translateBy(x: (size.width - vb.width * s) / 2, y: (size.height - vb.height * s) / 2)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -vb.minX, y: -vb.minY)

            var bar = Path()
            bar.move(to: CGPoint(x: 339.78, y: 292))
            bar.addLine(to: CGPoint(x: 393.78, y: 292))
            bar.addLine(to: CGPoint(x: 439.78, y: 349.5))
            bar.addLine(to: CGPoint(x: 439.78, y: 732))
            bar.addLine(to: CGPoint(x: 339.78, y: 732))
            bar.closeSubpath()

            var chevron = Path()
            chevron.move(to: CGPoint(x: 693, y: 792))
            chevron.addLine(to: CGPoint(x: 469, y: 512))
            chevron.addLine(to: CGPoint(x: 693, y: 232))

            ctx.drawLayer { layer in
                layer.fill(bar, with: .foreground)
                layer.blendMode = .destinationOut
                layer.stroke(chevron, with: .color(.black), style: StrokeStyle(lineWidth: 144, miterLimit: 4))
            }
            var clipped = ctx
            clipped.clip(to: Path(CGRect(x: 300, y: 292, width: 500, height: 440)))
            clipped.stroke(chevron, with: .foreground, style: StrokeStyle(lineWidth: 80, miterLimit: 4))
        }
        .accessibilityHidden(true)
    }
}

/// «Kontivo» als Wortmarke (Platzhalter des Bereichs onb: K aus dem Logo + «ontivo» in SF Pro Bold).
/// TODO design-API: durch die Wortmarke des Bereichs design ersetzen (Web v171: Inter Display Bold, O als Zeitring mit Messing-Segment).
struct OnbWordmark: View {
    var size: CGFloat = 36

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: -size * 0.055) {
            OnbKGlyph()
                .frame(width: size * 0.72 * 357.5 / 440, height: size * 0.72)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] }
            Text(verbatim: "ontivo")
                .font(.system(size: size, weight: .bold))
                .tracking(-size * 0.01)
        }
        .foregroundStyle(KColor.ink)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Kontivo")
    }
}

// MARK: - Seite 1: Willkommen (`.obwel`)

struct OnbWelcomePage: View {
    let first: Bool
    let onNext: () -> Void
    let onSecondary: () -> Void
    @Environment(\.onbMetrics) private var m

    static let promises = ["Alle Fixkosten auf einen Blick", "Nie mehr zu viel bezahlen", "Ganz privat, ohne Bankanbindung"]

    var body: some View {
        let vh = m.vh
        let logo: CGFloat = m.veryShort ? 68 : 84
        VStack(spacing: 0) {
            // Logo 84 px, Radius 19, Schatten 0 12 30 rgba(0,0,0,.28)
            Image("Logo")
                .resizable()
                .scaledToFill()
                .frame(width: logo, height: logo)
                .clipShape(RoundedRectangle(cornerRadius: m.veryShort ? 16 : 19, style: .continuous))
                .shadow(color: Color.black.opacity(0.28), radius: 15, y: 12)
                .accessibilityHidden(true)
            // gap 9 + margin 8
            Text(verbatim: "Deine Verträge, ganz entspannt.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(KColor.teal)
                .multilineTextAlignment(.center)
                .onbLine(17, 24.65, .semibold, .rounded)
                .padding(.top, 17)
            // gap 9 + margin max(22, 4.5vh); Spalte mit Lücke 4
            VStack(spacing: 4) {
                let span = OnbCSS.clamp(17, 5 * m.vw, 20)
                Text(verbatim: "Willkommen bei")
                    .font(.system(size: span, weight: .semibold))
                    .foregroundStyle(KColor.ink2)
                    .onbLine(span, span * 1.1, .semibold)
                let wm = OnbCSS.clamp(30, 9 * m.vw, 36)
                OnbWordmark(size: wm)
                    .frame(height: wm * 1.1)
            }
            .padding(.top, 9 + max(22, 4.5 * vh))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(verbatim: "Du weisst jederzeit, was jeden Monat\nfix weggeht – und was dir bleibt.")
                .font(.system(size: m.textSize))
                .foregroundStyle(KColor.ink2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .onbLine(m.textSize, m.textSize * 1.45)
                .padding(.top, 9 + max(14, 3.5 * vh))
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.promises, id: \.self) { line in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(KColor.brassFab)
                            .frame(width: 19, height: 19)
                            .overlay(OnbIcon(glyph: .check, size: 11, stroke: 3).foregroundStyle(KColor.onBrass))
                        Text(verbatim: line)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(KColor.teal)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .onbLine(15, 20.25, .semibold)
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .frame(maxWidth: .infinity)
            .padding(.top, 9 + max(12, 2.5 * vh))
            .accessibilityElement(children: .combine)
            Spacer(minLength: 9)
            OnbPrimaryButton(title: "Los geht’s", action: onNext)
            OnbGhostButton(title: first ? "Ich habe schon ein Backup" : "Schliessen", action: onSecondary)
                .padding(.top, m.short ? 9 : 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, m.veryShort ? 0 : 4 * vh)
    }
}

// MARK: - Seite 2: Automatisch erfassen (Web v197–v200)

struct OnbAutoPage: View {
    let showSkip: Bool
    let onSkip: () -> Void
    let onNext: () -> Void
    @Environment(\.onbMetrics) private var m

    /// Quellen (Web SRC): PDF und Foto gibt es nativ schon – daher ohne «bald» (Web-Kommentar: «PDF/Foto erst nativ, im Web bald»)
    static let sources: [(glyph: OnbGlyph, title: String, text: String)] = [
        (.bank, "Kontoauszug laden", "CSV-Datei aus dem E-Banking"),
        (.pdf, "PDF hochladen", "Kontoauszug, Rechnung oder Vertrag"),
        (.photo, "Foto machen", "Kontoauszug, Rechnung oder Brief"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: m.gap) {
            OnbTopBar(showSkip: showSkip, onSkip: onSkip) {
                OnbChip(glyph: .sparkle, text: "Automatisch erfassen")
            }
            title
            OnbSubtitle("Kontivo erkennt deine Verträge – du bestätigst nur noch.")
            sourceList
            Spacer(minLength: 0)
            safeNote
            OnbPrimaryButton(title: "Weiter", action: onNext)
            OnbGhostPlaceholder()
        }
        .padding(.top, 14)
    }

    /// «Alle Verträge von Hand erfassen?» (ausgeglichen umbrochen wie `text-wrap: balance`) + «Nicht mit Kontivo.» in Messing
    private var title: some View {
        let s = m.titleSize
        let lh = s * 1.1
        let lines: [(String, Bool)] = [("Alle Verträge von", false), ("Hand erfassen?", false), ("Nicht mit Kontivo.", true)]
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                Text(verbatim: l.0)
                    .font(.system(size: s, weight: .semibold))
                    .tracking(-0.012 * s)
                    .foregroundStyle(l.1 ? KColor.teal : KColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: lh)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Alle Verträge von Hand erfassen? Nicht mit Kontivo.")
        .accessibilityAddTraits(.isHeader)
    }

    /// `.obsrl`: Karte (Radius 18, Abstand 2/14, Schatten 0 4 16 rgba(0,0,0,.05)), Zeilen mit Trennlinie
    private var sourceList: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.sources.enumerated()), id: \.offset) { i, src in
                HStack(spacing: 12) {
                    let tile: CGFloat = m.short ? 32 : 38
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(KColor.tealFill)
                        .frame(width: tile, height: tile)
                        .overlay(OnbIcon(glyph: src.glyph, size: 21, stroke: 1.8).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: src.title)
                            .font(.system(size: 15.5, weight: .semibold))
                            .foregroundStyle(KColor.ink)
                            .onbLine(15.5, 22.475, .semibold)
                        Text(verbatim: src.text)
                            .font(.system(size: 13))
                            .foregroundStyle(KColor.ink2)
                            .onbLine(13, 16.9)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, m.short ? 6 : 10)
                .overlay(alignment: .top) {
                    if i > 0 { Rectangle().fill(KColor.line).frame(height: 1) }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KColor.surface)
            .shadow(color: Color.black.opacity(0.05), radius: 8, y: 4))
    }

    /// `.obsafe`: «Bleibt auf deinem Gerät.» (grün) + Text, Schloss 22 px
    private var safeNote: some View {
        HStack(spacing: 11) {
            OnbIcon(glyph: .lock, size: 22, stroke: 2).foregroundStyle(KColor.ok)
            (Text(verbatim: "Bleibt auf deinem Gerät.").fontWeight(.semibold).foregroundColor(KColor.ok)
                + Text(verbatim: " Kontoauszug und Fotos werden nur hier gelesen – nie hochgeladen, nie gespeichert.").foregroundColor(KColor.ink2))
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
                .onbLine(13, 18.2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(OnbColor.safeFill))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Seiten 3–6: Tabs

struct OnbTabPage: View {
    let tab: OnbTab
    let showSkip: Bool
    let onSkip: () -> Void
    let onNext: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.onbMetrics) private var m

    /// Grosse Schrift: Text scrollbar, Bildschirmfoto ausgeblendet, damit «Weiter» sichtbar bleibt
    private var compact: Bool { typeSize >= .xxxLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: m.gap) {
            OnbTopBar(showSkip: showSkip, onSkip: onSkip) {
                OnbChip(glyph: tab.glyph, text: tab.name)
            }
            if compact {
                ScrollView {
                    texts.frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                texts
                OnbShot(tab: tab)
                    .padding(.top, 4)
            }
            OnbPrimaryButton(title: "Weiter", action: onNext)
            OnbGhostPlaceholder()
        }
        .padding(.top, 14)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: m.gap) {
            OnbTitle(tab.title)
            // `.obpts`: Lücke 5, Haken 16 px (Strich 2.6, Teal), Text 15 px, Zeilenhöhe 1.3
            VStack(alignment: .leading, spacing: 5) {
                ForEach(tab.bullets, id: \.self) { b in
                    HStack(spacing: 9) {
                        OnbIcon(glyph: .check, size: 16, stroke: 2.6).foregroundStyle(KColor.teal)
                        Text(verbatim: b)
                            .font(.system(size: 15))
                            .foregroundStyle(KColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                            .onbLine(15, 19.5)
                    }
                }
            }
        }
    }
}

/// Bildschirmfoto (`.obshot`): Radius 22, oben bündig zugeschnitten, Verlauf unten, nachgebildete Tab-Leiste
struct OnbShot: View {
    let tab: OnbTab

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .overlay(alignment: .top) {
                    Image(tab.asset)
                        .resizable()
                        .scaledToFill()
                }
                .clipped()
            // `.obfade`: 96 px, transparent → Papier bei 78 %
            LinearGradient(stops: [.init(color: KColor.paper.opacity(0), location: 0), .init(color: KColor.paper, location: 0.78)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 96)
            OnbTabBar(active: tab)
                .padding(10)
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
        .background(KColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        // box-shadow: 0 10px 28px rgba(0,0,0,.13), 0 0 0 1px var(--line) (Ring ausserhalb)
        .background(RoundedRectangle(cornerRadius: 23, style: .continuous).fill(KColor.line).padding(-1))
        .shadow(color: Color.black.opacity(0.13), radius: 14, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bildschirmfoto: \(tab.name)")
        .accessibilityAddTraits(.isImage)
    }
}

/// `.obbar`: Glas (Unschärfe), Rand glassEdge, Schatten; aktiver Tab Teal auf 13 % Teal
struct OnbTabBar: View {
    let active: OnbTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OnbTab.allCases, id: \.self) { t in
                let on = t == active
                VStack(spacing: 1) {
                    OnbIcon(glyph: t.glyph, size: 21, stroke: 1.7)
                    Text(verbatim: t.name)
                        .font(.system(size: 10, weight: on ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(height: 14.5)
                }
                .foregroundStyle(on ? KColor.teal : KColor.ink2)
                .frame(maxWidth: .infinity)
                .padding(.top, 5)
                .padding(.bottom, 4)
                .background(Capsule().fill(on ? OnbColor.tealSoft : Color.clear))
            }
        }
        .padding(4)
        .background(Capsule().fill(KColor.glass))
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(KColor.glassEdge, lineWidth: 1))
        .shadow(color: KColor.glassShade, radius: 12, y: 8)
    }
}

// MARK: - Seite 7: Einrichten

struct OnbSetupPage: View {
    @Binding var home: Currency
    @Binding var moreOpen: Bool
    @Binding var name: String
    let onNext: () -> Void
    let onBackup: () -> Void
    @FocusState private var nameFocused: Bool
    @Environment(\.onbMetrics) private var m

    var body: some View {
        VStack(alignment: .leading, spacing: m.gap) {
            OnbTopBar(showSkip: false, onSkip: {}) {
                OnbChip(text: "Fast geschafft")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: m.gap) {
                    OnbTitle("Noch zwei Angaben")
                    OnbSubtitle("Beides kannst du später jederzeit unter «Mehr» ändern.")
                    OnbCard(title: "Hauptwährung") {
                        MoreCurrencyPicker(selection: home, expanded: $moreOpen) { c in home = c }
                        OnbHint("Andere Währungen rechnet Kontivo automatisch um.")
                    }
                    OnbCard(title: "Wie heisst du?") {
                        nameField
                        OnbHint("So ordnest du Verträge dir oder anderen im Haushalt zu.")
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            OnbPrimaryButton(title: "Weiter") {
                nameFocused = false
                onNext()
            }
            OnbGhostButton(title: "Backup einspielen") {
                nameFocused = false
                onBackup()
            }
        }
        .padding(.top, 14)
    }

    /// `.obinp`: Feld (Radius 11, Abstand 12/13, 16 px), Fokus mit 2 px Teal
    private var nameField: some View {
        TextField("Name", text: $name)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit { nameFocused = false }
            .font(.system(size: 16))
            .onbLine(16, 23.2)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.field))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(nameFocused ? KColor.teal : Color.clear, lineWidth: 2))
            .accessibilityLabel("Wie heisst du?")
    }
}

// MARK: - Seite 8: Womit fangen wir an?

/// Letzter Schritt (Web v199): Karte «Automatisch erfassen» (Kontoauszug), «oder», «Selbst erfassen» mit Vorlagen.
struct OnbStartPage: View {
    let items: [OnbQuick]
    @Binding var quick: Int?
    let onBank: (BankPickSource) -> Void
    let onCreate: () -> Void
    let onDone: () -> Void
    @State private var askSource = false
    @Environment(\.onbMetrics) private var m

    private var createTitle: String {
        if let q = quick, let item = items.first(where: { $0.id == q }) { return item.label + " erfassen" }
        return "Vertrag erfassen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.gap) {
            OnbTopBar(showSkip: false, onSkip: {}) {
                OnbChip(text: "Letzter Schritt")
            }
            OnbTitle("Womit fangen wir an?")
            OnbSubtitle("Am schnellsten geht es mit deinem Kontoauszug.")
            OnbAutoCard { askSource = true }
                .confirmationDialog("Kontoauszug", isPresented: $askSource, titleVisibility: .hidden) {
                    ForEach(BankPickSource.available, id: \.self) { s in
                        Button(s.dialogTitle) { onBank(s) }
                    }
                    Button("Abbrechen", role: .cancel) {}
                }
            OnbOr()
                .padding(.top, 4)
            // `.obsec`: 12 px 700 ink2, Abstand 8 oben / −6 unten
            Text(verbatim: "Selbst erfassen – tipp an, was du hast")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(KColor.ink2)
                .onbLine(12, 17.4, .bold)
                .padding(.top, 8)
                .padding(.bottom, -6)
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(items) { q in
                        OnbQuickChip(item: q, isOn: quick == q.id) { quick = q.id }
                    }
                }
                .padding(2)
            }
            .scrollBounceBehavior(.basedOnSize)
            OnbPrimaryButton(title: createTitle, enabled: quick != nil, action: onCreate)
            OnbGhostButton(title: "Erst mal umschauen", action: onDone)
        }
        .padding(.top, 14)
    }
}

/// «oder» mit Linien links und rechts (`.obor`: 13 px 600 ink3, Lücke 12)
struct OnbOr: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(KColor.line).frame(height: 1)
            Text(verbatim: "oder")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(KColor.ink3)
                .onbLine(13, 18.85, .semibold)
                .fixedSize()
            Rectangle().fill(KColor.line).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Karte «Automatisch erfassen» (`.obauto`): Bank-Symbol auf tealFill, Rahmen 1.5 px Teal, Fläche 9 % Teal
struct OnbAutoCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(KColor.tealFill)
                    .frame(width: 44, height: 44)
                    .overlay(OnbIcon(glyph: .bank, size: 23, stroke: 1.8).foregroundStyle(.white))
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Automatisch erfassen")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(KColor.ink)
                        .onbLine(17, 24.65, .bold, .rounded)
                    Text(verbatim: "Kontoauszug wählen, Verträge bestätigen")
                        .font(.system(size: 13.5))
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .onbLine(13.5, 18.225)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(OnbColor.autoFill))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(KColor.teal, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onbAutoFind")
    }
}

/// Vorlage (`.obchips.row .obchip`): Kachel 27 px links, Name (Rounded 14.5 px 600) und Kategorie (11.5 px ink3)
struct OnbQuickChip: View {
    let item: OnbQuick
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                mark
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.label)
                        .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .onbLine(14.5, 17.4, .semibold, .rounded)
                    Text(verbatim: item.category?.name ?? "")
                        .font(.system(size: 11.5))
                        .foregroundStyle(KColor.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .onbLine(11.5, 14.375)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(isOn ? KColor.teal : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder private var mark: some View {
        if let c = item.category {
            MarkView(category: c, size: 27)
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: KCategory.fallbackColor))
                .frame(width: 27, height: 27)
                .overlay(Image(systemName: "tag").font(.system(size: 12, weight: .medium)).foregroundStyle(.white))
                .accessibilityHidden(true)
        }
    }
}
