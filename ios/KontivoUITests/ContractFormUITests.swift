import XCTest

/// Vertragsformular Stand Web v160 (eine Seite «wie die Ansicht»): Mindestlaufzeit mit Drehrad «Andere …», «Zahlung am» als
/// Tagesraster, Kündigungsfrist «keine», Sichern ohne Vertragsende, Abbrechen mit Rückfrage, Bildschirmfotos (neu, Bearbeiten,
/// Probeabo, Dunkelmodus) für den Vergleich mit der Web-App.
final class ContractFormUITests: KontivoUITestCase {

    private func openNewForm() {
        openPlusMenuItem("Vertrag erfassen", expect: textField("form.label"))
        waitNav("Neuer Vertrag")
    }

    /// Erste Spalte eines Drehrads (UIPickerView mit Spalten)
    private func wheel(_ i: Int) -> XCUIElement {
        app.pickerWheels.element(boundBy: i)
    }

    /// Mindestlaufzeit (Web v145/v149): ohne Beginn Meldung; 2 Jahre bzw. «Andere …» 18 Monate rechnen das Vertragsende
    /// (Beginn + n Monate − 1 Tag); Knopf zeigt «18 Mt.», Verlängerung leer → 1 Monat (Web v156)
    func testMindestlaufzeitAndereDrehrad() {
        launch("-uiEmpty")
        openNewForm()
        tap(button("term.fixed"), "Knopf Mindestlaufzeit")
        tap(button("termMonths.24"), "Knopf 2 Jahre")
        wait(elContaining("Zuerst den Vertragsbeginn eintragen"), "Meldung ohne Vertragsbeginn")
        tap(button("Vertragsbeginn wählen"), "Vertragsbeginn (heute, 03.10.2026)")
        XCTAssertTrue(button("termMonths.24").isSelected, "Knopf 2 Jahre gewählt")
        // 03.10.2026 + 24 Monate − 1 Tag; Verlängerung 1 Monat vorbelegt
        reveal(elContaining("Kündigen bis 2. Oktober 2028, sonst +1 Monat."), "Hinweis mit Vertragsende aus 2 Jahren")

        revealUp(button("termMonths.other"), "Knopf Andere …")
        tap(button("termMonths.other"), "Knopf Andere …")
        let w = wheel(0)
        wait(w, "Drehrad Monate")
        w.adjust(toPickerWheelValue: "18")
        let ok = button("form.termMonthsOK")
        waitUntil("Knopf «18 Monate übernehmen»") { ok.exists && ok.label == "18 Monate übernehmen" }
        ctShot("Formular – Mindestlaufzeit Drehrad")
        tap(ok, "18 Monate übernehmen")
        waitGone(ok, "Drehrad zu")
        waitUntil("Knopf zeigt «18 Mt.»") { self.button("termMonths.other").label == "18 Mt." }
        XCTAssertTrue(button("termMonths.other").isSelected)
        XCTAssertFalse(button("termMonths.24").isSelected)
        reveal(elContaining("Kündigen bis 2. April 2028, sonst +1 Monat."), "Hinweis mit Vertragsende aus 18 Monaten")
    }

    /// «Zahlung am» (Web v151/v159): Tagesraster, Tag antippen übernimmt und klappt zu; monatlich ohne Monatsreihe
    func testZahlungAmTagesrasterMonatlich() {
        launch("-uiEmpty")
        openNewForm()
        let due = button("form.dueBtn")
        reveal(due, "Zeile «Zahlung am»")
        XCTAssertEqual(due.value as? String, "3. im Monat")
        tap(due, "Zahlung am")
        wait(button("due.day.20"), "Tagesraster")
        XCTAssertFalse(button("due.month.1").exists, "Monatlich: keine Monatsreihe")
        ctShot("Formular – Zahlung am, Tagesraster")
        tap(button("due.day.20"), "Tag 20.")
        waitGone(button("due.day.20"), "Raster klappt zu")
        waitUntil("Zahlung am 20.") { (due.value as? String) == "20. im Monat" }
        reveal(elContaining("nächste am 20.10.26"), "Hinweis «Zahlung monatlich am 20. · nächste am 20.10.26»")
    }

    /// Jährlich (Halbtax, 1. März): Monatsreihe, Monat antippen übernimmt und lässt offen, Tag übernimmt und klappt zu
    func testZahlungAmTagesrasterJaehrlich() {
        launch("-uiDemo")
        tap(buttonStarting("Halbtax"), "Vertragskarte Halbtax")
        wait(button("Bearbeiten"), "Detail Halbtax")
        tapTop("Bearbeiten")
        waitNav("Bearbeiten")
        let due = button("form.dueBtn")
        reveal(due, "Zeile «Zahlung am»")
        XCTAssertEqual(due.value as? String, "1. März")
        tap(due, "Zahlung am")
        let march = button("due.month.3")
        wait(march, "Monatsreihe")
        XCTAssertTrue(march.isSelected, "März markiert")
        ctShot("Formular – Zahlung am jährlich")
        tap(button("due.month.6"), "Juni")
        waitUntil("Zahlung am 1. Juni") { (due.value as? String) == "1. Juni" }
        XCTAssertTrue(button("due.day.15").exists, "Raster bleibt nach dem Monat offen")
        tap(button("due.day.15"), "Tag 15.")
        waitUntil("Zahlung am 15. Juni") { (due.value as? String) == "15. Juni" }
        waitGone(button("due.month.6"), "Raster zu")
        tapTop("Abbrechen")
        tapAlertButton("Verwerfen")
        waitGone(textField("form.label"), "Formular geschlossen")
    }

    /// Kündigungsfrist (Web v149/v156): 1/2/3 Monate (nochmals tippen löst nicht), «Andere …» mit Drehrad, «keine» setzt ohne Frist
    func testKuendigungsfristKeine() {
        launch("-uiEmpty")
        openNewForm()
        let one = button("notice.1")
        tap(one, "Frist 1 Monat")
        XCTAssertTrue(one.isSelected)
        reveal(elContaining("Ohne Mindestlaufzeit: kündbar mit der angegebenen Frist."), "Hinweis mit Frist")
        revealUp(one, "Frist 1 Monat")
        tap(one, "Frist 1 Monat nochmals")
        XCTAssertTrue(one.isSelected, "Zweites Tippen löst die Frist nicht")

        revealUp(button("notice.other"), "Andere …")
        tap(button("notice.other"), "Andere …")
        let n = wheel(0)
        wait(n, "Drehrad Frist")
        n.adjust(toPickerWheelValue: "keine")
        let ok = button("form.noticeOK")
        waitUntil("Knopf «Keine Frist übernehmen»") { ok.exists && ok.label == "Keine Frist übernehmen" }
        ctShot("Formular – Kündigungsfrist keine")
        tap(ok, "Keine Frist übernehmen")
        waitGone(ok, "Drehrad zu")
        XCTAssertFalse(button("notice.1").isSelected, "keine Frist gewählt")
        XCTAssertEqual(button("notice.other").label, "Andere …")
        reveal(elContaining("Ohne Mindestlaufzeit und ohne Frist: jederzeit kündbar."), "Hinweis ohne Frist")

        // Andere: 2 Wochen (Einheit im Drehrad, Knopf zeigt den Wert)
        revealUp(button("notice.other"), "Andere …")
        tap(button("notice.other"), "Andere …")
        wait(wheel(0), "Drehrad Frist")
        wheel(0).adjust(toPickerWheelValue: "2")
        wheel(1).adjust(toPickerWheelValue: "Wochen")
        waitUntil("Knopf «2 Wochen übernehmen»") { self.button("form.noticeOK").label == "2 Wochen übernehmen" }
        tap(button("form.noticeOK"), "2 Wochen übernehmen")
        waitUntil("Knopf zeigt «2 Wochen»") { self.button("notice.other").label == "2 Wochen" }
        XCTAssertTrue(button("notice.other").isSelected)
    }

    /// Sichern bei «Mindestlaufzeit» ohne Vertragsende wird blockiert (Web v143); mit Vertragsende klappt es
    func testSichernOhneVertragsendeBlockiert() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("form.label"), "Leasing\n", "Bezeichnung")
        enter(textField("form.amount"), "300", "Betrag")
        closeKeyboard()
        tap(button("form.category"), "Kategorie wählen")
        tap(button("Mobilität"), "Kategorie Mobilität")
        waitUntil("Kategorie übernommen") { self.button("form.category").label.contains("Mobilität") }
        revealUp(button("term.fixed"), "Knopf Mindestlaufzeit")
        tap(button("term.fixed"), "Knopf Mindestlaufzeit")
        tapTop("Sichern")
        wait(elContaining("Bis wann läuft der Vertrag?"), "Meldung ohne Vertragsende")
        XCTAssertTrue(navExists("Neuer Vertrag"), "Formular bleibt offen")
        ctShot("Formular – Sichern ohne Vertragsende")
        tap(button("Vertragsende wählen"), "Vertragsende setzen")
        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.navExists("Neuer Vertrag") && !self.textField("form.label").exists }
        wait(buttonStarting("Leasing"), "Vertrag in der Liste")
    }

    /// Abbrechen: mit Änderungen Rückfrage «Änderungen verwerfen?» (Weiter bearbeiten / Verwerfen), ohne Änderungen sofort zu
    func testAbbrechenFragt() {
        launch("-uiDemo", "-uiSheet", "edit")
        waitNav("Bearbeiten", timeout: 15)
        let label = textField("form.label")
        wait(label, "Bezeichnung")
        let old = (label.value as? String) ?? ""
        enter(label, "X", "Bezeichnung ändern")
        closeKeyboard()
        tapTop("Abbrechen")
        wait(elContaining("Änderungen verwerfen?"), "Rückfrage")
        ctShot("Formular – Abbrechen fragt")
        tapAlertButton("Weiter bearbeiten")
        XCTAssertTrue(navExists("Bearbeiten"), "Formular bleibt offen")
        XCTAssertNotEqual(label.value as? String, old, "Eingabe bleibt")
        tapTop("Abbrechen")
        tapAlertButton("Verwerfen")
        waitUntil("Formular geschlossen") { !self.navExists("Bearbeiten") }

        // ohne Änderung: sofort zu, keine Rückfrage
        let row = buttonStarting(old)
        scrollTo(row)
        tap(row, "Vertragskarte")
        wait(button("Bearbeiten"), "Detail")
        tapTop("Bearbeiten")
        waitNav("Bearbeiten")
        wait(textField("form.label"), "Formular")
        tapTop("Abbrechen")
        waitUntil("Formular ohne Rückfrage geschlossen") { !self.textField("form.label").exists }
        XCTAssertFalse(elContaining("Änderungen verwerfen?").exists, "Keine Rückfrage ohne Änderung")
    }

    /// Bildschirmfotos für den Vergleich mit Web v160 (393 × 852): neues Formular, Bearbeiten, Probeabo, Dunkelmodus
    func testFormularBildschirmfotos() {
        launch("-uiDemo", "-uiSheet", "edit")
        waitNav("Bearbeiten", timeout: 15)
        wait(textField("form.label"), "Formular Bearbeiten")
        ctShot("Formular Bearbeiten 1 – Kopf und Kosten")
        app.swipeUp(velocity: .slow)
        ctShot("Formular Bearbeiten 2 – Laufzeit")
        app.swipeUp(velocity: .slow)
        ctShot("Formular Bearbeiten 3 – Zuordnung und Kontakt")
        XCUIDevice.shared.appearance = .dark
        defer { XCUIDevice.shared.appearance = .light }
        sleep(1)
        ctShot("Formular Bearbeiten – Dunkelmodus")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        sleep(1)
        ctShot("Formular Bearbeiten – Dunkelmodus Kopf")
        XCUIDevice.shared.appearance = .light
        tapTop("Abbrechen")
        waitUntil("Formular geschlossen") { !self.navExists("Bearbeiten") }

        // Probeabo (Spotify, gratis bis 19.10.2026)
        let spotify = buttonStarting("Musik")
        scrollTo(spotify)
        tap(spotify, "Vertragskarte Musik (Probeabo)")
        wait(button("Bearbeiten"), "Detail Musik")
        tapTop("Bearbeiten")
        waitNav("Bearbeiten")
        let trial = button("term.trial")
        reveal(trial, "Knopf Probeabo")
        XCTAssertTrue(trial.isSelected, "Probeabo beim Öffnen gewählt")
        reveal(elContaining("Gratis bis 19. Oktober 2026"), "Hinweis Probeabo")
        ctShot("Formular Probeabo")
        tapTop("Abbrechen")
    }

    /// Neues Formular (leer) für den Vergleich mit der Web-App
    func testFormularNeuBildschirmfotos() {
        launch("-uiEmpty")
        openNewForm()
        ctShot("Formular neu 1")
        app.swipeUp(velocity: .slow)
        ctShot("Formular neu 2")
        app.swipeUp(velocity: .slow)
        ctShot("Formular neu 3")
    }
}
