import XCTest

/// Vertragsansicht, Kündigen und Fristen auf Stand Web v160:
/// «Schon gekündigt …» mit «Läuft bis», Probeabo-Kasten «Behalten», Prüfung vor «Per E-Mail kündigen» (Kundennummer fehlt),
/// Fristen «Endet von selbst» und Vertragspartner hinter dem Titel.
/// Fälle, die die Beispieldaten nicht haben, setzt das Startargument «-uiSeed» (siehe `CTUITestSeed`).
final class ContractDetailUITests: KontivoUITestCase {

    /// Menü ••• → «Schon gekündigt …» → Chip «30.11.26 (Termin)» → «Sichern»: Karte «gekündigt per 30.11.26»,
    /// Detail mit Pille «Gekündigt · läuft bis …» und «Kündigung zurücknehmen» statt «Schon gekündigt …» (Web v154)
    func testSchonGekuendigtLaeuftBis() {
        launch("-uiDemo", "-uiTab", "contracts")
        tap(buttonStarting("Fitnessabo"), "Karte Fitnessabo")
        wait(button("Bearbeiten"), "Detail Fitnessabo")
        tap(button("detail.menu"), "Menü •••")
        tap(buttonStarting("Schon gekündigt"), "Schon gekündigt …")
        waitNav("Schon gekündigt")
        wait(elContaining("Vorgeschlagen ist der nächste mögliche Termin"), "Text der Rückfrage")
        wait(button("heute"), "Chip heute")
        let termin = buttonStarting("30.11.26")
        wait(termin, "Chip «30.11.26 (Termin)»")
        ctShot("Detail – Schon gekündigt")
        tap(termin, "Chip Termin")
        tap(button("detail.cancelled.save"), "Sichern")
        waitGone(button("detail.menu"), "Detail nach dem Sichern")
        waitUntil("Karte «gekündigt per 30.11.26»") { self.buttonStarting("Fitnessabo").label.contains("gekündigt per 30.11.26") }

        tap(buttonStarting("Fitnessabo"), "Karte Fitnessabo")
        wait(elContaining("Gekündigt · läuft bis 30. November 2026"), "Pille «Gekündigt · läuft bis …»")
        tap(button("detail.menu"), "Menü •••")
        wait(button("Kündigung zurücknehmen"), "Menü Kündigung zurücknehmen")
        XCTAssertFalse(buttonStarting("Schon gekündigt").exists, "«Schon gekündigt …» nach der Kündigung")
        ctShot("Detail – gekündigt, Menü")
    }

    /// Laufendes Probeabo: Kasten «Probeabo bis 19. Oktober» · «danach kostenpflichtig …», Zeile «Probeabo: gratis bis …»;
    /// «Behalten» setzt das Probeabo auf behalten (Toast «… läuft nach dem Probeabo normal weiter»), danach kein Kasten mehr
    func testProbeaboKastenBehalten() {
        launch("-uiDemo", "-uiTab", "contracts")
        tap(buttonStarting("Musik"), "Karte Musik")
        wait(button("Bearbeiten"), "Detail Musik")
        wait(elContaining("Probeabo bis 19. Oktober"), "Kasten Probeabo")
        wait(elContaining("danach kostenpflichtig"), "Untertitel Kasten")
        wait(elContaining("gratis bis 19. Oktober 2026"), "Zeile Probeabo")
        ctShot("Detail – Probeabo")
        tap(button("detail.deadline.keep"), "Behalten")
        waitGone(button("detail.menu"), "Detail nach Behalten")

        tap(buttonStarting("Musik"), "Karte Musik")
        wait(button("Bearbeiten"), "Detail Musik")
        XCTAssertFalse(elContaining("Probeabo bis").exists, "Probeabo-Kasten nach «Behalten»")
        XCTAssertFalse(elContaining("gratis bis").exists, "Zeile Probeabo nach «Behalten»")
    }

    /// «Per E-Mail kündigen» ohne Kunden- und Vertragsnummer: Rückfrage «Kundennummer fehlt» → «Nummer eintragen» öffnet das Formular
    func testEmailPruefungKundennummer() {
        launch("-uiDemo", "-uiTab", "contracts", "-uiSeed", "mailcheck")
        tap(buttonStarting("Handy"), "Karte Handy")
        wait(button("Bearbeiten"), "Detail Handy")
        tap(button("detail.menu"), "Menü •••")
        tap(buttonStarting("Kündigen"), "Kündigen per E-Mail")
        let alert = app.alerts.firstMatch
        wait(alert, "Rückfrage «Kundennummer fehlt»")
        XCTAssertTrue(alert.label.contains("Kundennummer fehlt") || elContaining("Kundennummer fehlt").exists, "Titel: \(alert.label)")
        XCTAssertTrue(alert.buttons["Ohne senden"].exists, "Knopf «Ohne senden»")
        ctShot("Kündigen – Kundennummer fehlt")
        tapAlertButton("Nummer eintragen")
        waitNav("Bearbeiten", timeout: 12)
        tapTop("Abbrechen")
        if app.alerts.firstMatch.waitForExistence(timeout: 2) || app.sheets.firstMatch.exists {
            tapAlertButton("Verwerfen")
        }
        waitUntil("Formular geschlossen") { !self.navExists("Bearbeiten") }
    }

    /// Fristen: feste Laufzeit ohne Verlängerung als «Endet von selbst» ohne Knöpfe (Web v160), Vertragspartner grau hinter
    /// dem Titel (Web v143); Detail «Kündigung: nicht nötig · endet von selbst» ohne Zeitstrahl
    func testFristenEndetVonSelbst() {
        launch("-uiDemo", "-uiTab", "deadlines", "-uiSeed", "endsself")
        let row = buttonStarting("Fitnessabo")
        wait(row, "Zeile Fitnessabo")
        waitUntil("«Endet von selbst» (\(row.label))") { self.buttonStarting("Fitnessabo").label.contains("Endet von selbst") }
        XCTAssertTrue(row.label.contains("Update Fitness"), "Vertragspartner hinter dem Titel: \(row.label)")
        XCTAssertTrue(row.label.contains("endet 30.11."), "Chip «endet 30.11.»: \(row.label)")
        let trial = buttonStarting("Musik")
        wait(trial, "Zeile Probeabo Musik")
        XCTAssertTrue(trial.label.contains("Spotify"), "Vertragspartner Spotify: \(trial.label)")
        XCTAssertTrue(trial.label.contains("Probeabo · gratis bis 19.10."), "Probeabo-Zeile: \(trial.label)")
        ctShot("Fristen – Endet von selbst")

        tap(row, "Zeile Fitnessabo")
        wait(button("Bearbeiten"), "Detail Fitnessabo")
        reveal(elContaining("nicht nötig · endet von selbst"), "Zeile Kündigung")
        XCTAssertFalse(el("detail.timeline").exists, "Kein Zeitstrahl bei «Endet von selbst»")
        ctShot("Detail – Endet von selbst")
    }
}
