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
    /// Vollständigkeit (Web openVk), optional nur für einen Vertrag (Hinweis «Angaben fehlen → Ergänzen» im Detail)
    case completeness(only: UUID?)

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
        case .completeness(let only): return "vk-\(only?.uuidString ?? "alle")"
        }
    }

    /// Fenstertyp (für den Schutz vor Doppel-Präsentation in `AppModel.present`)
    var kind: AppSheetKind {
        switch self {
        case .contractDetail: return .contractDetail
        case .contractForm: return .contractForm
        case .incomeForm: return .incomeForm
        case .incomesAll: return .incomesAll
        case .letter: return .letter
        case .cancelChannelPick: return .cancelChannelPick
        case .mail: return .mail
        case .document: return .document
        case .manage: return .manage
        case .completeness: return .completeness
        }
    }
}

enum AppSheetKind: Hashable {
    case contractDetail, contractForm, incomeForm, incomesAll, letter, cancelChannelPick, mail, document, manage, completeness

    /// Darf nicht zweimal direkt übereinander liegen (Doppeltippen öffnet sonst z.B. zwei Mail-Fenster).
    /// Vertragsdetail und Verwalten dürfen übereinander liegen (z.B. Vertragspartner → anderer Vertrag).
    var singleOnTop: Bool {
        switch self {
        case .contractDetail, .manage: return false
        default: return true
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
    /// Direkt in eine Liste der Datenqualität (Web `openMdAt({k:"qlist"})`), z.B. «Kündigungsfrist und Laufzeit» aus «Fristen»
    case qualityList(QualityGroup, field: String, title: String)

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
        case .qualityList(let g, let f, _): return "ql-\(g.rawValue)-\(f)"
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
