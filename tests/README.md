# Prüffälle für die Rechenlogik

Zweck: Die SwiftUI-Version muss Fristen, Termine und Kosten genau gleich berechnen wie die Web-App.

- `cases.json`: 25 Verträge mit allen Sonderfällen (Kündigungsrhythmen m/q/h/y/a/p, Fristen in Tagen/Wochen/Monaten/«bis zum n.», befristet mit und ohne Verlängerung, verpasste Frist, Probeabo, Pause, Start in der Zukunft, Preisänderung, Fremdwährung, gekündigt, behalten, nicht beobachtet, Steuern, Monatsende 31., Schaltjahr 29.02.) und vier Stichtage.
- `golden.json`: erwartete Ergebnisse je Stichtag und Fall (Datumswerte als `JJJJ-MM-TT`, Beträge in Hauptwährung CHF mit festen Kursen EUR 0.94, USD 0.80):
  `termEnd`, `noticeDeadline`, `nextTerm`, `effEnd`, `nextDue`, `paymentsNext12`, `curPrice`, `monthlyCostHome`, `anytime`, `needsAction`, `trialNeeds`, `paused`, `shareSinan`, `shareLara`, `cancVia`.
- `make_golden.py`: erzeugt `golden.json` neu aus `index.html` (lokaler Server auf Port 8765, Playwright). Nach jeder Änderung an der Rechenlogik laufen lassen und Unterschiede bewusst prüfen.

In Swift: XCTest, das `cases.json` lädt, das Datum auf den Stichtag fixiert und jedes Feld mit `golden.json` vergleicht.
