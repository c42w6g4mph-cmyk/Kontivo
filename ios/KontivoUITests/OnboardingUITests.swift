import XCTest

/// a) Einführung (Web v224): durchwischen und «Weiter», Einrichten (CHF, Name), «Erst mal umschauen» → Verträge, Leerseite
final class OnboardingUITests: KontivoUITestCase {

    func testEinfuehrungBisLeerseite() {
        launch("-uiOnboarding")

        tap(buttonStarting("Los geht"), "Los geht’s")
        wait(elContaining("Alle Verträge von Hand erfassen"), "Seite Automatisch erfassen")

        // eine Seite per Wischen
        app.swipeLeft()
        waitUntil("Seite Verträge nach Wischen") { el("Endlich alles im Blick").exists && el("Endlich alles im Blick").isHittable }

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
        XCTAssertEqual(taps, 4, "Erwartet: 4× «Weiter» von Verträge bis Einrichten")

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

    /// b) Alle Seiten des Erststarts mit Bildschirmfotos und den Texten von Web v224
    ///    (Willkommen, Automatisch erfassen, 4 Tabs, Einrichten, letzter Schritt «Automatisch erfassen» + «Selbst erfassen»)
    func testEinfuehrungSeitenBildschirmfotos() {
        launch("-uiOnboarding")

        // 1 Willkommen
        wait(buttonStarting("Los geht"), "Los geht’s")
        XCTAssertTrue(elContaining("Nie mehr zu viel bezahlen").exists, "Versprechen «Nie mehr zu viel bezahlen» fehlt")
        XCTAssertTrue(button("Ich habe schon ein Backup").exists, "Knopf «Ich habe schon ein Backup» fehlt")
        keepShot("onb-1-willkommen")
        tap(buttonStarting("Los geht"), "Los geht’s")

        // 2 Automatisch erfassen (drei Wege, Hinweis «Bleibt auf deinem Gerät»)
        let autoTitle = elContaining("Alle Verträge von Hand erfassen")
        waitUntil("Seite «Automatisch erfassen»") { autoTitle.exists && autoTitle.isHittable }
        for w in ["Kontoauszug laden", "PDF hochladen", "Foto machen"] {
            XCTAssertTrue(elContaining(w).exists, "Weg «\(w)» fehlt")
        }
        XCTAssertFalse(elContaining("PDF hochladen").label.lowercased().contains("bald"), "PDF gibt es nativ schon – kein «bald»")
        XCTAssertTrue(elContaining("Bleibt auf deinem Gerät").exists, "Hinweis «Bleibt auf deinem Gerät» fehlt")
        XCTAssertTrue(button("Überspringen").exists, "«Überspringen» fehlt")
        keepShot("onb-2-automatisch")
        guard let w0 = firstHittable(buttons("Weiter")) else { return XCTFail("Kein «Weiter» auf «Automatisch erfassen»") }
        w0.tap()

        // 3–6 Tabs
        let pages: [(title: String, bullet: String?, shot: String)] = [
            ("Endlich alles im Blick", "CHF und EUR automatisch umgerechnet", "onb-3-vertraege"),
            ("Nie mehr überrascht", "Du siehst, was teurer geworden ist", "onb-4-kosten"),
            ("Wissen, was dir bleibt", nil, "onb-5-budget"),
            ("Nie mehr zu spät kündigen", "Kündigungsschreiben mit einem Tipp", "onb-6-fristen"),
        ]
        for p in pages {
            waitUntil("Seite «\(p.title)»") { self.el(p.title).exists && self.el(p.title).isHittable }
            if let b = p.bullet { XCTAssertTrue(el(b).exists, "Punkt «\(b)» fehlt") }
            keepShot(p.shot)
            guard let weiter = firstHittable(buttons("Weiter")) else { return XCTFail("Kein «Weiter» auf \(p.title)") }
            weiter.tap()
        }

        // 7 Einrichten
        waitUntil("Seite «Noch zwei Angaben»") { self.el("Noch zwei Angaben").exists && self.el("Noch zwei Angaben").isHittable }
        keepShot("onb-7-einrichten")
        guard let weiter2 = firstHittable(buttons("Weiter")) else { return XCTFail("Kein «Weiter» auf «Einrichten»") }
        weiter2.tap()

        // 8 Womit fangen wir an?
        waitUntil("Seite «Womit fangen wir an?»") { self.el("Womit fangen wir an?").exists && self.el("Womit fangen wir an?").isHittable }
        let auto = el("onbAutoFind")
        XCTAssertTrue(auto.exists, "Karte «Automatisch erfassen» fehlt")
        XCTAssertTrue(auto.label.contains("Automatisch erfassen"), "Karte: \(auto.label)")
        XCTAssertTrue(elContaining("Selbst erfassen").exists, "Abschnitt «Selbst erfassen – tipp an, was du hast» fehlt")
        XCTAssertTrue(el("oder").exists, "Trenner «oder» fehlt")
        XCTAssertTrue(buttonStarting("Versicherung").exists, "Vorlage «Versicherung» fehlt")
        keepShot("onb-8-start")

        // «Automatisch erfassen» bietet die Quellen an
        auto.tap()
        let datei = app.buttons.matching(pred("label BEGINSWITH %@", "Datei wählen")).firstMatch
        XCTAssertTrue(datei.waitForExistence(timeout: 5), "Auswahl «Datei wählen» fehlt")
        keepShot("onb-9-quelle")
        // Auswahl schliessen (iOS 26 zeigt sie als Popover ohne «Abbrechen»)
        let cancel = app.buttons.matching(pred("label == %@", "Abbrechen")).firstMatch
        if cancel.exists && cancel.isHittable { cancel.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.2)).tap() }
        if datei.exists && datei.isHittable { app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.2)).tap() }
        usleep(800_000)

        // Vorlage wählen: Knopf «Miete erfassen»
        tap(buttonStarting("Miete"), "Vorlage Miete")
        wait(button("Miete erfassen"), "Knopf «Miete erfassen»")
    }
}
