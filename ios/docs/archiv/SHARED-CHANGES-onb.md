# Geteilte Änderungen – Bereich onb (Intro, Einführung, Plus-Menü, Kontoauszug-Import)

## App/Routing.swift
- `AppSheet.bankImport(UUID)` – Fenster «Kontoauszug»/«Vorschläge» eines Imports (`BankImportCenter`-Sitzung). id `bank-<uuid>`, Art `.bankImport`.
- `AppSheet.completeness(only: UUID?)` – Vollständigkeit (Web `openVk(only)`), aufgerufen nach dem Import («Fast fertig!» → «Jetzt vervollständigen»). id `vk-<uuid|leer>`, Art `.completeness`.
  Falls core denselben Fall schon angelegt hat: den von core nehmen (gleiche Signatur `only: UUID?` erwartet).
- `AppSheetKind`: `.bankImport`, `.completeness` (beide `singleOnTop`).

## App/RootView.swift
- `@State private var splash = SplashView.enabled` und `.overlay { if splash { SplashView { splash = false } } }` am TabView sowie an `OnboardingView` im fullScreenCover (Intro beim Kaltstart, auch über der Einführung; beide Kopien laufen zeitgleich, siehe SplashView).
- `AppSheetView`: `.bankImport(id)` → `BankImportSheet(sessionID:)` (`interactiveDismissDisabled`), `.completeness(only)` → `CompletenessPlaceholder(only:)`.
  **Integrator:** Platzhalter durch die Vollständigkeit-Ansicht von core ersetzen und `Import/CompletenessPlaceholder.swift` löschen.

## App/UITestHooks.swift
- Startargument `-uiBankSample` (mit `-uiEmpty`/`-uiDemo`): startet nach 0.8 s `BankImportCenter.start(.data(BankSample.csv, …))` ohne Systemauswahl.
- Startargument `-uiSplash`: Intro auch im UI-Test (sonst in UI-Tests aus, `SplashView.enabled`).

## Contracts/ContractsTab.swift (Bereich contracts)
- Nur der Plus-Knopf in der Toolbar: statt `Button` → `AddMenuButton()` (Import/AddMenu.swift). Accessibility-Label jetzt «Hinzufügen» (Web `aria-label`).

## KontivoUITests/ContractFlowUITests.swift
- Zwei Aufrufe `tapOpen(button("Vertrag anlegen"), …)` → `openPlusMenuItem("Vertrag erfassen", expect: …)` (Helfer in `AddMenuHelpers.swift`), weil Plus jetzt ein Menü öffnet.

## project.yml
- `NSCameraUsageDescription` (Kontoauszug scannen, VisionKit-Dokumentscanner) und `NSPhotoLibraryUsageDescription` (Fotos vom Auszug wählen; PHPicker bräuchte sie nicht, auf Wunsch drin).

## Abhängigkeit zum Bereich bank (KontivoCore)
- Genutzt wie vereinbart: `BankImport.read/merge/readStatementText/find/ignoreKey/toContract`, `BankFile`, `BankSuggestion`, `BankFindResult`, `BankKnown`, `BankPriceMatch`, `BankReadError`, `BankConfidence`, `BankKind`.
  `contractID` wird als `UUID(uuidString:)` gelesen. `toContract(…, persons: [])` – danach setzt onb Personen, Kategorie, Vertragspartner (gleicher Name oder neu, Website aus Katalog), Währung, Rhythmus, Fälligkeit selbst und speichert mit `saveContract`.
- `Settings.bankIgn: [String]` und `Settings.bankAlias: [String: BankAlias]` mit `BankAlias(n:c:)` – nur in `Import/BankBridge.swift` benutzt; bei anderer Form dort anpassen.
- «Fast fertig!» zählt offene Angaben vorläufig selbst (`BankReview.incompleteCount`: kein Logo oder keine Kündigungsfrist); kann auf die Kernlogik der Vollständigkeit (core) umgestellt werden.

## Assets
- `onb-{list,stat,budget,term}.imageset/{light,dark}.png` aus Web `onb/*.webp` (v123, gleiche Grösse 714×1036).

## Doku
- `docs/inventar/6-backup-csv-einfuehrung.md` §8.2: Texte Web v135/v124/v110 nachgetragen.
