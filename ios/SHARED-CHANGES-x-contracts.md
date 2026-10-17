# Geteilte Änderungen – Bereich contracts (Nachzug Web v224, Branch swift-x-contracts)

## Fremde/geteilte Dateien
| Datei | Änderung | Grund |
|---|---|---|
| `Kontivo/Shared/DocumentViewer.swift` (design) | PDF: Zoom 1–4× (`minScaleFactor`/`maxScaleFactor`), Doppeltipp 1× ↔ 2.5×; Bild: max. 4×, Doppeltipp | Web v221 (9e82d69) Dokument-Vorschau mit Zoom. «Text ändern» war schon nur beim Brief. |
| `Kontivo/Resources/Assets.xcassets/ic.ct.*.imageset` (neu) | SVG-Symbole der Web-App (search, filter, sort, clip, more) mit Präfix `ic.ct.` | 1:1-Symbole, kollisionsfrei zu `ic.<name>` des Bereichs design. Bei der Integration auf gleichnamige `ic.*` des Bereichs design umstellen (`CTIcon.named`) und die `ic.ct.*` löschen. |
| `KontivoUITests/ContractListUITests.swift`, `ContractFormDetailUITests.swift` | Suchfeld per Kennung `contracts.search`; Katalogtreffer `form.tplHit`; keine Zeile `form.cancelAddr` mehr | eigene Suche (Web `.searchrow`), Trefferliste v213, v212 |
| `Kontivo/App/UITestHooks.swift` | `-uiSheet detail:<Bezeichnung>` öffnet das Detail dieses Vertrags | Bildschirmfoto Sonderkündigung |
| `.github/workflows/ios.yml` | Zeile `shoot … 10b-detail-sonderkuendigung -uiSeed skr -uiSheet detail:Krankenkasse` | Vergleich Web ↔ Swift |

## Lokale Stellen «TODO core-API» (bei der Integration auf Kern umstellen)
Kern-API laut `swift-x-core` (Commits c9a9c23, 198112a, cbbb623, 6838d3a; SHARED-CHANGES-x-core.md):

| Stelle (contracts) | Lokal | Kern (Bereich core) |
|---|---|---|
| `Contracts/ContractsTab.swift` `CTHeroText` + `CTListContent.effectiveHero` | Summe/Beschriftung/Unterzeile je Status-Filter (v189) | `calc.hero(filter:status:)` → `h.label`, `h.subtitle`, `h.monthlyTotal`, `h.status`; App-`HeroFilter` → `Calc.HeroStatus` (`.active/.paused/.future`). `CTHeroText` löschen. |
| `Contracts/ContractSpecialCancel.swift` `CTSpecialCancel` (`info`, `sheet`, `rule`, `isKvg`) | Regeln/Texte v205–v209 | `calc.specialCancel(c)` (Zeile: `head`, `tail`) und `calc.specialCancelSheet(c)` (`title`, `intro`, `rows[key,value,sub,accent]`, `tips`, `footer`). `CTSkrLine`/`CTSkrSheet` (Ansicht) behalten, nur die Daten tauschen; `CTSkr*`-Typen löschen. Alt `Calc.specialCancelHint/specialCancelText` nicht mehr verwenden. |
| `Contracts/ContractFormPartner.swift` `CTCatalogHits` (`all`, `hits`, `term`, `subtitle`) | Katalogtreffer v213 | `Catalog.all/find(label:preferred:)`, `Catalog.hits`, `hitSubtitle`, `hitDomains`, `CatalogEntry.termShort` |
| `Contracts/ContractFormModel.swift` `isChPower`/`chPowerDefault`, Leasing in `applyTemplate` | v210/v214 | `isSwissPower`/`swissPowerStep`, `isLeasing` (Ablauf `tmTouched`/`chPower` im Formular bleibt) |
| `Contracts/ContractFormModel.swift` `save`/`addPrice`/`addExtra` Meldungen «… fehlt» | v218 Texte lokal | `checkContract`/`checkPriceChange`/`checkExtra` mit Zielfeld; Zielfeld auf `form.miss(_:)` abbilden (Markierung `ctMiss` bleibt) |
| `Contracts/ContractsShared.swift` `CTFormText` | «Pflichtvertrag», «Kündigen nur mit neuem Anbieter», Info-Text | `ContractFormRules.mandatoryTitle/-Subtitle/-Info` |

### Kündigungsweg Telefon (v210) – Kern hat ihn schon (CancelChannel.phone, CancelVia.tel)
Der Bereich core hat dafür auch App-Stellen im Bereich contracts geändert (`cancelFlowPhone` in CancelLogic, `CTText.cancelButton(.tel)` «Anrufen», `ContractFormFocus.tel`, Segment/Auswahl Telefon). Auf diesem Branch:
- `ContractFormFocus.tel` ist wortgleich ergänzt (Merge ohne Konflikt); `cancelFlowPhone` gibt es hier bewusst **nicht** (Version von core übernehmen).
- `CTCancelWaySegment.items` (ContractFormParts) und `CancelChannelPickView.options` bauen die Liste aus `CancelChannel.allCases` → mit `.phone` erscheinen «Telefon» bzw. «Per Telefon · Kundendienst anrufen» automatisch. **Merge-Konflikt** an diesen zwei Stellen und in `ContractFormTerm.cancelWayRows` (`switch`): jeweils die Fassung von contracts nehmen (`default:` deckt `.phone` ab, kein Folgefeld wie Web).

## Integrationshinweise
- Bereich design hat (swift-x-design, SHARED-CHANGES-x-design.md) gemeinsame Bausteine gebaut. Bei der Integration umstellen:
  - `CTPageHeader` (ContractsTab.swift) → `KTabHeader(title: "Verträge") { AddMenuButton() im KAddButton-Look }` + `.kTabPage(title:)` (bringt zusätzlich die Mini-Kopfzeile `.minibar` beim Scrollen, die hier noch fehlt).
  - `CTSheetBar`/`CTBarCancelButton`/`CTBarConfirmButton` (ContractSheetBar.swift; Detail, Formular, Brief) → `.kSheetBar()` + `ToolbarItem { KBarButton(…) }.kPlain()`. `CTBarMenuLabel` (••• 34 pt, `--sunken`) bleibt oder wandert nach Design.
  - `CTIcon.named("x")` → `KIcon.view("ic.x", size)`; alle verwendeten Namen gibt es bei design (search, filter, sort, clip, more, pen, book, plus). Danach `ic.ct.*.imageset` löschen.
  - `CTListMetric.side` (17) → `KMetric.gutter` (bei design jetzt 17), `CTListMetric.groupRadius` → `KMetric.groupRadius`.
- Der Verträge-Tab blendet die Navigationsleiste aus (`.toolbar(.hidden, for: .navigationBar)`), Titel und Plus scrollen mit der Seite (wie Web).
- `MarkView` (design): Web-Radien 12 (50 pt), 17 (76 pt), 9 (34 pt) statt `size * 0.25`; Pastell-Kategorien (Web v166) kommen vom Bereich design.
