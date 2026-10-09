import XCTest

/// Vertragsformular und -detail auf Stand Web v141:
/// Art des Vertrags als Kacheln, Kündigungsweg mit Folgefeld, Katalog-Zusammenfassung mit «Rückgängig»,
/// Warnungen bei Preisänderungen, Detail als reine Ansicht mit Dokumente-Knopf, Kennzahlen, Menü ••• und Preisverlauf.
final class ContractFormDetailUITests: KontivoUITestCase {

    private func openNewForm() {
        tapOpen(button("Vertrag anlegen"), "Knopf +", expect: textField("form.label"))
        waitNav("Neuer Vertrag")
    }

    /// Kacheln «Flexibel | Mindestlaufzeit | Probeabo | Nicht kündbar» zeigen nur ihre Felder;
    /// Kündigungsweg-Kacheln zeigen genau ein Folgefeld, nochmals tippen hebt die Wahl auf.
    func testFormularKachelnUndKuendigungsweg() {
        launch("-uiEmpty")
        openNewForm()

        let open = button("term.open")
        wait(open, "Kachel Flexibel")
        XCTAssertTrue(open.isSelected, "Neuer Vertrag startet mit «Flexibel»")
        wait(textField("form.notice"), "Kündigungsfrist bei Flexibel")
        wait(elContaining("Ohne Mindestlaufzeit"), "Hinweis Flexibel")

        // Probeabo: Dauer-Chips statt Frist/Beginn
        tap(button("term.trial"), "Kachel Probeabo")
        wait(button("1 Monat"), "Chip 1 Monat")
        wait(elContaining("Wie lange läuft das Probeabo?"), "Hinweis ohne Dauer")
        XCTAssertFalse(textField("form.notice").exists, "Keine Kündigungsfrist im Probeabo")
        tap(button("1 Monat"), "Chip 1 Monat")
        wait(elContaining("Endet am"), "Hinweis mit Enddatum")
        ctShot("Formular – Probeabo")

        // Mindestlaufzeit: Vertragsende und Verlängerung
        tap(button("term.fixed"), "Kachel Mindestlaufzeit")
        wait(elContaining("Vertragsende"), "Feld Vertragsende")
        wait(elContaining("Verlängert sich um"), "Feld Verlängerung")

        // Nicht kündbar: keine Frist, kein Kündigungsweg
        tap(button("term.tax"), "Kachel Nicht kündbar")
        wait(elContaining("Gebühren und Abgaben wie Serafe"), "Hinweis Nicht kündbar")
        waitGone(button("cancelWay.online"), "Kündigungsweg bei «Nicht kündbar»")
        XCTAssertFalse(textField("form.notice").exists, "Keine Frist bei «Nicht kündbar»")

        // Zurück auf Flexibel → Kündigungsweg
        tap(button("term.open"), "Kachel Flexibel")
        tap(button("cancelWay.email"), "Kündigungsweg E-Mail")
        wait(textField("form.cancelMail"), "Feld «E-Mail-Adresse für die Kündigung»")
        XCTAssertFalse(textField("form.cancelURL").exists)

        tap(button("cancelWay.letter"), "Kündigungsweg Brief")
        let addr = button("form.cancelAddr")
        wait(addr, "Zeile «Adresse des Vertragspartners»")
        XCTAssertEqual(addr.label, "Erfassen")
        wait(elContaining("Noch keine Adresse"), "Hinweis ohne Adresse")
        waitGone(textField("form.cancelMail"), "E-Mail-Feld beim Brief")
        ctShot("Formular – Kündigungsweg Brief")

        // Nochmals tippen hebt die Wahl auf
        tap(button("cancelWay.letter"), "Kündigungsweg Brief abwählen")
        waitGone(button("form.cancelAddr"), "Adresszeile nach dem Abwählen")
        XCTAssertFalse(button("cancelWay.letter").isSelected)

        tap(button("cancelWay.online"), "Kündigungsweg Online")
        wait(textField("form.cancelURL"), "Feld Kündigungslink")

        // «Erfassen» öffnet Weitere Angaben bei der Adresse
        tap(button("cancelWay.registered"), "Kündigungsweg Einschreiben")
        tap(button("form.cancelAddr"), "Adresse erfassen")
        waitNav("Weitere Angaben")
        // ohne Vertragspartner: Hinweis unter der Adresse; Schalter aus «Erinnerung und Wechsel»
        wait(elContaining("Zuerst den Vertragspartner eintragen"), "Abschnitt Adresse")
        wait(elContaining("Nicht an Frist erinnern"), "Schalter «Nicht an Frist erinnern»")
        ctShot("Formular – Weitere Angaben bei der Adresse")
    }

    /// Katalog-Treffer: Karte «Aus dem Katalog übernommen» mit Liste; «Rückgängig» setzt die Felder zurück
    func testKatalogZusammenfassungUndRueckgaengig() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("z.B. Swisscom"), "CSS", "Vertragspartner")
        tap(buttonStarting("CSS übernehmen"), "Vorlage «CSS übernehmen»")
        wait(elContaining("Aus dem Katalog übernommen"), "Karte Katalog")
        wait(elContaining("Pflichtvertrag"), "Liste nennt Pflichtvertrag")
        wait(elContaining("Bitte kurz prüfen"), "Prüfhinweis")
        let reg = button("cancelWay.registered")
        reveal(reg, "Kachel Einschreiben")
        XCTAssertTrue(reg.isSelected, "Katalog setzt Kündigungsweg Einschreiben")
        ctShot("Formular – Katalog übernommen")

        tap(button("form.tplUndo"), "Rückgängig")
        waitGone(elContaining("Aus dem Katalog übernommen"), "Karte nach Rückgängig")
        waitUntil("Kündigungsweg zurückgesetzt") { !self.button("cancelWay.registered").isSelected }
        wait(buttonStarting("CSS übernehmen"), "Vorlage wieder angeboten")
        ctShot("Formular – Katalog rückgängig")
    }

    /// «Preis bleibt gleich» fragt nicht blockierend nach; Datum vor dem Vertragsbeginn wird abgelehnt
    func testPreisaenderungWarnungen() {
        launch("-uiEmpty")
        openNewForm()
        enter(textField("form.label"), "Preistest\n", "Bezeichnung")
        enter(textField("form.amount"), "45", "Betrag")
        tap(button("form.more"), "Weitere Angaben")
        waitNav("Weitere Angaben")
        tap(button("Gültig ab wählen"), "Datum der Preisänderung")
        enter(textField("form.priceAmount"), "45", "Neuer Betrag")
        tap(button("form.priceAdd"), "Preisänderung hinzufügen")
        wait(app.alerts["Preis bleibt gleich"], "Rückfrage «Preis bleibt gleich»")
        ctShot("Formular – Preis bleibt gleich")
        tapAlertButton("Trotzdem hinzufügen")
        wait(elContaining("1 Änderung"), "Preisänderung trotzdem vorgemerkt")

        // Vertragsbeginn heute → Preisänderung heute liegt nicht danach
        goBack()
        tap(button("Vertragsbeginn wählen"), "Vertragsbeginn setzen")
        tap(button("form.more"), "Weitere Angaben")
        waitNav("Weitere Angaben")
        tap(button("Gültig ab wählen"), "Datum der Preisänderung")
        enter(textField("form.priceAmount"), "50", "Neuer Betrag")
        tap(button("form.priceAdd"), "Preisänderung hinzufügen")
        wait(elContaining("Datum muss nach dem Vertragsbeginn liegen"), "Meldung Datum vor Beginn")
    }

    /// Detail als reine Ansicht: Kennzahlen, Zahlungsregel, Dokumente-Knopf (Liste ohne Löschen), Menü •••
    func testDetailReineAnsichtUndDokumente() {
        launch("-uiDemo", "-uiSheet", "detail")
        wait(button("Bearbeiten"), "Detail Swisscom", timeout: 15)
        wait(el("detail.kz.month"), "Kachel pro Monat")
        wait(elContaining("pro Jahr"), "Kachel pro Jahr")
        wait(elContaining("insgesamt bezahlt"), "Kachel insgesamt bezahlt")
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
        wait(button("Ins Archiv"), "Menü Ins Archiv")
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
