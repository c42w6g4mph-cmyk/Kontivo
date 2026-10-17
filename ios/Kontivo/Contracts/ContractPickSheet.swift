import SwiftUI
import KontivoCore

/// Auswahlblatt wie Web `#sheetPick`: Titel 22/600 (44 rechts frei), × rechts oben (36, `--sunken`), Inhalt mit 12 Abstand,
/// unten «Schliessen» (Rahmen, Radius 13, 14 px Tinte 2). Seitenrand 17, Fläche `--paper`, Ecken 19.
struct CTPickSheet<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(KFont.title(22))
                    .tracking(KFont.tracking(-0.012, 22))
                    .foregroundStyle(KColor.ink)
                    .lineSpacing(5.6)
                    .padding(.trailing, 44)
                    .padding(.top, 24)
                    .padding(.bottom, 3)
                    .accessibilityAddTraits(.isHeader)
                content
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                Button {
                    dismiss()
                } label: {
                    Text("Schliessen")
                        .font(.system(size: 14))
                        .foregroundStyle(KColor.ink2)
                        .frame(maxWidth: .infinity)
                        .padding(13)
                        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(KColor.line, lineWidth: 1))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 9)
            }
            .padding(.horizontal, 17)
            .padding(.bottom, 18)
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Text("×")
                    .font(.system(size: 20))
                    .foregroundStyle(KColor.ink2)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(KColor.sunken))
            }
            .buttonStyle(.plain)
            .padding(.top, 16).padding(.trailing, 12)
            .accessibilityLabel("Schliessen")
        }
        .background(KColor.paper.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(19)
    }
}

/// Zeile im Auswahlblatt (Web `.pick`: Fläche `--field`, Radius 11, 13/14, 16 px; gewählt Messing gefüllt, weiss 600;
/// rechts 12.5 Tinte 3)
struct CTPickRow: View {
    let title: String
    var detail = ""
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 16, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.white : KColor.ink)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : KColor.ink3)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 13).padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(selected ? KColor.tealFill : KColor.field))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// «Sortieren nach» (Web `openPick("sort")`): Fälligkeit, Kosten, Vertragspartner, Kategorie, Person; Antippen sortiert und schliesst
struct CTSortSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cur = model.data.settings.sort
        CTPickSheet(title: "Sortieren nach") {
            VStack(spacing: 6) {
                ForEach(ContractSort.pickerOrder, id: \.self) { s in
                    CTPickRow(title: s.optionLabel, selected: s == cur) {
                        if s != cur { model.update { $0.settings.sort = s } }
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
