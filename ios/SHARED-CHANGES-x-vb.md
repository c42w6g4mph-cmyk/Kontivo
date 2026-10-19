# Geteilte Dateien – Bereich B (Kosten, Budget, Einnahmen, Bericht), Branch swift-x-vb

Keine Änderungen an Dateien von Bereich C (Components.swift, Theme.swift, KTabHeader). Wünsche an C:

| Datei | Wunsch | Grund (Web v224, getComputedStyle) |
|---|---|---|
| Design/Components.swift `KTabHeader` | Titelzeile: `.top` = padding-top 17 + Zeile 40 (Titel 30/33 und Knöpfe 36 vertikal zentriert), Höhe 57. Heute `frame(minHeight: 57, alignment: .bottom)` mit 36er Zeile → Titel und Jahr-/Teilen-Knöpfe ≈2–3 pt zu tief (Kosten/Budget: Titel Web 82.5 pt, Swift ≈85). Vorschlag: HStack `.frame(height: 40)`, Titel `.frame(height: 33)`, `.padding(.top, 17)`. | Fotos 04, 05, 21, 24, 34, c7 |
| Design/Components.swift `KPrimaryButton` | `maxWidth` gilt heute für den Text, danach `padding(14)` → Knopf 348 statt 320 pt breit. Web `.esbtn`: `width:100%; max-width:320px` inkl. Innenabstand (border-box). Vorschlag: `.padding(14)` vor `.frame(maxWidth: maxWidth)`. | Fotos 21, 34 (Leerseiten Kosten/Budget), auch 02 |

Weitere geteilte Datei:

| Datei | Änderung | Grund |
|---|---|---|
| tests/visual/web_shots.py | c2/c8 (Preistreiber) und c3 (Budget-Listen): Scroll-Versatz 120/100 → 105.4 pt | Swift `-uiScrollTo` legt die Gruppe (Kopf 20 + 23.4) an den oberen Sicherheitsabstand 62 → Karte/Liste bei 105.4 pt; vorher verglich das Werkzeug unterschiedliche Scroll-Lagen. |
