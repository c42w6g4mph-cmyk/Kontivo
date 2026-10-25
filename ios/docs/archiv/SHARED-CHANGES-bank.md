# Geteilte Änderungen – Bereich «bank» (Kontoauszug-Import, Kern)

## `KontivoCore/Sources/KontivoCore/Models.swift` – `Settings`
- Neu (additiv, mit Default): `bankIgn: [String] = []` und `bankAlias: [String: BankAlias] = [:]`, im `init(from:)` gelesen
  (`lossyArray` bzw. `value(..., [:])`). JSON-Schlüssel wie im Web (`settings.bankIgn`, `settings.bankAlias` mit `{n, c}`).
- Warum: `BankImport.find` blendet ausgeblendete Vorschläge aus und wendet gelernte Korrekturen an wie Web `bankFind`/`bankApplyAlias`;
  `BankImport.ignore` / `rememberCorrection` schreiben dorthin. Typ `BankAlias` steht in `BankTypes.swift`.
- Hinweis an «core»: `WebImport.importObject` übernimmt die beiden Felder aus einem Web-Backup noch nicht
  (`s["bankIgn"]` als Liste von Texten, `s["bankAlias"]` als Objekt `{schlüssel: {n, c}}`). Optional nachziehen.

## `KontivoCore/Package.swift` – Test-Target
- `resources: [.process("Resources"), .copy("BankFixtures")]`
- Warum: Parität-Tests brauchen die Musterdateien mit Ordnerstruktur (`samples/…`, `real/ch/…`, `real/de/…`; gleiche Dateinamen in
  mehreren Ordnern würden mit `.process` kollidieren) und `expected.json` (Erwartungswerte aus der Web-App).
