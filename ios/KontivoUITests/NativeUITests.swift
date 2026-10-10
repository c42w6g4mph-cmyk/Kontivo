import XCTest

/// Bereich native: Einstellungen «Erinnerungen» / «Tage vorher» / «App-Sperre» unter Mehr, «In Kalender» in «Fristen»,
/// Kündigungsschreiben direkt per Mail bzw. Drucken.
/// Systemabfragen (Mitteilungen, Kalender, Face ID) lassen sich im CI nicht zuverlässig beantworten:
/// mit `-uiNativeStub` gelten Berechtigungen als erteilt; ein Test prüft den Ablauf bis zur Systemabfrage.
final class NativeUITests: KontivoUITestCase {

    private func switchValue(_ e: XCUIElement) -> String { (e.value as? String) ?? "" }

    /// Beschriftung ist eine von mehreren (deutsch/englisch, Systemdialoge)
    private func labelIn(_ labels: [String]) -> NSPredicate {
        NSPredicate(format: "label IN %@", argumentArray: [labels])
    }

    /// Schalter rechts antippen (ein Tipp auf die Beschriftung schaltet SwiftUI-Toggles nicht um)
    private func flip(_ e: XCUIElement, _ what: String) {
        reveal(e, what)
        let inner = e.switches.firstMatch
        if inner.exists && inner.isHittable {
            inner.tap()
        } else {
            e.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: Mehr → Erinnerungen und Sicherheit

    func testErinnerungenUndAppSperreSchalter() {
        launch("-uiDemo", "-uiTab", "more", "-uiNativeStub")
        let remind = app.switches["native.remind"]
        reveal(remind, "Schalter Erinnerungen")
        XCTAssertEqual(switchValue(remind), "0", "Erinnerungen sind anfangs aus")
        XCTAssertTrue(elContaining("Erinnerungen und Sicherheit").exists, "Gruppentitel fehlt")

        // «Tage vorher» ist ohne Erinnerungen gesperrt
        let lead = app.buttons["native.lead"]
        wait(lead, "Auswahl Tage vorher")
        XCTAssertFalse(lead.isEnabled, "«Tage vorher» sollte ohne Erinnerungen gesperrt sein")

        flip(remind, "Erinnerungen einschalten")
        waitUntil("Erinnerungen an") { self.switchValue(remind) == "1" }
        waitUntil("«Tage vorher» frei") { lead.isEnabled }

        // 14 Tage wählen
        tap(lead, "Tage vorher")
        tap(button("14 Tage"), "14 Tage")
        waitUntil("14 Tage gewählt") { ((lead.value as? String) ?? "").contains("14") || lead.label.contains("14") || self.app.staticTexts["14 Tage"].exists || self.app.buttons["14 Tage"].exists }

        // App-Sperre ein und wieder aus
        let lock = app.switches["native.lock"]
        reveal(lock, "Schalter App-Sperre")
        XCTAssertEqual(switchValue(lock), "0")
        flip(lock, "App-Sperre einschalten")
        waitUntil("App-Sperre an") { self.switchValue(lock) == "1" }
        flip(lock, "App-Sperre ausschalten")
        waitUntil("App-Sperre aus") { self.switchValue(lock) == "0" }

        // Erinnerungen aus → «Tage vorher» wieder gesperrt
        flip(remind, "Erinnerungen ausschalten")
        waitUntil("Erinnerungen aus") { self.switchValue(remind) == "0" }
        waitUntil("«Tage vorher» gesperrt") { !lead.isEnabled }
    }

    /// Ohne Stub: Einschalten führt bis zur Systemabfrage «Mitteilungen»; erlaubt → Schalter an.
    func testErinnerungenSystemabfrage() {
        launch("-uiDemo", "-uiTab", "more")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var sawPrompt = false
        let monitor = addUIInterruptionMonitor(withDescription: "Mitteilungen erlauben") { alert in
            for label in ["Erlauben", "Allow"] where alert.buttons[label].exists {
                sawPrompt = true
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        defer { removeUIInterruptionMonitor(monitor) }

        let remind = app.switches["native.remind"]
        reveal(remind, "Schalter Erinnerungen")
        flip(remind, "Erinnerungen einschalten")
        // Systemabfrage liegt in Springboard: direkt beantworten, sonst über den Monitor
        let allow = springboard.alerts.buttons.matching(labelIn(["Erlauben", "Allow"])).firstMatch
        if allow.waitForExistence(timeout: 6) {
            sawPrompt = true
            attachScreenshot("Systemabfrage Mitteilungen")
            allow.tap()
        } else {
            app.tap() // löst den Monitor aus, falls die Abfrage als Unterbrechung kommt
        }
        // Erlaubt (oder schon früher erlaubt) → an; früher abgelehnt → aus mit Hinweis «Einstellungen»
        waitUntil("Schalter entschieden", timeout: 12) { remind.isEnabled }
        if sawPrompt {
            waitUntil("Erinnerungen an nach «Erlauben»") { self.switchValue(remind) == "1" }
        } else {
            attachScreenshot("Ohne Systemabfrage (bereits entschieden)")
        }
    }

    // MARK: Fristen → In Kalender

    func testInKalenderInFristen() {
        launch("-uiDemo", "-uiTab", "deadlines", "-uiNativeStub")
        let keep = buttons("Behalten")
        wait(keep.firstMatch, "Zeilen mit Knöpfen")
        // Wie Web: keine zusätzlichen Knöpfe in der Zeile; «In Kalender» per langem Drücken und im Vertragsdetail (Menü •••)
        let row = app.buttons.matching(pred("label CONTAINS %@", "Kündigung bis")).firstMatch
        wait(row, "Zeile mit Kündigungsfrist")
        row.press(forDuration: 1.2)
        let cal = app.buttons.matching(pred("label == %@", "In Kalender")).firstMatch
        wait(cal, "Kontextmenü mit «In Kalender»")
        attachScreenshot("Kontextmenü Frist")
        tap(cal, "In Kalender")
        let editor = app.buttons.matching(labelIn(["Hinzufügen", "Add", "Abbrechen", "Cancel"])).firstMatch
        if editor.waitForExistence(timeout: 8) {
            attachScreenshot("Termin hinzufügen")
            let cancel = app.buttons.matching(labelIn(["Abbrechen", "Cancel"])).firstMatch
            if cancel.exists { cancel.tap() }
        } else {
            attachScreenshot("Kalenderdialog nicht erkannt")
        }
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: Kündigungsschreiben direkt senden / drucken

    func testKuendigungsschreibenDirektMailUndDrucken() {
        launch("-uiDemo", "-uiTab", "deadlines", "-uiNativeStub")
        tap(buttonStarting("Krankenkasse"), "Karte Krankenkasse")
        startCancelFromDetail()
        waitNav("Kündigung")
        let mail = button("letter.mail")
        let printBtn = button("letter.print")
        reveal(mail, "Per Mail senden")
        XCTAssertTrue(printBtn.exists, "Knopf «Drucken» fehlt")

        // Drucken: Systemdialog statt Vorschau
        tap(printBtn, "Drucken")
        sleep(2)
        attachScreenshot("Drucken")
        XCTAssertFalse(button("Text ändern").exists, "Drucken soll ohne Vorschau gehen")
        let cancelPrint = app.buttons.matching(labelIn(["Abbrechen", "Cancel"])).firstMatch
        if cancelPrint.waitForExistence(timeout: 4) { cancelPrint.tap() }
        usleep(800_000)

        // Mail: im Simulator meist ohne Mail-Konto → Teilen-Menü mit dem PDF, sonst Mail-Fenster
        if !mail.isHittable { app.swipeDown(velocity: .fast); usleep(800_000) }
        if !mail.isHittable {
            attachScreenshot("Druckdialog bleibt offen (Simulator)")
            return
        }
        tap(mail, "Per Mail senden")
        sleep(2)
        attachScreenshot("Per Mail senden")
        XCTAssertFalse(button("Text ändern").exists, "Mail soll ohne Vorschau gehen")
        XCTAssertEqual(app.state, .runningForeground)
    }
}
