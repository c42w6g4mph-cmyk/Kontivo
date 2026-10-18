import SwiftUI
import KontivoCore

/// Fensterleiste wie Web `.shbar` (Detail, Formular): weisse Fläche (`--surface`) mit Trennlinie unten,
/// links «Schliessen»/«Abbrechen» (16 px, Tinte 2), Titel 18/600 mittig, rechts z.B. «Bearbeiten»/«Sichern» (16/700 Messing).
/// Bleibt eine Navigationsleiste (Titel für VoiceOver und UI-Tests), ohne die Glasflächen von iOS 26 um die Knöpfe.
/// Integration: Falls der Bereich design eine gemeinsame Fensterleiste baut, diese verwenden.
struct CTSheetBar<Leading: View, Trailing: View>: ViewModifier {
    let title: String
    var titleVisible = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    func body(content: Content) -> some View {
        let base = content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(KColor.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle().fill(KColor.line).frame(height: 1)
            }
        if #available(iOS 26.0, *) {
            base.toolbar {
                ToolbarItem(placement: .topBarLeading) { leading() }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .principal) { titleView }
                    .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .topBarTrailing) { trailing() }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            base.toolbar {
                ToolbarItem(placement: .topBarLeading) { leading() }
                ToolbarItem(placement: .principal) { titleView }
                ToolbarItem(placement: .topBarTrailing) { trailing() }
            }
        }
    }

    private var titleView: some View {
        Text(title)
            .font(KFont.title(18))
            .tracking(KFont.tracking(-0.012, 18))
            .foregroundStyle(KColor.ink)
            .lineLimit(1)
            .opacity(titleVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: titleVisible)
            .accessibilityHidden(!titleVisible)
    }
}

/// Knopf links in der Leiste (Web `.shx`: 16 px, Tinte 2)
struct CTBarCancelButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(KColor.ink2)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 6)
                .frame(minWidth: 78, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Knopf rechts in der Leiste (Web `.shok`: 16/700 Messing)
struct CTBarConfirmButton: View {
    let title: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(disabled ? KColor.ink3 : KColor.teal)
                .lineLimit(1)
                .fixedSize()
                .padding(.vertical, 6)
                .frame(minWidth: 78, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

/// Runder Menüknopf ••• (Web `.dmbtn`: 34, Fläche `--sunken`, Punkte Messing 20)
struct CTBarMenuLabel: View {
    var body: some View {
        CTIcon.named("more", 20)
            .foregroundStyle(KColor.teal)
            .frame(width: 34, height: 34)
            .background(Circle().fill(KColor.sunken))
            .contentShape(Circle())
    }
}

extension View {
    func ctSheetBar<L: View, T: View>(_ title: String, titleVisible: Bool = true,
                                      @ViewBuilder leading: @escaping () -> L,
                                      @ViewBuilder trailing: @escaping () -> T) -> some View {
        modifier(CTSheetBar(title: title, titleVisible: titleVisible, leading: leading, trailing: trailing))
    }
}
