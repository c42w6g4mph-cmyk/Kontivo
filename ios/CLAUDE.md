# CLAUDE.md – Kontivo iOS

Gilt für jede Claude-Sitzung am Swift-Code, auch für Claude in Xcode.

## Ziel
Native Kontivo-App (SwiftUI, iOS 17+, iPhone zuerst, iPad mit) auf dem Funktions- und Designniveau der Web-Version. Massstab ist die Web-Version im Zweig `main` (`index.html`): alles, was dort ist, kommt in die App, inkl. variable Kosten. Dazu native Zusätze (Face ID/App-Sperre, Mitteilungen, Kalender, Mail/Drucken, iCloud-Sync, Kamera-Scan) und Kauf in der App (StoreKit 2: Abo oder Einmalkauf, Testphase, Käufe wiederherstellen).

## Stand und Plan
- Rechenkern auf Stand Web v323, Oberfläche auf Stand Web v225. Alle Web-Änderungen v226–v323 stehen einzeln in der Nachzug-Checkliste (Projekt-Dokument `kontivo-swift-nachzug`); Kern und Oberfläche sind erst fertig, wenn dort alles abgehakt ist.
- Plan: `kontivo-swift-plan`; Bestandsaufnahme: `kontivo-swift-bestandsaufnahme`; Datenmodell: `main/docs/datenmodell.md`; Regeln aus dem Web-Code: `kontivo-swift-hinweise`.

## Regeln
- Deutsch, Schweizer Rechtschreibung (ss statt ß). In der App immer «Vertragspartner», nie «Partner».
- Gewollte Abweichungen vom Web nur bei iOS-typischen Bedienelementen (Sheets, Alerts, PDF, Gesten); sie stehen in `ARCHITEKTUR.md`.
- Rechnung nur in `KontivoCore`, nie in Views. Stichtag (`Day`) und Person immer als Parameter.
- Kleine Views (Richtwert unter 400 Zeilen je Datei), ein Modell je Formular. Grosse Dateien beim Anfassen aufteilen.
- Keine Compiler-Warnungen.
- Import von Web-Backups über `WebImport` inkl. Migrationen; neue Web-Felder dort immer mitziehen.

## Prüfungen (müssen grün sein)
- Kern: `golden.json`, `golden_budget.json`, `golden_ui.json`, `golden_form.json`, Kontoauszug-Erwartungswerte. Generatoren in `ios/Tools/golden` (mit `WEB=<main-Repo>`, schreiben direkt nach `KontivoCore/Tests/KontivoCoreTests/Resources/`); Budget, Fristen-Ansicht und Formular aus `main/tests`.
- Oberfläche: UI-Tests; Bildvergleich Web gegen Simulator (`ios/Tools/visual/compare.py`) am Ende jedes Bereichs.

## Arbeitsweise
- Push auf den Zweig `swift` nur nach Freigabe durch Sinan («Swift pushen»).
- Nach jeder Änderung kurz berichten: was geändert wurde, was zu testen ist. Erledigte Punkte in der Nachzug-Checkliste abhaken (mit Commit).
