import XCTest

/// b) Neuer Vertrag → Liste → Detail → Bearbeiten → Duplizieren → Pausieren/Fortsetzen → Löschen
final class ContractFlowUITests: KontivoUITestCase {

    private let contractName = "QA Testvertrag"

    private var rows: XCUIElementQuery { app.buttons.matching(pred("label BEGINSWITH %@", contractName)) }

    func testVertragAnlegenBearbeitenDuplizierenPausierenLoeschen() {
        launch("-uiEmpty")

        // Neuer Vertrag über «+»
        openPlusMenuItem("Vertrag erfassen", expect: textField("form.label"))
        waitNav("Neuer Vertrag")
        enter(textField("form.label"), contractName + "\n", "Bezeichnung")
        enter(textField("form.amount"), "45", "Betrag")
        tap(button("form.category"), "Kategorie wählen")
        tap(button("Abos & Medien"), "Kategorie Abos & Medien")
        waitUntil("Kategorie übernommen") { self.button("form.category").label.contains("Abos & Medien") }
        tapTop("Sichern")

        // erscheint in der Liste
        wait(rows.firstMatch, "Vertrag in der Liste", timeout: 10)
        XCTAssertEqual(rows.count, 1)

        // Detail öffnen
        tap(rows.firstMatch, "Vertragskarte")
        wait(button("Bearbeiten"), "Detail")
        wait(elContaining("45.00 CHF"), "Betrag im Detail")

        // Bearbeiten → Betrag ändern → Sichern
        tapTop("Bearbeiten")
        waitNav("Vertrag bearbeiten")
        let amount = textField("form.amount")
        wait(amount, "Betragsfeld")
        XCTAssertEqual(amount.value as? String, "45.00")
        replace(amount, "52", "Betrag ändern")
        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.navExists("Vertrag bearbeiten") }
        wait(elContaining("52.00 CHF"), "Neuer Betrag im Detail")
        XCTAssertFalse(elContaining("45.00 CHF").exists, "Alter Betrag noch sichtbar")

        // Duplizieren (Menü ••• oben, Web 4be2078)
        tap(button("detail.menu"), "Menü •••")
        tap(button("Duplizieren"), "Duplizieren")
        waitNav("Duplizieren")
        tapTop("Sichern")
        waitGone(textField("form.amount"), "Formular Kopie")
        tapTop("Schliessen")
        waitUntil("Zwei Verträge in der Liste") { self.rows.count == 2 }

        // Pausieren → Fortsetzen (Menü •••)
        tap(rows.firstMatch, "Vertragskarte")
        tap(button("detail.menu"), "Menü •••")
        tap(button("Pausieren"), "Pausieren")
        tap(buttonStarting("1 Monat"), "1 Monat")
        // Detail schliesst sich nach Aktionen (wie Web)
        waitGone(button("Bearbeiten"), "Detail nach dem Pausieren")
        let pausedRow = app.buttons.matching(pred("label BEGINSWITH %@ AND label CONTAINS %@", contractName, "pausiert")).firstMatch
        tap(pausedRow, "Pausierte Vertragskarte")
        wait(elContaining("Pausiert bis"), "Pille «Pausiert bis»")
        tap(button("detail.menu"), "Menü •••")
        tap(button("Fortsetzen"), "Fortsetzen nach dem Pausieren")
        waitGone(button("Bearbeiten"), "Detail nach dem Fortsetzen")
        waitUntil("Keine Karte mehr «pausiert»") { !pausedRow.exists }
        tap(rows.firstMatch, "Vertragskarte")
        tap(button("detail.menu"), "Menü •••")
        wait(button("Pausieren"), "Pausieren nach dem Fortsetzen")

        // Löschen mit Bestätigung → Detail schliesst sich
        tap(button("Löschen"), "Löschen")
        wait(app.alerts.firstMatch, "Rückfrage «Vertrag löschen?»")
        tapAlertButton("Löschen")
        waitGone(button("Bearbeiten"), "Detail nach dem Löschen")
        waitUntil("Ein Vertrag übrig") { self.rows.count == 1 }
    }

    /// Abbrechen mit Änderungen fragt nach; «Verwerfen» schliesst ohne zu sichern
    func testFormularVerwerfen() {
        launch("-uiEmpty")
        openPlusMenuItem("Vertrag erfassen", expect: textField("form.label"))
        enter(textField("form.label"), "Wird verworfen", "Bezeichnung")
        tapTop("Abbrechen")
        tapAlertButton("Verwerfen")
        waitGone(textField("form.label"), "Formular")
        wait(button("Ersten Vertrag erfassen"), "Leerseite bleibt")
    }
}
