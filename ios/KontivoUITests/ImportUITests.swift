import XCTest

/// Plus-Menü und Kontoauszug-Import (Bereich import, Web v177–v346)
final class ImportUITests: KontivoUITestCase {

    /// Plus öffnet das Menü «Vertrag erfassen» | «Aus Kontoauszug» mit der Wahl der Quelle
    func testPlusMenue() {
        launch("-uiDemo")
        let erfassen = buttonStarting("Vertrag erfassen")
        tapOpen(button("Hinzufügen"), "Knopf +", expect: erfassen)
        XCTAssertTrue(buttonStarting("Aus Kontoauszug").exists, "Menüpunkt «Aus Kontoauszug» fehlt")
        keepShot("plus-menue")

        // Untermenü: Quelle wählen
        let datei = buttonStarting("Datei wählen")
        tapOpen(buttonStarting("Aus Kontoauszug"), "Aus Kontoauszug", expect: datei)
        XCTAssertTrue(buttonStarting("Aus Fotos wählen").exists, "Quelle «Aus Fotos wählen» fehlt")
        keepShot("plus-menue-kontoauszug")

        // Menü schliessen, «Vertrag erfassen» öffnet das Formular
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).tap()
        openPlusMenuItem("Vertrag erfassen", expect: textField("form.label"))
        waitNav("Neuer Vertrag")
    }

    /// Beispiel-CSV (PostFinance) ohne Systemauswahl: Ladeanzeige → Fixkosten → Vorschlag im Formular → Einnahmen → Fristen →
    /// übernehmen → «Fast fertig!»
    func testKontoauszugBeispiel() {
        launch("-uiEmpty", "-uiBankSample")

        // Ladeanzeige mit grüner Box
        // (nur kurz sichtbar: im UI-Test ohne Logosuche ~1 s)
        if el("Kontivo sucht Fixkosten und Einnahmen").waitForExistence(timeout: 6) {
            keepShot("bank-1-laden")
            if !elContaining("Bleibt auf deinem Gerät").exists { print("HINWEIS: Ladeanzeige schon vorbei, grüne Box nicht geprüft") }
        }

        // Schritt 1: Fixkosten
        wait(el("Sind das deine Fixkosten?"), "Schritt Fixkosten", timeout: 25)
        waitNav("Kontoauszug")
        let apply = el("bankApply")
        wait(apply, "Knopf unten")
        XCTAssertEqual(apply.label, "Weiter zu Einnahmen", "Knopf im ersten Schritt")
        wait(button("bankRow-Swisscom"), "Vorschlag Swisscom")
        wait(el("bankHero"), "Kopfkarte «n Verträge erkannt»")
        XCTAssertTrue(elContaining("Verträge erkannt").exists, "Kopfkarte ohne «Verträge erkannt»")
        keepShot("bank-2-fixkosten")

        // Zahlungen aufklappen (Plakette «n Zahlungen») und wieder zu
        let pay = button("bankPay-Swisscom")
        wait(pay, "Plakette Zahlungen Swisscom")
        XCTAssertTrue(pay.label.hasSuffix("Zahlungen"), "Plakette: \(pay.label)")
        tap(pay, "Zahlungen aufklappen")
        wait(elContaining("20.09.2026"), "Zahlung vom 20.09.2026 (Datum TT.MM.JJJJ)")
        keepShot("bank-2b-zahlungen")
        tap(pay, "Zahlungen zuklappen")
        waitGone(elContaining("20.09.2026"), "Zahlungsliste")

        // Vorschlag öffnet das normale Vertragsformular «Vorschlag»
        tap(button("bankRow-Swisscom"), "Zeile Swisscom")
        waitNav("Vorschlag")
        keepShot("bank-3-vorschlag")
        tap(button("Sichern"), "Sichern (zurück in den Vorschlag)")
        wait(el("Sind das deine Fixkosten?"), "zurück in der Liste")

        // Abwählen und wieder an
        let check = button("bankCheck-Swisscom")
        wait(check, "Häkchen Swisscom")
        XCTAssertEqual(check.value as? String, "ausgewählt")
        tap(check, "Häkchen Swisscom aus")
        waitUntil("Häkchen aus") { (check.value as? String) == "nicht ausgewählt" }
        tap(check, "Häkchen Swisscom an")
        waitUntil("Häkchen an") { (check.value as? String) == "ausgewählt" }

        // Schritt 2: Einnahmen
        tap(apply, "Weiter zu Einnahmen")
        wait(el("Und deine Einnahmen?"), "Schritt Einnahmen")
        XCTAssertEqual(apply.label, "Weiter zu Kündigungsfristen", "Knopf im zweiten Schritt")
        waitUntil("Knopf «‹ Zurück»") { self.button("bankCancel").label == "‹ Zurück" }
        keepShot("bank-4-einnahmen")

        // Schritt 3: Kündigungsfristen (Miete ohne Katalog)
        tap(apply, "Weiter zu Kündigungsfristen")
        wait(elContaining("Kündigungsfrist"), "Schritt Fristen")
        tap(button("1 Monat"), "Schnellwahl 1 Monat")
        XCTAssertTrue(apply.label.hasSuffix("Einträge übernehmen"), "Knopf: \(apply.label)")
        print("KONTOAUSZUG-KNOPF: \(apply.label)")
        keepShot("bank-5-fristen")

        // Zurück und wieder vor
        tap(button("bankCancel"), "‹ Zurück")
        wait(el("Und deine Einnahmen?"), "zurück bei den Einnahmen")
        tap(apply, "Weiter")
        wait(elContaining("Kündigungsfrist"), "wieder bei den Fristen")

        // Übernehmen → Verträge, Rückfrage «Fast fertig!»
        tap(apply, "Einträge übernehmen")
        tapAlertButtonIfShown("Später", screenshot: "bank-6-fast-fertig")
        wait(elContaining("Swisscom"), "Vertrag Swisscom in der Liste", timeout: 10)
        XCTAssertFalse(button("Ersten Vertrag erfassen").exists, "Leerseite noch sichtbar")
        keepShot("bank-7-vertraege")

        // Mehr → Daten: Zeitraum des letzten Imports (Web v275: gespeichert, weil etwas übernommen wurde)
        tapTab("Mehr")
        let row = button("bankMoreRow")
        scrollTo(row)
        wait(row, "Zeile «Kontoauszug einlesen»")
        XCTAssertTrue(row.label.contains("Zuletzt eingelesen: 01.10.2025 bis 30.09.2026"), "Zeile: \(row.label)")
        keepShot("bank-11-mehr-letzter-import")
    }

    /// Mit Beispieldaten (zwei Personen): «Zuordnen an», neuer Preis bei erfasstem Vertrag, schon erfasste aufklappen
    func testKontoauszugMitVertraegen() {
        launch("-uiDemo", "-uiBankSample")
        wait(el("Sind das deine Fixkosten?"), "Schritt Fixkosten", timeout: 25)
        wait(el("bankWho"), "«Zuordnen an»")
        wait(elContaining("Neuer Preis bei erfassten Verträgen"), "Abschnitt neuer Preis")
        keepShot("bank-8-mit-vertraegen")
        let known = button("bankKnownToggle")
        if known.waitForExistence(timeout: 3) {
            XCTAssertTrue(known.label.hasSuffix("schon in Kontivo ›"), "Knopf: \(known.label)")
            app.swipeUp()
            tap(known, "Schon erfasste zeigen")
            waitUntil("Schon erfasste aufgeklappt") { known.label == "Schon erfasste ausblenden" }
            keepShot("bank-9-schon-erfasst")
        }
        // Abbrechen mit Ergebnis fragt nach (Web v285): «Weiter prüfen» bleibt, «Import abbrechen» schliesst ohne Änderung
        tap(button("bankCancel"), "Abbrechen")
        wait(app.alerts["Import abbrechen?"], "Rückfrage «Import abbrechen?»")
        tapAlertButton("Weiter prüfen")
        wait(el("Sind das deine Fixkosten?"), "noch in der Liste")
        tap(button("bankCancel"), "Abbrechen")
        tapAlertButton("Import abbrechen")
        waitGone(el("Sind das deine Fixkosten?"), "Fenster Kontoauszug")
    }

    /// Rückfrage in der Zeile (Web v327 `.bkdup`): gleicher Betrag wie ein erfasster Vertrag → «Derselbe Vertrag?»; ohne Antwort nicht
    /// ausgewählt, «Nein, neu» wählt aus, «Ja, schon erfasst» wieder ab
    func testKontoauszugRueckfrage() {
        launch("-uiDemo", "-uiBankSample")
        wait(el("Sind das deine Fixkosten?"), "Schritt Fixkosten", timeout: 25)
        let box = elContaining("Gleicher Betrag wie")
        scrollTo(box)
        wait(box, "Rückfrage «Gleicher Betrag wie …»")
        let no = app.buttons.matching(pred("identifier BEGINSWITH %@", "bankAskNo-")).firstMatch
        let yes = app.buttons.matching(pred("identifier BEGINSWITH %@", "bankAskYes-")).firstMatch
        wait(no, "Knopf «Nein, neu»")
        // Box liegt sonst unter dem Knopf unten («Weiter zu Einnahmen») – ganz nach oben schieben
        app.swipeUp(velocity: .slow)
        waitUntil("Knopf «Nein, neu» frei") { no.isHittable && no.frame.maxY < self.el("bankApply").frame.minY }
        XCTAssertEqual(no.label, "Nein, neu")
        XCTAssertEqual(yes.label, "Ja, schon erfasst")
        let name = String(no.identifier.dropFirst("bankAskNo-".count))
        let check = button("bankCheck-" + name)
        XCTAssertEqual(check.value as? String, "nicht ausgewählt", "ohne Antwort nicht ausgewählt")
        keepShot("bank-10-rueckfrage")
        tap(no, "Nein, neu")
        waitUntil("ausgewählt nach «Nein, neu»") { (check.value as? String) == "ausgewählt" && no.isSelected }
        tap(yes, "Ja, schon erfasst")
        waitUntil("abgewählt nach «Ja, schon erfasst»") { (check.value as? String) == "nicht ausgewählt" && yes.isSelected }
    }

    /// Lernt aus Korrekturen (Web v331 ff.): beim letzten Import bewusst abgewählt → vorab abgewählt mit Plakette
    /// «letztes Mal nicht übernommen»; erneut angehakt ist der Vorschlag wieder ausgewählt
    func testKontoauszugGelernt() {
        launch("-uiEmpty", "-uiBankSample", "-uiBankLearned")
        wait(el("Sind das deine Fixkosten?"), "Schritt Fixkosten", timeout: 25)
        let check = button("bankCheck-Swisscom")
        wait(check, "Häkchen Swisscom")
        XCTAssertEqual(check.value as? String, "nicht ausgewählt", "letztes Mal abgewählt → vorab abgewählt")
        wait(elContaining("letztes Mal nicht übernommen"), "Plakette «letztes Mal nicht übernommen»")
        XCTAssertEqual(button("bankCheck-CSS").value as? String, "ausgewählt", "andere Vorschläge unverändert")
        keepShot("bank-12-gelernt")
        tap(check, "Häkchen Swisscom an")
        waitUntil("Häkchen an") { (check.value as? String) == "ausgewählt" }
    }

    /// Mehr → Daten: Zeile «Kontoauszug einlesen» (Web v266, Zeitraum des letzten Imports erst nach einem Import)
    func testMehrKontoauszugZeile() {
        launch("-uiDemo", "-uiTab", "more")
        let row = button("bankMoreRow")
        scrollTo(row)
        wait(row, "Zeile «Kontoauszug einlesen»")
        XCTAssertEqual(row.label, "Kontoauszug einlesen", "ohne Import nur der Titel (Zeitraum erst nach einem Import)")
    }

    /// Rückfrage abwarten (bis 8 s), fotografieren und mit `label` schliessen
    private func tapAlertButtonIfShown(_ label: String, screenshot: String) {
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 8), "Rückfrage «Fast fertig!» fehlt")
        XCTAssertTrue(alert.label.contains("Fast fertig") || app.staticTexts["Fast fertig!"].exists, "Titel: \(alert.label)")
        keepShot(screenshot)
        tapAlertButton(label)
    }
}
