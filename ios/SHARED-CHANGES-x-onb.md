# Geteilte Änderungen – Bereich onb (Nachzug Web v224: Einführung ohne Splash, Tab Fristen)

Branch `swift-x-onb`. Eigene Dateien: `Onboarding/OnboardingView.swift`, `Onboarding/OnboardingPages.swift`, neu `Onboarding/OnbStyle.swift`,
`Deadlines/DeadlinesTab.swift`, Assets `onb-*.imageset`, `KontivoUITests/OnboardingUITests.swift`.

## .github/workflows/ios.yml (nur Zeilen ergänzt)
- Bildschirmfotos: `40-onb-1…7` (Einführung hell, Seiten 1–7), `41-fristen-vorgemerkt`, `42-fristen-offen`,
  nach dem Umschalten auf dunkel `43-dunkel-onb-0…7`, `44-dunkel-fristen`, `45-dunkel-fristen-offen`, `46-dunkel-leer-fristen`.
  Grund: Vergleich Web ↔ Swift hell/dunkel je Einführungsseite und für den ganzen Fristen-Tab.

## Startargumente (ohne Änderung an UITestHooks.swift, nur in eigenen Dateien, nur DEBUG)
- `-uiOnbPage <n>` (mit `-uiOnboarding`): Einführung startet auf Seite n (OnboardingView.prepare).
- `-uiDeadlines review,marked,folds,end` (mit `-uiDemo`): Quartals-Check fällig, «Halbtax» vorgemerkt, Klappgruppen offen,
  ans Ende gescrollt (`DLUITestSeed` in DeadlinesTab.swift). Bestehendes `-uiSeed endsself` (Contracts) wird für v163 genutzt.

## Lokale Kern-Logik (TODO core-API)
- `DeadlineItemRow.level` (DeadlinesTab.swift): Web v163 – Chip «endet …» bei «Endet von selbst» neutral, rot nur bei gekündigt
  (`item.kind == .ended && contract.cancelPer == nil → .none`). Entfällt, sobald `Calc.deadlineOverview()` (core) `chipLevel`
  entsprechend liefert (Calc.swift Zeile ~765: `lvl = c.cancelPer != nil ? .end : .none`).

## Abhängigkeiten zu anderen Bereichen (Integrator)
- **design – Wortmarke**: `OnbWordmark` (OnboardingPages.swift) ist ein Platzhalter (K aus dem Logo + «ontivo» in SF Pro Bold).
  Ersetzen durch die Wortmarke von design (Web v171: Inter Display Bold, «O» als Zeitring mit Messing-Segment). Aufruf:
  `OnbWordmark(size: clamp(30, 9vw, 36))` in `OnbWelcomePage`, Höhe 1.1 × Grösse.
- **design – MarkView**: Fristen und Vorlagen nutzen `MarkView` in den Web-Grössen 34 (Radius 9), 50 (12), 30 (8), 27 (8)
  und erwarten die Pastell-Kacheln von v166 (Fläche 20 %/30 % Kategoriefarbe, Symbol in Kategoriefarbe). Radius heute size × 0.25.
- **design – Titelzeile**: Web v184 `.top` 57 px. Fristen nutzt weiter `.navigationTitle("Fristen")`; der Kopf (`.tstat`) beginnt
  22 px unter der Titelzeile. Falls design eine eigene Titelzeile baut, dort einhängen.
- **design – Seitenrand**: Web-Rand der Seiten ist 17 px (berechnet), Fristen nutzt `KMetric.gutter` (16).
- **design – Logo**: Willkommen nutzt `Image("Logo")` (84 px, Radius 19); neues App-Icon von design wird automatisch übernommen.
- **design – MoreCurrencyPicker**: Einrichten nutzt die Währungskacheln von «Mehr» (`.obcur` ist im Web dieselbe Komponente).
- `OnbStyle.swift`: `onbLine(size, lineHeight, weight, design)` (CSS line-height), `OnbIcon`/`OnbGlyph` (Web-SVG-Pfade als Shape,
  Strichstärke wie CSS), `OnbChevron` (CSS-Rahmen-Chevron), `OnbColor` (berechnete color-mix-Werte). Kann von design durch
  globale Bausteine ersetzt werden.
- `OnbQuick.category(named:in:)` bleibt unverändert (BankReview, Bereich import).
- `OnbKGlyph` bleibt (SplashView, Bereich design).
