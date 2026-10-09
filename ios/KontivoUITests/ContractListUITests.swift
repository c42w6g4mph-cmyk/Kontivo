import XCTest

/// Liste «Verträge»: Suche, Sortierung, Filter, Archiv, Wischen und langes Drücken
final class ContractListUITests: KontivoUITestCase {

    func testSucheSortierungFilterArchiv() {
        launch("-uiDemo", "-uiTab", "contracts")
        wait(buttonStarting("Handy"), "Liste mit Beispieldaten")

        // Suche
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            app.swipeDown(velocity: .slow)
        }
        enter(search, "Netflix", "Suchfeld")
        waitUntil("Nur «Streaming»") { self.buttonStarting("Streaming").exists && !self.buttonStarting("Handy").exists }
        // Suche beenden (iOS 26: «Schließen», früher «Abbrechen»)
        if let close = firstHittable(app.buttons.matching(NSPredicate(format: "label == 'Schließen' OR label == 'Abbrechen'")), timeout: 4) {
            close.tap()
        } else {
            tap(button("Text löschen"), "Suchtext löschen")
        }
        wait(buttonStarting("Handy"), "Liste nach der Suche")

        // Sortierung über das Menü
        tap(buttonStarting("Sortierung ändern"), "Sortierung")
        tap(button("Kosten, höchste zuerst"), "Kosten, höchste zuerst")
        wait(buttonStarting("Sortierung ändern, sortiert nach Kosten"), "Sortiert nach Kosten")

        // Filter Kategorie «Versicherung»
        tap(button("Filter"), "Filter")
        waitNav("Filter")
        tap(buttonStarting("Kategorie"), "Kategorie")
        tap(buttonStarting("Versicherung"), "Versicherung")
        waitUntil("Nur Versicherungen") { self.buttonStarting("Krankenkasse").exists && !self.buttonStarting("Handy").exists }
        // Der Knopf meldet die ganze Zeilenbreite als Rahmen; den Chip selbst (Text) antippen
        let chip = button("Filter Versicherung entfernen")
        wait(chip, "Filter-Chip")
        chip.staticTexts["Versicherung"].firstMatch.tap()
        waitGone(chip, "Filter-Chip")
        // nach Kosten sortiert steht «Handy» weiter unten
        reveal(buttonStarting("Handy"), "Alle Verträge wieder sichtbar")
        XCTAssertFalse(button("Filter Versicherung entfernen").exists, "Filter noch aktiv")

        // Archiv aufklappen
        tap(buttonStarting("Archiv"), "Archiv")
        wait(buttonStarting("TV"), "Beendeter Vertrag «TV» im Archiv")
    }

    func testWischenUndLangesDruecken() {
        launch("-uiDemo", "-uiTab", "contracts")
        let row = buttonStarting("Fitnessabo")
        reveal(row, "Fitnessabo")

        // Wischen → Pausieren → ohne Enddatum
        row.swipeLeft()
        tapTop("Pausieren")
        tap(buttonStarting("Ohne Enddatum"), "Ohne Enddatum")
        waitUntil("Karte zeigt «pausiert» (\(row.label))") { self.buttonStarting("Fitnessabo").label.contains("pausiert") }

        // Wischen → Fortsetzen
        buttonStarting("Fitnessabo").swipeLeft()
        tapTop("Fortsetzen")
        waitUntil("Karte ohne «pausiert»") { !self.buttonStarting("Fitnessabo").label.contains("pausiert") }

        // Langes Drücken → Bearbeiten
        let fit = buttonStarting("Fitnessabo")
        reveal(fit, "Fitnessabo")
        fit.press(forDuration: 1.3)
        tap(button("Bearbeiten"), "Kontextmenü Bearbeiten")
        waitNav("Bearbeiten")
        wait(textField("form.label"), "Formular")
        XCTAssertEqual(textField("form.label").value as? String, "Fitnessabo")
        tapTop("Abbrechen")
        waitUntil("Formular geschlossen") { !self.navExists("Bearbeiten") && !self.textField("form.label").exists }
    }
}
