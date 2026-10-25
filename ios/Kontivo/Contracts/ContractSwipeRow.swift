import SwiftUI
import KontivoCore

/// Zeile nach links wischen (Web v317/v318 `swipeDel`, wie iOS-Listen): bis 88 pt zeigt «Löschen» (bzw. «Verwerfen»),
/// ganz durchwischen (über 55 % der Breite) löscht direkt. Das Formular ist eine `ScrollView` (keine `List`), daher eigene Geste
/// statt `.swipeActions`; senkrechtes Ziehen bleibt beim Scrollen. Bedienungshilfen: Aktion «Löschen».
struct CTSwipeDelete<Content: View>: View {
    var title = "Löschen"
    var identifier = ""
    let onDelete: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0
    @State private var base: CGFloat = 0
    @State private var horizontal: Bool?
    @State private var width: CGFloat = 320
    private let W: CGFloat = 88

    var body: some View {
        ZStack(alignment: .trailing) {
            if offset < 0 {
                Button {
                    delete()
                } label: {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: Swift.max(W, -offset), alignment: .center)
                        .frame(maxHeight: .infinity)
                        .background(KColor.alert)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 1)
                .accessibilityIdentifier(identifier.isEmpty ? "" : identifier + ".delete")
            }
            content
                .background(KColor.surface)
                .offset(x: offset)
                .allowsHitTesting(offset == 0)
                .overlay {
                    // offene Zeile: Antippen schliesst (Web `shut`)
                    if offset < 0 {
                        Color.clear
                            .contentShape(Rectangle())
                            .offset(x: offset)
                            .onTapGesture { close() }
                    }
                }
        }
        .clipped()
        .background(GeometryReader { g in
            Color.clear
                .onAppear { width = g.size.width }
                .onChange(of: g.size.width) { _, w in width = w }
        })
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .local)
                .onChanged { v in
                    if horizontal == nil {
                        horizontal = abs(v.translation.width) > abs(v.translation.height)
                        base = offset
                    }
                    guard horizontal == true else { return }
                    offset = Swift.min(0, base + v.translation.width)
                }
                .onEnded { _ in
                    defer { horizontal = nil }
                    guard horizontal == true else { return }
                    if -offset > width * 0.55 {
                        delete()
                    } else if -offset > W / 2 {
                        withAnimation(.easeOut(duration: 0.2)) { offset = -W }
                    } else {
                        close()
                    }
                }
        )
        .accessibilityAction(named: Text(title)) { onDelete() }
    }

    private func close() {
        withAnimation(.easeOut(duration: 0.2)) { offset = 0 }
    }

    private func delete() {
        withAnimation(.easeInOut(duration: 0.2)) {
            offset = 0
            onDelete()
        }
    }
}
