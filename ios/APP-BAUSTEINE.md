# App-Bausteine (für alle Bereiche)

Kurzreferenz des App-Grundgerüsts in `ios/Kontivo/App` und `ios/Kontivo/Design`. Diese Dateien gehören allen; Bereiche ändern sie nicht, sondern melden Wünsche.

## AppModel (`@Environment(AppModel.self) private var model`)
- `model.data: AppData` – alle Daten (nur lesen in Ansichten)
- `model.calc: Calc` – Rechenkern mit heutigem Datum; `model.today: Day`
- `model.update { d in try d.saveContract(...) }` – jede Änderung; speichert automatisch, zeigt `MutationError.message` als Toast; gibt Bool zurück
- `model.toast("…")` – wird VoiceOver vorgelesen; ein Speicherfehler bleibt 5 s stehen (andere Toasts in dieser Zeit werden verworfen)
- `model.today` ist beobachtbar (Tageswechsel beim Aktivieren und um Mitternacht); Tests setzen `todayOverride`
- Fenster: `model.present(.contractDetail(id))`, `.contractForm(.new(prefill: nil))`, `.contractForm(.edit(id))`, `.contractForm(.duplicate(id))`, `.contractForm(.newProvider(draft))`, `.incomeForm(nil|id)`, `.incomesAll`, `.letter(id, trial:)`, `.cancelChannelPick(id, trial:)`, `.mail(MailDraft)`, `.document(DocumentRef)`, `.manage(.overview|.partners|.partner(id)|.persons|.person(id)|.sender(id)|.assign(personFilter:)|.categories|.quality)`
- `model.dismissTop()`, `model.dismissAll()`, `model.goTab(.contracts|.costs|.budget|.deadlines|.more)`
- **Fensterwechsel ohne feste Wartezeiten (neu):** Nach `dismissTop/dismissAll/dismiss(level:)` merkt sich das Modell «Schliessen läuft», bis SwiftUI das Schliessen meldet (`onDismiss` in `SheetLevel` bzw. an der Einführung; Sicherheitsnetz 1.5 s).
  - `model.present(x)` während eines laufenden Schliessens wird automatisch danach ausgeführt. Ausserdem öffnet `present` denselben Fenstertyp nicht zweimal direkt übereinander (Mail, Dokument, Brief, Formular, Kündigungsweg … – Doppeltippen); nur Vertragsdetail und Verwalten dürfen übereinander liegen.
  - `model.presentAfterDismiss(x)` – Fenster öffnen, sobald das Schliessen fertig ist (sofort, wenn nichts schliesst)
  - `model.afterDismiss { … }` – beliebige Aktion danach (z.B. `cancelQuestion` setzen, Link öffnen, Dateiauswahl)
  - `model.dismissAll(then: { … })`, `model.dismissTop(then: { … })` – Kurzform
  - `model.closeOnboarding(then: { … })` – Einführung schliessen und danach z.B. ein Formular öffnen
  - Ersetzt `dismissAll(); Task.sleep(…); present(…)`. Beispiel: `model.dismissAll(); model.presentAfterDismiss(.contractForm(.edit(id)))`
- **Rückfrage (neu):** `model.ask(title:message:ok:destructive:cancel:onCancel:action:)` – Alert mit OK- und Abbrechen-Knopf auf der obersten Ebene (wie «Gekündigt?»), erscheint erst nach einem laufenden Schliessen. Ersetzt UIKit-Rückfragen wie `CancelFlowUI.ask` (Aufruf 1:1: `model.ask(title: t, message: m, ok: o) { … }`). Die Aktion läuft nach dem Schliessen des Alerts.
- Gemeinsamer Zustand: `costFilter` (Kategorie/Vertragspartner/Person für Verträge-Liste und Kosten), `selectedYear`, `selectedMonth` (1–12, Kosten und Budget), `budgetPerson`, `searchText`, `heroFilter`, `showArchive`
- Kündigung: `model.startCancel(id, trial:)` (Bereich Kündigung), `pendingCancel`, `cancelQuestion` (Alert «Gekündigt?» zeigt das Grundgerüst auf der obersten Ebene)
- Einführung: `model.onboarding = .firstRun | .tour` öffnen; schliessen mit `model.closeOnboarding(then:)`
- Kündigung/Viewer: Fensterwechsel gebündelt in `Cancel/CancelWindowFlow.swift` (`isTop`, `dismiss(ifTop:)`, `present(over:)`, `afterDismiss` mit Zustandsprüfung über die Warteschlange des Modells, `ask` → `model.ask`)
- Dateien: `model.image(id) -> UIImage?`, `model.storeFile(data, type:) -> String?`, `model.files` (FileStore: `data(id)`, `type(id)`, `put`, `delete`, `has`, `allIDs`, `deleteAll`, `url(id)`)
  - Verwaiste Dateien (von keinem Vertrag, keiner Einnahme, keinem Vertragspartner/keiner Person referenziert, älter als 7 Tage) werden einmal pro Tag nach dem Start gelöscht (`files.collectGarbage(keeping:)`).
- Speichern sofort: `model.saveNow()` – gibt `false` zurück, wenn nicht gespeichert wurde (Fehler oder gesperrt); dann keine Erfolgsmeldung zeigen
- Sicheres Laden: defekte `data.json` wird als `data.broken-<Zeit>.json` beiseitegelegt, beim Speichern bleibt `data.prev.json` als Vorversion (Rückfall beim Laden). Bis der Nutzer die Meldung bestätigt, ist Speichern gesperrt (`model.saveBlocked`).
- UI-Test-Modus (`-uiDemo`, `-uiEmpty`, `-uiOnboarding`): eigener Dateiordner (tmp/KontivoUITest), Kosten/Budget auf dem Monat des Stichtags

## Fenster
Fenster werden gestapelt: Ein Fenster kann über `model.present` weitere öffnen (z.B. Detail → Formular). Jedes Fenster bringt seine eigene `NavigationStack` mit (Titel, Toolbar). Schliessen über `@Environment(\.dismiss)` oder `model.dismissTop()`. Toast, «Gekündigt?» und `model.ask` erscheinen automatisch auf der obersten Ebene.
Bereichsinterne Auswahllisten öffnet die Ansicht selbst mit `.sheet` / `.confirmationDialog` / `.alert`.

## Design (`Design/Theme.swift`, `Design/Components.swift`)
- Farben `KColor.paper, surface, sunken, field, ink, ink2, ink3, line, teal, ok, warn, alert` (hell/dunkel automatisch), `Color(hex:)`
- `KIcon.symbol(forKey:)`, `KIcon.symbol(for: KCategory?)` – SF Symbol zu Kategorie/Einnahmenart
- `KMetric.radius (13)`, `gutter (16)`, `maxContent (600)`; `.kContentWidth()`, `.kPageBackground()`
- `MarkView(contract:data:size:)`, `MarkView(income:)`, `MarkView(category:)`, `PersonAvatar(person:size:)`
- `.kKeyboardDone()` – «Fertig» über der (Ziffern-)Tastatur (früher `CTKeyboardDone`, bleibt als Alias)
- `MoneyText(amount:currency:)`, `KCard { … }`, `SectionHead(title:trailing:)`, `Chip(title:isOn:action:)`, `Pill(text:tone:)`, `EmptyHero(symbol:title:text:hooks:buttonTitle:action:footer:)`, `CloseButton()`
- **Wichtig:** `Category` ist wegen UIKit/ObjectiveC mehrdeutig → immer `KCategory` (= `KontivoCore.Category`).

## Gemeinsame Bausteine anderer Bereiche (Signaturen fest, siehe `Shared/`)
- `DocumentViewer(ref:)`, `AddressSearch.find(name:domain:currency:)`, `AddressPickSheet(candidates:onPick:)`, `SignaturePadSheet(title:onDone:)`, `SignatureSuggestionsSheet(first:last:onPick:)` – Bereich Fristen/Kündigung
- `LogoSearchSheet(name:currency:web:onPick:)`, `ImageCropSheet(image:title:onDone:)` – Bereich Verwalten
- `RateService.refreshIfNeeded(model, force:)` – Bereich Mehr
- `NetCheck.isOnline()`, `WebLinks.googleImages(…)` (LogoSearchSheet), `ImageImport` (ImageCropSheet: Fotos/Dateien/Einfügen, Verkleinerung auf 1600 px)

## Gemeinsame Kern-Hilfen
- `Format.parseNum` – einziger Zahlenleser für alle Eingaben (wie Web `parseNum`)
- `Format.noticeValue(_:unit:)` – Kündigungsfrist prüfen (wie Web `noticeVal`); `CTNumber.noticeValue` und `AppData.mdNoticeValue` leiten darauf um
- `AppData.sharedEntryCount(a, b)` – gemeinsame Einträge (Hinweis «Alle übertragen»)
- `Partners.find` (nur gleicher Name), `Partners.similar` (Hinweis)
- Fachaktionen der Verwalten-Editoren: `ExtManage.swift` (`mdSet…`, `mdCheckNotice` …)

## Regeln
- iOS 17 APIs (neuere nur mit `if #available`), Swift 5, keine Fremdbibliotheken.
- Texte wörtlich wie die Web-App (siehe `docs/inventar/`), Schweizer Rechtschreibung, «Vertragspartner».
- Zahlen über `Format.money` usw. (de-CH «1’284.50»), Daten über `Format.fmtD`, `fmtShort`.
- iPhone zuerst; auf dem iPad Inhalt mittig mit max. 600 pt (`.kContentWidth()`).
- Bedienhilfen: sinnvolle `accessibilityLabel`, Dynamic Type nicht brechen.
