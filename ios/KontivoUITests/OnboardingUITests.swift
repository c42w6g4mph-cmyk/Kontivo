import XCTest

/// a) Einführung: durchwischen und «Weiter», Einrichten (CHF, Name), «Erst mal umschauen» → Verträge, Leerseite
final class OnboardingUITests: KontivoUITestCase {

    func testEinfuehrungBisLeerseite() {
        launch("-uiOnboarding")

        tap(buttonStarting("Los geht"), "Los geht’s")
        wait(el("Alle Verträge im Blick"), "Seite Verträge")

        // eine Seite per Wischen
        app.swipeLeft()
        waitUntil("Seite Kosten nach Wischen") { el("Jeden Monat im Voraus geplant").exists && el("Jeden Monat im Voraus geplant").isHittable }

        // weiter mit «Weiter» bis zur Seite «Noch zwei Angaben»
        let setupTitle = el("Noch zwei Angaben")
        var taps = 0
        while !(setupTitle.exists && setupTitle.isHittable) && taps < 6 {
            guard let weiter = firstHittable(buttons("Weiter")) else {
                XCTFail("Kein antippbarer Knopf «Weiter»")
                return
            }
            weiter.tap()
            taps += 1
            usleep(700_000)
        }
        XCTAssertTrue(setupTitle.isHittable, "Seite «Noch zwei Angaben» nicht erreicht")
        XCTAssertEqual(taps, 4, "Erwartet: 4× «Weiter» von Kosten bis Einrichten")

        // Hauptwährung CHF und Name
        let chf = buttonStarting("CHF")
        tap(chf, "Währung CHF")
        waitUntil("CHF gewählt") { chf.isSelected }
        enter(textField("Wie heisst du?"), "Sinan\n", "Name")

        guard let weiter = firstHittable(buttons("Weiter")) else {
            XCTFail("Kein «Weiter» auf der Seite Einrichten")
            return
        }
        weiter.tap()
        waitUntil("Seite «Womit fangen wir an?»") { el("Womit fangen wir an?").exists && el("Womit fangen wir an?").isHittable }

        tap(button("Erst mal umschauen"), "Erst mal umschauen")

        // Tab Verträge mit Leerseite
        wait(button("Ersten Vertrag erfassen"), "Leerseite Verträge", timeout: 10)
        XCTAssertTrue(el("Jeden Vertrag im Griff.\nJede Frist im Blick.").exists || elContaining("Jeden Vertrag im Griff").exists,
                      "Titel der Leerseite fehlt")
        let tab = app.tabBars.buttons["Verträge"].firstMatch
        if tab.exists { XCTAssertTrue(tab.isSelected, "Tab Verträge nicht gewählt") }

        // Einrichten wurde übernommen: CHF und Name in «Mehr»
        tapTab("Mehr")
        let chfMore = buttonStarting("CHF")
        wait(chfMore, "CHF in Mehr")
        XCTAssertTrue(chfMore.isSelected, "Hauptwährung CHF nicht übernommen")
        let holders = buttonStarting("Personen")
        wait(holders, "Zeile Personen")
        XCTAssertTrue(holders.label.contains("Sinan"), "Name nicht übernommen: \(holders.label)")
    }
}
