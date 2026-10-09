# Geteilte Änderungen – Bereich contracts (Swift-Nachzug auf Web v141)

## Kontivo/App/Routing.swift
- `AppSheet`: neuer Fall `case completeness(only: UUID?)` (id `vk-<uuid|alle>`), `kind` → neuer `AppSheetKind.completeness`.
- Warum: Hinweis «n Angaben fehlen noch … Ergänzen ›» im Vertragsdetail öffnet die Vollständigkeit nur für diesen Vertrag
  (Web `openVk(idv)`). Falls der Bereich core die Route schon anders angelegt hat (z.B. als `ManageRoute`), den Aufruf in
  `Contracts/ContractDetailParts.swift` (`CTDetailCompletenessHint`) umstellen und diesen Fall entfernen.

## Kontivo/App/RootView.swift
- `AppSheetView.content`: Fall `.completeness` zeigt vorläufig `ManageView(start: .quality)` (Rückfall Datenqualität).
- Integrator: durch die Vollständigkeit-Ansicht des Bereichs core ersetzen (z.B. `CompletenessView(only: only)`).

## Lokale Hilfen (erledigt)
- `Contracts/ContractsLocalCalc.swift` gelöscht: Hinweis im Detail über `Completeness.hint` (inkl. `settings.logoSkip`),
  `Format.pctText`, «insgesamt bezahlt» über `CTDetailKeyFigures.paidSoFar` (Vertragswährung; `Calc.paidSoFar` rechnet in Hauptwährung).

## UI-Tests ausserhalb des Bereichs
- `KontivoUITests/CostsBudgetUITests.swift` (`testAufteilungDetailUndFormular`): «Bisher bezahlt» → «insgesamt bezahlt»
  (Detail-Kennzahlen ersetzen die Zeile, Web v95).
- `KontivoUITests/ContractFlowUITests.swift`: Aktionen über das Menü ••• (`detail.menu`) statt «Weitere Aktionen»/Leiste.
