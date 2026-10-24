# Prüffälle für die Rechenlogik

Zweck: Die SwiftUI-Version muss Fristen, Termine und Kosten genau gleich berechnen wie die Web-App.

- `cases.json`: 25 Verträge mit allen Sonderfällen (Kündigungsrhythmen m/q/h/y/a/p, Fristen in Tagen/Wochen/Monaten/«bis zum n.», befristet mit und ohne Verlängerung, verpasste Frist, Probeabo, Pause, Start in der Zukunft, Preisänderung, Fremdwährung, gekündigt, behalten, nicht beobachtet, Steuern, Monatsende 31., Schaltjahr 29.02.) und vier Stichtage.
- `golden.json`: erwartete Ergebnisse je Stichtag und Fall (Datumswerte als `JJJJ-MM-TT`, Beträge in Hauptwährung CHF mit festen Kursen EUR 0.94, USD 0.80):
  `termEnd`, `noticeDeadline`, `nextTerm`, `effEnd`, `nextDue`, `paymentsNext12`, `curPrice`, `monthlyCostHome`, `anytime`, `needsAction`, `trialNeeds`, `paused`, `shareSinan`, `shareLara`, `cancVia`.
- `make_golden.py`: erzeugt `golden.json` neu aus `index.html` (lokaler Server auf Port 8765, Playwright). Nach jeder Änderung an der Rechenlogik laufen lassen und Unterschiede bewusst prüfen (`git diff tests/golden.json` muss leer bleiben). Der Live-Kursabruf ist blockiert, es gelten immer die festen Testkurse.

In Swift: XCTest, das `cases.json` lädt, das Datum auf den Stichtag fixiert und jedes Feld mit `golden.json` vergleicht.

## Summen, Budget, Duplikate (`cases_budget.json`)
- `cases_budget.json`: ein Haushalt mit zwei Personen (14 Verträge, 5 Einnahmen, 3 variable Kosten) an drei Stichtagen. Enthält Aufteilung (60/40, 70/30), Preisänderungen, Sonderzahlung und Gutschrift, Probeabo, Pause, Fremdwährungen EUR/USD, gekündigt, nicht kündbar, Beginn in der Zukunft, Leasing mit Ende, einmalige Einnahme, variable Kosten mit Beginn/Ende, zwei Verträge desselben Vertragspartners («Swisscom AG»/«Swisscom») und Abfragen für den Duplikat-Hinweis (`dupQueries`).
- `golden_budget.json`: erwartete Werte je Stichtag für Vorjahr, Stichtagsjahr und Folgejahr, je Person (alle, Sinan, Lara) und Kostenart (`all`, `fix`, `none`): Fixkosten pro Monat (Kopfzeile), Kosten-Tab je Monat (Summe, bezahlt, offen, Anzahl), Budget je Monat (Einnahmen, Fixkosten, variable, verfügbar), Vorjahresmonat, «Fair geteilt?», Einnahmen und variable Kosten pro Monat, Duplikat-Treffer, Vertragspartner-Dubletten. Beträge in CHF auf Rappen gerundet.
- `make_golden_budget.py`: erzeugt `golden_budget.json` aus `index.html` (wie `make_golden.py`). `git diff tests/golden_budget.json` muss nach Änderungen leer bleiben, ausser die Rechnung soll sich bewusst ändern.
- Die Funktionen dazu stehen im Abschnitt «Rechnen» von index.html und sind über `window.KontivoCalc()` erreichbar: `fixMonthSum`, `costMonths`, `paySum`, `budgetYear`, `budgetMonth`, `fairShare`, `varMonth`, `incMonthNow`, `dupOf`, `partnerGroups`.

## Datenmodell (`check_model.py`)
- `python3 tests/check_model.py [Datei.json …]` prüft Daten (Backup, localStorage-Inhalt, Testdaten) gegen `docs/datenmodell.md`: unbekannte Felder und falsche Typen. Ohne Angabe wird `cases_budget.json` geprüft. Kein Server nötig.

# Prüfungen für den Kontoauszug-Import (`tests/bank/`)

## Voraussetzungen
- Python 3 mit Playwright und Chromium: `pip install playwright && playwright install chromium`
- `zipfmt.py` zusätzlich: `pip install openpyxl`; für ODS LibreOffice (`soffice`), ohne `soffice` wird ODS übersprungen
- Lokaler Server im Repo-Ordner: `python3 -m http.server 8765`. Alle Prüfskripte nehmen standardmässig `http://localhost:8765/index.html`, ein anderer Port über `KONTIVO_URL`, z.B. `KONTIVO_URL=http://localhost:8775/index.html python3 tests/bank/check.py`
- Alle Skripte setzen das Datum fest (`window.__KONTIVO_TODAY`), blockieren den Kursabruf (`page.route`) und setzen `rateCheckedAt`, damit das Ergebnis nicht vom Netz oder vom Tag abhängt
- Exit-Code 0 = alles grün, 1 = mindestens eine Abweichung

## Prüfskripte (Server nötig)
| Skript | Zweck | Daten |
|---|---|---|
| `bank/check.py [-v]` | Erwartete Vorschläge je Musterdatei: Vertragspartner, Rhythmus, Betrag, Preisänderungen (CSS 2026-01, Spotify 2026-07, Deutschlandticket), Abgleich mit erfassten Verträgen | `samples/` |
| `bank/real.py [-v] [Filter]` | Nachgebaute echte Bankformate CH/DE (66 Dateien, Quellen in `real/*/SOURCES.md`): erwartete Verträge, nichts Überflüssiges | `real/ch`, `real/de` |
| `bank/edge.py` | Grenzfälle aus dem Review (Namen, Zuordnung, Fälligkeit, Aliasse) und Laufzeit der Stressdateien (< 3 s) | `edge_cases.json`, `stress/` |
| `bank/multi.py` | Mehrere Dateien: gleiche Datei doppelt zählt einmal, Konto + Kreditkarte ergänzen sich | `samples/`, `real/de` |
| `bank/zipfmt.py` | ZIP-basierte Formate: xlsx (auch mit Präfixen), ODS, ZIP mit CSV, ZIP ohne Auszug | erzeugt aus `samples/de_deutschebank.csv` |
| `bank/stress/run_stress.py [-v]` | Lange Auszüge (18 Monate, viele Alltagsbuchungen): erwartete Verträge und Einnahmen, nichts Überflüssiges | `stress/*.csv` |
| `bank/ui_flow.py` | Bedienablauf im Browser (iPhone-Grösse, hell und dunkel): Datei wählen, Vorschlag bearbeiten, ausblenden, übernehmen, Rückfrage «Fast fertig!», zweiter Import, falsche Datei. Screenshots nach `KONTIVO_SHOTS` (Standard `/tmp/kontivo-bank-ui`) | `samples/ch_postfinance.csv` |

## Generatoren (ohne Server; erzeugen die eingecheckten Testdaten byte-gleich)
| Skript | Ergebnis |
|---|---|
| `bank/make_samples.py` | `samples/` (gängige CH-/DE-Formate, einfaches Szenario) |
| `bank/real/gen/gen.py`, `bank/real/gen/camt.py` | `real/ch` (Szenario in `scenario.py`) |
| `bank/real/gen/gen_de.py <Zielordner>` | `real/de` |
| `bank/stress/make_stress.py` | `stress/*.csv` |

`samples/` und `real/` überschneiden sich bei den Banken, haben aber verschiedene Aufgaben: `samples/` mit `check.py` prüft Preisänderungen und den Abgleich mit erfassten Verträgen und wird von `multi.py`, `zipfmt.py` und `ui_flow.py` gebraucht; `real/` deckt die Formatvielfalt ab. Für den SwiftUI-Nachbau reichen `real/`, `edge_cases.json` und die Erwartungen aus `check.py`.

## Alles auf einmal
```
python3 -m http.server 8765 &
python3 tests/make_golden.py && git diff --stat tests/golden.json
python3 tests/make_golden_budget.py && git diff --stat tests/golden_budget.json
python3 tests/check_model.py
for t in check edge multi real zipfmt ui_flow; do python3 tests/bank/$t.py | tail -2; done
python3 tests/bank/stress/run_stress.py | tail -2
```
