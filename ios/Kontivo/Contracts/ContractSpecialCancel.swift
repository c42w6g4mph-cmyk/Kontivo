import SwiftUI
import KontivoCore

// Sonderkündigung bei Preiserhöhung (Web v205–v209 `openSkr`, Stand v224): kurze Zeile im Detail
// («Sonderkündigung möglich · bis 30.11.») und Erklärblatt mit Einleitung, Eckdaten (Neuer Preis / Kündigen bis / Vertrag endet),
// «Gut zu wissen» und Grundlage. Regeln und Texte im Kern: `calc.specialCancel(c)` / `calc.specialCancelSheet(c)` (SpecialCancel.swift).

// MARK: - Zeile im Detail (Web `.skrl`: Fläche `--field`, Radius 12, 10/12, ⓘ 17 in Georgia, 13.5 px, › Messing)

struct CTSkrLine: View {
    let info: SpecialCancelInfo
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 9) {
                Text("i")
                    .font(.custom("Georgia", size: 10.5).weight(.semibold).italic())
                    .foregroundStyle(KColor.ink2)
                    .frame(width: 17, height: 17)
                    .overlay(Circle().strokeBorder(KColor.ink2, lineWidth: 1))
                (Text(info.head).fontWeight(.semibold).foregroundColor(KColor.ink)
                 + Text(info.tail.isEmpty ? "" : " · " + info.tail).foregroundColor(KColor.ink2))
                    .font(.system(size: 13.5))
                    .lineSpacing(1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("›")
                    .font(.system(size: 18))
                    .foregroundStyle(KColor.teal)
            }
            .padding(.vertical, 10).padding(.horizontal, 12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 10)
        .accessibilityLabel(info.head + (info.tail.isEmpty ? "" : ", " + info.tail))
        .accessibilityHint("Erklärung öffnen")
        .accessibilityIdentifier("detail.skr")
    }
}

// MARK: - Erklärblatt (Web `openSkr` im Auswahlblatt `#sheetPick`)

struct CTSkrSheet: View {
    let data: SpecialCancelSheet

    var body: some View {
        CTPickSheet(title: data.title) {
            VStack(alignment: .leading, spacing: 0) {
                Text(data.intro)
                    .font(.system(size: 15))
                    .foregroundStyle(KColor.ink)
                    .lineSpacing(3.9)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 14)
                VStack(spacing: 0) {
                    ForEach(Array(data.rows.enumerated()), id: \.element.id) { i, r in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(r.key)
                                .font(.system(size: 15))
                                .foregroundStyle(KColor.ink2)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(r.value)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(r.accent ? KColor.teal : KColor.ink)
                                    .multilineTextAlignment(.trailing)
                                if !r.sub.isEmpty {
                                    Text(r.sub)
                                        .font(.system(size: 12.5))
                                        .foregroundStyle(KColor.ink2)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .top) {
                            if i > 0 { Rectangle().fill(KColor.line).frame(height: 1) }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
                Text(data.tipsTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KColor.ink3)
                    .padding(.horizontal, 4)
                    .padding(.top, 18)
                    .padding(.bottom, 6)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(data.tips.enumerated()), id: \.offset) { i, s in
                        Text(s)
                            .font(.system(size: 14))
                            .foregroundStyle(KColor.ink2)
                            .lineSpacing(3.6)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 11)
                            .overlay(alignment: .top) {
                                if i > 0 { Rectangle().fill(KColor.line).frame(height: 1) }
                            }
                    }
                }
                .padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.field))
                Text(data.footer)
                    .font(.system(size: 12))
                    .foregroundStyle(KColor.ink3)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .padding(.top, 16)
            }
        }
        .accessibilityIdentifier("skr.sheet")
    }
}

/// Blatt-Inhalt als Identifiable (für .sheet(item:))
struct CTSkrSheetItem: Identifiable {
    let id = UUID()
    let data: SpecialCancelSheet
}
