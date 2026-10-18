import SwiftUI
import KontivoCore

/// Vorschlag aus dem Kontoauszug als Entwurf für das normale Vertragsformular (Web v181 `bkContractOf` → `openForm(c, false, "Vorschlag")`).
/// Der Vertragspartner steht als Name drin (es gibt ihn evtl. noch nicht), dazu Website, Adresse und Logo.
/// Gleichheit nur über `id` (Fenster-Identität in `AppSheet`).
struct BankFormDraft: Hashable {
    var id = UUID()
    var contract: Contract
    var partnerName: String
    var web: String
    var address: PostalAddress
    var logoID: String?
    var logoBg: String?

    static func == (a: BankFormDraft, b: BankFormDraft) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Verbindung Vorschlagsliste ↔ Formulare der Bereiche contracts/costs (Web `fBank`).
/// - Vertrag: `model.present(.contractForm(.bankSuggestion(draft)))`; das Formular ruft beim Sichern `contractDone` statt zu speichern,
///   «Nie mehr vorschlagen» (unten im Formular) ruft `ignore`.
/// - Einnahme: Entwurf hier ablegen, `model.present(.incomeForm(draft.id))`; `IncomeFormView` holt ihn mit `income(_:)`,
///   «Sichern» ruft `incomeDone`.
@MainActor
final class BankFormBridge {
    static let shared = BankFormBridge()

    private var contractHandlers: [UUID: (done: (BankFormDraft) -> Void, ignore: () -> Void)] = [:]
    private var incomes: [UUID: Income] = [:]
    private var incomeHandlers: [UUID: (Income) -> Void] = [:]

    // MARK: Vertrag

    func openContract(_ draft: BankFormDraft, model: AppModel, done: @escaping (BankFormDraft) -> Void, ignore: @escaping () -> Void) {
        contractHandlers[draft.id] = (done, ignore)
        model.present(.contractForm(.bankSuggestion(draft)))
    }

    /// Vom Vertragsformular beim «Sichern» (Vorschlag) aufgerufen
    func contractDone(_ draft: BankFormDraft) {
        contractHandlers.removeValue(forKey: draft.id)?.done(draft)
    }

    /// «Nie mehr vorschlagen» im Formular
    func ignore(_ id: UUID) {
        contractHandlers.removeValue(forKey: id)?.ignore()
    }

    // MARK: Einnahme

    func openIncome(_ draft: Income, model: AppModel, done: @escaping (Income) -> Void) {
        incomes[draft.id] = draft
        incomeHandlers[draft.id] = done
        model.present(.incomeForm(draft.id))
    }

    /// Entwurf zu einer ID (nil = keine Einnahme aus dem Kontoauszug)
    func income(_ id: UUID?) -> Income? {
        guard let id else { return nil }
        return incomes[id]
    }

    /// Vom Einnahmenformular beim «Sichern» (Vorschlag) aufgerufen
    func incomeDone(_ x: Income) {
        incomes[x.id] = nil
        incomeHandlers.removeValue(forKey: x.id)?(x)
    }
}

/// «Nie mehr vorschlagen» unten im Vertragsformular «Vorschlag» (Web `.fbankign`: volle Breite, Fläche, Rot, 15.5 pt)
struct BankFormIgnoreButton: View {
    let draftID: UUID
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
            BankFormBridge.shared.ignore(draftID)
        } label: {
            Text("Nie mehr vorschlagen")
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(KColor.alert)
                .frame(maxWidth: .infinity)
                .padding(13)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(KColor.surface))
        }
        .buttonStyle(.plain)
        .padding(.top, 18)
        .accessibilityIdentifier("bankFormIgnore")
    }
}
