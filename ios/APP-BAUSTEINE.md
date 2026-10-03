# App-Bausteine (für alle Bereiche)

Kurzreferenz des App-Grundgerüsts in `ios/Kontivo/App` und `ios/Kontivo/Design`. Diese Dateien gehören allen; Bereiche ändern sie nicht, sondern melden Wünsche.

## AppModel (`@Environment(AppModel.self) private var model`)
- `model.data: AppData` – alle Daten (nur lesen in Ansichten)
- `model.calc: Calc` – Rechenkern mit heutigem Datum; `model.today: Day`
- `model.update { d in try d.saveContract(...) }` – jede Änderung; speichert automatisch, zeigt `MutationError.message` als Toast; gibt Bool zurück
- `model.toast("…")`
- Fenster: `model.present(.contractDetail(id))`, `.contractForm(.new(prefill: nil))`, `.contractForm(.edit(id))`, `.contractForm(.duplicate(id))`, `.contractForm(.newProvider(draft))`, `.incomeForm(nil|id)`, `.incomesAll`, `.letter(id, trial:)`, `.cancelChannelPick(id, trial:)`, `.mail(MailDraft)`, `.document(DocumentRef)`, `.manage(.overview|.partners|.partner(id)|.persons|.person(id)|.sender(id)|.assign(personFilter:)|.categories|.quality)`
- `model.dismissTop()`, `model.dismissAll()`, `model.goTab(.contracts|.costs|.budget|.deadlines|.more)`
- Gemeinsamer Zustand: `costFilter` (Kategorie/Vertragspartner/Person für Verträge-Liste und Kosten), `selectedYear`, `selectedMonth` (1–12, Kosten und Budget), `budgetPerson`, `searchText`, `heroFilter`, `showArchive`
- Kündigung: `model.startCancel(id, trial:)` (Bereich Kündigung), `pendingCancel`, `cancelQuestion` (Alert «Gekündigt?» zeigt das Grundgerüst auf der obersten Ebene)
- Einführung: `model.onboarding = .firstRun | .tour`
- Dateien: `model.image(id) -> UIImage?`, `model.storeFile(data, type:) -> String?`, `model.files` (FileStore: `data(id)`, `type(id)`, `put`, `delete`, `has`, `allIDs`, `deleteAll`, `url(id)`)
- Speichern sofort: `model.saveNow()`

## Fenster
Fenster werden gestapelt: Ein Fenster kann über `model.present` weitere öffnen (z.B. Detail → Formular). Jedes Fenster bringt seine eigene `NavigationStack` mit (Titel, Toolbar). Schliessen über `@Environment(\.dismiss)` oder `model.dismissTop()`. Toast und «Gekündigt?» erscheinen automatisch auf der obersten Ebene.
Bereichsinterne Auswahllisten öffnet die Ansicht selbst mit `.sheet` / `.confirmationDialog` / `.alert`.

## Design (`Design/Theme.swift`, `Design/Components.swift`)
- Farben `KColor.paper, surface, sunken, field, ink, ink2, ink3, line, teal, ok, warn, alert` (hell/dunkel automatisch), `Color(hex:)`
- `KIcon.symbol(forKey:)`, `KIcon.symbol(for: KCategory?)` – SF Symbol zu Kategorie/Einnahmenart
- `KMetric.radius (13)`, `gutter (16)`, `maxContent (600)`; `.kContentWidth()`, `.kPageBackground()`
- `MarkView(contract:data:size:)`, `MarkView(income:)`, `MarkView(category:)`, `PersonAvatar(person:size:)`
- `MoneyText(amount:currency:)`, `KCard { … }`, `SectionHead(title:trailing:)`, `Chip(title:isOn:action:)`, `Pill(text:tone:)`, `EmptyHero(symbol:title:text:hooks:buttonTitle:action:footer:)`, `CloseButton()`
- **Wichtig:** `Category` ist wegen UIKit/ObjectiveC mehrdeutig → immer `KCategory` (= `KontivoCore.Category`).

## Gemeinsame Bausteine anderer Bereiche (Signaturen fest, siehe `Shared/`)
- `DocumentViewer(ref:)`, `AddressSearch.find(name:domain:currency:)`, `AddressPickSheet(candidates:onPick:)`, `SignaturePadSheet(title:onDone:)`, `SignatureSuggestionsSheet(first:last:onPick:)` – Bereich Fristen/Kündigung
- `LogoSearchSheet(name:currency:web:onPick:)`, `ImageCropSheet(image:title:onDone:)` – Bereich Verwalten
- `RateService.refreshIfNeeded(model, force:)` – Bereich Mehr

## Regeln
- iOS 17 APIs (neuere nur mit `if #available`), Swift 5, keine Fremdbibliotheken.
- Texte wörtlich wie die Web-App (siehe `docs/inventar/`), Schweizer Rechtschreibung, «Vertragspartner».
- Zahlen über `Format.money` usw. (de-CH «1’284.50»), Daten über `Format.fmtD`, `fmtShort`.
- iPhone zuerst; auf dem iPad Inhalt mittig mit max. 600 pt (`.kContentWidth()`).
- Bedienhilfen: sinnvolle `accessibilityLabel`, Dynamic Type nicht brechen.
