import XCTest

/// c) Fristen: «Behalten» (Zähler sinkt), «Kündigen» → «Als gekündigt markieren»
/// d) Kündigung per Brief: Kündigungsschreiben → PDF → Viewer → «Text ändern» zurück
final class DeadlineUITests: KontivoUITestCase {

    private var keepButtons: XCUIElementQuery { buttons("Behalten") }

    /// Status «3 Entscheidungen offen» bzw. «1 Entscheidung offen» (Variante 1)
    private func openCount() -> Int? {
        let q = app.staticTexts.matching(pred("label MATCHES %@", "^[0-9]+ Entscheidung(en)? offen.*"))
        guard q.firstMatch.exists else { return nil }
        let label = q.firstMatch.label
        return Int(label.prefix { $0.isNumber })
    }

    func testBehaltenUndAlsGekuendigtMarkieren() {
        launch("-uiDemo", "-uiTab", "deadlines")
        wait(keepButtons.firstMatch, "Liste mit Knöpfen")
        // Knöpfe gibt es ab 30 Tagen vor der Frist oder 2 Monaten vor Vertragsende → mindestens so viele wie offene Entscheidungen
        let b0 = keepButtons.count
        guard let n0 = openCount() else { return XCTFail("Status «… offen» fehlt") }
        XCTAssertGreaterThanOrEqual(n0, 2, "Beispieldaten sollten mindestens 2 offene Entscheidungen haben")
        XCTAssertGreaterThanOrEqual(b0, n0)

        // Behalten (erste Zeile = früheste Frist)
        tap(keepButtons.firstMatch, "Behalten")
        waitUntil("Ein Knopfpaar weniger") { self.keepButtons.count == b0 - 1 }
        waitUntil("Status «\(n0 - 1) offen»") { self.openCount() == n0 - 1 || (n0 == 1 && self.elContaining("Alles erledigt").exists) }

        // Kündigen → Als gekündigt markieren
        let kill = buttons("Kündigen").firstMatch
        tap(kill, "Kündigen")
        tap(buttonStarting("Als gekündigt markieren"), "Als gekündigt markieren")
        waitUntil("Noch ein Knopfpaar weniger") { self.keepButtons.count == b0 - 2 }
        if n0 - 2 > 0 {
            waitUntil("Status «\(n0 - 2) offen»") { self.openCount() == n0 - 2 }
        } else {
            wait(elContaining("Alles erledigt"), "Alles erledigt")
        }
        // Der gekündigte Vertrag steht in der Liste als «Gekündigt» mit Chip «endet …»
        wait(elContaining("Gekündigt"), "Eintrag «Gekündigt»")
    }

    func testKuendigungsschreibenPDFUndZurueck() {
        launch("-uiDemo", "-uiTab", "deadlines")
        // Krankenkasse (CSS, Versicherung → Brief, Adresse vorhanden, Absender vollständig)
        tap(buttonStarting("Krankenkasse"), "Karte Krankenkasse")
        tap(button("detail.menu"), "Menü •••")
        // Menüeintrag «Kündigen/Wechseln · per Brief» (Krankenkasse ist Pflichtvertrag → «Wechseln»)
        tap(app.buttons.matching(pred("label CONTAINS %@", "per Brief")).firstMatch, "Menü: per Brief")
        waitNav("Kündigung")
        let pdf = button("PDF erstellen")
        tap(pdf, "PDF erstellen")
        // Viewer
        let back = button("Text ändern")
        wait(back, "Viewer mit «Text ändern»", timeout: 12)
        XCTAssertTrue(el("PDF-Vorschau").exists, "PDF-Vorschau fehlt")
        XCTAssertTrue(button("Drucken").exists, "Knopf Drucken fehlt")
        tap(back, "Text ändern")
        waitGone(back, "Viewer")
        waitNav("Kündigung")
        XCTAssertTrue(button("PDF erstellen").exists, "Zurück im Kündigungsschreiben")
        tapTop("Schliessen")
        waitUntil("Kündigung geschlossen") { !self.navExists("Kündigung") }
    }

    /// Hausrat: keine Empfängeradresse, zweiter Inhaber ohne Absender → beide Rückfragen, dann Viewer
    func testKuendigungsschreibenMitRueckfragen() {
        launch("-uiDemo", "-uiTab", "deadlines")
        tap(buttonStarting("Hausrat"), "Zeile Hausrat")
        tap(button("detail.menu"), "Menü •••")
        // Menüeintrag «Kündigen/Wechseln · per Brief» (Krankenkasse ist Pflichtvertrag → «Wechseln»)
        tap(app.buttons.matching(pred("label CONTAINS %@", "per Brief")).firstMatch, "Menü: per Brief")
        waitNav("Kündigung")
        tap(button("PDF erstellen"), "PDF erstellen")
        wait(app.alerts.firstMatch, "Rückfrage «Ohne Empfängeradresse?»")
        XCTAssertTrue(app.alerts.firstMatch.label.contains("Empfängeradresse") || elContaining("Empfängeradresse").exists)
        tapAlertButton("Trotzdem erstellen")
        // zweite Rückfrage (Absender von Lara fehlt)
        let second = app.alerts.firstMatch
        if second.waitForExistence(timeout: 4) {
            tapAlertButton("Trotzdem erstellen")
        }
        let back = button("Text ändern")
        wait(back, "Viewer", timeout: 12)
        tap(back, "Text ändern")
        waitNav("Kündigung")
    }

    /// Kündigen ohne Kündigungsweg: Auswahl «Per Brief» öffnet das Kündigungsschreiben
    func testKuendigungswegWaehlen() {
        launch("-uiDemo", "-uiTab", "deadlines")
        wait(keepButtons.firstMatch, "Entscheidungskarten")
        tap(buttons("Kündigen").firstMatch, "Kündigen")
        tap(buttonStarting("Kündigen: Weg wählen"), "Kündigen: Weg wählen …")
        waitNav("Kündigungsweg")
        tap(buttonStarting("Per Brief"), "Per Brief")
        waitNav("Kündigung", timeout: 12)
        wait(button("PDF erstellen"), "Kündigungsschreiben")
        tapTop("Schliessen")
        waitUntil("Kündigung geschlossen") { !self.navExists("Kündigung") }
    }

    /// Pflichtvertrag «Wechseln» → «Gekündigt, neuen Anbieter erfassen» → Formular «Neuer Anbieter»
    func testPflichtvertragWechseln() {
        launch("-uiDemo", "-uiTab", "deadlines")
        tap(buttons("Wechseln").firstMatch, "Wechseln")
        tap(buttonStarting("Gekündigt, neuen Anbieter erfassen"), "Gekündigt, neuen Anbieter erfassen")
        waitNav("Neuer Anbieter", timeout: 12)
        XCTAssertEqual(textField("form.label").value as? String, "Krankenkasse")
        tapTop("Abbrechen")
        if app.sheets.firstMatch.waitForExistence(timeout: 2) || app.alerts.firstMatch.exists {
            tapAlertButton("Verwerfen")
        }
        waitUntil("Formular geschlossen") { !self.navExists("Neuer Anbieter") }
        wait(elContaining("Gekündigt"), "Krankenkasse als «Gekündigt» in der Liste")
    }
}
