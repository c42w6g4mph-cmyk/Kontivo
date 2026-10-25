import XCTest

/// Vertragsformular (Stand Web v160, eine Seite) und -detail:
/// Vertragsart als 2×2-Knöpfe, Kündigungsweg mit Folgefeld, Katalog-Zusammenfassung mit «Rückgängig»,
/// Warnungen bei Preisänderungen, Detail als reine Ansicht mit Dokumente-Knopf, Kennzahlen, Menü ••• und Preisverlauf.
/// Weitere Formular-Abläufe: ContractFormUITests.
final class ContractFormDetailUITests: KontivoUITestCase {

    private func openNewForm() {
        openPlusMenuItem("Vertrag erfassen", expect: textField("form.label"))
        waitNav("Neuer Vertrag")
    }

    /// Vertragsart «Flexibel | Mindestlaufzeit | Probeabo | Nicht kündbar» (2×2-Knöpfe, Web v151) zeigt nur ihre Felder;
    /// Kündigungsweg Online · E-Mail · Brief zeigt genau ein Folgefeld, nochmals tippen hebt die Wahl auf.
    func testFormularKachelnUndKuendigungsweg() {
        launch("-uiEmpty")
        openNewForm()

        let open = button("term.open")
        reveal(open, "Knopf Flexibel")
        XCTAssertTrue(open.isSelected, "Neuer Vertrag startet mit «Flexibel»")
        reveal(button("notice.1"), "Kündigungsfrist bei Flexibel")
        reveal(elContaining("Ohne Mindestlaufzeit"), "Hinweis Flexibel")
        XCTAssertFalse(el("form.remind").exists, "Flexibel, jederzeit: kein Schalter «An Frist erinnern» (Web v152)")

        // Probeabo: Dauer-Knöpfe statt Frist; Vertragsbeginn bleibt (Web v156)
        tap(button("term.trial"), "Knopf Probeabo")
        wait(button("trial.1m"), "Knopf 1 Monat")
        reveal(elContaining("Wie lange läuft das Probeabo?"), "Hinweis ohne Dauer")
        XCTAssertFalse(button("notice.1").exists, "Keine Kündigungsfrist im Probeabo")
        tap(button("trial.1m"), "Knopf 1 Monat")
        reveal(elContaining("Gratis bis"), "Hinweis «Gratis bis …, ab … kostenpflichtig»")
        reveal(button("Vertragsbeginn wählen"), "Vertragsbeginn im Probeabo")
        ctShot("Formular – Probeabo")

        // Mindestlaufzeit: Knöpfe 1/2/3 Jahre, Vertragsende, Verlängerung, «An Frist erinnern»
        revealUp(button("term.fixed"), "Knopf Mindestlaufzeit")
        tap(button("term.fixed"), "Knopf Mindestlaufzeit")
        wait(button("termMonths.12"), "Knopf 1 Jahr")
        reveal(elContaining("Vertragsende"), "Feld Vertragsende")
        reveal(elContaining("Verlängert sich um"), "Feld Verlängerung")
        reveal(el("form.remind"), "Schalter «An Frist erinnern»")

        // Nicht kündbar: keine Frist, kein Kündigungsweg
        revealUp(button("term.tax"), "Knopf Nicht kündbar")
        tap(button("term.tax"), "Knopf Nicht kündbar")
        reveal(elContaining("Gebühren und Abgaben wie die Rundfunkgebühr"), "Hinweis Nicht kündbar")
        waitGone(button("cancelWay.online"), "Kündigungsweg bei «Nicht kündbar»")
        XCTAssertFalse(button("notice.1").exists, "Keine Frist bei «Nicht kündbar»")

        // Zurück auf Flexibel → Kündigungsweg
        revealUp(button("term.open"), "Knopf Flexibel")
        tap(button("term.open"), "Knopf Flexibel")
        tap(button("cancelWay.email"), "Kündigungsweg E-Mail")
        wait(textField("form.cancelMail"), "Feld «E-Mail für Kündigung»")
        XCTAssertFalse(textField("form.cancelURL").exists)

        // Brief: kein Folgefeld mehr (Web v212: Adresse nur bei den Kontaktdaten)
        tap(button("cancelWay.letter"), "Kündigungsweg Brief")
        waitGone(textField("form.cancelMail"), "E-Mail-Feld beim Brief")
        XCTAssertFalse(button("form.cancelAddr").exists, "Keine Zeile «Adresse des Vertragspartners» (v212)")
        ctShot("Formular – Kündigungsweg Brief")

        // Nochmals tippen hebt die Wahl auf
        tap(button("cancelWay.letter"), "Kündigungsweg Brief abwählen")
        waitUntil("Brief abgewählt") { !self.button("cancelWay.letter").isSelected }

        tap(button("cancelWay.online"), "Kündigungsweg Online")
        wait(textField("form.cancelURL"), "Feld Kündigungslink")
    }

    /// Katalog-Treffer: Erfolgskarte «Vertragsdaten ergänzt» (Web v240–v243) mit Feld/Wert-Liste, Fusszeile, «Rückgängig»
    func testKatalogZusammenfassungUndRueckgaengig() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("form.partner"), "CSS", "Vertragspartner")
        // Gemeinsame Trefferliste (Web v213): Abschnitt «Katalog» unter dem Feld
        let hit = app.buttons.matching(pred("identifier == %@ AND label CONTAINS %@", "form.tplHit", "Pflichtvertrag")).firstMatch
        wait(hit, "Katalogtreffer CSS (Pflichtvertrag)")
        ctShot("Formular – Trefferliste")
        hit.tap()
        wait(elContaining("Vertragsdaten ergänzt"), "Erfolgskarte")
        wait(elContaining("aus dem Kontivo-Katalog"), "Unterzeile n Angaben")
        wait(elContaining("Pflichtvertrag"), "Liste nennt Pflichtvertrag")
        wait(elContaining("Stand 10/2026"), "Fusszeile Stand 10/2026")
        XCTAssertFalse(elContaining("Bitte kurz prüfen").exists, "Satz «Bitte kurz prüfen» entfällt (v240)")
        closeKeyboard()
        ctShot("Formular – Erfolgskarte Katalog")
        let reg = button("cancelWay.letter")
        reveal(reg, "Kachel Brief")
        XCTAssertTrue(reg.isSelected, "Katalog setzt Kündigungsweg Brief (Web v145: Einschreiben = Brief)")

        let undo = button("form.tplUndo")
        revealUp(undo, "Rückgängig")
        tap(undo, "Rückgängig")
        waitGone(elContaining("Vertragsdaten ergänzt"), "Karte nach Rückgängig")
        reveal(button("cancelWay.letter"), "Kachel Brief nach Rückgängig")
        waitUntil("Kündigungsweg zurückgesetzt") { !self.button("cancelWay.letter").isSelected }
        ctShot("Formular – Katalog rückgängig")
    }

    /// Feld leeren und neu tippen
    private func replace(_ f: XCUIElement, _ text: String, _ what: String) {
        tap(f, what)
        usleep(300_000)
        // Schreibmarke ans Ende setzen (rechtsbündiges Feld), dann alles löschen
        f.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        usleep(300_000)
        let n = (f.value as? String)?.count ?? 0
        f.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: n + 2) + text)
    }

    /// Zeile nach links wischen (Web v317/v318); ganz durchwischen löscht, sonst «Löschen» antippen
    private func swipeDelete(_ e: XCUIElement, dx: CGFloat = 0.3, _ what: String) {
        let a = e.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(CGVector(dx: -300, dy: 0)))
        usleep(500_000)
        let del = app.buttons.matching(pred("label == %@ OR label == %@", "Löschen", "Verwerfen")).firstMatch
        if e.exists && del.exists && del.isHittable { del.tap() }
    }

    /// Preisverlauf als Zeitstrahl (Web v314–v320): «+ Preisänderung» öffnet eine neue Zeile (Datum heute), Betrag fertig →
    /// übernommen; «Preis bleibt gleich» fragt nach; Betrag direkt in der Zeile ändern (Tausendertrennung); Löschen per Wischen
    func testPreisaenderungZeitstrahl() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("form.label"), "Preistest\n", "Bezeichnung")
        wait(el("form.currency"), "Zeile Währung oben (v319)")
        enter(textField("form.amount"), "45", "Betrag")
        closeKeyboard()
        let kz = el("form.kz.month")
        wait(kz, "Kachel pro Monat (live aus dem Entwurf)")
        XCTAssertTrue(kz.label.contains("45.00"), "Kachel pro Monat: \(kz.label)")
        tapOpen(button("form.priceOpen"), "+ Preisänderung", expect: textField("form.priceAmount"))
        wait(el("neu"), "Neue Zeile «neu»")
        ctShot("Formular – neue Preisänderung als Zeile")
        enter(textField("form.priceAmount"), "45", "Neuer Betrag")
        closeKeyboard()
        wait(app.alerts["Preis bleibt gleich"], "Rückfrage «Preis bleibt gleich»")
        ctShot("Formular – Preis bleibt gleich")
        tapAlertButton("Trotzdem hinzufügen")
        let step = textField("form.priceAmt.0")
        wait(step, "Stufe im Zeitstrahl")
        wait(textField("Anfangspreis"), "Startzeile «Anfangspreis»")
        wait(elContaining("aktuell"), "Stufe «aktuell»")

        // Betrag direkt in der Zeile ändern: 1234.5 → «1’234.50», +2’643 %
        replace(step, "1234.5", "Betrag der Stufe")
        closeKeyboard()
        waitUntil("Betrag mit Tausendertrennung") { ((step.value as? String) ?? "").contains("234.50") }
        XCTAssertTrue(((step.value as? String) ?? "").contains("1"), "Betrag: \(String(describing: step.value))")
        ctShot("Formular – Zeitstrahl")

        // ungültiger Betrag: Meldung, Zeile bleibt
        replace(step, "abc", "Betrag ungültig")
        closeKeyboard()
        wait(elContaining("Betrag prüfen"), "Meldung Betrag prüfen")

        // Löschen per Wischen
        swipeDelete(step, dx: -0.6, "Stufe")
        waitGone(textField("form.priceAmt.0"), "Stufe nach dem Wischen")
        waitUntil("Startzeile wieder «Betrag»") { self.textField("Betrag").exists }

        // Vertragsbeginn heute → neue Änderung heute liegt nicht danach
        let st = button("Vertragsbeginn wählen")
        reveal(st, "Vertragsbeginn")
        tap(st, "Vertragsbeginn setzen")
        revealUp(button("form.priceOpen"), "+ Preisänderung")
        app.swipeDown(velocity: .slow)
        usleep(500_000)
        tapOpen(button("form.priceOpen"), "+ Preisänderung", expect: textField("form.priceAmount"))
        enter(textField("form.priceAmount"), "50", "Neuer Betrag")
        closeKeyboard()
        wait(elContaining("Datum muss nach dem Vertragsbeginn liegen"), "Meldung Datum vor Beginn")
    }

    /// Sonderzahlung erfassen und per Wischen löschen (Web v318: kein × mehr)
    func testSonderzahlungWischen() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("form.label"), "Wischtest\n", "Bezeichnung")
        enter(textField("form.amount"), "20", "Betrag")
        closeKeyboard()
        let open = button("form.extraOpen")
        reveal(open, "+ Sonderzahlung")
        tap(open, "+ Sonderzahlung")
        let pick = button("form.extraDate.pick")
        reveal(pick, "Datum wählen")
        tap(pick, "Datum")
        enter(textField("form.extraAmount"), "99", "Betrag Sonderzahlung")
        closeKeyboard()
        let add = button("form.extraAdd")
        reveal(add, "Sonderzahlung hinzufügen")
        tap(add, "Sonderzahlung hinzufügen")
        let money = elContaining("99.00")
        reveal(money, "Zeile Sonderzahlung")
        XCTAssertFalse(button("Sonderzahlung entfernen").exists, "Kein × mehr (v318)")
        ctShot("Formular – Sonderzahlung")
        swipeDelete(money, dx: 0.5, "Sonderzahlung")
        waitGone(elContaining("99.00"), "Sonderzahlung nach dem Wischen")
    }

    /// Detail als reine Ansicht: Kennzahlen, Zahlungsregel, Dokumente-Knopf (Liste ohne Löschen), Menü •••
    func testDetailReineAnsichtUndDokumente() {
        launch("-uiDemo", "-uiSheet", "detail")
        wait(button("Bearbeiten"), "Detail Swisscom", timeout: 15)
        wait(el("detail.kz.month"), "Kachel pro Monat")
        wait(elContaining("pro Jahr"), "Kachel pro Jahr")
        wait(elContaining("bisher bezahlt (ca.)"), "Kachel bisher bezahlt (Web v156)")
        wait(elContaining("monatlich am 15."), "Zeile Zahlung")
        XCTAssertFalse(buttonContaining("Preisänderung").exists, "Keine Preisänderung im Detail")
        XCTAssertFalse(button("Weitere Aktionen").exists, "Keine Aktionen unten")

        let docs = button("detail.docs")
        wait(docs, "Dokumente-Knopf")
        XCTAssertEqual(docs.label, "Dokument anhängen")
        ctShot("Detail – Kopf und Kennzahlen")

        tap(docs, "Dokumente")
        wait(button("detail.docAttach"), "Datei anhängen")
        wait(elContaining("Noch keine Dokumente"), "Leere Liste")
        XCTAssertFalse(button("Entfernen").exists, "Kein Löschen im Detail")
        ctShot("Detail – Dokumente")
        tapTop("Schliessen")
        waitGone(button("detail.docAttach"), "Dokumente geschlossen")

        tap(button("detail.menu"), "Menü •••")
        wait(button("Duplizieren"), "Menü Duplizieren")
        wait(buttonStarting("Schon gekündigt"), "Menü Schon gekündigt … (Web v154)")
        wait(button("Löschen"), "Menü Löschen")
        ctShot("Detail – Menü")
    }

    /// Preisverlauf im Detail: geplante Preisänderung als Plakette, Pille «Neuer Preis ab …»
    func testDetailPreisverlauf() {
        launch("-uiDemo")
        tap(buttonStarting("Halbtax"), "Vertragskarte Halbtax")
        wait(button("Bearbeiten"), "Detail Halbtax")
        wait(elContaining("Neuer Preis ab"), "Pille Neuer Preis")
        let chart = el("detail.priceChart")
        reveal(chart, "Preisverlauf")
        XCTAssertTrue(chart.label.contains("geplant ab"), "Plakette «geplant ab …»: \(chart.label)")
        wait(elContaining("jährlich am 1. März"), "Zeile Zahlung jährlich")
        ctShot("Detail – Preisverlauf")
    }
}

extension KontivoUITestCase {
    /// Bildschirmfoto als Anhang (bleibt erhalten)
    func ctShot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
