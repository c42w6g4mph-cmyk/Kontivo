# Geteilte Änderungen – Bereich C (swift-x-vc, optischer Abgleich Web ↔ Swift)

Für A (swift-x-va) und B (swift-x-vb): diese Punkte sind zentral erledigt, bitte nicht doppelt korrigieren.

| Datei | Änderung | Grund / Wirkung für A/B |
|---|---|---|
| Design/Components.swift `KTabHeader` | Titel in einer 40-pt-Zeile senkrecht mittig (17 oben + 40 = 57), statt unten bündig | Web `.top` (align-items:center, h1 Zeilenhöhe 33): Grosstitel aller Tabs sass ≈2–4 pt zu tief. **Alle Tabs** profitieren, nicht lokal nachkorrigieren. Inhalt darunter bleibt unverändert (Kopf weiter 57 pt). |
| Design/Theme.swift `KMetric.maxContent` | 600 → **580** (= Web `.wrap` max-width inkl. Seitenrand 17 → Inhalt 546) | iPad-Inhaltsbreite. `kContentWidth()` um einen Inhalt **mit** innerem Rand 17 ergibt jetzt 546 pt wie Web. Wo `maxContent` als reine Inhaltsbreite benutzt wird: `maxContent - 2*17` bzw. `CTListMetric.side(for:)` (angepasst). Offen bei A: `Cancel/LetterView.swift` (`maxContent + 34` → `maxContent`). Offen bei B: `Budget/IncomeFormView.swift` prüfen (Rand innen?). |
| Design/Theme.swift `KMetric.tabPageBottom` (neu, 56) | Unterer Abstand am Ende einer Tab-Seite | Web `.wrap` padding-bottom 138 ab Bildschirmrand minus Tabbar-Sicherheitsabstand. In Mehr benutzt. **A (Fristen-Ende, 42/45)** und **B (Kosten/Budget-Ende)** bitte diesen Wert als letzten Abstand im ScrollView-Inhalt nehmen. |
| Design/Components.swift `KPrimaryButton` | Breite 320 **inkl.** Innenabstand (vorher 320 + 28), Zeilenhöhe 24.65 → 52.6 hoch | Web `.esbtn`; betrifft alle Leerseiten-Knöpfe (EmptyHero). B: 34-leer-budget / 21-leer-kosten Knopfbreite damit erledigt. |
| Contracts/ContractsTab.swift `CTListMetric.side(for:)` | `(width - maxContent)/2 + side` | Folge von maxContent 580 (Inhalt 546 auf dem iPad). |
| Contracts/ContractsTab.swift `CTEmptyContracts` | `.padding(.vertical, 32)` → nur unten; Fusszeile `.espriv`/`.eslink` 1:1 (12.5 pt, Schild grün 16 pt, max. 284 breit; «Ich habe ein Backup» 15 pt Medium) | Leerseite Verträge (Bereich C). **B:** Kosten/Budget-Leerseiten haben dieselbe Ursache: `.padding(.top, 36)` an der Aufrufstelle verdoppelt den inneren Abstand von `EmptyHero` (36) → entfernen (21/34 ≈36 pt zu tief). |
| Contracts/ContractFormView.swift | Seitenrand über `CTListMetric.side(for:)` | Folge von maxContent 580. |
| App/RootView.swift | `KPageSheetSizing` (neu): Vertrags- und Einnahmen-Formular auf dem iPad als hohes Blatt, 580 breit (`.page.fitted(horizontal:)` + idealWidth, iOS 18+) | 28-ipad-formular: Web zeigt das Formular als hohes Blatt; iPhone unverändert. |
| Manage/ManageComponents.swift | Neue Bausteine `mdScrollPage()`, `mdScrollStyle()`, `MDGroup`, `MDSec`, `MDRowBox`, `MDAddRowLabel`, `MDGroupHint`, `MDLightButton`, `KColor.mdMultiFill` | Verwalten-Seiten als Karten wie Web (`.mdgrp/.mdsec/.mdrow/.mdhint/.lbtn`). |
| ios/project.yml, ios/Kontivo.xcodeproj | `MARKETING_VERSION` 0.1.0 → 1.0 | Versionsanzeige wie Web. Dateiliste unverändert. |
