import SwiftUI
import KontivoCore

// PLATZHALTER – wird vom zuständigen Bereich ersetzt (Signatur beibehalten)
/// Wechselkurse automatisch (Frankfurter/EZB, Rückfall open.er-api), höchstens einmal pro Tag.
enum RateService {
    @MainActor static func refreshIfNeeded(_ model: AppModel, force: Bool) async {}
}
