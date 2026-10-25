# Fix-Liste swift-f1 (Bereich Kern)

## Erledigt
- A9 (s5): Day(date:)/date()/today()/reviewDue/Backup.confirmText Standardkalender = Day.calendar (gregorianisch, aktuelle Zeitzone)
- BK-1: Backup-Rückfrage «1 Logo/Dokument»
- W-1..W-6, BK-2, addrSplit-Nachtrag (WebImport), C-2/F6 (regDom SLD2), M-2 (Partners.find nur gleicher Name, Partners.similar als Hinweis)
- Q-1/F3, Q-2/F5, Q-3b (Quality), M-5 (duplicateCategory/duplicatePerson), M-6 (Art folgt Umbenennen), Calc.isTax mit «Steuern…»-Namensregel

- L-1 (isRent wie Web), L-2 (Absender-Kürzung senderCut), L-3 (Frist-Hinweis zweiter Satz)
- C-1 (catalog.json neu erzeugt, Bank-Regel Monatsende), N-0 (index.html im Worktree = main)

- CSV-1 (Frist 0/«jederzeit»/Pflicht beim Rundlauf), CSV-2 (Turnus runden, adjustedCycles), CSV-3 (einzeilige Adresse), CSV-4 (Inhaber wie Web), CSV-5 a/b (badDates, JJJJ/MM/TT)
- M-1/F1 (transferAll wie mapHolders, sharedEntryCount), M-3 (Inhaber sortiert, cancelURL nur Online, invalidNotice), M-4 (setSender ohne Ketten), Format.noticeValue

- K-1 (Format.fixed1 wie toFixed(1)), F-1 (domain klein + Punycode), COD-1 (Listen elementweise lesen, AppData wirft bei unlesbarer Liste)
- F-2: bereits in ARCHITEKTUR.md als bewusste Abweichung (U+2212)

- Teil B: tests/make_golden_texts.py + cases_texts.json → golden_texts.json; Swift TextGoldenTests (urgency, Fristen, CSV, Datenqualität, Briefe)

- CI: Kern- und Vergleichstests grün (Lauf 57); letzter Lauf ohne [noui]

## Bewusst nicht behoben
- W-3 (a): Vertrag ohne Vertragspartner, Adresse ohne Firmenzeile → Vertragspartner heisst wie die Bezeichnung (Brief zeigt sie als erste Zeile). Sauber nur mit Adressfeld am Vertrag (Datenmodell) – Rückfrage nötig.
- Q-3 (a): gelöschte Kategorie ohne Namen im Grund (ID-Modell, Name unbekannt); Import legt fehlende Kategorien ohnehin an.
- CSV-5 (c): Tausender-Erkennung «1.000» = 1000 bleibt (bewusster Swift-Fix L1).
- CSV-6: Spalte «Einheit» bleibt «m» auch ohne Frist (nur Text, Import gleichwertig).
- M-5 teilweise: Umbenennen von Person/Vertragspartner auf bestehenden Namen bleibt `duplicateName` (App fragt nach Zusammenführen).
- B-1, K-2: liegen in ExtKostenBudget.swift (Bereich f3).
