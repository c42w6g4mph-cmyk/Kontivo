import XCTest

/// c) Fristen: «Behalten» (Zähler sinkt), «Kündigen» → «Als gekündigt markieren»
/// d) Kündigung per Brief: Kündigungsschreiben → PDF → Viewer → «Text ändern» zurück
final class DeadlineUITests: KontivoUITestCase {

    private var keepButtons: XCUIElementQuery { buttons("Behalten") }

    /// Kopfzeile «3 offen · …»
    private func openCount() -> Int? {
        let q = app.staticTexts.matching(pred("label MATCHES %@", "^[0-9]+ offen.*"))
        guard q.firstMatch.exists else { return nil }
        let label = q.firstMatch.label
        return Int(label.prefix { $0.isNumber })
    }

    func testBehaltenUndAlsGekuendigtMarkieren() {
        launch("-uiDemo", "-uiTab", "deadlines")
        wait(keepButtons.firstMatch, "Entscheidungskarten")
        let n0 = keepButtons.count
        XCTAssertGreaterThanOrEqual(n0, 2, "Beispieldaten sollten mindestens 2 offene Entscheidungen haben")
        waitUntil("Kopfzeile «\(n0) offen»") { self.openCount() == n0 }

        // Behalten
        tap(keepButtons.firstMatch, "Behalten")
        waitUntil("Eine Entscheidung weniger") { self.keepButtons.count == n0 - 1 }
        waitUntil("Kopfzeile «\(n0 - 1) offen»") { self.openCount() == n0 - 1 || (n0 == 1 && self.elContaining("Alles erledigt").exists) }

        // Kündigen → Als gekündigt markieren
        let kill = buttons("Kündigen").firstMatch
        tap(kill, "Kündigen")
        tap(buttonStarting("Als gekündigt markieren"), "Als gekündigt markieren")
        waitUntil("Noch eine Entscheidung weniger") { self.keepButtons.count == n0 - 2 }
        if n0 - 2 > 0 {
            waitUntil("Kopfzeile «\(n0 - 2) offen»") { self.openCount() == n0 - 2 }
        } else {
            wait(elContaining("Alles erledigt"), "Alles erledigt")
        }
        // Der gekündigte Vertrag steht jetzt bei «Kommende Termine» als «gekündigt · endet …»
        wait(elContaining("gekündigt · endet"), "Eintrag «gekündigt · endet»")
    }

    func testKuendigungsschreibenPDFUndZurueck() {
        launch("-uiDemo", "-uiTab", "deadlines")
        // Krankenkasse (CSS, Versicherung → Brief, Adresse vorhanden, Absender vollständig)
        tap(buttonStarting("Krankenkasse"), "Karte Krankenkasse")
        tap(button("Kündigungsschreiben"), "Kündigungsschreiben")
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
        tap(button("Kündigungsschreiben"), "Kündigungsschreiben")
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
}
