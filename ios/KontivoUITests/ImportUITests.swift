import XCTest

/// Plus-Menü und Kontoauszug-Import (Bereich import, Web v177–v223)
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
        if el("Kontivo sucht deine Fixkosten").waitForExistence(timeout: 6) {
            keepShot("bank-1-laden")
            if !elContaining("Bleibt auf deinem Gerät").exists { print("HINWEIS: Ladeanzeige schon vorbei, grüne Box nicht geprüft") }
        }

        // Schritt 1: Fixkosten
        wait(el("Sind das deine Fixkosten?"), "Schritt Fixkosten", timeout: 25)
        waitNav("Kontoauszug")
        let apply = el("bankApply")
        wait(apply, "Knopf unten")
        XCTAssertEqual(apply.label, "Weiter", "Knopf im ersten Schritt")
        wait(button("bankRow-Swisscom"), "Vorschlag Swisscom")
        XCTAssertTrue(elContaining("Frist fehlt").exists, "Plakette «Frist fehlt» (Miete) fehlt")
        keepShot("bank-2-fixkosten")

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
        tap(apply, "Weiter")
        wait(el("Und deine Einnahmen?"), "Schritt Einnahmen")
        waitUntil("Knopf «‹ Zurück»") { self.button("bankCancel").label == "‹ Zurück" }
        keepShot("bank-4-einnahmen")

        // Schritt 3: Kündigungsfristen (Miete ohne Katalog)
        tap(apply, "Weiter")
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
        // Abbrechen schliesst ohne Änderung
        tap(button("bankCancel"), "Abbrechen")
        waitGone(el("Sind das deine Fixkosten?"), "Fenster Kontoauszug")
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
