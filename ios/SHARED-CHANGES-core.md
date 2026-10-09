# Geteilte Änderungen – Bereich core (Nachzug Web v89–v141)

## Geteilte Dateien

| Datei | Änderung | Warum |
|---|---|---|
| `ios/Kontivo/App/Routing.swift` | `ManageRoute.completeness(only: UUID?)` + `idPart` «vk-…» (additiv) | Einstieg «Vollständigkeit» von überall: `model.present(.manage(.completeness(only: nil)))` (Mehr, Kontoauszug «Fast fertig!») bzw. `only: vertragsID` (Hinweis im Vertragsdetail). `ManageView` zeigt dafür `CompletenessFlowView` statt des Seitenstapels; RootView bleibt unverändert. |
| `ios/Kontivo/Design/Components.swift` | `MoneyText`: `Format.money(amount, Currency(rawValue: currency))` | Zahlenformat nach Währung (EUR «1.234,50»). |
| `KontivoCore/Models.swift` | `Settings.logoSkip: [String] = []` (Codable, fehlt in Altdaten → []), Init-Parameter mit Default am Ende; `ContractSort.holder` Texte «Person» | Vollständigkeit «Ohne Logo» (Web `settings.logoSkip`, Schlüssel = Name klein). |
| `KontivoCore/Mutations.swift` | `CatalogFillItem.cancelChannel` (optional), `applyCatalogFill` setzt ihn nur bei leerem Kündigungsweg; Texte «Diese Person gibt es schon», «Mindestens eine Person ist nötig», «→ ohne Person» | Web `vkAutoPlan` (Katalog ergänzt Kündigungsweg). |
| `KontivoCore/WebImport.swift` | `settings.logoSkip` (Objekt) → `Settings.logoSkip` | Web-Backup-Rundlauf. |
| `KontivoCore/Format.swift` | `Format.homeCurrency` (global, setzt `Calc.init`), `NumberStyle`, `numberStyle(_:)`, `money/money0(_:_ currency: Currency? = nil)`, `moneySigned(…, currency:)`, `number(…, currency:)`, `number(_:minFractionDigits:maxFractionDigits:style:)`, `pctText`, `amountInput(_:_:)` (Web `amtIn`), `parseAmount` (Web `parseAmt`), `decimalSplit` (Web `decAt`) | Zahlenformat nach Währung (26b431d). Alle alten Aufrufe kompilieren weiter (Default = Hauptwährung). |
| `KontivoCore/Calc.swift` | `Calc.init` setzt `Format.homeCurrency`; `DeadlineItemKind.keptEnd` (neuer Fall); `payRule`; Jahresvergleich mit Dezimalkomma bei EUR | siehe unten |
| `ios/KontivoUITests/MoreUITests.swift`, `OnboardingUITests.swift` | «Inhaber» → «Personen», Datenqualität über Vollständigkeit → «Alle Prüfungen im Detail» | Texte/Einstieg geändert. |

## Neue Kern-API (für andere Bereiche)

- `Calc.payRule(_ c)` / `Calc.payRule(cycle:due:)` – «monatlich am 27.», «monatlich am Monatsende», «jährlich am 1. Januar» (Detail-Zeile «Zahlung», Live-Hinweis «Zahlung am» im Formular).
- `Calc.priceChart(_ c) -> PriceChart?` (`PriceChart.swift`): Punkte mit x-Lage 0…1, `labeled`, `valueText` («gratis» bei 0), `dateText` («Anfang»), `pctText` (nil nach Gratis-Phase), `isNow/isFuture`, `todayX`, `min/maxValue`, `sinceText`, `badgeText/badgeTone` («geplant ab», «vorher gratis», «unverändert», «↑ n % teurer»), `accessibilityLabel`. Werte gegen Web v141 gemessen (WebSync141Tests). Ersetzt die Rechnung in `ContractPriceChart.swift`.
- `Completeness` (`Completeness.swift`): `report(data,today,only:,hasFile:)`, `hint(contract:…)`, `autoPlan`, Texte; Fachaktionen `AppData.saveCompletenessTerm/-Sender/setCompletenessSenderSame/skipLogo/applyCompletenessAuto`.
- App: `CompletenessHintButton(contractID:)` (Manage/CompletenessFlow.swift) – fertiger Hinweis «✨ n Angaben fehlen noch … Ergänzen ›» für das Vertragsdetail (zeigt nichts, wenn nichts fehlt).
- `CSV.via(_:)` (Web `csvVia`), CSV mit 41 Spalten.

## Für den Integrator (andere Bereiche)

- Verträge: Beträge in Vertragswährung mit Währung formatieren: `ContractCardRow` 103/123/127, `ContractDetailView` 321/394/552/557/796 (`currency` Parameter), `ContractPriceChart` (oder `Calc.priceChart` nutzen), `ContractFormView` 324/336/357 (`form.currency`), `ContractFormMore` 123/126. Eingaben: `CTNumber.parse` → `Format.parseAmount`, `CTNumber.field(v)` → `Format.amountInput(v, currency)`.
- Doku: ARCHITEKTUR.md/APP-BAUSTEINE.md «Zahlenformat fest de-CH» ist überholt → «EUR de-DE, CHF de-CH, übrige nach Hauptwährung (`Format.money(v, cur)`)»; Verwalten-Übersicht ohne «Kontaktdaten ergänzen»/«Datenqualität» (beides über Vollständigkeit).
