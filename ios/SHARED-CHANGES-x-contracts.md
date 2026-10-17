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
| Stelle | Lokal | Kern (Bereich core) |
|---|---|---|
| `Contracts/ContractsTab.swift` `CTHeroText` | Summe/Beschriftung/Unterzeile je Status-Filter (v189) | `Calc.hero(filter:status:)` mit `label`, `status` (Commit c9a9c23 auf swift-x-core). `HeroFilter` (App) ↔ `Calc.HeroStatus` abbilden, dann `CTHeroText` löschen. |
| `Contracts/ContractSpecialCancel.swift` `CTSpecialCancel` | Regeln/Zeile/Blatt Sonderkündigung (v205–v209) | `Calc.specialCancel(_:)` / `SpecialCancelInfo` / `SpecialCancelSheet` (SpecialCancel.swift). `CTSkrLine`/`CTSkrSheet` (Ansicht) bleiben, Daten aus dem Kern. Danach `Calc.specialCancelHint`/`specialCancelText` (alt) nicht mehr verwenden. |
| `Contracts/ContractFormPartner.swift` `CTCatalogHits` | Katalogtreffer für die Trefferliste (`tplAll`, `tplHits`, `tplTerm`) | z.B. `Catalog.all(named:currency:)`, `Catalog.hits(_:currency:more:)`, `CatalogEntry.termShort` |
| `Contracts/ContractsShared.swift` `CTFormText` | «Pflichtvertrag», «Kündigen nur mit neuem Anbieter», Info-Text (v202/v210) | `ContractFormRules.mandatoryTitle/-Subtitle/-Info` |
| `Cancel/CancelLogic.swift` `cancelFlowPhone` | «Anrufen» (Web v210 `ktel`): ohne Nummer «Telefonnummer fehlt» → Formular bei Telefon, sonst `tel:` und Rückfrage «Gekündigt?» | Kündigungsweg Telefon im Modell (`CancelChannel` «Telefon», `CancelVia.tel`). Dann: `startCancel` `case .tel: cancelFlowPhone(c, trial:)`; Kündigungsweg-Kachel «Telefon» im Formular (`CTCancelWaySegment`); Auswahl «Per Telefon · Kundendienst anrufen» in `CancelChannelPickView`; Menü-Untertitel kommt aus `Calc.detailMenu`. `ContractFormFocus.tel` ist schon da. |

## Integrationshinweise
- `CTPageHeader` (Titelzeile «Verträge» mit Plus, Web `.top` 57 pt) und `CTSheetBar` (Fensterleiste Detail/Formular, Web `.shbar`) sind lokal gebaut. Falls der Bereich design gemeinsame Bausteine dafür hat, diese verwenden.
- Der Verträge-Tab blendet die Navigationsleiste aus (`.toolbar(.hidden, for: .navigationBar)`), Titel und Plus scrollen mit der Seite (wie Web).
- `MarkView` (design): Web-Radien 12 (50 pt), 17 (76 pt), 9 (34 pt) statt `size * 0.25`; Pastell-Kategorien (Web v166) kommen vom Bereich design.
