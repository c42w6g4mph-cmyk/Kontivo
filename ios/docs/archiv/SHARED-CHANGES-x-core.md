# Geteilte Änderungen – Bereich core (Nachzug Web v162–v224, Branch swift-x-core)

Stand: Web v224 (main d8933a6). Alle Kern-Änderungen sind in `ios/KontivoCore` (ohne `Bank*`). Erwartungswerte aus der
Web-App: `tests/golden.json` (erweitert um Probeabo/endsSelf, Kopf mit Filter/Status, Sonderkündigung), `tests/golden_texts.json`.

## Geänderte geteilte bzw. fremde Dateien (nur additiv bzw. minimal)

| Datei | Änderung | Grund |
|---|---|---|
| `KontivoCore/Models.swift` | `Settings.rateCheckedAt: Date?` (Codable, fehlt in Altdaten → nil) | Web v162 `settings.rateCheckedAt` |
| `KontivoCore/Models.swift` | `CancelChannel.phone` (Rohwert `"phone"`, Web-Text «Telefon»), `CancelVia.tel` (`"tel"`) | Web v210 Kündigungsweg Telefon |
| `KontivoCore/Models.swift` | `Category.standardColors`/`palette`/`editColors` = Web v224, neu `previousStandardColors`, `legacyColorMap`, `migratedColor(_:)`, `displayFallbackColor`, `displayColorHex`; `AppData.color(of:)` nutzt die Anzeigefarbe; `IncomeKind` Nebeneinkommen/Sonstiges | Web v165/v190 (kräftigere Kategoriefarben, altes Türkis) |
| `KontivoCore/Mutations.swift` | `wipeAll` behält `rateCheckedAt`; neue Verträge merken nur **eine** Person (`lastHolderIDs`), `defaultHolderIDs` nur bei genau einer gemerkten Person | Web v162, v179/v180 |
| `ios/Kontivo/Shared/RateService.swift` | Prüfregel `RatePolicy.needsFetch`, `RatePolicy.markChecked`, neu `RateService.startHourly(_:)` | Web v162 |
| `ios/Kontivo/App/AppModel.swift` | `sceneBecameActive()`: eine Zeile `RateService.startHourly(self)` | Web v162 stündlich bei offener App |
| `ios/Kontivo/Design/Components.swift` | `MarkView(category:)` nutzt `category.displayColorHex` statt `colorHex` | Web `catColor` (v190) |
| `ios/Kontivo/Contracts/ContractsShared.swift` | `CTText.cancelButton(.tel)` «Anrufen»; `ContractFormFocus.tel` | neuer Fall `CancelVia.tel` (sonst Compilerfehler), Sprungziel «Telefon» |
| `ios/Kontivo/Contracts/ContractFormTerm.swift` | `case .phone: EmptyView()` (kein Folgefeld) | neuer Fall `CancelChannel.phone` |
| `ios/Kontivo/Contracts/ContractFormParts.swift` | Segment Kündigungsweg mit 4. Knopf «Telefon» (`cancelWay.phone`) | Web v210 `#fCancT` |
| `ios/Kontivo/Contracts/ContractFormModel.swift` | Zusammenfassung «Kündigung per Telefon» | Web v210 `tplSumItems` |
| `ios/Kontivo/Cancel/CancelChannelPickView.swift` | Option «Per Telefon · Kundendienst anrufen» | Web v210 `openCancViaPick` |
| `ios/Kontivo/Cancel/CancelLogic.swift` | `startCancel` `.tel` → `cancelFlowPhone` (ohne Nummer «Telefonnummer fehlt» → Formular «Telefon»; sonst Toast «Nach dem Anruf hier bestätigen», `tel:`-Link, Rückfrage «Gekündigt?» beim Zurückkehren) | Web v210 `ktel` |
| `ios/KontivoUITests/ContractFormUITests.swift` | Meldung «Vertragsende fehlt» statt «Bis wann läuft der Vertrag?» | Web v218 (`ContractFormRules.missingEndText`) |
| `KontivoCore/Tests/.../BankFixtures/expected.json` | neu erzeugt mit Web-Bankcode v161 + **Katalog v224** (sonst schlagen die Bank-Paritätstests nur wegen der neuen Katalogdaten fehl) | Übergang; der Bereich **import** ersetzt die Datei mit v224 (dessen Fassung gilt beim Zusammenführen) |

## Neue Kern-API (für andere Bereiche)

### Wechselkurs (v162) – `RatePolicy.swift`
- `RatePolicy.needsFetch(_ s: Settings, today: Day, now: Date = Date()) -> Bool` – USD fehlt → ja; `rateDate == today` → nein; letzter Abruf < 3 h → nein.
- `RatePolicy.markChecked(&settings, today:, now:)` setzt `rateChecked` und `rateCheckedAt`.
- `RatePolicy.recheckInterval` (3 h), `RatePolicy.foregroundInterval` (1 h).

### Kopf «Verträge» (v164/v189) – `Calc.hero(filter:status:)`
```swift
let h = calc.hero(filter: model.costFilter, status: .paused)   // HeroStatus: .active ("act"), .paused, .future ("fut")
h.label      // «Fixkosten pro Monat» | «Pausiert, pro Monat» | «Noch nicht aktiv, pro Monat»
h.subtitle   // «24’240 CHF im Jahr», mit Filter «… im Jahr – Wohnen · Lara»; pausiert: «Zählt nicht zu deinen Fixkosten, solange pausiert»
h.status     // wirksamer Status (nil, wenn der Zähler 0 ist – Web setzt heroF zurück)
h.monthlyTotal, h.activeCount, h.pausedCount, h.futureCount, h.showsChips
```
`Calc.effectiveHeroStatus(_:active:paused:future:)`, `Calc.filterLabel(_:)`. Contracts: `CTHeroView` soll `h.label` statt
«Aktuelle Fixkosten pro Monat» zeigen und den Hero-Filter als `status` übergeben (App-`HeroFilter` → `Calc.HeroStatus`).
Gruppensumme im Kopf einer Gruppe entfällt bei nur 1 Vertrag (Web v164 `list.length<2`) – App-Logik in Contracts.

### Fristen (v163)
`DeadlineItem.chipLevel` bei `kind == .ended`: `.end` (rot) nur mit `cancelPer`, «Endet von selbst» `.none` (neutral).

### Sonderkündigung (v205–v209) – `SpecialCancel.swift`
```swift
if let x = calc.specialCancel(c) {          // Zeile im Detail (nicht bei gekündigt/beendet/nicht kündbar)
    Text(x.head) + " · " + x.tail           // = x.lineText, z.B. «Sonderkündigung möglich · bis 30.11.»
}
let sheet = calc.specialCancelSheet(c)!     // Blatt (Titel = head)
sheet.intro                                 // Einleitung
sheet.rows                                  // [Row(key: "Neuer Preis", value: "430.00 CHF", sub: "ab 01.01.27 · +7 % (+30.00/Mt.)", accent: false), «Kündigen bis» (accent = Messing), «Vertrag endet»]
sheet.tipsTitle, sheet.tips                 // «Gut zu wissen»
sheet.footer                                // «Grundlage: Art. 7 Abs. 2 KVG · Massgebend sind dein Vertrag und die Mitteilung. Keine Rechtsberatung.»
```
Weitere: `calc.specialCancelInfo(c)` (ohne Statusprüfung, Web `skrInfo`: `from`, `amount`, `previous`, `percent`, `until`, `rule`),
`calc.specialCancelRule(c, from:)` (`SpecialCancelRule.kind` .kvg/.energyDE/.telecomDE/.rentDE/.insuranceDE/.insuranceCH/.other),
`calc.isKvg(c)`, `Day.weekday` (0 = So). `calc.specialCancelHint(c)` = `specialCancel(c) != nil` (alter Kasten veraltet).
`Calc.priceIncreaseToast` = «Preiserhöhung vorgemerkt – Hinweis zur Kündigung steht im Detail.» (Formular, v205).
Fixkosten-Bericht (v220, Handlungsbedarf): `specialCancelInfo(c)?.percent` / `.from` für «Preis +n % ab TT.MM.JJ».

### Formular (v202, v210, v214–v218) – `ContractFormRules`
- `mandatoryTitle` «Pflichtvertrag», `mandatorySubtitle` «Kündigen nur mit neuem Anbieter», Infoknopf: `mandatoryInfoTitle`, `mandatoryInfo`, `mandatoryInfoAccessibility`.
- `placeholder` = «hinzufügen» (alle leeren Felder inkl. Beträge und Datumsfelder, v216/v217).
- `missingEndText` = «Vertragsende fehlt». Prüfungen mit Zielfeld (Web `goMiss`): `checkContract(partner:label:hasCategory:amountText:noticeValid:mode:end:trial:)`,
  `checkPriceChange(from:start:amountText:)`, `checkExtra(date:amountText:)`, `checkIncome(name:label:amountText:)`, `checkIncomePrice(from:amountText:)`
  → `Missing(field: FormField, message:)`; `amountMessage(_:)` («Betrag fehlt» / «Betrag prüfen»).
- Strom CH (v210/v215): `isSwissPower(currency:categoryKind:label:partner:catalogEntry:)`, `swissPowerStep(isNew:kindTouched:hasCategory:isSwissPower:appliedBefore:)` → `.setNotCancellable` / `.revert` / `.keep`.
- Katalog: `CatalogEntry.isLeasing` (→ Art «Mindestlaufzeit», Verlängerung leer, Zusammenfassung «feste Laufzeit»/«Mindestlaufzeit»), `CatalogEntry.isSwissPower`.

### Katalog (v210–v224) – `Catalog.swift`, `catalog.json` (572 Einträge)
- `CatalogEntry.id` = «Name|Land|Bezeichnung» (gleiche Namen möglich, z.B. CSS Krankenkasse/Zusatzversicherung).
- `Catalog.all(name, currency:)` (Web `tplAll`), `Catalog.find(name, currency:, label:, preferred:)` (Web `tplFind`; `preferred` = zuletzt übernommener Eintrag, Web `draft.tplIdx`).
- Trefferliste (v213): `Catalog.hits(query, currency:, more:) -> (entries, hasMore)`, `Catalog.hitSubtitle(entry, currency:)` («Krankenkasse · Schweiz · Pflichtvertrag»), `Catalog.hitDomains(_:)` (Internet-Treffer mit gleicher Website ausblenden), `CatalogEntry.termShort`, `CatalogEntry.countryName`.
- Kündigungsweg Telefon: `CancelChannel.phone` / `Calc.cancVia` → `.tel`; Detailmenü und «Kündigen: …» zeigen wie im Web «Weg wählen» bzw. «Kündigen: Weg wählen …»; Absender ist bei Telefon nicht nötig (Vollständigkeit).

### Farben (v165/v190)
`Category.displayColorHex` überall statt `colorHex` für Anzeige (Kategoriezeichen, Kosten, Formular-Farbe «A», Katalogliste).
Offene Stellen in fremden Bereichen: `ContractFormView.swift:430`, `ContractFormModel.swift:683`, `ContractFormSheets.swift:171`, `BankReviewView.swift:176`, `ManageCategories.swift`.
