# Geteilte Änderungen – Bereich «import» (Nachzug Web v177–v223: Kontoauszug-Import, Logos)

Alle Änderungen ausserhalb von `KontivoCore/Bank*`, `Tests/BankFixtures`, `Import/*` und `Shared/LogoSearchSheet.swift`.
Nur additiv bzw. ein Einstiegspunkt; beim Zusammenführen mit den anderen Bereichen bitte erhalten.

## `Kontivo/App/Routing.swift` – `ContractFormContext`
- Neu: `case bankSuggestion(BankFormDraft)` und `idPart` → `"bank-<id>"`.
- Warum: Web v181 `bkOpenForm` – ein Vorschlag aus dem Kontoauszug wird im **normalen Vertragsformular** bearbeitet (Titel «Vorschlag»);
  «Sichern» schreibt nicht in die Daten, sondern zurück in den Vorschlag. `BankFormDraft` steht in `Import/BankFormBridge.swift`.

## `Kontivo/Contracts/ContractFormModel.swift` (Bereich contracts) – drei Einstiegsstellen, je mit Kommentar «Bereich import»
1. `init`: `case .bankSuggestion(let b)` → `c = b.contract`, `title = "Vorschlag"`.
2. `init` nach `logoBg = c.logoBg`: Vertragspartner-Name, Website, Adresse aus dem Entwurf (den Vertragspartner gibt es evtl. noch nicht).
3. `save(model:)` nach `let addr = …`: bei `.bankSuggestion` Entwurf füllen (Vertrag, Name, Website, Adresse, Logo) und
   `BankFormBridge.shared.contractDone(b)` statt zu speichern; `return true`.
- Bitte bei einer Neufassung des Formulars genau diese drei Stellen übernehmen.

## `Kontivo/Contracts/ContractFormView.swift` (Bereich contracts)
- `CTFormHost.save()`: bei `.bankSuggestion` keine Meldung «Vertrag angelegt» (Web: zurück zur Liste ohne Toast).
- `CTFormPage`: nach `CTFormNoteSection` bei `.bankSuggestion` eine Section mit `BankFormIgnoreButton` («Nie mehr vorschlagen», Web `#fBankIgn`).

## `Kontivo/Budget/IncomeFormView.swift` (Bereich costs)
- `IncomeFormView.body`: liegt für die ID ein Entwurf in `BankFormBridge.shared.income(id)`, wird er mit `bankSuggestion: true` gezeigt.
- `KBIncomeForm.init(initial:isNew:bankSuggestion: = false)`: Titel «Vorschlag», Betrag vorbelegt; `save()` ruft bei Vorschlag
  `BankFormBridge.shared.incomeDone(d)` und schliesst, statt zu speichern.

## `Kontivo/App/UITestHooks.swift`
- Neu: `-uiBankStep <inc|term>` (mit `-uiBankSample`): nach dem Laden direkt zu diesem Schritt (Bildschirmfotos); `start(…, step:)`.

## `.github/workflows/ios.yml`
- Nur neue `shoot`-Zeilen für die Import-Schritte (siehe Datei, Namen `30-import-*`).

## `KontivoCore/Sources/KontivoCore/Resources/catalog.json` (Bereich core)
- Neu erzeugt aus `index.html` v224 (572 Einträge) – nötig, damit die Parität `Tests/BankFixtures/expected.json` (aus v224) stimmt.
- Kündigungsweg «Telefon» (Web v210) steht als `"cancelChannel": "phone"`; `CatalogEntry` dekodiert unbekannte Werte als `nil`,
  bis «core» `CancelChannel.phone` ergänzt. **Beim Zusammenführen die Fassung von «core» nehmen** (gleiche Quelle, ggf. eigener Name
  für Telefon); `make_catalog.py` wurde hier nicht geändert (Datei mit lokaler Zuordnung «Telefon» → «phone» erzeugt).

## Kern (eigener Bereich, nur zur Info für andere)
- `BankTx.sub` (Einzelposten), `BankFile.owner` (Kontoinhaber), `BankSuggestion.catalog` (Eintrag statt Name; `catalogName` bleibt lesbar).
- Neu: `BankImport.findIncome` (Einnahmen), `payMethod`, `numbers`, `label`, `who`; `toContract` setzt Zahlungsart und Nummern.

## Hinweis an «onb»/«design»
- `BankSafeNote` (Import/BankImportSheet.swift) ist die grüne Box «Bleibt auf deinem Gerät.» (Web `.safenote`). Die Einführung zeigt
  dieselbe Box – bei Bedarf zusammenlegen (Name bewusst mit Präfix, damit es keine Kollision gibt).
- `LogoCandidatesView` (Shared/LogoSearchSheet.swift) ist die Web-Vorschlagsliste `.lcands` zum Einbetten im Formular (Web zeigt die
  Logo-Auswahl unter dem Logo, v181 «nebeneinander»); `LogoSearchSheet` nutzt sie im Fenster.
