# Nachzug Web v162–v224 → Swift (Start 17.10.2026)

Auftrag Sinan: Swift auf exakt denselben Stand wie die Web-App bringen. **1:1 identisch** – Abstände, Schriften, Farben, Radien, Symbole, Texte, Reihenfolge, Verhalten, Funktionen.

## Quelle der Wahrheit
- `index.html` (Kopie von main d8933a6, Web v224) im Repo-Wurzelordner dieses Branches. Commit-Liste: `git log bb0dbf1..d8933a6` im Web-Repo (main); Messages beschreiben jede Version. Der Swift-Stand vor dem Nachzug entspricht Web v161 (bb0dbf1).
- Das Web-Repo `main` ist unter `origin/main` abrufbar (`git fetch origin main`), Diffs je Version: `git show <hash> -- index.html`.
- Technik-Doku (Stand teils älter): ios/ARCHITEKTUR.md, ios/APP-BAUSTEINE.md, ios/docs/.

## Regeln für 1:1
- CSS-px = iOS-pt. Werte immer aus den **berechneten** Styles der Web-App holen (Playwright, `getComputedStyle`, Viewport 402×874 = iPhone 17 Pro, `color_scheme` light/dark), nicht aus einzelnen CSS-Regeln: die Design-Schicht «Graphit & Messing» am Ende des `<style>` überschreibt vieles mit `!important`.
- Farben: nur `KColor.*` (Design/Theme.swift, Werte = Web v224). Namen bleiben stabil (`teal` = Akzent Messing). Neu: `alertFill`, `brass`, `brassFab`, `onBrass`, `glass`, `glassEdge`, `glassShade`, `lift(_:)`.
- Schriften: `KFont.serif(size, weight)` für grosse Beträge (Web `--serif`), `KFont.rounded` für Beträge in Listen, `KFont.title(size)` für Überschriften (SF Pro Semibold, v176), sonst `.system(size:weight:)` mit exakter Grösse aus dem Web. Keine Dynamic-Type-Textstile (`.headline` usw.), wenn das Web eine feste Grösse hat.
- Symbole: Die Web-App nutzt eigene Inline-SVGs. Für 1:1 dieselben Pfade verwenden (als SVG im Asset-Katalog mit «Preserve Vector Data», Template-Rendering) statt SF Symbols, wo das Web ein eigenes Symbol zeigt. Gemeinsame Symbole legt der Bereich **design** in `ios/Kontivo/Resources/Assets.xcassets/Icons/` an (Name = `ic.<webname>`); andere Bereiche dürfen fehlende Symbole selbst dort ergänzen (eigener Ordner je Symbol, kollisionsfrei).
- Texte wörtlich aus dem Web (Schweizer Rechtschreibung, «Vertragspartner», «Person», «Zahlungsrhythmus»).
- Echte Personendaten nie ins Repo (public). Rechtliches: Anbieter-Adresse bleibt Platzhalter.

## Vergleich Web ↔ Swift (Pflicht vor «fertig»)
1. Web: Playwright, Viewport 402×874, `device_scale_factor` 3, hell und dunkel, gleiche Daten wie Swift-`DemoData` (Web-Daten in `localStorage['vertraege.v1']` nachbauen), Stichtag über `window.__KONTIVO_TODAY`. Splash abwarten (≥ 4.2 s) oder `#splash` entfernen.
2. Swift: Commit-Message mit `[shots]` → CI macht Bildschirmfotos (`ci-logs` Branch, Ordner `shots-<branch>/`). Eigene Bildschirmfotos über neue `shoot`-Zeilen sind erlaubt (Workflow `.github/workflows/ios.yml`, nur Zeilen ergänzen; Startargumente in `App/UITestHooks.swift`).
3. Bilder nebeneinander ansehen (Read-Tool), Abweichungen beheben, wiederholen. Statusleiste/Home-Indikator ignorieren.

## CI
- Push auf `swift-x-<bereich>` startet `.github/workflows/ios.yml` (Kern-Tests, Build, UI-Tests ~60–110 min). `[noui]` in der Message überspringt UI-Tests (schneller Build-Check). Ergebnis: `git fetch origin ci-logs && git show origin/ci-logs:swift-x-<bereich>.txt` (Kopfzeile `core=… app=… ui=…`, sha prüfen).
- Der Git-Proxy erlaubt nur 2 gleichzeitige Git-Operationen pro Repo. Bei HTTP 429: 20–60 s warten, bis 6× wiederholen. Nie parallel klonen.
- Kein lokales Swift (Linux ohne Toolchain): Code sorgfältig schreiben, CI ist der Compiler.

## Bereiche (je ein Branch, parallel)
| Bereich | Branch | Besitzt (darf frei ändern) |
|---|---|---|
| design | swift-x-design | Design/*, Resources/* (Icons, AppIcon, Fonts, Farben), App/RootView (Tabbar), Shared/ allgemeine Komponenten, Splash/Wortmarke, More/* (Mehr inkl. Rechtliches) |
| core | swift-x-core | KontivoCore (ausser Bank*), Scripts/, tests/golden* |
| import | swift-x-import | KontivoCore/Bank*, Tests/BankFixtures, Import/*, Shared/LogoSearchSheet.swift (Logo-Aufbereitung) |
| contracts | swift-x-contracts | Contracts/*, Cancel/* |
| costs | swift-x-costs | Costs/*, Budget/*, neuer Fixkosten-Bericht (PDF) |
| onb | swift-x-onb | Onboarding/* (ohne Splash), Deadlines/* |

Geteilte Dateien (Routing.swift, AppModel.swift, UITestHooks.swift, DemoData.swift, Models.swift, ios.yml, Components.swift): nur **additive** Änderungen, jede in `ios/SHARED-CHANGES-x-<bereich>.md` mit Datei, Änderung, Grund festhalten. Fremde Bereichsdateien nur minimal (z.B. ein Einstiegspunkt) und dokumentiert.
