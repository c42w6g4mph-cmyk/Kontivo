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

    /// Katalog-Treffer: Karte «Aus dem Katalog übernommen» mit Liste; «Rückgängig» setzt die Felder zurück
    func testKatalogZusammenfassungUndRueckgaengig() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("form.partner"), "CSS", "Vertragspartner")
        // Gemeinsame Trefferliste (Web v213): Abschnitt «Katalog» unter dem Feld
        let hit = app.buttons.matching(pred("identifier == %@ AND label CONTAINS %@", "form.tplHit", "Pflichtvertrag")).firstMatch
        wait(hit, "Katalogtreffer CSS (Pflichtvertrag)")
        ctShot("Formular – Trefferliste")
        hit.tap()
        wait(elContaining("Aus dem Katalog übernommen"), "Karte Katalog")
        wait(elContaining("Pflichtvertrag"), "Liste nennt Pflichtvertrag")
        wait(elContaining("Bitte kurz prüfen"), "Prüfhinweis")
        closeKeyboard()
        let reg = button("cancelWay.letter")
        reveal(reg, "Kachel Brief")
        XCTAssertTrue(reg.isSelected, "Katalog setzt Kündigungsweg Brief (Web v145: Einschreiben = Brief)")
        ctShot("Formular – Katalog übernommen")

        let card = elContaining("Aus dem Katalog übernommen")
        revealUp(card, "Karte Katalog")
        let undo = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "form.tplUndo", "Rückgängig")).firstMatch
        if undo.exists && undo.isHittable {
            undo.tap()
        } else {
            // Karte als ein Element zusammengefasst: «Rückgängig» rechts in der Titelzeile antippen
            card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.12)).tap()
        }
        waitGone(elContaining("Aus dem Katalog übernommen"), "Karte nach Rückgängig")
        reveal(button("cancelWay.letter"), "Kachel Brief nach Rückgängig")
        ctShot("Formular – nach Rückgängig, Kündigungsweg")
        waitUntil("Kündigungsweg zurückgesetzt") { !self.button("cancelWay.letter").isSelected }
        ctShot("Formular – Katalog rückgängig")
    }

    /// Preisänderung in der Karte «Kosten» (Web v145): «Preis bleibt gleich» fragt nicht blockierend nach; danach Preisliste,
    /// Beschriftung «Anfangspreis» und Kacheln; Datum vor dem Vertragsbeginn wird abgelehnt
    func testPreisaenderungWarnungen() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("form.label"), "Preistest\n", "Bezeichnung")
        enter(textField("form.amount"), "45", "Betrag")
        closeKeyboard()
        let kz = el("form.kz.month")
        wait(kz, "Kachel pro Monat (live aus dem Entwurf)")
        XCTAssertTrue(kz.label.contains("45.00"), "Kachel pro Monat: \(kz.label)")
        tap(button("form.priceOpen"), "+ Preisänderung")
        tap(button("Gültig ab wählen"), "Datum der Preisänderung")
        enter(textField("form.priceAmount"), "45", "Neuer Betrag")
        closeKeyboard()
        tap(button("form.priceAdd"), "Preisänderung hinzufügen")
        wait(app.alerts["Preis bleibt gleich"], "Rückfrage «Preis bleibt gleich»")
        ctShot("Formular – Preis bleibt gleich")
        tapAlertButton("Trotzdem hinzufügen")
        wait(button("form.priceRow.0"), "Preisänderung in der Liste")
        wait(textField("Anfangspreis"), "Beschriftung «Anfangspreis»")
        ctShot("Formular – Preisliste")

        // Vertragsbeginn heute → Preisänderung heute liegt nicht danach
        tap(button("Vertragsbeginn wählen"), "Vertragsbeginn setzen")
        revealUp(button("form.priceOpen"), "+ Preisänderung")
        // Tipp kann während des Nachscrollens verloren gehen: dann ein zweiter Versuch
        tapOpen(button("form.priceOpen"), "+ Preisänderung", expect: button("Gültig ab wählen"))
        revealNear(button("Gültig ab wählen"), "Datum der Preisänderung")
        tap(button("Gültig ab wählen"), "Datum der Preisänderung")
        enter(textField("form.priceAmount"), "50", "Neuer Betrag")
        closeKeyboard()
        tap(button("form.priceAdd"), "Preisänderung hinzufügen")
        wait(elContaining("Datum muss nach dem Vertragsbeginn liegen"), "Meldung Datum vor Beginn")
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
        waitNav("Dokumente")
        wait(button("detail.docAttach"), "Datei anhängen")
        wait(elContaining("Noch keine Dokumente"), "Leere Liste")
        XCTAssertFalse(button("Entfernen").exists, "Kein Löschen im Detail")
        ctShot("Detail – Dokumente")
        tapTop("Fertig")
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
