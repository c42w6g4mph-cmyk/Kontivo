import XCTest

/// Vertragsformular Stand Web v160 (eine Seite «wie die Ansicht»): Kündigungsfrist mit «keine», Mindestlaufzeit mit Drehrad
/// «Andere …», «Zahlung am» als Tagesraster, Sichern ohne Vertragsende, Abbrechen mit Rückfrage, Bildschirmfotos (neu,
/// Bearbeiten, Dunkelmodus) für den Vergleich mit der Web-App. Probeabo: ContractFormDetailUITests.
final class ContractFormUITests: KontivoUITestCase {

    private func openNewForm() {
        openPlusMenuItem("Vertrag erfassen", expect: textField("form.label"))
        waitNav("Neuer Vertrag")
    }

    /// Spalte eines Drehrads (eine UIPickerView mit Spalten)
    private func wheel(_ i: Int) -> XCUIElement {
        app.pickerWheels.element(boundBy: i)
    }

    /// Antippen, nachdem das Element sicher im sichtbaren Bereich liegt (nicht unter der Navigationsleiste)
    private func tapVisible(_ e: XCUIElement, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(e, what, file: file, line: line)
        var n = 0
        while e.exists && e.frame.minY < 150 && n < 6 {
            app.swipeDown(velocity: .slow)
            n += 1
            usleep(300_000)
        }
        reveal(e, what, file: file, line: line)
        e.tap()
    }

    /// Kündigungsfrist (Web v149/v156): 1/2/3 Monate (nochmals tippen löst nicht), «Andere …» mit Drehrad, «keine» setzt ohne
    /// Frist, Einheit im Drehrad. Mindestlaufzeit (Web v145/v149): ohne Beginn Meldung; 2 Jahre bzw. «Andere …» 18 Monate
    /// rechnen das Vertragsende (Beginn + n Monate − 1 Tag); Knopf zeigt «18 Mt.», Verlängerung leer → 1 Monat (Web v156).
    func testKuendigungsfristUndMindestlaufzeit() {
        launch("-uiEmpty")
        openNewForm()
        ctShot("Formular neu 1")

        // Kündigungsfrist: Schnellwahl
        let one = button("notice.1")
        tapVisible(one, "Frist 1 Monat")
        XCTAssertTrue(one.isSelected)
        reveal(elContaining("Ohne Mindestlaufzeit: kündbar mit der angegebenen Frist."), "Hinweis mit Frist")
        ctShot("Formular neu 2")
        tapVisible(one, "Frist 1 Monat nochmals")
        XCTAssertTrue(one.isSelected, "Zweites Tippen löst die Frist nicht")

        // «Andere …» → Drehrad «keine»
        tapVisible(button("notice.other"), "Andere …")
        wait(wheel(0), "Drehrad Frist")
        wheel(0).adjust(toPickerWheelValue: "keine")
        let nok = button("form.noticeOK")
        waitUntil("Knopf «Keine Frist übernehmen»") { nok.exists && nok.label == "Keine Frist übernehmen" }
        ctShot("Formular – Kündigungsfrist keine")
        tapVisible(nok, "Keine Frist übernehmen")
        waitGone(nok, "Drehrad zu")
        XCTAssertFalse(button("notice.1").isSelected, "keine Frist gewählt")
        XCTAssertEqual(button("notice.other").label, "Andere …")
        reveal(elContaining("Ohne Mindestlaufzeit und ohne Frist: jederzeit kündbar."), "Hinweis ohne Frist")

        // «Andere …» → 2 Wochen (Einheit Einzahl/Mehrzahl im Drehrad, Knopf zeigt den Wert)
        tapVisible(button("notice.other"), "Andere …")
        wait(wheel(0), "Drehrad Frist")
        wheel(0).adjust(toPickerWheelValue: "2")
        wheel(1).adjust(toPickerWheelValue: "Wochen")
        waitUntil("Knopf «2 Wochen übernehmen»") { self.button("form.noticeOK").label == "2 Wochen übernehmen" }
        tapVisible(button("form.noticeOK"), "2 Wochen übernehmen")
        waitUntil("Knopf zeigt «2 Wochen»") { self.button("notice.other").label == "2 Wochen" }
        XCTAssertTrue(button("notice.other").isSelected)

        // Mindestlaufzeit ohne Beginn: Meldung und Sprung zum Beginn
        tapVisible(button("term.fixed"), "Knopf Mindestlaufzeit")
        tapVisible(button("termMonths.24"), "Knopf 2 Jahre")
        wait(elContaining("Zuerst den Vertragsbeginn eintragen"), "Meldung ohne Vertragsbeginn")
        tapVisible(button("Vertragsbeginn wählen"), "Vertragsbeginn (heute, 03.10.2026)")
        XCTAssertTrue(button("termMonths.24").isSelected, "Knopf 2 Jahre gewählt")
        // 03.10.2026 + 24 Monate − 1 Tag = 02.10.2028; Verlängerung 1 Monat vorbelegt; Frist 2 Wochen
        reveal(elContaining("Kündigen bis 18. September 2028, sonst +1 Monat."), "Hinweis mit Vertragsende aus 2 Jahren")

        // «Andere …» → Drehrad 18 Monate (Ende 02.04.2028)
        tapVisible(button("termMonths.other"), "Knopf Andere …")
        wait(wheel(0), "Drehrad Monate")
        wheel(0).adjust(toPickerWheelValue: "18")
        let ok = button("form.termMonthsOK")
        waitUntil("Knopf «18 Monate übernehmen»") { ok.exists && ok.label == "18 Monate übernehmen" }
        ctShot("Formular – Mindestlaufzeit Drehrad")
        tapVisible(ok, "18 Monate übernehmen")
        waitGone(ok, "Drehrad zu")
        waitUntil("Knopf zeigt «18 Mt.»") { self.button("termMonths.other").label == "18 Mt." }
        XCTAssertTrue(button("termMonths.other").isSelected)
        XCTAssertFalse(button("termMonths.24").isSelected)
        reveal(elContaining("Kündigen bis 19. März 2028, sonst +1 Monat."), "Hinweis mit Vertragsende aus 18 Monaten")
    }

    /// «Zahlung am» (Web v151/v159): Tagesraster, Tag antippen übernimmt und klappt zu; monatlich ohne Monatsreihe.
    /// Jährlich: Monatsreihe, Monat antippen übernimmt und lässt offen, Tag übernimmt und klappt zu.
    func testZahlungAmTagesraster() {
        launch("-uiEmpty")
        openNewForm()
        let due = button("form.dueBtn")
        reveal(due, "Zeile «Zahlung am»")
        XCTAssertEqual(due.value as? String, "3. im Monat")
        tapVisible(due, "Zahlung am")
        wait(button("due.day.20"), "Tagesraster")
        XCTAssertFalse(button("due.month.1").exists, "Monatlich: keine Monatsreihe")
        ctShot("Formular – Zahlung am, Tagesraster")
        tapVisible(button("due.day.20"), "Tag 20.")
        waitGone(button("due.day.20"), "Raster klappt zu")
        waitUntil("Zahlung am 20.") { (due.value as? String) == "20. im Monat" }
        reveal(elContaining("nächste am 20.10.26"), "Hinweis «Zahlung monatlich am 20. · nächste am 20.10.26»")

        // jährlich: Monatsreihe
        tapVisible(button("form.cycle"), "Zahlungsrhythmus")
        tap(button("jährlich"), "jährlich")
        waitUntil("Zahlung am 20. Oktober") { (due.value as? String) == "20. Oktober" }
        tapVisible(due, "Zahlung am")
        let oct = button("due.month.10")
        wait(oct, "Monatsreihe")
        XCTAssertTrue(oct.isSelected, "Oktober markiert")
        ctShot("Formular – Zahlung am jährlich")
        tapVisible(button("due.month.6"), "Juni")
        waitUntil("Zahlung am 20. Juni") { (due.value as? String) == "20. Juni" }
        XCTAssertTrue(button("due.day.15").exists, "Raster bleibt nach dem Monat offen")
        tapVisible(button("due.day.15"), "Tag 15.")
        waitUntil("Zahlung am 15. Juni") { (due.value as? String) == "15. Juni" }
        waitGone(button("due.month.6"), "Raster zu")
        reveal(elContaining("nächste am 15.06.27"), "Hinweis nächste Zahlung jährlich")
    }

    /// Bearbeiten aus dem Detail (zwei Fenster übereinander, Halbtax jährlich am 1. März mit Preisänderung): Tagesraster mit Monatsreihe
    func testZahlungAmAusDetail() {
        launch("-uiDemo")
        tap(buttonStarting("Halbtax"), "Vertragskarte Halbtax")
        wait(button("Bearbeiten"), "Detail Halbtax")
        tapTop("Bearbeiten")
        let due = button("form.dueBtn")
        wait(textField("form.label"), "Formular Bearbeiten", timeout: 12)
        reveal(due, "Zeile «Zahlung am»")
        XCTAssertEqual(due.value as? String, "1. März")
        ctShot("Formular Halbtax – vor Zahlung am")
        tapVisible(due, "Zahlung am")
        sleep(1)
        ctShot("Formular Halbtax – Zahlung am offen")
        let march = button("due.month.3")
        wait(march, "Monatsreihe")
        XCTAssertTrue(march.isSelected, "März markiert")
        tapVisible(button("due.day.15"), "Tag 15.")
        waitUntil("Zahlung am 15. März") { (due.value as? String) == "15. März" }
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
        tapVisible(button("term.fixed"), "Knopf Mindestlaufzeit")
        tapTop("Sichern")
        wait(elContaining("Bis wann läuft der Vertrag?"), "Meldung ohne Vertragsende")
        XCTAssertTrue(navExists("Neuer Vertrag"), "Formular bleibt offen")
        ctShot("Formular – Sichern ohne Vertragsende")
        tapVisible(button("Vertragsende wählen"), "Vertragsende setzen")
        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.navExists("Neuer Vertrag") && !self.textField("form.label").exists }
        wait(buttonStarting("Leasing"), "Vertrag in der Liste")
    }

    /// Abbrechen mit Änderungen: Rückfrage «Änderungen verwerfen?» – «Weiter bearbeiten» behält die Eingabe, «Verwerfen» schliesst.
    /// (Ohne Änderungen schliesst «Abbrechen» sofort: ContractListUITests.testWischenUndLangesDruecken.)
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
        waitUntil("Formular geschlossen") { !self.textField("form.label").exists }
        let row = buttonStarting(old)
        scrollTo(row)
        XCTAssertTrue(row.exists, "Bezeichnung unverändert in der Liste")
    }

    /// Bildschirmfotos für den Vergleich mit Web v160 (Bearbeiten Swisscom, hell und dunkel)
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
        ctShot("Formular Bearbeiten – Dunkelmodus unten")
        app.swipeDown(velocity: .fast)
        app.swipeDown(velocity: .fast)
        sleep(1)
        ctShot("Formular Bearbeiten – Dunkelmodus oben")
    }
}
