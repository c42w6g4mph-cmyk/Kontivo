import UIKit

/// Betragsfelder (Zahlentastatur mit Komma/Punkt): beim Antippen steht der Cursor immer am Ende, Löschen beginnt bei den
/// Rappen/Cents (Web v259 `focusin` auf `input[inputmode="decimal"]`). Gilt für alle Betragsfelder der App.
@MainActor
enum AmountCursor {
    private static var observer: NSObjectProtocol?

    static func install() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(forName: UITextField.textDidBeginEditingNotification, object: nil,
                                                          queue: .main) { note in
            MainActor.assumeIsolated {
                if let tf = note.object as? UITextField { moveToEnd(tf) }
            }
        }
    }

    private static func moveToEnd(_ tf: UITextField) {
        guard tf.keyboardType == .decimalPad else { return }
        // zweimal wie im Web (sofort und nach 80 ms): UIKit setzt die Einfügemarke nach dem Fokus noch an die Tippstelle
        Task { @MainActor [weak tf] in
            for wait: UInt64 in [0, 80_000_000] {
                if wait > 0 { try? await Task.sleep(nanoseconds: wait) }
                guard let tf, tf.isFirstResponder else { return }
                let end = tf.endOfDocument
                tf.selectedTextRange = tf.textRange(from: end, to: end)
            }
        }
    }
}
