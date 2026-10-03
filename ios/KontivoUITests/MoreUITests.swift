import XCTest

/// f) Mehr: Darstellung; Verwalten → Kategorien, Inhaber/Absender, Datenqualität
/// g) Alle Daten löschen
final class MoreUITests: KontivoUITestCase {

    func testDarstellung() {
        launch("-uiDemo", "-uiTab", "more")
        let dark = button("Dunkel")
        tap(dark, "Dunkel")
        waitUntil("Dunkel gewählt") { dark.isSelected }
        let auto = button("Automatisch")
        tap(auto, "Automatisch")
        waitUntil("Automatisch gewählt") { auto.isSelected }
        XCTAssertFalse(dark.isSelected)
    }

    func testKategorieAnlegenUmbenennenLoeschen() {
        launch("-uiDemo", "-uiTab", "more")
        tap(buttonStarting("Kategorien"), "Zeile Kategorien")
        waitNav("Kategorien")

        // Neue Kategorie
        tap(button("Kategorie hinzufügen"), "Kategorie hinzufügen")
        waitNav("Neue Kategorie")
        // Eingabetaste übernimmt (onSubmit)
        enter(textField("Name"), "QA Haustier\n", "Name")
        waitNav("Kategorien")
        let row = buttonStarting("QA Haustier")
        tap(row, "Neue Kategorie in der Liste")

        // Umbenennen
        waitNav("QA Haustier")
        let field = textField("Name")
        wait(field, "Namensfeld")
        replace(field, "QA Tiere\n", "Name ändern")
        waitNav("QA Tiere")

        // Löschen (leer → einfache Rückfrage)
        tap(button("Kategorie löschen"), "Kategorie löschen")
        tapAlertButton("Löschen")
        waitNav("Kategorien")
        waitUntil("Kategorie entfernt") { !self.buttonStarting("QA Tiere").exists && !self.buttonStarting("QA Haustier").exists }
        tapTop("Fertig")
        waitUntil("Verwalten geschlossen") { !self.navExists("Kategorien") }
    }

    func testInhaberAnlegenUndAbsender() {
        launch("-uiDemo", "-uiTab", "more")
        tap(buttonStarting("Inhaber"), "Zeile Inhaber")
        waitNav("Inhaber")
        tap(button("Inhaber hinzufügen"), "Inhaber hinzufügen")
        waitNav("Neuer Inhaber")
        enter(textField("Name"), "Mia", "Name")
        tapContent("Hinzufügen")
        waitNav("Inhaber")

        // Personenkarte
        tap(buttonStarting("Mia"), "Person Mia")
        waitNav("Mia")
        tap(buttonStarting("Absender"), "Absender")
        waitNav("Absender")
        enter(textField("Vorname"), "Mia", "Vorname")
        enter(textField("Nachname"), "Muster", "Nachname")
        enter(textField("Strasse und Nr."), "Seeweg 1", "Strasse")
        enter(textField("PLZ"), "8280", "PLZ")
        enter(textField("Ort"), "Kreuzlingen", "Ort")
        goBack()
        waitNav("Mia")
        let sender = buttonStarting("Absender")
        wait(sender, "Zeile Absender")
        waitUntil("Absender gespeichert (\(sender.label))") { sender.label.contains("Seeweg 1") && sender.label.contains("8280 Kreuzlingen") }
        tapTop("Fertig")
    }

    func testDatenqualitaetInlineWert() {
        launch("-uiDemo", "-uiTab", "more")
        tap(buttonStarting("Datenqualität"), "Zeile Datenqualität")
        waitNav("Datenqualität")
        tap(buttonStarting("Kündigungsweg gewählt"), "Kriterium Kündigungsweg")
        waitNav("Kündigungsweg gewählt")
        let online = buttons("Online")
        wait(online.firstMatch, "Auswahl Online")
        let n0 = online.count
        XCTAssertGreaterThan(n0, 0)
        tap(online.firstMatch, "Online")
        if n0 > 1 {
            waitUntil("Ein Eintrag weniger") { online.count == n0 - 1 }
            wait(elContaining(n0 - 1 == 1 ? "1 Eintrag" : "\(n0 - 1) Einträge"), "Zähler im Kopf")
        } else {
            wait(el("Erledigt."), "Erledigt.")
        }
        goBack()
        waitNav("Datenqualität")
        tapTop("Fertig")
    }

    func testAlleDatenLoeschen() {
        launch("-uiDemo", "-uiTab", "more")
        tap(button("Alle Daten löschen"), "Alle Daten löschen")
        wait(app.alerts.firstMatch, "Rückfrage 1")
        tapAlertButton("Weiter")
        wait(app.alerts.firstMatch, "Rückfrage 2", timeout: 6)
        tapAlertButton("Endgültig löschen")
        wait(button("Ersten Vertrag erfassen"), "Leerseite Verträge", timeout: 10)
        tapTab("Kosten")
        wait(elContaining("im Voraus geplant"), "Leerseite Kosten")
        tapTab("Budget")
        wait(button("Einnahme erfassen"), "Leerseite Budget")
        tapTab("Fristen")
        wait(elContaining("Frist verpassen"), "Leerseite Fristen")
    }

    func testVertragspartnerOeffnen() {
        launch("-uiDemo", "-uiTab", "more")
        tap(buttonStarting("Vertragspartner"), "Zeile Vertragspartner")
        waitNav("Vertragspartner")
        tap(buttonStarting("Swisscom"), "Swisscom")
        waitNav("Swisscom")
        goBack()
        waitNav("Vertragspartner")
        tapTop("Fertig")
        waitUntil("Verwalten geschlossen") { !self.navExists("Vertragspartner") }
    }
}
