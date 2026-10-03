import SwiftUI
import KontivoCore

/// Achtung: «Category» ist in UIKit/ObjectiveC mehrdeutig – in der App immer KCategory verwenden.
typealias KCategory = KontivoCore.Category

// MARK: - Logo / Symbol-Kachel («mark» der Web-App)

/// Quadratische Kachel: Logo (falls vorhanden) oder Kategorie-Symbol auf Kategoriefarbe.
struct MarkView: View {
    @Environment(AppModel.self) private var model
    let logoID: String?
    let logoBg: String?
    let colorHex: String
    let symbol: String
    var size: CGFloat = 40

    var body: some View {
        let r = size * 0.25
        ZStack {
            if let img = model.image(logoID) {
                RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color(hex: logoBg ?? "#FFFFFF"))
                Image(uiImage: img).resizable().scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: r, style: .continuous).fill(Color(hex: colorHex))
                Image(systemName: symbol)
                    .font(.system(size: size * 0.45, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: r, style: .continuous).strokeBorder(KColor.line.opacity(0.6), lineWidth: 0.5))
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
        self.init(logoID: nil, logoBg: nil, colorHex: category.colorHex, symbol: KIcon.symbol(for: category), size: size)
    }
}

/// Rundes Personenbild oder Initiale
struct PersonAvatar: View {
    @Environment(AppModel.self) private var model
    let person: Person?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            if let img = model.image(person?.avatarID) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Circle().fill(KColor.teal.opacity(0.14))
                Text(String((person?.name ?? "?").prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(KColor.teal)
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
            Text(Format.money(amount)).font(font).monospacedDigit()
            Text(currency).font(currencyFont).foregroundStyle(KColor.ink2)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Karten und Abschnitte

/// Weisse Karte mit Rundung (wie .grp in der Web-App)
struct KCard<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).fill(KColor.surface))
            .overlay(RoundedRectangle(cornerRadius: KMetric.radius, style: .continuous).strokeBorder(KColor.line, lineWidth: 0.5))
    }
}

/// Abschnittskopf: links Titel, rechts optionaler Text (z.B. Summe)
struct SectionHead: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(KColor.ink2).textCase(.uppercase)
            Spacer()
            if let t = trailing { Text(t).font(.footnote).foregroundStyle(KColor.ink2).monospacedDigit() }
        }
        .padding(.horizontal, 4).padding(.top, 14).padding(.bottom, 6)
    }
}

/// Auswahl-Chip (Filter, Personen)
struct Chip: View {
    let title: String
    var isOn: Bool
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .semibold : .regular))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(isOn ? Color.white : KColor.ink)
                .background(Capsule().fill(isOn ? KColor.teal : KColor.field))
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
            .font(.footnote.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(fg)
            .background(Capsule().fill(fg.opacity(0.12)))
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

// MARK: - Leere Seiten (emptyHero der Web-App)

struct EmptyHero: View {
    let symbol: String
    let title: String
    let text: String
    var hooks: [String] = []
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil
    var footer: AnyView? = nil

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(KColor.teal)
                .padding(.bottom, 2)
            Text(title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(KColor.ink)
            Text(text)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(KColor.ink2)
            if !hooks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(hooks, id: \.self) { h in
                        Label {
                            Text(h).lineLimit(1).minimumScaleFactor(0.8)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(KColor.teal)
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.top, 4)
            }
            if let b = buttonTitle, let action {
                Button(action: action) {
                    Text(b).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 6)
            }
            if let footer { footer }
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity)
    }
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

/// Schliessen-Knopf für Fenster-Kopfzeilen
struct CloseButton: View {
    @Environment(\.dismiss) private var dismiss
    var title: String = "Fertig"
    var body: some View {
        Button(title) { dismiss() }.fontWeight(.semibold)
    }
}
