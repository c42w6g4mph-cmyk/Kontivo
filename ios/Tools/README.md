# Werkzeuge

Nicht Teil der App. Alle Skripte lesen die Web-App aus dem Branch `main` (Pfad über `WEB=<main-Repo>` bzw. als Argument).

- `golden/` – Prüffälle aus der Web-App erzeugen (Playwright, lokaler Server im Web-Repo). Schreiben direkt nach
  `KontivoCore/Tests/KontivoCoreTests/Resources/`: `make_golden.py` (Rechenkern), `make_golden_texts.py` (Texte),
  `make_golden_drivers.py` (Kosten «Was sich verändert hat»), `make_golden_import.py` (Backup-Bereinigung).
  Budget und Fristen-Ansicht: `main/tests/make_golden_budget.py`, `main/tests/make_golden_ui.py`.
- `visual/` – Bildvergleich Web gegen Simulator (`web_shots.py`, `compare.py`).
- `design/` – Symbole (`web_icons.py`) und Wortmarke (`wordmark_glyphs.py`) aus der Web-App übernehmen.
- Kontoauszug-Erwartungswerte: `KontivoCore/Tests/KontivoCoreTests/BankFixtures/make_expected.py`, `make_zip.py`.
- Anbieterkatalog: `KontivoCore/Scripts/make_catalog.py <main-Repo>/index.html`.
