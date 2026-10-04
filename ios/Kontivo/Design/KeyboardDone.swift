import SwiftUI

/// Knopf «Fertig» über der Tastatur (Zifferntastaturen haben keine Eingabetaste). Für alle Bereiche:
/// `.kKeyboardDone()` an die Seite hängen (am besten zusammen mit `.scrollDismissesKeyboard(.interactively)`).
struct KKeyboardDone: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .fontWeight(.semibold)
            }
        }
    }
}

/// Früherer Name (Bereich Verträge) – bleibt für bestehende Aufrufe
typealias CTKeyboardDone = KKeyboardDone

extension View {
    /// «Fertig» über der Tastatur
    func kKeyboardDone() -> some View { modifier(KKeyboardDone()) }
}
