# Geteilte Änderungen – Bereich costs (Nachzug Web v162–v224)

## Geteilte / fremde Dateien (nur additiv)

| Datei | Änderung | Grund |
|---|---|---|
| `ios/Kontivo/App/Routing.swift` | `AppSheet.fixReport(person: UUID?, fromCosts: Bool)`, `id` «fixreport», `AppSheetKind.fixReport` | Fixkosten-Bericht (v220) von «Kosten» (Teilen-Symbol) und «Mehr» öffnen |
| `ios/Kontivo/App/RootView.swift` (design) | `AppSheetView`: `case .fixReport` → `FixReportOptionsSheet` | Einstieg Bericht |
| `ios/Kontivo/More/MoreTab.swift` (design) | eine Zeile `MoreReportGroup()` als erste Gruppe | Web v220: «Mehr» → Gruppe «Bericht» → «Fixkosten-Bericht» (Baustein in `Costs/FixReportSheet.swift`) |
| `ios/Kontivo/App/UITestHooks.swift` | `-uiSheet report` (Auswahl), `-uiSheet reportPDF` (fertiges PDF in der Dokumentansicht) | Bildschirmfotos/Tests Bericht |
| `.github/workflows/ios.yml` | Bildschirmfotos `c1`–`c8` (Kosten-Liste, Preistreiber, Budget-Listen, Bericht, Bericht-PDF, Einnahme bearbeiten, dunkel Budget/Preistreiber) | Vergleich Web ↔ Swift |

## Neue Kern-Dateien (KontivoCore, mit Tests `CostDriversReportTests`)

- `CostDrivers.swift`: `Calc.costDrivers(year:filter:)` (Web `ptSection`), `driverReason` (`ptReason`), `yearSum` (`ptYearSum`), `driverDeltaText`, `kbFilterValuesWithAmounts` (Filterauswahl mit Jahresbetrag und Anteil, v190).
- `FixReport.swift`: `Calc.fixReport(person:showIDs:)` (Web `repData`), `reportTerm` (`repTerm`), `reportSheetLines`, `reportTopSub`, `reportSheetSub`, `reportPriceIncrease` (vereinfachtes `skrInfo`: nur Datum/Prozent), `reportAvailable`, Texte.
- `CategoryPalette.swift`: Anzeigefarben der Kategorien (Web `catColor` mit `OLD_COL`/`CAT_OLD`/`CAT_COLOR`, v190 «kräftigere Kategoriefarben»), `AppData.categoryDisplayColor(named:)`.
- Testdaten `Tests/KontivoCoreTests/Resources/costs_demo_backup.json` (= DemoData).

## Für den Integrator

- `MarkView` (design) zeigt Kategoriefarben noch aus `Category.colorHex`/`AppData.color(of:)` (alte Werte, z.B. Versicherung #0E5A5E). Web zeigt seit v190 `catColor` → bitte `CategoryPalette.display(_:key:)` bzw. `categoryDisplayColor(named:)` dort verwenden (Pastellfläche v166 ebenfalls design).
- Kosten/Budget haben einen eigenen Seitenkopf (`KBPageHeader` + `KBPage` mit Minileiste «Kosten · 2026», Navigationsleiste ausgeblendet). Falls design einen gemeinsamen Seitenkopf baut: in `CostsTab`/`BudgetTab` ersetzen.
- `Calc.costEvolution`/`kbSplit` (alte «Aufteilung und Entwicklung») werden in der App nicht mehr benutzt (`Costs/CostsSplit.swift` entfernt); im Kern belassen (Bereich core).
