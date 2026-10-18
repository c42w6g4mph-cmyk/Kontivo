# Prüffälle für die Rechenlogik

Zweck: Die SwiftUI-Version muss Fristen, Termine und Kosten genau gleich berechnen wie die Web-App.

- `cases.json`: 25 Verträge mit allen Sonderfällen (Kündigungsrhythmen m/q/h/y/a/p, Fristen in Tagen/Wochen/Monaten/«bis zum n.», befristet mit und ohne Verlängerung, verpasste Frist, Probeabo, Pause, Start in der Zukunft, Preisänderung, Fremdwährung, gekündigt, behalten, nicht beobachtet, Steuern, Monatsende 31., Schaltjahr 29.02.) und vier Stichtage.
- `golden.json`: erwartete Ergebnisse je Stichtag und Fall (Datumswerte als `JJJJ-MM-TT`, Beträge in Hauptwährung CHF mit festen Kursen EUR 0.94, USD 0.80):
  `termEnd`, `noticeDeadline`, `nextTerm`, `effEnd`, `nextDue`, `paymentsNext12`, `curPrice`, `monthlyCostHome`, `anytime`, `needsAction`, `trialNeeds`, `paused`, `shareSinan`, `shareLara`, `cancVia`.
- Seit Web v224 zusätzlich je Fall `trialOn`, `endsSelf` und `skr` (Sonderkündigung, Web `skrInfo`); je Stichtag `hero` (Kopf «Verträge» mit Filter Person/Kategorie und Status aktiv/pausiert/noch nicht aktiv, aus dem DOM nach `renderHero`); `skr` für die Fälle `skrCases` (eigene Stichtage `skrTodays`: KVG, EnWG, TKG, § 561 BGB, VVG, AVB/AGB) mit Regel, Zeile im Detail und Erklärblatt (DOM von `openSkr`). Für Funktionen ausserhalb von `window.KontivoCalc` ergänzt `make_golden.py` index.html beim Laden im Speicher um den Haken `window.__KX` (Datei bleibt unverändert).
- `make_golden.py`: erzeugt `golden.json` neu aus `index.html` (lokaler Server auf Port 8765, Playwright). Nach jeder Änderung an der Rechenlogik laufen lassen und Unterschiede bewusst prüfen.

In Swift: XCTest, das `cases.json` lädt, das Datum auf den Stichtag fixiert und jedes Feld mit `golden.json` vergleicht.
