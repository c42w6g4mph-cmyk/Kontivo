import XCTest

/// Vollständigkeit (Web v120–v134, v143): Mehr → Vollständigkeit → Start → Fristen-Frage → Adresse → optional Logos
/// («Ohne Logo», «Ohne Logos fertig») → Abschluss (Ring/Überschrift nach Prozent, Liste nur bei komplett).
/// Zweiter Durchgang mit Adresse von Lara → komplett; dritter Start «Alles startklar!» mit «Logos ergänzen».
/// Start mit «-uiVkTerm»: bei «Stadtwerke Konstanz» fehlt die Kündigungsfrist (sonst stellen die Beispieldaten keine Fristen-Frage).
/// Im UI-Test sucht die App keine Logos im Netz (alle Kacheln «Suchen»). Bildschirmfotos als Anhang.
final class CompletenessUITests: KontivoUITestCase {

    private func shot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testVollstaendigkeitAblauf() {
        launch("-uiDemo", "-uiTab", "more", "-uiVkTerm")

        // Zeile unter «Mehr → Verwalten» mit Plakette «n offen»
        let row = button("more.completeness")
        wait(row, "Zeile Vollständigkeit")
        XCTAssertTrue(row.label.contains("noch nicht startklar"), "Vorlesetext: \(row.label)")
        shot("0-Mehr")
        tap(row, "Zeile Vollständigkeit")

        // Start: Ring, «Noch n kurze Fragen» (ohne Logos), «Los geht’s · ca. n Minute(n)»
        waitNav("Vollständigkeit")
        wait(elContaining("2 kurze Fragen"), "Startseite: Frist + Adresse, Logos zählen nicht")
        let go = button("vk.go")
        wait(go, "Los geht’s")
        XCTAssertTrue(go.label.hasPrefix("Los geht’s · ca."), "Knopf: \(go.label)")
        shot("1-Start")
        tap(go, "Los geht’s")

        // 1 Fristen-Frage für Stadtwerke Konstanz (Web v143: Fristen zuerst)
        waitNav("Fristen")
        wait(el("Wie ist «Stadtwerke Konstanz» kündbar?"), "Frage Fristen")
        XCTAssertTrue(el("Frage 1 von 2").exists, "Fortschritt «Frage 1 von 2»")
        tap(button("vk.mode.open"), "Jederzeit kündbar")
        let notice = textField("vk.notice")
        wait(notice, "Feld Kündigungsfrist")
        replace(notice, "1", "Kündigungsfrist")
        shot("2-Frist")
        tap(button("vk.termSave"), "Weiter")

        // 2 Adresse von Lara: überspringen
        waitNav("Adresse")
        wait(el("Adresse von Lara"), "Frage Adresse")
        XCTAssertTrue(el("Frage 2 von 2").exists, "Fortschritt «Frage 2 von 2»")
        shot("3-Adresse")
        tap(button("vk.senderSkip"), "Später eintragen")

        // 3 optional Logos am Schluss: im Test ohne Netz → «Logos ergänzen», Kachel antippen → «Ohne Logo»
        waitNav("Logos")
        wait(el("Logos ergänzen"), "Frage Logos")
        XCTAssertTrue(el("Optional · Logos").exists, "Fortschritt «Optional · Logos»")
        let tile = button("vk.tile.Swisscom")
        wait(tile, "Kachel Swisscom")
        shot("4-Logos")
        tap(tile, "Kachel Swisscom")
        waitNav("Swisscom")
        wait(el("Logo für «Swisscom»"), "Auswahl Swisscom")
        tap(button("vk.noLogo"), "Ohne Logo")
        waitNav("Logos")
        waitUntil("Swisscom «ohne Logo»") { self.button("vk.tile.Swisscom").label.contains("ohne Logo") }
        let logoNext = button("vk.logoNext")
        XCTAssertEqual(logoNext.label, "Ohne Logos fertig", "Knopf ohne Auswahl")
        tap(logoNext, "Ohne Logos fertig")

        // Abschluss: Ring + Überschrift nach Prozent, Liste nur bei komplett (Lara fehlt noch)
        waitNav("Vollständigkeit")
        waitUntil("Abschluss") {
            self.el("Fast geschafft!").exists || self.el("Gute Basis!").exists || self.el("Ein Anfang ist gemacht").exists
        }
        XCTAssertTrue(elContaining("noch nicht startklar").exists, "Text «… noch nicht startklar»")
        XCTAssertFalse(el("Kontivo erinnert dich vor jeder Frist").exists, "Liste nur, wenn alles startklar ist")
        shot("5-Ende")
        tap(button("vk.done"), "Fertig")
        waitUntil("Vollständigkeit geschlossen") { !self.navExists("Vollständigkeit") }

        // Zweiter Durchgang: Stadtwerke hat jetzt eine Frist → nur noch die Adresse; ausfüllen → komplett
        // («Gleich wie Sinan» übernimmt nur die Adresse, der Name fehlte dann weiter – wie Web `sndOk`)
        tap(button("more.completeness"), "Zeile Vollständigkeit erneut")
        waitNav("Vollständigkeit")
        wait(elContaining("1 kurze Frage"), "Startseite mit einer Frage")
        tap(button("vk.go"), "Los geht’s")
        waitNav("Adresse")
        enter(textField("Vorname"), "Lara", "Vorname")
        enter(textField("Nachname"), "Muster", "Nachname")
        enter(textField("Strasse und Nr."), "Seestrasse 12", "Strasse")
        enter(textField("PLZ"), "8280", "PLZ")
        enter(textField("Ort"), "Kreuzlingen", "Ort")
        closeKeyboard()
        tap(button("vk.senderSave"), "Weiter")
        waitNav("Logos")
        XCTAssertFalse(button("vk.tile.Swisscom").exists, "Swisscom sollte bewusst ohne Logo sein")
        tap(button("vk.logoNext"), "Ohne Logos fertig")
        waitNav("Vollständigkeit")
        wait(el("100 % – alles komplett!"), "Abschluss komplett")
        wait(el("Kontivo erinnert dich vor jeder Frist"), "Liste Abschluss")
        shot("6-Komplett")
        tap(button("vk.done"), "Fertig")
        waitUntil("Vollständigkeit geschlossen") { !self.navExists("Vollständigkeit") }
        waitUntil("Zeile «alle Verträge startklar»") { self.button("more.completeness").label.contains("alle Verträge startklar") }

        // Dritter Start: nur Logos fehlen → «Alles startklar!» mit «Logos ergänzen» / «Fertig»
        tap(button("more.completeness"), "Zeile Vollständigkeit ein drittes Mal")
        waitNav("Vollständigkeit")
        wait(el("Alles startklar!"), "Startseite «Alles startklar!»")
        XCTAssertTrue(elContaining("noch kein Logo").exists, "Hinweis auf fehlende Logos")
        wait(button("vk.readyDone"), "Knopf Fertig")
        shot("7-Startklar")
        tap(button("vk.readyLogos"), "Logos ergänzen")
        waitNav("Logos")
        tap(button("vk.logoNext"), "Ohne Logos fertig")
        waitNav("Vollständigkeit")
        wait(el("100 % – alles komplett!"), "Abschluss komplett")
        tap(button("vk.done"), "Fertig")
        waitUntil("Vollständigkeit geschlossen") { !self.navExists("Vollständigkeit") }
    }
}
