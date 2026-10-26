import SwiftUI
import KontivoCore

/// Erfolgskarte nach dem Übernehmen aus dem Katalog (Web v240–v243 `.tplsum.ok`): grüner Haken «Vertragsdaten ergänzt ·
/// n Angaben aus dem Kontivo-Katalog», darunter je Zeile Feld links und übernommener Wert rechts (bricht um, nie «…»),
/// erster ganzer Satz des Anbieter-Hinweises (Rest hinter «mehr»), Prüfhinweis bei unbestätigten Daten, Fusszeile
/// «Stand 10/2026 · Änderungen vorbehalten» und «Rückgängig». Texte und Regeln im Kern (`CatalogCard`).
struct CTCatalogSuccessCard: View {
    @Environment(AppModel.self) private var model
    @Bindable var form: CTFormState
    let hint: CatalogHintShort
    let items: [CatalogSumItem]
    @State private var hintOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 11) {
                CTCheckDot(size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(CatalogCard.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KColor.ink)
                    Text(CatalogCard.subtitle(items.count))
                        .font(.system(size: 12.5))
                        .foregroundStyle(KColor.ink2)
                }
            }
            .accessibilityElement(children: .combine)
            if !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { i, x in
                        if i > 0 { Rectangle().fill(KColor.line.opacity(0.7)).frame(height: 1) }
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            CTCheckDot(size: 16).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                            Text(x.field)
                                .font(.system(size: 13.5))
                                .foregroundStyle(KColor.ink)
                                .fixedSize()
                            Text(x.value)
                                .font(.system(size: 12.5))
                                .foregroundStyle(KColor.ink2)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 5)
                        .accessibilityElement(children: .combine)
                    }
                }
                .accessibilityIdentifier("form.tplItems")
            }
            hintView
            HStack(spacing: 10) {
                Text(CatalogCard.footer)
                    .font(.system(size: 11.5))
                    .foregroundStyle(KColor.ink3)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 6)
                Button(CatalogCard.undo) {
                    form.tplUndoApply(data: model.data)
                    model.toast("Katalogdaten entfernt")
                }
                .buttonStyle(.borderless)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(KColor.teal)
                .accessibilityIdentifier("form.tplUndo")
            }
            .padding(.top, -2)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.sunken))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.ok.opacity(0.10)).allowsHitTesting(false))
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("form.tplSummary")
    }

    /// Erster Satz, «mehr» bzw. «Hinweis zum Kündigen anzeigen», Prüfhinweis (Web hnShort)
    @ViewBuilder private var hintView: some View {
        if !hint.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if hint.onlyLink {
                    if hintOpen {
                        hintText(hint.full)
                    } else {
                        moreButton(CatalogCard.showHint)
                    }
                } else if !hint.first.isEmpty {
                    if hintOpen || hint.rest.isEmpty {
                        hintText(hint.first + (hint.rest.isEmpty ? "" : " " + hint.rest))
                    } else {
                        // «mehr» direkt hinter dem Satz (Web `.hnm` inline)
                        Text(moreLine)
                            .font(.system(size: 12.5))
                            .foregroundStyle(KColor.ink2)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .environment(\.openURL, OpenURLAction { _ in
                                withAnimation(.easeInOut(duration: 0.2)) { hintOpen = true }
                                return .handled
                            })
                    }
                }
                if !hint.warn.isEmpty {
                    Text(hint.warn)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(KColor.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityIdentifier("form.tplHint")
        }
    }

    private var moreLine: AttributedString {
        var a = AttributedString(hint.first + " ")
        var m = AttributedString(CatalogCard.more)
        m.link = URL(string: "kontivo-intern://mehr")
        m.foregroundColor = KColor.brass
        m.font = .system(size: 12.5, weight: .semibold)
        a.append(m)
        return a
    }

    private func hintText(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 12.5))
            .foregroundStyle(KColor.ink2)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func moreButton(_ t: String) -> some View {
        Button(t) { withAnimation(.easeInOut(duration: 0.2)) { hintOpen = true } }
            .buttonStyle(.borderless)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(KColor.brass)
            .accessibilityIdentifier("form.tplHintMore")
    }
}

/// Grüner Kreis mit Haken (Web `.tplsum .gk`)
struct CTCheckDot: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(KColor.ok)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(KColor.surface)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
