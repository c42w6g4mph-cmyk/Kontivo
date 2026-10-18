# Geteilte Änderungen – Bereich design (Nachzug Web v162–v224)

Stand: siehe letzter Commit auf `swift-x-design`. Alle Werte aus berechneten Styles der Web-App v224 (Playwright, 402×874).

## Neue/geänderte Bausteine (für alle Bereiche)

| Baustein | Datei | Web | Hinweis für andere Bereiche |
|---|---|---|---|
| `KIcon.symbol(forKey:)` / `symbol(for:)` liefern jetzt **Asset-Namen** `ic.cat.<slug>` statt SF-Symbol-Namen | Design/Theme.swift | `CAT_ICON`, `TAG_ICON` | Nie mehr `Image(systemName: KIcon.symbol…)`. Anzeigen mit `KIcon.image(name)` (kann «ic.…» und SF-Namen) oder `KIcon.view(name, size)` (feste Grösse, Vorlage). `MarkView(symbol:)` nimmt beides. |
| Web-Symbole `ic.*` (61 Stück) | Resources/Assets.xcassets/Icons/ic.<name>.imageset | Inline-SVGs | Vektor + Template. Liste: `ios/design-tools/web_icons.py` (erzeugt die Ordner neu). Tab: `ic.tab.list/stat/budget/term/set`; UI: `ic.plus, search, filter, sort, share, more, partner, persons, categories, check, check.bold, check.hook, check.done, check.small, upload, download, table, pen, edit, bank, income, mail, book, clip, lock, drag, pdf, camera, gift, share.people, cloud, bell, sparkle, shield`; Kategorien `ic.cat.*`. Fehlende Symbole dürfen andere Bereiche als eigenen Ordner ergänzen (Skript erweitern oder SVG von Hand: `<g fill="none" stroke="#000000" stroke-width=… stroke-linecap="round" stroke-linejoin="round">`). |
| `MarkView` | Design/Components.swift | `.mark`, v166 Pastell | Fläche = Kategoriefarbe 20 % (hell) / 30 % (dunkel) über `--surface`, Symbol 56 % in Kategoriefarbe (dunkel 45 % + Weiss); Radius je Grösse `KMetric.markRadius(size)`; kein Rand mehr. Web-Grössen: Vertragsliste 50, Verwalten 40, Kategorien 34, Import 36/44. |
| `KColor.categoryFill(_:)`, `categoryInk(_:)`, `displayHex(_:)`, `mix`, `brassSoft`, `tealTint`, `esArt` | Design/Theme.swift | `color-mix`, `OLD_COL` | `Color(hex:)` ersetzt jetzt altes Türkis automatisch (`newCol`). |
| `KMetric.gutter` = **17** (vorher 16) | Design/Theme.swift | `.wrap` padding 0 17px | Wert geändert, Name gleich. Neu: `groupRadius` 16, `controlRadius` 10, `rowDividerInset` 62, `titleBarHeight` 57, `markRadius(_:)`. |
| `KFont.text(size, weight)`, `KFont.wordmark(size)`, `KFont.naturalLineHeight`, `View.kLineHeight(size, lineHeight)` | Design/Theme.swift | `line-height` | `kLineHeight` bildet CSS-Zeilenhöhe nach (Zeilenabstand + halber Durchschuss oben/unten). |
| `KCard` | Design/Components.swift | `.grp .card`, `.dgrp` | Radius 16, kein Rand (v164). |
| `SectionHead` | Design/Components.swift | `.grphead` | 12 pt, Titel Semibold `--ink`, rechts `--ink2`, oben 20 / unten 6, **ohne Versalien** (v166). |
| `KDivider(inset:)`, `KChevron` | Design/Components.swift | Trennlinie 1 px `--line`, «›» 18 pt | Zeilen mit Marke: `KDivider(inset: KMetric.rowDividerInset)`. |
| `Chip` | Design/Components.swift | `.chip` | Rand 1 pt `--line`, 14 pt `--ink2`; gewählt `--ink`/`--paper` Semibold. |
| `KSegmented` | Design/Components.swift | `.seg2`/`.hseg` | Fläche `--sunken`, Radius 10, gewählt weiss mit Schatten. |
| `KPrimaryButton` | Design/Components.swift | `.esbtn` | Messing, 17 pt Semibold, Radius 14, max. 320. |
| `KTabHeader(title:) { trailing }` + `.kTabPage(title:)` | Design/Components.swift | `.top` (57 pt, v184) + `.minibar` | **Jede Tab-Seite** sollte statt `.navigationTitle(...)` (grosser System-Titel) `KTabHeader` als erstes Element im ScrollView-Inhalt und `.kTabPage(title:)` an der Seite verwenden (blendet die System-Leiste aus, zeigt die Mini-Kopfzeile beim Scrollen). Plus-Knopf: `KTabHeader(title: "Verträge") { KAddButton { … } }` bzw. `AddMenuButton` im selben Look. Bisher nur «Mehr» umgestellt (Bereich design). |
| `KAddButton` | Design/Components.swift | `#addBtn` | 40 pt Kreis `--brassFab`, Plus 22 pt `--onBrass`. |
| `EmptyHero` | Design/Components.swift | `emptyHero` (`.esv.eh`) | Symbolkachel 68/20, Titel 22 Rounded Bold, Text 15, Haken 18, Knopf `KPrimaryButton`. SF-Namen «doc.text/chart.bar/wallet.pass/stopwatch» werden auf `ic.tab.*` abgebildet. |
| `Pill` | Design/Components.swift | Plakette | 12.5 pt Semibold, Fläche 14 %. |
| `PersonAvatar` | Design/Components.swift | `.mdav` | Kreis `--tealFill`, Initiale weiss Bold. |
| `CloseButton` | Design/Components.swift | `.shbar` rechts | 16 pt Bold Messing. |
| `ToastView` | App/RootView.swift | `.status` | 14 pt `--paper` auf `--ink`, Kapsel 9/15. |
| `KAppearance.apply()` | Design/Appearance.swift (aufgerufen in `RootView.init`) | `.tabbar`, `.shbar` | Tabbar (UITabBarAppearance, Glas bleibt): Beschriftung 11 pt (gewählt Semibold Messing, sonst Medium `--ink2`), Plakette `--brassFab`. Navigationsleisten: nur Titel 18 pt Semibold −0.012em (keine globale Fläche – das blendete unter iOS 26 die grossen Tab-Titel aus). |
| `.kSheetBar()`, `ToolbarContent.kPlain()`, `KBarButton(title:bold:)` | Design/Components.swift | `.shbar`, `.shok`, `.shx` | **Fenster** (Sheets): `.kSheetBar()` an der Seite (Fläche `--surface`), Textknöpfe `ToolbarItem { KBarButton(title: "Fertig") { … } }.kPlain()` (ohne Glas-Kapsel, 16 pt Bold Messing; `bold: false` = «‹ Zurück» 16 pt `--ink2`). Umgesetzt in Verwalten und Vollständigkeit. |
| Marke: `KAppLogo`, `KLogoKShape`, `KWordmark`, `KArc` | Design/Brand.swift | `#splash`, `.brandfoot`, brand/ | Wortmarke als Vektor (deckungsgleich mit brand/*.svg). `OnbKGlyph` (Bereich onb) kann durch `KLogoKShape` ersetzt werden, «Willkommen bei Kontivo» durch `KWordmark(size:)`. |
| `MoreReport.open` | More/MoreTab.swift | v220 «Mehr → Bericht» | **Bereich costs:** `MoreReport.open = { model in … }` setzen (z.B. in einem `init`/`onAppear` des Berichts), dann öffnet die Zeile «Fixkosten-Bericht» den PDF-Bericht. Ohne Eintrag passiert nichts. |

## Geänderte fremde/geteilte Dateien

| Datei | Änderung | Grund |
|---|---|---|
| `KontivoCore/Models.swift` (core) | `Category.standardColors` = Web `CAT_COLOR` v224, `palette` = `COLORS`, `editColors` = `CE_COL`, `fallbackColor` #6B7280, `IncomeKind.colorHex` (Nebeneinkommen #4A5A66, Sonstiges #6B7280); neu `Category.oldColors`, `oldStandardColors`, `displayColor(_:key:)`, `displayColorHex`; `AppData.color(of:)` liefert Anzeigefarbe | v165/v224 Kategoriepaletten, `OLD_COL`/`CAT_OLD` beim Anzeigen (Daten bleiben unverändert). |
| `KontivoCore/ExtKostenBudget.swift` (core) | `kbPartnerPalette[0]` #4A5A66, `kbCategoryColor` nutzt `displayColorHex` | Web `PAL` v165. |
| `Budget/IncomeFormView.swift` (costs) | 2 Stellen: `Label(…, systemImage: KIcon…)` → `Label { } icon: { KIcon.image(…) }`, Symbol in der Art-Kachel `KIcon.view(…, 15)` | KIcon liefert Asset-Namen. |
| `Manage/ManageCategories.swift` | Symbolauswahl `KIcon.view(…, 17)` | dito |
| `project.yml` | `UIAppFonts` + `InterDisplay-Bold.ttf` | Wortmarke v171 (Datei Resources/Fonts/InterDisplay-Bold.ttf, OFL-Inter.txt). |
| `.github/workflows/ios.yml` | Zeilen 29–34 (dunkel Mehr/Verwalten, Splash angehalten, Mehr unten, Vollständigkeit, leeres Budget) | Bildschirmfoto-Vergleich. |
| `Onboarding/SplashView.swift` | neu gezeichnet (Vektor-Logo, Segment-Drehung, Wortmarke); Startargument `-uiSplashHold` | v172–v174 (Splash gehört laut NACHZUG zu design). |
| `Resources/Assets.xcassets/AppIcon`, `Logo` | aus brand/kontivo-icon.svg (Variante B) | v174 |

## Für den Integrator

- `KIcon.symbol(...)` liefert Asset-Namen: in anderen Bereichen jede Stelle `Image(systemName: KIcon.symbol…)` auf `KIcon.image(…)` umstellen (auf design-Stand: keine mehr vorhanden).
- Tab-Seiten (Verträge, Kosten, Budget, Fristen): auf `KTabHeader` + `.kTabPage(title:)` umstellen. UI-Test `CompletenessUITests` wartet mit `waitNav("Fristen")` auf die Navigationsleiste – nach der Umstellung von «Fristen» auf `tapTab`/`kPageTitle` prüfen (Kennung `kPageTitle`).
- `KMetric.gutter` 16 → 17 wirkt überall.
- Kategorie-Farben: Bereiche, die `category.colorHex` direkt anzeigen, besser `category.displayColorHex` nutzen.
