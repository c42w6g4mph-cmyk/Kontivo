# Kontivo iOS – Architektur (verbindlich für den Nachbau)

Ziel: Die Web-App (index.html im Repo-Wurzelordner) 1:1 als SwiftUI-App nachbauen, ohne Funktionsverlust.
Quelle der Wahrheit für Verhalten und Texte: die Web-App selbst und die Inventare in `ios/docs/inventar/` (pro Bereich, alle Texte wörtlich).
Wo die Inventare einen «⚠ Fund» oder «Befund» nennen, gilt das **korrigierte** Verhalten (die Web-App wurde am 03.10.2026 entsprechend korrigiert; im Zweifel den aktuellen Code in index.html lesen).

## Rahmen
- iOS 17.0+, iPhone zuerst, iPad mitgedacht (gleiche Ansichten, max. Inhaltsbreite ~600 pt zentriert).
- Swift 5 Sprachmodus (`SWIFT_VERSION = 5.0`), SwiftUI, Observation (`@Observable`), Swift Charts, PDFKit, PencilKit, MessageUI, EventKitUI.
- Keine Fremdbibliotheken.
- Sprache Deutsch, Schweizer Rechtschreibung (ss statt ß), immer «Vertragspartner», nie «Partner» in sichtbaren Texten.
- Zahlenformat fest de-CH: `1’284.50` (Tausender U+2019, Dezimalpunkt), auch für EUR. Minuszeichen U+2212 in Anzeigen.
- Daten lokal auf dem Gerät (JSON-Datei + Dateien-Ordner). iCloud später.

## Ordner
```
ios/
  project.yml                 XcodeGen-Projekt (App + Tests), erzeugt Kontivo.xcodeproj
  KontivoCore/                Swift Package, nur Foundation (läuft mit `swift test` auch auf dem Mac ohne Simulator)
    Package.swift
    Sources/KontivoCore/
      Day.swift               Kalenderdatum ohne Uhrzeit
      Models.swift            Datenmodell (unten)
      Calc.swift              Rechenkern (1:1 zur Web-App, golden-getestet)
      Format.swift            Zahlen, Daten, Texte (money, fmtD, fmtShort, inDays, humanDays, noticeText, CYCLE, TERMS)
      Quality.swift           Datenqualität (qualItems)
      Letter.swift            Kündigungsschreiben: Textbausteine (letterParts), isRent, Unterzeichner
      Catalog.swift + Resources/catalog.json   Anbieterkatalog TPL + STD_RULES + stdFor
      WebImport.swift         Web-Backup (JSON der Web-App) → AppData
      Backup.swift            Natives Backup (Export/Import)
      CSV.swift               CSV-Export/-Import
      Partners.swift          pkey, Gruppen, Dubletten
      Mutations.swift         Fachaktionen auf AppData (kündigen, behalten, pausieren, duplizieren, umbenennen, zusammenführen …)
    Tests/KontivoCoreTests/   golden-Tests (Resources: cases.json, golden.json aus ../../tests/)
  Kontivo/                    App-Target
    App/                      KontivoApp, AppModel (@Observable, Laden/Speichern), RootView (TabView)
    Design/                   Farben, Schriften, wiederverwendbare Bausteine (Mark/Logo, Karten, Chips, Segment, Leerzustand)
    Contracts/                Verträge-Tab, Detail, Formular, Weitere Angaben
    Costs/                    Kosten-Tab (Monatsdiagramm, Filter, Liste)
    Budget/                   Budget-Tab, Einnahmen-Formular, Alle Einnahmen
    Deadlines/                Fristen-Tab, Behalten/Kündigen, Kalender (EventKitUI)
    Cancel/                   Kündigungsweg, Brief, PDF, Unterschrift, Namenszüge, Mail/Drucken
    More/                     Mehr: Darstellung, Währung, Daten (Backup/CSV), Hilfe, Rechtliches
    Manage/                   Verwalten: Vertragspartner, Inhaber (Personen), Kategorien, Datenqualität
    Onboarding/               Einführung
    Resources/                Assets.xcassets (AppIcon, Farben), Fonts/*.ttf (Namenszüge), Onboarding-Bilder
  KontivoTests/               (optional) App-Tests
  docs/inventar/              Verhaltens-Inventar der Web-App je Bereich
```

## Datenmodell (KontivoCore/Models.swift)
Alle Typen `Codable, Hashable, Identifiable, Sendable` (wo sinnvoll). IDs sind `UUID`, ausser Anhänge (String, 32 Hex wie in der Web-App, damit Backups übertragbar bleiben).

```swift
public struct Day: Hashable, Comparable, Codable, Sendable { year, month (1–12), day }   // JSON: "YYYY-MM-DD"
public enum Currency: String, Codable, CaseIterable { case CHF, EUR, USD, GBP, TRY }
public enum NoticeUnit: String, Codable { case months = "m", weeks = "w", days = "d", dayOfMonth = "k" }
public enum CancelTerm: String, Codable { case anytime = "", period = "p", monthEnd = "m", quarterEnd = "q", halfYearEnd = "h", yearEnd = "y", contractYear = "a" }
public enum CancelChannel: String, Codable, CaseIterable { case online, email, letter, registered }   // Web: «Online / Kundenkonto», «E-Mail», «Brief», «Einschreiben»
public enum CancelVia: String { case online, mail, post, none }                                   // cancVia()
public enum CategoryKind: String, Codable { housing, energy, insurance, health, telecom, media, mobility, family, leisure, taxes, finance, other }
public enum IncomeKind: String, Codable, CaseIterable { lohn, nebeneinkommen, bonus, kapitalertraege, vermietung, rente }   // Anzeige: Lohn, Nebeneinkommen, Bonus, Kapitalerträge, Vermietung, Rente

public struct PostalAddress: Codable, Hashable { company, extra, street, zip, city, country: String }   // leer = ""
public struct SenderAddress: Codable, Hashable { first, last, street, zip, city, country: String }

public struct Person { id: UUID; name: String; sender: SenderAddress; sameAddressAs: UUID?; signatureJPEG: Data?; avatarID: String? }
public struct Category { id: UUID; name: String; colorHex: String; icon: String; kind: CategoryKind? }   // kind = Standardkategorie (Fachregeln: taxes → keine Frist, insurance → Brief, housing → Miete); bleibt beim Umbenennen
public struct Partner { id: UUID; name: String; web: String; logoID: String?; logoBg: String?; address: PostalAddress }

public struct PriceChange { from: Day; amount: Double }
public struct ExtraPayment { id: UUID; date: Day; amount: Double; note: String }   // Gutschrift negativ
public struct Pause { from: Day; until: Day? }                                     // [from, until) ohne Zahlungen; until nil = offen
public struct Attachment { id: String; name: String; type: String }               // Datei in Files/<id>

public struct Contract {
  id: UUID; label: String; partnerID: UUID?; categoryID: UUID?
  amount: Double; currency: Currency; cycle: Int            // Monate: 1,2,3,6,12,24; 0 = einmalig
  due: Day?; start: Day?; end: Day?
  notice: Int; noticeUnit: NoticeUnit; renewMonths: Int; cancelTerm: CancelTerm
  mandatory: Bool; noWatch: Bool; isRent: Bool?             // isRent nil = Heuristik (Letter.isRentHeuristic)
  customerNo, contractNo: String; holderIDs: [UUID]
  payMethod, payAccount: String; cancelChannel: CancelChannel?; cancelURL: String
  trial: Day?; trialKept: Day?
  tel, mail, note: String; colorHex: String?; logoID: String?; logoBg: String?   // logoID nur ohne Vertragspartner; sonst Partner.logoID
  prices: [PriceChange]; documents: [Attachment]; extras: [ExtraPayment]
  status: ContractStatus (.active/.cancelled = «ins Archiv»); cancelledAt: Day?
  cancelPer: Day?; cancelledOn: Day?; keptFor: Day?; pauses: [Pause]
  createdAt: Date
}
public struct Income { id: UUID; name, label: String; kind: IncomeKind; amount: Double; currency: Currency; cycle: Int; due, start, end: Day?
  holderID: UUID?  /* genau ein Empfänger */; prices: [PriceChange]; note: String; logoID: String?; logoBg: String?; colorHex: String?; createdAt: Date }

public struct Settings { homeCurrency: Currency; rates: [String: Double] /* CHF pro Einheit, Schlüssel EUR/USD/GBP/TRY */; rateDate: Day?; rateChecked: Day?; rateSource: String
  theme: Theme (.auto/.light/.dark); sort: ContractSort (.due,.cost,.partner,.category,.holder); onboarded: Int; lastHolderIDs: [UUID]
  qualityIgnored: [String]; lastReview: Day?; reviewSnooze: Day?; dataVersion: Int }

public struct AppData { settings; persons: [Person]; categories: [Category] /* Reihenfolge = Anzeige */; partners: [Partner]; contracts: [Contract]; incomes: [Income] }
```
Reihenfolgen sind Arrays (Einfügereihenfolge wie `Object.keys` in der Web-App).

## Rechenkern (Calc.swift)
`public struct Calc { public let data: AppData; public let today: Day }` mit den Funktionen der Web-App unter gleichem Namen (Swift-Stil): `priceAt`, `curPrice`, `monthlyCost` (in Hauptwährung), `conv`, `occurrences(from:to:)`, `payments`, `nextDue`, `limit`, `effEnd`, `noticeDeadline(for:end:)` (= nDl), `nextTerm(base:after:)`, `termEnd`, `renewAfter`, `renewTo`, `isTax`, `noticeDeadline`, `urgency`, `isPaused`, `notStarted`, `endedByNotice`, `endedByTerm`, `isEnded`, `isKept`, `isAnytime`, `needsAction`, `trialNeeds`, `holderShare`, `cancVia`, sowie Listen `active`, `running`, `archived`.
Exakt wie index.html Zeilen «Rechnen» (inkl. Korrekturen vom 03.10.2026: Monatsletzter-Regel addMonthsE, nDl auf Monatsende, isAnytime nur bei monatlicher Periode, endedByTerm, Vertragsjahr ab 29.02.).
Pausen: mehrere `Pause`-Einträge; `occurrences` überspringt Termine in jeder Pause; `isPaused` = eine Pause mit `from <= heute < until` (oder `until == nil`).
Prüfung: `Tests/KontivoCoreTests/GoldenTests.swift` lädt `cases.json` + `golden.json`, wandelt jeden Fall über `WebImport` in einen `Contract`, rechnet mit fixem Stichtag und vergleicht jedes Feld.

## Web-Backup übernehmen (WebImport.swift)
Eingabe: Backup-Datei der Web-App (`{app:"vertraege", version, exported, settings, contracts, incomes, files}`), siehe Inventar 6, Abschnitt 2.
- Personen: alle Namen aus `settings.holders`, aus `holders[]` aller Verträge/Einnahmen und aus den Schlüsseln von `senders/sigs/avatars` (in dieser Reihenfolge, ohne Doppel). `senders[name]` → `sender`, `same` → `sameAddressAs`, `sigs[name]` (Data-URL) → JPEG-Daten, `avatars[name]` → `avatarID`.
- Kategorien: `settings.catList` (oder Standardliste + altes `cats`), plus unbekannte Kategorienamen aus Verträgen (Farbe Standard, Symbol «tag»). `kind` aus dem Standardnamen (Wohnen→housing … Sonstiges→other), für eigene nil. Einnahmen-Arten → `IncomeKind`.
- Vertragspartner: Gruppen nach `pkey(partner)` (wie Web); Name = erster Name der Gruppe; `web`, Logo (`logoId`, `logoBg`) und Adresse (`addr` mehrzeilig → `PostalAddress` wie `addrSplit`) aus dem ersten Vertrag, der das Feld hat.
- Verträge: Felder 1:1; `cancF`-Text → `CancelChannel`; `paused/pausedAt/pausedUntil` → `pauses` (from = pausedAt oder Importtag); `t` (ms) → `createdAt`.
- Migrationen der Web-App (migModel/migCats, Inventar 6 Abschnitt 7) vor der Umwandlung anwenden (alte Felder `rate`, `holder`, `sender`, `senderF`, `sig`, alte Kategorienamen nur bei fehlender `dataVer`).
- Dateien: `files[id] = {type, data(Base64)}` → Datei mit derselben ID.

## App-Zustand
`@Observable final class AppModel` (App-Target): hält `AppData`, speichert nach jeder Änderung (entprellt) als JSON in `Application Support/Kontivo/data.json`, Dateien in `Application Support/Kontivo/Files/<id>`. `calc` liefert `Calc(data:today:)`. Alle Änderungen laufen über Methoden, die `Mutations` aus dem Kern aufrufen (Ansichten ändern `data` nie direkt an mehreren Stellen).
Formulare bearbeiten eine Kopie (`Contract`) und übernehmen beim Sichern nur die Formularfelder (nie Status-Felder überschreiben).

## Web → iOS (bewusste Ersetzungen)
| Web | iOS |
|---|---|
| Bottom-Sheets, eigener Navigationsstapel | `.sheet` mit `NavigationStack` |
| `ask()` Rückfrage | `.confirmationDialog` / `.alert` |
| Toast | kleines Overlay unten (eigene `ToastCenter`) |
| Teilen-Menü für PDF | eigene Knöpfe: Mail mit Anhang (`MFMailComposeViewController`), Drucken (`UIPrintInteractionController`), Teilen (`ShareLink`) |
| mailto | `MFMailComposeViewController`, Rückfall `mailto:` |
| visibilitychange-Rückfrage «Gekündigt?» | `scenePhase` → `.active` |
| eigener PDF-Schreiber | `UIGraphicsPDFRenderer` (A4, gleiche Masse wie Inventar 3) |
| Canvas-Unterschrift | `PKCanvasView` |
| Namenszug-Schriften | Fonts im Bundle (`UIAppFonts`), gleiche 6 Schriften |
| pdf.js-Vorschau | `PDFKit.PDFView` |
| Kalender (Web entfernt) | `EKEventEditViewController` auf den Fristen-Karten (siehe kontivo-technik «Für die native Version vorgemerkt») |
| langes Drücken Pop-up | `.contextMenu` mit Vorschau |
| Monatswechsel Wischen | `DragGesture` / paging `TabView` |
| Service Worker, Manifest | entfällt |
