import XCTest

/// Plus-Menü und Kontoauszug-Import (Bereich onb)
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

    /// Beispiel-CSV (PostFinance) ohne Systemauswahl: Ladeanzeige → Vorschläge → Editor → anlegen → «Fast fertig!»
    func testKontoauszugBeispiel() {
        launch("-uiEmpty", "-uiBankSample")

        // Ladeanzeige (kurz sichtbar, mindestens 0.9 s)
        if el("Kontivo sucht deine Fixkosten").waitForExistence(timeout: 6) { keepShot("bank-1-laden") }

        waitNav("Vorschläge", timeout: 20)
        let header = el("bankHeader")
        wait(header, "Kopfzeile")
        XCTAssertTrue(header.label.hasPrefix("PostFinance · 62 Buchungen"), "Kopfzeile: \(header.label)")
        XCTAssertTrue(header.label.contains("Okt 25 – Sep 26"), "Zeitraum: \(header.label)")
        wait(elContaining("Neu gefunden"), "Abschnitt «Neu gefunden»")
        wait(elContaining("Swisscom"), "Vorschlag Swisscom")
        let apply = el("bankApply")
        wait(apply, "Knopf anlegen")
        XCTAssertTrue(apply.label.hasSuffix("Verträge anlegen"), "Knopf: \(apply.label)")
        print("KONTOAUSZUG-KNOPF: \(apply.label)")
        keepShot("bank-2-vorschlaege")

        // Zeile aufklappen: Editor mit «Im Auszug»
        tap(button("bankRow-Swisscom"), "Zeile Swisscom")
        wait(textField("bankName"), "Feld Vertragspartner")
        XCTAssertTrue(elContaining("Im Auszug").exists, "Kasten «Im Auszug» fehlt")
        XCTAssertTrue(button("Nie mehr vorschlagen").exists, "«Nie mehr vorschlagen» fehlt")
        keepShot("bank-3-editor")
        tap(button("bankRowDone"), "Fertig")
        waitGone(textField("bankName"), "Editor")

        // Abwählen ändert den Knopf
        let before = apply.label
        tap(button("Swisscom übernehmen"), "Häkchen Swisscom")
        waitUntil("Knopf zählt eins weniger") { apply.label != before }
        tap(button("Swisscom übernehmen"), "Häkchen Swisscom wieder an")
        waitUntil("Knopf wie vorher") { apply.label == before }

        // Anlegen → Verträge, Rückfrage «Fast fertig!»
        tap(apply, "Verträge anlegen")
        tapAlertButtonIfShown("Später", screenshot: "bank-4-fast-fertig")
        wait(elContaining("Swisscom"), "Vertrag Swisscom in der Liste", timeout: 10)
        XCTAssertFalse(button("Ersten Vertrag erfassen").exists, "Leerseite noch sichtbar")
        keepShot("bank-5-vertraege")
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
