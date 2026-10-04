# Prüffälle für die Rechenlogik

Zweck: Die SwiftUI-Version muss Fristen, Termine und Kosten genau gleich berechnen wie die Web-App.

- `cases.json`: 25 Verträge mit allen Sonderfällen (Kündigungsrhythmen m/q/h/y/a/p, Fristen in Tagen/Wochen/Monaten/«bis zum n.», befristet mit und ohne Verlängerung, verpasste Frist, Probeabo, Pause, Start in der Zukunft, Preisänderung, Fremdwährung, gekündigt, behalten, nicht beobachtet, Steuern, Monatsende 31., Schaltjahr 29.02.) und vier Stichtage.
- `golden.json`: erwartete Ergebnisse je Stichtag und Fall (Datumswerte als `JJJJ-MM-TT`, Beträge in Hauptwährung CHF mit festen Kursen EUR 0.94, USD 0.80):
  `termEnd`, `noticeDeadline`, `nextTerm`, `effEnd`, `nextDue`, `paymentsNext12`, `curPrice`, `monthlyCostHome`, `anytime`, `needsAction`, `trialNeeds`, `paused`, `shareSinan`, `shareLara`, `cancVia`.
- `make_golden.py`: erzeugt `golden.json` neu aus `index.html` (lokaler Server auf Port 8765, Playwright). Nach jeder Änderung an der Rechenlogik laufen lassen und Unterschiede bewusst prüfen.

In Swift: XCTest, das `cases.json` lädt, das Datum auf den Stichtag fixiert und jedes Feld mit `golden.json` vergleicht.

## Texte und Regeln (Ergänzung)

- `cases_texts.json`: kleines Test-Backup (Web-Format) mit Stichtag, für Datenqualität und Kündigungsschreiben.
- `golden_texts.json`: Referenzwerte aus der Web-App, erzeugt mit `make_golden_texts.py`:
  je Stichtag aus `cases.json` die Dringlichkeit (`urgency`: Stufe, Tage, Datum), den Tab «Fristen» (Kopfzeile, Entscheidungskarten, Kommende Termine, Klappgruppen) und den CSV-Export;
  für `cases_texts.json` die Datenqualität (Kopf, Checkliste mit Zählern, Einträge je «n offen»-Seite mit Schlüssel, Name, Zusatz) und das Kündigungsschreiben (Absenderzeile, Empfänger, Betreff, Text, Hinweise).
- `make_golden_texts.py` liest das gerenderte DOM (index.html bleibt unverändert); nur `urgency` wird aus dem Quelltext von index.html mit den Funktionen von `window.KontivoCalc()` berechnet.
  Aufruf: `python3 -m http.server 8771 &` und `KONTIVO_URL=http://localhost:8771/index.html python3 tests/make_golden_texts.py`.
- Swift: `TextGoldenTests` (Kopien der JSON-Dateien liegen in `ios/KontivoCore/Tests/KontivoCoreTests/Resources/`). Nach dem Neuerzeugen beide Dateien dorthin kopieren.
