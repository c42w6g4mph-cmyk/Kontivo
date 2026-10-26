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
    /// Einnahme ansehen (Web v155 `openIncDetail`): Kacheln, Verlauf, Angaben, Bearbeiten, Menü Duplizieren/Löschen
    case incomeDetail(UUID)
    /// Fenster «Alle Einnahmen»
    /// Variable Kosten erfassen (nil) oder bearbeiten (Web v227 `openVar`)
    case variableForm(UUID?)
    /// Variable Kosten ansehen (Web v227 `openVarDetail`): Kacheln, Angaben, Bearbeiten, Menü Duplizieren/Löschen
    case variableDetail(UUID)
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
    /// Kontoauszug einlesen: Ladeanzeige und Vorschläge eines Imports (Bereich onb, `BankImportCenter`)
    case bankImport(UUID)
    /// Vollständigkeit (Web `openVk(only)`): nil = alle Verträge, sonst nur dieser (Bereich core)
    case completeness(only: UUID?)
    /// Fixkosten-Bericht: Auswahl Person/Nummern vor dem PDF (Web v220 `openRepOpts`, Bereich costs); aus «Kosten» mit dessen Personenfilter, aus «Mehr» mit der letzten Auswahl
    case fixReport(person: UUID?, fromCosts: Bool)
    /// Rückfrage «Gekündigt am» / «Läuft bis» beim Markieren als gekündigt (Web v249 `askCancelled`)
    case cancelledAsk(CancelledAsk)

    var id: String {
        switch self {
        case .contractDetail(let u): return "detail-\(u)"
        case .contractForm(let c): return "form-\(c.idPart)"
        case .incomeForm(let u): return "income-\(u?.uuidString ?? "neu")"
        case .incomeDetail(let u): return "incdetail-\(u)"
        case .variableForm(let u): return "var-\(u?.uuidString ?? "neu")"
        case .variableDetail(let u): return "vardetail-\(u)"
        case .letter(let u, let t): return "letter-\(u)-\(t)"
        case .cancelChannelPick(let u, let t): return "cvia-\(u)-\(t)"
        case .mail(let m): return "mail-\(m.id)"
        case .document(let d): return "doc-\(d.id)"
        case .manage(let r): return "manage-\(r.idPart)"
        case .bankImport(let u): return "bank-\(u)"
        case .completeness(let u): return "vk-\(u?.uuidString ?? "")"
        case .fixReport: return "fixreport"
        case .cancelledAsk(let a): return "cxl-\(a.contractID)"
        }
    }

    /// Fenstertyp (für den Schutz vor Doppel-Präsentation in `AppModel.present`)
    var kind: AppSheetKind {
        switch self {
        case .contractDetail: return .contractDetail
        case .contractForm: return .contractForm
        case .incomeForm: return .incomeForm
        case .incomeDetail: return .incomeDetail
        case .variableForm: return .variableForm
        case .variableDetail: return .variableDetail
        case .letter: return .letter
        case .cancelChannelPick: return .cancelChannelPick
        case .mail: return .mail
        case .document: return .document
        case .manage: return .manage
        case .bankImport: return .bankImport
        case .completeness: return .completeness
        case .fixReport: return .fixReport
        case .cancelledAsk: return .cancelledAsk
        }
    }
}

enum AppSheetKind: Hashable {
    case contractDetail, contractForm, incomeForm, incomeDetail, letter, cancelChannelPick, mail, document, manage, bankImport, completeness
    case fixReport, cancelledAsk
    case variableForm, variableDetail

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
    /// Vorschlag aus dem Kontoauszug (Bereich import, Web v181 `bkOpenForm`): Titel «Vorschlag», «Sichern» schreibt nicht in die Daten,
    /// sondern über `BankFormBridge.contractDone` zurück in den Vorschlag; unten «Nie mehr vorschlagen»
    case bankSuggestion(BankFormDraft)

    var idPart: String {
        switch self {
        case .new: return "neu"
        case .edit(let u): return "edit-\(u)"
        case .duplicate(let u): return "dup-\(u)"
        case .newProvider(let c): return "np-\(c.id)"
        case .bankSuggestion(let b): return "bank-\(b.id)"
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
    /// Ablauf «Vollständigkeit» (Web `openVk(only)`): nil = alle Verträge (Start mit Ring), sonst nur dieser Vertrag
    /// (Hinweis «Angaben fehlen → Ergänzen» im Detail). Eigenes Fenster mit eigener Navigation.
    case completeness(only: UUID?)

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
        case .completeness(let u): return "vk-\(u?.uuidString ?? "")"
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
