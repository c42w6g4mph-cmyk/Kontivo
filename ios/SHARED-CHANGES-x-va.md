# Geteilte Dateien – Bereich A (swift-x-va: Verträge, Detail, Formular, Brief, Kündigungsweg, Fristen)

Keine Änderungen an Dateien von Bereich C (Components.swift, Theme.swift, KTabHeader) oder anderen geteilten Dateien.

## Wünsche an Bereich C (nicht selbst geändert)

| Datei | Wunsch | Grund |
|---|---|---|
| Design/Components.swift (`KTabHeader` / `kTabPage`) | Grosstitel 2–4 pt höher (Web `h1` Oberkante 82.5 pt bei Safe-Area 62: `.top` padding-top 17, Zeile 33) | 03/23 Verträge, 06/41/44 Fristen: Titel und alles darunter 2–4 pt zu tief. Bewusst nicht lokal ausgeglichen, damit es nicht doppelt korrigiert wird, wenn C den Titel anpasst. |
| Design/Components.swift (`Chip`) | Zeilenhöhe 20.3 (`frame(minHeight: 20.3)`) und 8 statt 7 Innenabstand oben/unten (Web `.chips .chip`: 14 px, Zeile 20.3, 7/12 + Rand 1 → 36.3 hoch) | Chip ist heute ≈31 pt hoch. Im Vertragsformular («Personen») nutzt A darum `CTFormChip(fill: false, fontSize: 14)`. |

## Neue Hilfen im Bereich A (für andere nutzbar)

- `View.ctLines(_ size:, _ lh:)` (Contracts/ContractsTab.swift): mehrzeiliger SF-Text mit CSS-Zeilenhöhe (Zeilenabstand + half-leading oben/unten).
- `View.ctLineExact(_ h:)`: einzeiliger Text mit genau der CSS-Zeilenhöhe, auch wenn die Schrift höher ist (New York/Serif).
- `View.ctRowMinHeight(_:)` (Contracts/ContractFormParts.swift): eigene Mindesthöhe einer Zeile in `CTCardRows` (z.B. `.fadd` 46).
