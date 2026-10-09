import SwiftUI
import UIKit
import KontivoCore

// MARK: - Daten der Einführung (OB_PAGES, OB_TIPS, OB_QUICK der Web-App)

/// Seiten der Einführung
enum OnbPage: Hashable {
    case welcome
    case tab(OnbTab)
    case tips
    case setup
    case start

    /// Erststart: 8 Seiten
    static let firstRun: [OnbPage] = [.welcome, .tab(.list), .tab(.stat), .tab(.budget), .tab(.term), .tips, .setup, .start]
    /// Tour aus «Mehr»: 6 Seiten (ohne Einrichten und Start)
    static let tour: [OnbPage] = [.welcome, .tab(.list), .tab(.stat), .tab(.budget), .tab(.term), .tips]
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

    /// Gleiche Symbole wie die Tab-Leiste der App
    var symbol: String {
        switch self {
        case .list: return "doc.text"
        case .stat: return "chart.bar"
        case .budget: return "wallet.pass"
        case .term: return "stopwatch"
        case .more: return "ellipsis"
        }
    }

    var title: String {
        switch self {
        case .list: return "Alle Verträge im Blick"
        case .stat: return "Jeden Monat im Voraus geplant"
        case .budget: return "Weisst du, was dir bleibt?"
        case .term: return "Keine ungewollten Vertragsverlängerungen"
        case .more: return ""
        }
    }

    var bullets: [String] {
        switch self {
        case .list: return ["Alle Vertragsdetails auf einen Blick", "Per Kontoauszug in Minuten erfasst", "Monatliche Fixkosten sofort sichtbar"]
        case .stat: return ["Alle Abbuchungen übersichtlich geplant", "Bezahlt oder offen sofort erkennen", "Keine Überraschungen im Briefkasten"]
        case .budget: return ["Einnahmen minus Fixkosten klar berechnet", "Monatlich und jährlich auf einen Blick"]
        case .term: return ["Kündigungsfristen automatisch berechnet", "Rechtzeitig vor Fristablauf informiert", "Kündigen mit einem Tipp – Schreiben fertig"]
        case .more: return []
        }
    }

    /// Bildschirmfoto im Asset-Katalog (hell/dunkel automatisch)
    var asset: String { "onb-" + rawValue }
}

/// Punkt der Seite «Gut zu wissen»
struct OnbTip: Identifiable {
    let id: Int
    let colorHex: String
    let symbol: String
    let title: String
    let text: String
    var soon: Bool = false

    /// Wie Web OB_TIPS (v124). Nativ gibt es den Import als PDF oder Foto schon – dort kein «Bald».
    static let all: [OnbTip] = [
        OnbTip(id: 0, colorHex: "#475569", symbol: "building.columns", title: "Kontoauszug einlesen", text: "Fixkosten aus der CSV-Datei der Bank finden."),
        OnbTip(id: 1, colorHex: "#B0562A", symbol: "chart.line.uptrend.xyaxis", title: "Preisverlauf", text: "Sieh, wie sich Vertragspreise verändern."),
        OnbTip(id: 2, colorHex: "#A93227", symbol: "gift", title: "Probeabos im Blick", text: "Erinnerung, bevor Kosten entstehen."),
        OnbTip(id: 3, colorHex: "#2E6A4E", symbol: "person.2", title: "Für den ganzen Haushalt", text: "Verträge nach Personen getrennt."),
        OnbTip(id: 4, colorHex: "#6B4E9E", symbol: "paperclip", title: "Dokumente am Vertrag", text: "PDFs direkt beim Vertrag ablegen."),
        OnbTip(id: 5, colorHex: "#8A6A1F", symbol: "tag", title: "Verträge kategorisieren", text: "Kosten nach Bereichen ordnen."),
        OnbTip(id: 6, colorHex: "#1F4E8C", symbol: "doc.text", title: "Kündigung leicht gemacht", text: "PDF erstellen, drucken oder per E-Mail versenden."),
        OnbTip(id: 7, colorHex: "#B23A6F", symbol: "camera", title: "Kontoauszug als PDF oder Foto", text: "Einfach fotografieren oder PDF wählen."),
        OnbTip(id: 8, colorHex: "#2F86A6", symbol: "checkmark.icloud", title: "iCloud-Synchronisierung", text: "Deine Daten auf deinen Geräten aktuell.", soon: true),
    ]
}

/// Schnellstart-Vorlage: Bezeichnung → Kategorie
struct OnbQuick: Identifiable {
    let id: Int
    let label: String
    let category: KCategory?

    static let templates: [(label: String, category: String)] = [
        ("Miete", "Wohnen"), ("Strom", "Energie & Wasser"), ("Handy", "Mobilfunk & Internet"), ("Internet", "Mobilfunk & Internet"),
        ("Streaming", "Abos & Medien"), ("Fitness", "Freizeit & Sport"), ("Kfz-Versicherung", "Versicherung"), ("Rundfunkbeitrag", "Steuern & Gebühren"),
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

// MARK: - Gemeinsame Bausteine

/// Hintergrund: Papier mit sanftem Schein oben (wie die Web-App)
struct OnbBackground: View {
    static let glow = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 95 / 255, green: 179 / 255, blue: 181 / 255, alpha: 0.15)
            : UIColor(red: 120 / 255, green: 185 / 255, blue: 178 / 255, alpha: 0.30)
    })

    var body: some View {
        ZStack(alignment: .top) {
            KColor.paper
            RadialGradient(colors: [OnbBackground.glow, OnbBackground.glow.opacity(0)], center: .top, startRadius: 0, endRadius: 380)
                .frame(height: 420)
        }
    }
}

/// Fortschritt: ein Strich pro Seite, aktiv bis zur aktuellen Seite
struct OnbProgress: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { j in
                Capsule()
                    .fill(j <= index ? KColor.teal : KColor.ink.opacity(0.13))
                    .frame(height: 3)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: index)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Seite \(index + 1) von \(count)")
    }
}

/// Kopfzeile: links Chip, rechts «Überspringen»
struct OnbTopBar<Chip: View>: View {
    var showSkip: Bool = false
    var onSkip: () -> Void = {}
    @ViewBuilder var chip: Chip

    var body: some View {
        HStack {
            chip
            Spacer(minLength: 8)
            if showSkip {
                Button("Überspringen", action: onSkip)
                    .font(.subheadline)
                    .foregroundStyle(KColor.ink2)
                    .buttonStyle(.plain)
                    .padding(.vertical, 4)
                    .padding(.leading, 12)
            }
        }
        .frame(minHeight: 24)
    }
}

/// Chip oben links (Tab-Symbol + Name in Grossbuchstaben, Teal)
struct OnbChip: View {
    var symbol: String? = nil
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            if let s = symbol {
                Image(systemName: s)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(verbatim: text)
                .font(.caption.weight(.bold))
                .tracking(0.8)
                .textCase(.uppercase)
        }
        .foregroundStyle(KColor.teal)
        .accessibilityElement(children: .combine)
    }
}

struct OnbTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(.system(.title, design: .rounded).weight(.bold))
            .foregroundStyle(KColor.ink)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct OnbSubtitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(verbatim: text)
            .font(.subheadline)
            .foregroundStyle(KColor.ink2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Hauptknopf (Teal, volle Breite)
struct OnbPrimaryButton: View {
    let title: String
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(KColor.teal))
                .contentShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .padding(.top, 6)
    }
}

/// Zweitknopf (Text in Teal)
struct OnbGhostButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(KColor.teal)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Weisse Karte mit kleinem Titel (Einrichten)
struct OnbCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(verbatim: title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(KColor.ink3)
            content
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(KColor.surface))
    }
}

// MARK: - Wortmarke

/// Das «K» aus dem Logo (nachgezeichnet aus dem SVG der Web-App): Balken mit ausgesparter Spitze plus Winkel.
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

/// «Kontivo» als Wortmarke: K aus dem Logo + «ontivo»
struct OnbWordmark: View {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 34

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

// MARK: - Seite 1: Willkommen

struct OnbWelcomePage: View {
    let first: Bool
    let onNext: () -> Void
    let onSecondary: () -> Void

    private static let promises = ["Fixkosten, Budget & Fristen im Blick", "Kontoauszug rein – Fixkosten erkannt",
                                   "Ohne Bankanbindung – ganz privat", "Für dich, deine Familie oder deine WG"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Image("Logo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                        .shadow(color: Color(red: 14 / 255, green: 90 / 255, blue: 94 / 255).opacity(0.3), radius: 15, y: 12)
                        .accessibilityHidden(true)
                    Text("Deine Verträge, ganz entspannt.")
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(KColor.teal)
                        .multilineTextAlignment(.center)
                        .padding(.top, 17)
                    VStack(spacing: 4) {
                        Text("Willkommen bei")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(KColor.ink2)
                        OnbWordmark()
                    }
                    .padding(.top, 26)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    Text("Maximale Transparenz über alles,\nwas jeden Monat fix weggeht.")
                        .font(.subheadline)
                        .foregroundStyle(KColor.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                    promiseText
                        .font(.subheadline.weight(.semibold))
                        .lineSpacing(10)
                        .multilineTextAlignment(.leading)
                        .lineLimit(4)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 18)
                        .accessibilityLabel(Self.promises.joined(separator: ", "))
                }
                .padding(.top, 28)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
            }
            .scrollBounceBehavior(.basedOnSize)
            OnbPrimaryButton(title: "Los geht’s", action: onNext)
            OnbGhostButton(title: first ? "Ich habe schon ein Backup" : "Schliessen", action: onSecondary)
        }
    }

    /// Vier Zeilen mit grünem Haken als ein Text, damit alle Zeilen gemeinsam verkleinert werden (einzeilig wie im Web)
    private var promiseText: Text {
        var t = Text(verbatim: "")
        for (i, line) in Self.promises.enumerated() {
            if i > 0 { t = t + Text(verbatim: "\n") }
            t = t + Text(Image(systemName: "checkmark.circle.fill")).foregroundColor(KColor.ok)
                + Text(verbatim: " " + line).foregroundColor(KColor.teal)
        }
        return t
    }
}

// MARK: - Seiten 2–5: Tabs

struct OnbTabPage: View {
    let tab: OnbTab
    let showSkip: Bool
    let onSkip: () -> Void
    let onNext: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Grosse Schrift: Text scrollbar, Bildschirmfoto ausgeblendet, damit «Weiter» und «Überspringen» sichtbar bleiben
    private var compact: Bool { typeSize >= .xxxLarge }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbTopBar(showSkip: showSkip, onSkip: onSkip) {
                OnbChip(symbol: tab.symbol, text: tab.name)
            }
            if compact {
                ScrollView {
                    texts
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                texts
                OnbShot(tab: tab)
                    .padding(.top, 4)
            }
            OnbPrimaryButton(title: "Weiter", action: onNext)
        }
        .padding(.top, 14)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbTitle(tab.title)
                .minimumScaleFactor(compact ? 1 : 0.8)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(tab.bullets, id: \.self) { b in
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(KColor.teal)
                            .accessibilityHidden(true)
                        Text(verbatim: b)
                            .font(.subheadline)
                            .foregroundStyle(KColor.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// Bildschirmfoto mit Verlauf und nachgebildeter Tab-Leiste (aktiver Tab hervorgehoben)
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
            LinearGradient(stops: [.init(color: KColor.paper.opacity(0), location: 0), .init(color: KColor.paper, location: 0.78)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 96)
            OnbTabBar(active: tab)
                .padding(10)
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
        .background(KColor.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.13), radius: 14, y: 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bildschirmfoto: \(tab.name)")
        .accessibilityAddTraits(.isImage)
    }
}

struct OnbTabBar: View {
    let active: OnbTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(OnbTab.allCases, id: \.self) { t in
                let on = t == active
                VStack(spacing: 1) {
                    Image(systemName: t.symbol)
                        .font(.system(size: 18, weight: on ? .semibold : .regular))
                        .frame(height: 22)
                    Text(verbatim: t.name)
                        .font(.system(size: 10, weight: on ? .bold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(on ? KColor.teal : KColor.ink2)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(Capsule().fill(on ? KColor.teal.opacity(0.13) : Color.clear))
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 8)
    }
}

// MARK: - Seite 6: Gut zu wissen

struct OnbTipsPage: View {
    let isLast: Bool
    let showSkip: Bool
    let onSkip: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbTopBar(showSkip: showSkip, onSkip: onSkip) {
                OnbChip(symbol: "ellipsis", text: "Gut zu wissen")
            }
            OnbTitle("Clever bis ins Detail")
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(OnbTip.all) { tip in
                        OnbTipRow(tip: tip)
                    }
                }
                .padding(.top, 6)
                .padding(.horizontal, 2)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)
            OnbPrimaryButton(title: isLast ? "Fertig" : "Weiter", action: onNext)
        }
        .padding(.top, 14)
    }
}

struct OnbTipRow: View {
    let tip: OnbTip

    var body: some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: tip.colorHex))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: tip.symbol)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(verbatim: tip.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(KColor.ink)
                    if tip.soon {
                        Text(verbatim: "Bald")
                            .font(.system(size: 10.5, weight: .bold))
                            .tracking(0.4)
                            .textCase(.uppercase)
                            .foregroundStyle(KColor.teal)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(KColor.teal.opacity(0.13)))
                    }
                }
                Text(verbatim: tip.text)
                    .font(.caption)
                    .foregroundStyle(KColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbTopBar(showSkip: false, onSkip: {}) {
                OnbChip(text: "Fast geschafft")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    OnbTitle("Noch zwei Angaben")
                    OnbSubtitle("Beides kannst du später jederzeit unter «Mehr» ändern.")
                    OnbCard(title: "Hauptwährung") {
                        MoreCurrencyPicker(selection: home, expanded: $moreOpen) { c in home = c }
                        Text("Andere Währungen rechnet Kontivo automatisch um.")
                            .font(.caption)
                            .foregroundStyle(KColor.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                    OnbCard(title: "Wie heisst du?") {
                        nameField
                        Text("So ordnest du Verträge dir oder anderen im Haushalt zu.")
                            .font(.caption)
                            .foregroundStyle(KColor.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.bottom, 6)
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

    private var nameField: some View {
        TextField("Name", text: $name)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .onSubmit { nameFocused = false }
            .font(.body)
            .padding(.horizontal, 13)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(KColor.field))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(nameFocused ? KColor.teal : Color.clear, lineWidth: 2))
            .accessibilityLabel("Wie heisst du?")
    }
}

// MARK: - Seite 8: Womit fangen wir an?

/// Letzter Schritt (Web e56e05e, Variante 1): Karte «Automatisch finden» (Kontoauszug) + «Mit Vorlage starten» mit kompakten Vorlagen.
struct OnbStartPage: View {
    let items: [OnbQuick]
    @Binding var quick: Int?
    let onBank: (BankPickSource) -> Void
    let onCreate: () -> Void
    let onDone: () -> Void
    @State private var askSource = false

    private var createTitle: String {
        if let q = quick, let item = items.first(where: { $0.id == q }) { return item.label + " erfassen" }
        return "Vertrag erfassen"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            OnbTopBar(showSkip: false, onSkip: {}) {
                OnbChip(text: "Letzter Schritt")
            }
            OnbTitle("Womit fangen wir an?")
            OnbSubtitle("Lass Kontivo suchen oder starte mit einer Vorlage.")
            OnbAutoCard { askSource = true }
                .confirmationDialog("Kontoauszug", isPresented: $askSource, titleVisibility: .hidden) {
                    ForEach(BankPickSource.available, id: \.self) { s in
                        Button(s.dialogTitle) { onBank(s) }
                    }
                    Button("Abbrechen", role: .cancel) {}
                }
            Text(verbatim: "Mit Vorlage starten")
                .font(.caption.weight(.bold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(KColor.ink2)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            OnbSubtitle("Tipp an, was du hast – den Rest ergänzt du.")
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

/// Karte «Automatisch finden» (`.obauto`): Bank-Symbol auf Teal, Rahmen Teal, leicht getönt
struct OnbAutoCard: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(KColor.teal)
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "building.columns")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Automatisch finden")
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundStyle(KColor.ink)
                    Text(verbatim: "Kontoauszug wählen, Vorschläge bestätigen")
                        .font(.footnote)
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(KColor.teal.opacity(0.09)).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(KColor.teal, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onbAutoFind")
    }
}

/// Kompakte Vorlage (`.obchips.row`): Kachel links, Name und Kategorie rechts
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
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(verbatim: item.category?.name ?? "")
                        .font(.caption2)
                        .foregroundStyle(KColor.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(hex: KCategory.fallbackColor))
                .frame(width: 27, height: 27)
                .overlay(Image(systemName: "tag").font(.system(size: 12, weight: .medium)).foregroundStyle(.white))
                .accessibilityHidden(true)
        }
    }
}
