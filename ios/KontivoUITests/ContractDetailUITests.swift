import XCTest

/// Vertragsansicht, Kündigen und Fristen auf Stand Web v160:
/// Probeabo-Kasten «Behalten», «Schon gekündigt …» mit «Läuft bis», Fristen «Endet von selbst» und Vertragspartner hinter
/// dem Titel, Prüfung vor «Per E-Mail kündigen» (Kundennummer fehlt).
/// Fälle, die die Beispieldaten nicht haben, setzt das Startargument «-uiSeed» (siehe `CTUITestSeed`).
/// Je Test nur ein Start (die UI-Tests der CI haben ein knappes Zeitbudget).
final class ContractDetailUITests: KontivoUITestCase {

    /// 1) Laufendes Probeabo: Kasten «Probeabo bis 19. Oktober» · «danach kostenpflichtig …», Zeile «Probeabo: gratis bis …»;
    ///    «Behalten» setzt das Probeabo auf behalten, danach kein Kasten mehr.
    /// 2) Menü ••• → «Schon gekündigt …» → «Gekündigt am» heute, «Läuft bis» 30.11.26 → «Ja, gekündigt»: Karte «gekündigt per 30.11.26», Detail mit
    ///    Pille «Gekündigt · läuft bis …» und «Kündigung zurücknehmen» statt «Schon gekündigt …» (Web v154)
    func testProbeaboBehaltenUndSchonGekuendigt() {
        launch("-uiDemo", "-uiTab", "contracts")

        // 1) Probeabo «Musik»
        tap(buttonStarting("Musik"), "Karte Musik")
        wait(elContaining("Probeabo bis 19. Oktober"), "Kasten Probeabo")
        XCTAssertTrue(elContaining("danach kostenpflichtig").exists, "Untertitel Kasten")
        XCTAssertTrue(elContaining("gratis bis 19. Oktober 2026").exists, "Zeile Probeabo")
        ctShot("Detail – Probeabo")
        tap(button("detail.deadline.keep"), "Behalten")
        waitGone(button("detail.menu"), "Detail nach Behalten")
        tap(buttonStarting("Musik"), "Karte Musik")
        wait(button("detail.menu"), "Detail Musik")
        XCTAssertFalse(elContaining("Probeabo bis").exists, "Probeabo-Kasten nach «Behalten»")
        XCTAssertFalse(elContaining("gratis bis").exists, "Zeile Probeabo nach «Behalten»")
        tapTop("Schliessen")
        waitGone(button("detail.menu"), "Detail Musik geschlossen")

        // 2) «Schon gekündigt …» bei «Fitnessabo»
        tap(buttonStarting("Fitnessabo"), "Karte Fitnessabo")
        tap(button("detail.menu"), "Menü •••")
        tap(buttonStarting("Schon gekündigt"), "Schon gekündigt …")
        // Web v249: «Gekündigt am» (heute) und «Läuft bis» (ab diesem Tag gerechnet: 30.11.26)
        waitNav("Schon gekündigt")
        XCTAssertTrue(elContaining("Das Vertragsende rechnet Kontivo ab diesem Tag").exists, "Text der Rückfrage")
        wait(el("cancelled.on"), "Feld «Gekündigt am»")
        wait(el("cancelled.per"), "Feld «Läuft bis»")
        ctShot("Detail – Schon gekündigt")
        tap(button("cancelled.yes"), "Ja, gekündigt")
        waitGone(button("detail.menu"), "Detail nach dem Sichern")
        waitUntil("Karte «gekündigt per 30.11.26»") { self.buttonStarting("Fitnessabo").label.contains("gekündigt per 30.11.26") }
        tap(buttonStarting("Fitnessabo"), "Karte Fitnessabo")
        wait(elContaining("Gekündigt · läuft bis 30. November 2026"), "Pille «Gekündigt · läuft bis …»")
        tap(button("detail.menu"), "Menü •••")
        wait(button("Kündigung zurücknehmen"), "Menü Kündigung zurücknehmen")
        XCTAssertFalse(buttonStarting("Schon gekündigt").exists, "«Schon gekündigt …» nach der Kündigung")
        ctShot("Detail – gekündigt, Menü")
    }

    /// 1) Fristen: feste Laufzeit ohne Verlängerung als «Endet von selbst» ohne Knöpfe (Web v160), Vertragspartner grau hinter
    ///    dem Titel (Web v143); Detail «Kündigung: nicht nötig · endet von selbst» ohne Zeitstrahl.
    /// 2) «Per E-Mail kündigen» ohne Kunden- und Vertragsnummer: Rückfrage «Kundennummer fehlt» → «Nummer eintragen» öffnet
    ///    das Formular.
    func testEndetVonSelbstUndEmailPruefung() {
        launch("-uiDemo", "-uiTab", "deadlines", "-uiSeed", "endsself,mailcheck")

        // 1) Fristen
        let row = buttonStarting("Fitnessabo")
        wait(row, "Zeile Fitnessabo")
        waitUntil("«Endet von selbst» (\(row.label))") { self.buttonStarting("Fitnessabo").label.contains("Endet von selbst") }
        XCTAssertTrue(row.label.contains("Update Fitness"), "Vertragspartner hinter dem Titel: \(row.label)")
        XCTAssertTrue(row.label.contains("endet 30.11."), "Chip «endet 30.11.»: \(row.label)")
        let trial = buttonStarting("Musik")
        XCTAssertTrue(trial.label.contains("Spotify"), "Vertragspartner Spotify: \(trial.label)")
        XCTAssertTrue(trial.label.contains("Probeabo · gratis bis 19.10."), "Probeabo-Zeile: \(trial.label)")
        ctShot("Fristen – Endet von selbst")
        tap(row, "Zeile Fitnessabo")
        reveal(elContaining("nicht nötig · endet von selbst"), "Zeile Kündigung")
        XCTAssertFalse(el("detail.timeline").exists, "Kein Zeitstrahl bei «Endet von selbst»")
        tapTop("Schliessen")
        waitGone(button("detail.menu"), "Detail Fitnessabo geschlossen")

        // 2) E-Mail-Prüfung bei «Handy» (Kündigungsweg E-Mail, ohne Nummern)
        tapTab("Verträge")
        tap(buttonStarting("Handy"), "Karte Handy")
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
}
