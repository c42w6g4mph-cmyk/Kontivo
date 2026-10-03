import SwiftUI
import KontivoCore

/// Alle bereichsübergreifenden Fenster. Jedes Fenster kann über `model.present(...)` weitere Fenster darüber öffnen.
/// Bereichsinterne Fenster (z.B. Auswahllisten) öffnen die Ansichten selbst mit `.sheet`.
enum AppSheet: Identifiable, Hashable {
    /// Vertragsdetail
    case contractDetail(UUID)
    /// Vertragsformular (neu, bearbeiten, duplizieren, neuer Anbieter nach Pflichtvertrag-Wechsel)
    case contractForm(ContractFormContext)
    /// Einnahme erfassen (nil) oder bearbeiten
    case incomeForm(UUID?)
    /// Fenster «Alle Einnahmen»
    case incomesAll
    /// Kündigungsschreiben (Brief) für einen Vertrag; trial = Kündigung des Probeabos
    case letter(UUID, trial: Bool)
    /// Auswahl des Kündigungswegs (Online / E-Mail / Brief)
    case cancelChannelPick(UUID, trial: Bool)
    /// Mail verfassen (MFMailComposeViewController)
    case mail(MailDraft)
    /// Datei ansehen (Dokument am Vertrag, PDF des Briefs)
    case document(DocumentRef)
    /// Fenster «Verwalten» mit eigener Navigation
    case manage(ManageRoute)

    var id: String {
        switch self {
        case .contractDetail(let u): return "detail-\(u)"
        case .contractForm(let c): return "form-\(c.idPart)"
        case .incomeForm(let u): return "income-\(u?.uuidString ?? "neu")"
        case .incomesAll: return "incomes"
        case .letter(let u, let t): return "letter-\(u)-\(t)"
        case .cancelChannelPick(let u, let t): return "cvia-\(u)-\(t)"
        case .mail(let m): return "mail-\(m.id)"
        case .document(let d): return "doc-\(d.id)"
        case .manage(let r): return "manage-\(r.idPart)"
        }
    }
}

enum ContractFormContext: Hashable {
    /// Neuer Vertrag, optional mit Vorbelegung (z.B. aus der Einführung: Bezeichnung + Kategorie)
    case new(prefill: Contract?)
    case edit(UUID)
    case duplicate(UUID)
    /// Pflichtvertrag gekündigt: Entwurf für den neuen Anbieter (Titel «Neuer Anbieter»)
    case newProvider(Contract)

    var idPart: String {
        switch self {
        case .new: return "neu"
        case .edit(let u): return "edit-\(u)"
        case .duplicate(let u): return "dup-\(u)"
        case .newProvider(let c): return "np-\(c.id)"
        }
    }
}

/// Einstieg in «Verwalten»
enum ManageRoute: Hashable {
    case overview
    case partners
    case partner(UUID)
    case persons
    case person(UUID)
    /// Absender und Unterschrift einer Person
    case sender(UUID)
    case assign(personFilter: UUID?)
    case categories
    case quality

    var idPart: String {
        switch self {
        case .overview: return "o"
        case .partners: return "p"
        case .partner(let u): return "p-\(u)"
        case .persons: return "h"
        case .person(let u): return "h-\(u)"
        case .sender(let u): return "hs-\(u)"
        case .assign(let u): return "ha-\(u?.uuidString ?? "")"
        case .categories: return "c"
        case .quality: return "q"
        }
    }
}

struct MailDraft: Hashable, Identifiable {
    var id = UUID()
    var to: [String]
    var subject: String
    var body: String
    /// Anhang (z.B. Kündigungs-PDF)
    var attachment: Data?
    var attachmentName: String = ""
    var attachmentType: String = "application/pdf"
    /// Nach dem Senden fragen «Gekündigt?» für diesen Vertrag
    var cancelContractID: UUID?
    var cancelTrial: Bool = false
}

struct DocumentRef: Hashable, Identifiable {
    var id = UUID()
    /// Gespeicherte Datei (FileStore) oder direkt übergebene Daten (z.B. frisch erzeugtes PDF)
    var fileID: String?
    var data: Data?
    var type: String
    var title: String
    var fileName: String
    /// Brief-PDF: zeigt die Aktionen «Text ändern», «Mail», «Drucken», «Teilen»
    var letterContractID: UUID?
    var letterTrial: Bool = false
}
