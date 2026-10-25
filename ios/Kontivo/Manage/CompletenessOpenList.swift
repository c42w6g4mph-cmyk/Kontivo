import SwiftUI
import KontivoCore

/// Offene Punkte bis 100 % im Abschluss der Vollständigkeit (Web 01b0f3d `vkOpenList`, `.vkfl`): zuerst die Adresse, dann je Vertrag
/// die fehlende Frist. Antippen ergänzt den Punkt direkt (`CompletenessFlowState.fixItem`).
struct CFOpenList: View {
    let items: [CompletenessOpenItem]
    let pick: (CompletenessOpenItem.Kind) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                if i > 0 { Rectangle().fill(KColor.line).frame(height: 1) }
                row(it)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(KColor.surface))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 6)
        .padding(.bottom, 16)
        .accessibilityIdentifier("vk.openList")
    }

    private func row(_ it: CompletenessOpenItem) -> some View {
        Button {
            pick(it.kind)
        } label: {
            HStack(spacing: 12) {
                icon(it.kind)
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: it.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(KColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(verbatim: it.subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(KColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(verbatim: "›")
                    .font(.system(size: 18))
                    .foregroundStyle(KColor.ink3)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("vk.fix." + it.id)
    }

    @ViewBuilder
    private func icon(_ k: CompletenessOpenItem.Kind) -> some View {
        switch k {
        case .sender:
            Image(systemName: "envelope")
                .font(.system(size: 15))
                .foregroundStyle(KColor.teal)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(KColor.sunken))
                .accessibilityHidden(true)
        case .term(let id):
            if let c = model.data.contract(id) {
                MarkView(contract: c, data: model.data, size: 34)
            }
        }
    }
}
