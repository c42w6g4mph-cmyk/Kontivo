import SwiftUI
import Observation
import KontivoCore

/// Achtung: «Category» ist in UIKit/ObjectiveC mehrdeutig – in der App immer KCategory verwenden.
typealias KCategory = KontivoCore.Category

// MARK: - Logo / Symbol-Kachel («mark» der Web-App)

/// Quadratische Kachel (Web `markHtml`/`.mark`): Logo auf Logo-Hintergrund, sonst Kategorie-Symbol in Pastell
/// (Fläche = Kategoriefarbe 20 % hell / 30 % dunkel, Symbol 56 % der Kachel in Kategoriefarbe, v166).
struct MarkView: View {
    @Environment(AppModel.self) private var model
    let logoID: String?
    let logoBg: String?
    let colorHex: String
    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: KMetric.markRadius(size), style: .continuous)
        ZStack {
            if let img = model.image(logoID) {
                shape.fill(Color(hex: logoBg ?? "#FFFFFF"))
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                shape.fill(KColor.categoryFill(colorHex))
                KIcon.image(symbol)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .frame(width: size * 0.56, height: size * 0.56)
                    .foregroundStyle(KColor.categoryInk(colorHex))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .accessibilityHidden(true)
    }
}

extension MarkView {
    /// Kachel für einen Vertrag (Logo des Vertragspartners bzw. des Vertrags, sonst Kategorie)
    init(contract c: Contract, data: AppData, size: CGFloat = 40) {
        let logo = data.logo(of: c)
        self.init(logoID: logo?.id, logoBg: logo?.background, colorHex: data.color(of: c),
                  symbol: KIcon.symbol(for: data.category(c.categoryID)), size: size)
    }

    /// Kachel für eine Einnahme
    init(income i: Income, size: CGFloat = 40) {
        self.init(logoID: i.logoID, logoBg: i.logoBg, colorHex: i.colorHex ?? i.kind.colorHex,
                  symbol: KIcon.symbol(forKey: i.kind.icon), size: size)
    }

    /// Kachel für eine Kategorie
    init(category: KCategory, size: CGFloat = 40) {
        self.init(logoID: nil, logoBg: nil, colorHex: category.displayColorHex, symbol: KIcon.symbol(for: category), size: size)
    }
}

/// Rundes Personenbild oder Initiale (Web `.mdav`)
struct PersonAvatar: View {
    @Environment(AppModel.self) private var model
    let person: Person?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            if let img = model.image(person?.avatarID) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                // Web `.mdav`: Kreis `--tealFill`, Initiale weiss Bold (16 pt bei 38 pt)
                Circle().fill(KColor.tealFill)
                Text(String((person?.name ?? "?").prefix(1)).uppercased())
                    .font(.system(size: (size * 16 / 38).rounded(), weight: .bold))
                    .foregroundStyle(KColor.onBrass)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

// MARK: - Beträge

/// Betrag mit kleiner Währung dahinter: «59.90 CHF»
struct MoneyText: View {
    let amount: Double
    let currency: String
    var font: Font = .body.weight(.semibold)
    var currencyFont: Font = .caption.weight(.medium)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            // Zahlenformat nach Währung (EUR «1.234,50», CHF «1’234.50»)
            Text(Format.money(amount, Currency(rawValue: currency))).font(font).monospacedDigit()
            Text(currency).font(currencyFont).foregroundStyle(KColor.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Karten und Abschnitte

/// Weisse Fläche einer gruppierten Liste (Web `.grp .card`/`.dgrp`/`.mcard`): Radius 16, ohne Rand und Schatten (v164)
struct KCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: KMetric.groupRadius, style: .continuous).fill(KColor.surface))
    }
}

/// Abschnittskopf über einer Gruppe (Web `.grphead`): links Titel 12 px Semibold in `--ink`, rechts z.B. Summe 12 px `--ink2`.
/// Ohne Versalien (v166). Abstand oben 20 (`.grp` padding-top), unten 6.
struct SectionHead: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(KFont.text(12, .semibold)).foregroundStyle(KColor.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if let t = trailing { Text(t).font(KFont.text(12)).foregroundStyle(KColor.ink2).monospacedDigit() }
        }
        .kLineHeight(12, 17.4)
        .padding(.top, 20).padding(.bottom, 6)
    }
}

/// Trennlinie zwischen Zeilen einer Gruppe (1 px `--line`); `inset` = Abstand links (Zeilen mit Marke: 62, v164)
struct KDivider: View {
    var inset: CGFloat = 0
    var body: some View {
        Rectangle().fill(KColor.line).frame(height: 1).padding(.leading, inset).accessibilityHidden(true)
    }
}

/// Pfeil rechts in Listenzeilen (Web «›» 18 px `--ink3`)
struct KChevron: View {
    var size: CGFloat = 18
    var body: some View {
        Text("›").font(KFont.text(size)).foregroundStyle(KColor.ink3).accessibilityHidden(true)
    }
}

/// Auswahl-Chip (Web `.chip`): Rand 1 px `--line`, 14 px `--ink2`; gewählt: Fläche `--ink`, Schrift `--paper` Semibold
struct Chip: View {
    let title: String
    var isOn: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KFont.text(14, isOn ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(isOn ? KColor.paper : KColor.ink2)
                .background(Capsule().fill(isOn ? KColor.ink : Color.clear))
                .overlay(Capsule().strokeBorder(isOn ? KColor.ink : KColor.line, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Kleine Pille (Status im Detail)
struct Pill: View {
    enum Tone { case neutral, warn, alert, ok }
    let text: String
    var tone: Tone = .neutral
    var body: some View {
        Text(text)
            .font(KFont.text(12.5, .semibold))
            .padding(.horizontal, 9).padding(.vertical, 3)
            .foregroundStyle(fg)
            .background(Capsule().fill(fg.opacity(0.14)))
    }
    private var fg: Color {
        switch tone {
        case .neutral: return KColor.ink2
        case .warn: return KColor.warn
        case .alert: return KColor.alert
        case .ok: return KColor.ok
        }
    }
}

/// Segment-Umschalter (Web `.seg2`/`.hseg`): Fläche `--sunken`, Radius 10, Innenabstand 3; gewählt weiss mit leichtem Schatten.
struct KSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selection: T
    var fontSize: CGFloat = 14
    var label: String = ""

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let (v, t) = options[i]
                let on = v == selection
                Button { selection = v } label: {
                    Text(t)
                        .font(KFont.text(fontSize, on ? .semibold : .medium))
                        .foregroundStyle(on ? KColor.ink : KColor.ink2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .kLineHeight(fontSize, (fontSize * 1.45).rounded())
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(KColor.surface)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: KMetric.controlRadius, style: .continuous).fill(KColor.sunken))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }
}

/// Hauptknopf (Web `.esbtn`/`.fok`): Messing gefüllt, 17 px Semibold, Radius 14, Innenabstand 14
struct KPrimaryButton: View {
    let title: String
    var maxWidth: CGFloat = 320
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(KFont.text(17, .semibold))
                .foregroundStyle(KColor.onBrass)
                .frame(maxWidth: maxWidth)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.tealFill))
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Titelzeile der Tabs (Web `.top` + `.minibar`)

/// Titelzeile oben auf jeder Tab-Seite (Web `.top`, v184): 57 pt hoch, Titel 30 pt SF Pro Semibold, Laufweite −0.015em,
/// rechts optional ein Knopf (Plus, Jahr). Steht als erstes Element im ScrollView-Inhalt; zusammen mit `.kTabPage(title:)`.
/// Beim Wegscrollen erscheint oben die Mini-Kopfzeile mit demselben Titel.
struct KTabHeader<Trailing: View>: View {
    @Environment(\.kMiniBarState) private var mini
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(KFont.title(30))
                .tracking(KFont.tracking(-0.015, 30))
                .foregroundStyle(KColor.ink)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("kPageTitle")
            Spacer(minLength: 8)
            trailing
        }
        .padding(.top, 17)
        .frame(minHeight: KMetric.titleBarHeight, alignment: .bottom)
        .id(KTabHeaderID.top)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.frame(in: .global).maxY
        } action: { maxY in
            guard let mini else { return }
            let hidden = maxY < mini.topInset + 8
            if mini.visible != hidden { mini.visible = hidden }
        }
    }
}

/// Sprungziel «nach oben» der Mini-Kopfzeile (Web: Tipp auf `#miniBar` → `scrollTo(top:0)`)
enum KTabHeaderID {
    static let top = "kTabTop"
}

extension KTabHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Plus-Knopf der Titelzeile (Web `#addBtn`): 40 pt Kreis `--brassFab`, Symbol 22 pt `--onBrass`
struct KAddButton: View {
    var label: String = "Hinzufügen"
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            KIcon.view("ic.plus", 22)
                .foregroundStyle(KColor.onBrass)
                .frame(width: 40, height: 40)
                .background(Circle().fill(KColor.brassFab))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

@Observable final class KMiniBarState {
    var visible = false
    /// Oberer Sicherheitsabstand (Statusleiste) im Fenster
    var topInset: CGFloat = 0
}

private struct KMiniBarKey: EnvironmentKey {
    static let defaultValue: KMiniBarState? = nil
}

extension EnvironmentValues {
    var kMiniBarState: KMiniBarState? {
        get { self[KMiniBarKey.self] }
        set { self[KMiniBarKey.self] = newValue }
    }
}

/// Tab-Seite wie im Web: keine System-Navigationsleiste, eigene Titelzeile (`KTabHeader` im Inhalt) und
/// Mini-Kopfzeile (Web `.minibar`: 16 pt Semibold zentriert, Papier 84 % mit Unschärfe, Linie unten), sobald der Titel weg ist.
struct KTabPageModifier: ViewModifier {
    let title: String
    /// Text der Mini-Kopfzeile (Web `updMini`: Titel, mit Jahresleiste «Kosten · 2026»); nil = Titel
    var miniTitle: String?
    @State private var mini = KMiniBarState()

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .environment(\.kMiniBarState, mini)
                .navigationTitle(title)
                .toolbar(.hidden, for: .navigationBar)
                .overlay(alignment: .top) {
                    KMiniBar(title: miniTitle ?? title, visible: mini.visible) {
                        withAnimation(.easeInOut) { proxy.scrollTo(KTabHeaderID.top, anchor: .top) }
                    }
                }
                .background {
                    GeometryReader { g in
                        Color.clear
                            .onAppear { mini.topInset = g.frame(in: .global).minY }
                            .onChange(of: g.frame(in: .global).minY) { _, v in mini.topInset = v }
                    }
                }
        }
    }
}

struct KMiniBar: View {
    let title: String
    let visible: Bool
    /// Antippen scrollt nach oben (Web `#miniBar` click)
    var action: () -> Void = {}
    var body: some View {
        GeometryReader { g in
            Button(action: action) {
                VStack(spacing: 0) {
                    Text(verbatim: title)
                        .font(KFont.text(16, .semibold))
                        .foregroundStyle(KColor.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.top, g.safeAreaInsets.top + 10)
                        .padding(.bottom, 10)
                        .padding(.horizontal, 16)
                        .background(.ultraThinMaterial)
                        .background(KColor.paper.opacity(0.84))
                    KDivider()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .ignoresSafeArea(edges: .top)
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : -6)
            .animation(.easeOut(duration: 0.18), value: visible)
            .allowsHitTesting(visible)
        }
        .frame(height: 0, alignment: .top)
        .accessibilityHidden(true)
    }
}

extension View {
    /// Tab-Seite mit Web-Titelzeile (siehe `KTabHeader`); `miniTitle` für die Mini-Kopfzeile, z.B. «Kosten · 2026»
    func kTabPage(title: String, miniTitle: String? = nil) -> some View {
        modifier(KTabPageModifier(title: title, miniTitle: miniTitle))
    }
}

// MARK: - Leere Seiten (emptyHero der Web-App)

/// Leere Seite (Web `emptyHero`, `.esv.eh`): Symbolkachel 68 pt Radius 20 (Messing 12 %), Titel 22 pt Rounded Bold,
/// Text 15 pt `--ink2`, Haken-Liste 15 pt Medium, Knopf Messing 17 pt.
struct EmptyHero: View {
    let symbol: String
    let title: String
    let text: String
    var hooks: [String] = []
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    var footer: AnyView? = nil

    /// SF-Symbol-Namen älterer Aufrufe → Web-Symbole (`ES_ICON`)
    private var iconName: String {
        switch symbol {
        case "doc.text": return "ic.tab.list"
        case "chart.bar": return "ic.tab.stat"
        case "wallet.pass": return "ic.tab.budget"
        case "stopwatch", "timer": return "ic.tab.term"
        default: return symbol
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            KIcon.image(iconName)
                .resizable().renderingMode(.template).scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundStyle(KColor.teal)
                .frame(width: 68, height: 68)
                .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(KColor.esArt))
                .padding(.bottom, 14)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(KColor.ink)
                .kLineHeight(22, 26.4)
                .frame(maxWidth: 326)
            Text(text)
                .font(KFont.text(15))
                .multilineTextAlignment(.center)
                .foregroundStyle(KColor.ink2)
                .kLineHeight(15, 21.75)
                .frame(maxWidth: 303)
                .padding(.top, 8)
                .padding(.bottom, 18)
            if !hooks.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(hooks, id: \.self) { h in
                        HStack(spacing: 10) {
                            KIcon.view("ic.check.hook", 18).foregroundStyle(KColor.teal)
                            Text(h).font(KFont.text(15, .medium)).foregroundStyle(KColor.ink)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        .kLineHeight(15, 21.75)
                    }
                }
                .padding(.bottom, 6)
            }
            if let b = buttonTitle, let action {
                KPrimaryButton(title: b, action: action)
                    .padding(.top, 18)
            }
            if let footer { footer }
        }
        .padding(.top, 36)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
}

extension KColor {
    /// Kachel der leeren Seiten (Web `color-mix(--teal 12%, --surface)`)
    static let esArt = Color(UIColor { tc in
        tc.userInterfaceStyle == .dark ? UIColor(rgb: KColor.mix(0xC6AB78, 0x36373B, 0.12)) : UIColor(rgb: KColor.mix(0x86671F, 0xFFFFFF, 0.12))
    })
}

// MARK: - Hilfen

extension View {
    /// Inhalt auf dem iPad mittig mit max. Breite
    func kContentWidth() -> some View {
        frame(maxWidth: KMetric.maxContent).frame(maxWidth: .infinity)
    }

    /// Hintergrund der Seiten (Papier)
    func kPageBackground() -> some View {
        background(KColor.paper.ignoresSafeArea())
    }
}

/// Schliessen-Knopf für Fenster-Kopfzeilen (Web `.shbar` rechts: 16 pt Bold in Messing)
struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var title: String = "Fertig"
    var body: some View {
        Button { dismiss() } label: {
            Text(title).font(KFont.text(16, .bold)).foregroundStyle(KColor.teal)
        }
        .accessibilityLabel(title)
    }
}

// MARK: - Fenster-Kopfzeile (Web `.shbar`)

extension View {
    /// Kopfzeile eines Fensters wie die Web-`.shbar`: Fläche `--surface` mit Linie unten (Titel/Schrift über `KAppearance`)
    func kSheetBar() -> some View {
        self.toolbarBackground(KColor.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }
}

extension ToolbarContent {
    /// Textknopf in der Kopfzeile ohne Glas-Kapsel (iOS 26), wie die Textknöpfe der Web-`.shbar`
    @ToolbarContentBuilder func kPlain() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

/// Textknopf «Fertig»/«Später» der Kopfzeile (16 pt Bold Messing)
struct KBarButton: View {
    let title: String
    var bold = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(KFont.text(16, bold ? .bold : .regular)).foregroundStyle(bold ? KColor.teal : KColor.ink2)
        }
        .accessibilityLabel(title)
    }
}

