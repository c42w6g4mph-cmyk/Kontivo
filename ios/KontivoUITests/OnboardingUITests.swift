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

    /// b) Alle Seiten des Erststarts mit Bildschirmfotos und den Texten von Web v141
    ///    (Kontoauszug, Kündigen per Tipp, Tipps, letzter Schritt «Automatisch finden» + «Mit Vorlage starten»)
    func testEinfuehrungSeitenBildschirmfotos() {
        launch("-uiOnboarding")

        // 1 Willkommen
        wait(buttonStarting("Los geht"), "Los geht’s")
        XCTAssertTrue(elContaining("Kontoauszug rein – Fixkosten erkannt").exists, "Versprechen Kontoauszug fehlt")
        keepShot("onb-1-willkommen")
        tap(buttonStarting("Los geht"), "Los geht’s")

        // 2–5 Tabs
        let pages: [(title: String, bullet: String?, shot: String)] = [
            ("Alle Verträge im Blick", "Per Kontoauszug in Minuten erfasst", "onb-2-vertraege"),
            ("Jeden Monat im Voraus geplant", nil, "onb-3-kosten"),
            ("Weisst du, was dir bleibt?", nil, "onb-4-budget"),
            ("Keine ungewollten Vertragsverlängerungen", "Kündigen mit einem Tipp – Schreiben fertig", "onb-5-fristen"),
        ]
        for p in pages {
            waitUntil("Seite «\(p.title)»") { self.el(p.title).exists && self.el(p.title).isHittable }
            if let b = p.bullet { XCTAssertTrue(el(b).exists, "Punkt «\(b)» fehlt") }
            keepShot(p.shot)
            guard let weiter = firstHittable(buttons("Weiter")) else { return XCTFail("Kein «Weiter» auf \(p.title)") }
            weiter.tap()
        }

        // 6 Gut zu wissen
        waitUntil("Seite «Clever bis ins Detail»") { self.el("Clever bis ins Detail").exists && self.el("Clever bis ins Detail").isHittable }
        let einlesen = elContaining("Kontoauszug einlesen")
        XCTAssertTrue(einlesen.exists, "Tipp «Kontoauszug einlesen» fehlt")
        let pdf = elContaining("Kontoauszug als PDF oder Foto")
        XCTAssertTrue(pdf.exists, "Tipp «Kontoauszug als PDF oder Foto» fehlt")
        XCTAssertFalse(pdf.label.contains("Bald"), "PDF/Foto gibt es nativ schon – kein «Bald»: \(pdf.label)")
        keepShot("onb-6-tipps")
        guard let weiter = firstHittable(buttons("Weiter")) else { return XCTFail("Kein «Weiter» auf «Gut zu wissen»") }
        weiter.tap()

        // 7 Einrichten
        waitUntil("Seite «Noch zwei Angaben»") { self.el("Noch zwei Angaben").exists && self.el("Noch zwei Angaben").isHittable }
        keepShot("onb-7-einrichten")
        guard let weiter2 = firstHittable(buttons("Weiter")) else { return XCTFail("Kein «Weiter» auf «Einrichten»") }
        weiter2.tap()

        // 8 Womit fangen wir an?
        waitUntil("Seite «Womit fangen wir an?»") { self.el("Womit fangen wir an?").exists && self.el("Womit fangen wir an?").isHittable }
        let auto = el("onbAutoFind")
        XCTAssertTrue(auto.exists, "Karte «Automatisch finden» fehlt")
        XCTAssertTrue(auto.label.contains("Automatisch finden"), "Karte: \(auto.label)")
        XCTAssertTrue(elContaining("Mit Vorlage starten").exists, "Abschnitt «Mit Vorlage starten» fehlt")
        XCTAssertTrue(buttonStarting("Miete").exists, "Vorlage «Miete» fehlt")
        keepShot("onb-8-start")

        // «Automatisch finden» bietet die Quellen an
        auto.tap()
        let datei = app.buttons.matching(pred("label BEGINSWITH %@", "Datei wählen")).firstMatch
        XCTAssertTrue(datei.waitForExistence(timeout: 5), "Auswahl «Datei wählen» fehlt")
        keepShot("onb-9-quelle")
        tapAlertButton("Abbrechen")

        // Vorlage wählen: Knopf «Miete erfassen»
        tap(buttonStarting("Miete"), "Vorlage Miete")
        wait(button("Miete erfassen"), "Knopf «Miete erfassen»")
    }
}
