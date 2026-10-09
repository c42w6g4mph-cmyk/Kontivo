# Geteilte Änderungen – Bereich contracts (Swift-Nachzug auf Web v141)

## Kontivo/App/Routing.swift
- `AppSheet`: neuer Fall `case completeness(only: UUID?)` (id `vk-<uuid|alle>`), `kind` → neuer `AppSheetKind.completeness`.
- Warum: Hinweis «n Angaben fehlen noch … Ergänzen ›» im Vertragsdetail öffnet die Vollständigkeit nur für diesen Vertrag
  (Web `openVk(idv)`). Falls der Bereich core die Route schon anders angelegt hat (z.B. als `ManageRoute`), den Aufruf in
  `Contracts/ContractDetailParts.swift` (`CTDetailCompletenessHint`) umstellen und diesen Fall entfernen.

## Kontivo/App/RootView.swift
- `AppSheetView.content`: Fall `.completeness` zeigt vorläufig `ManageView(start: .quality)` (Rückfall Datenqualität).
- Integrator: durch die Vollständigkeit-Ansicht des Bereichs core ersetzen (z.B. `CompletenessView(only: only)`).

## Lokale Hilfen mit TODO (statt Kern), zum Umstellen durch den Integrator
- `Contracts/ContractsLocalCalc.swift`:
  - `CTLocalCalc.payRule(due:cycle:)` → `Calc.payRule` (core)
  - `CTLocalCalc.pctText`, Preisverlauf-Zusammenfassung in `CTPriceChartModel` → Kernfunktion (core), falls vorhanden
  - `CTLocalCalc.paidSoFar` (Summe in Vertragswährung; `Calc.paidSoFar` rechnet in Hauptwährung)
  - `CTCompletenessLocal.needs/hint` (Web `vkNeeds(id)`/`vkHintHtml`) → `Completeness` (core); `settings.logoSkip` fehlt hier noch
- Danach `ContractsLocalCalc.swift` löschen.

## UI-Tests ausserhalb des Bereichs
- `KontivoUITests/CostsBudgetUITests.swift` (`testAufteilungDetailUndFormular`): «Bisher bezahlt» → «insgesamt bezahlt»
  (Detail-Kennzahlen ersetzen die Zeile, Web v95).
- `KontivoUITests/ContractFlowUITests.swift`: Aktionen über das Menü ••• (`detail.menu`) statt «Weitere Aktionen»/Leiste.
