import XCTest

/// Vollständigkeit (Web v120–v134): Mehr → Vollständigkeit → Start → Logos («Ohne Logo») → Fristen-Frage → Adresse → Abschluss.
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

        // Start: Ring, «Noch n kurze Fragen», «Los geht’s · ca. n Minute(n)»
        waitNav("Vollständigkeit")
        wait(elContaining("kurze Frage"), "Startseite")
        let go = button("vk.go")
        wait(go, "Los geht’s")
        XCTAssertTrue(go.label.hasPrefix("Los geht’s · ca."), "Knopf: \(go.label)")
        shot("1-Start")
        tap(go, "Los geht’s")

        // Logos: im Test ohne Netz → «Logos ergänzen», Kachel antippen → «Ohne Logo»
        waitNav("Logos")
        wait(el("Logos ergänzen"), "Frage Logos")
        let tile = button("vk.tile.Swisscom")
        wait(tile, "Kachel Swisscom")
        shot("2-Logos")
        tap(tile, "Kachel Swisscom")
        waitNav("Swisscom")
        wait(el("Logo für «Swisscom»"), "Auswahl Swisscom")
        tap(button("vk.noLogo"), "Ohne Logo")
        waitNav("Logos")
        waitUntil("Swisscom «ohne Logo»") { self.button("vk.tile.Swisscom").label.contains("ohne Logo") }
        tap(button("vk.logoNext"), "Weiter")

        // Fristen-Frage für Stadtwerke Konstanz
        waitNav("Fristen")
        wait(el("Wie ist «Stadtwerke Konstanz» kündbar?"), "Frage Fristen")
        tap(button("vk.mode.open"), "Jederzeit kündbar")
        let notice = textField("vk.notice")
        wait(notice, "Feld Kündigungsfrist")
        replace(notice, "1", "Kündigungsfrist")
        shot("3-Frist")
        tap(button("vk.termSave"), "Weiter")

        // Adresse von Lara: überspringen
        waitNav("Adresse")
        wait(el("Adresse von Lara"), "Frage Adresse")
        shot("4-Adresse")
        tap(button("vk.senderSkip"), "Später eintragen")

        // Abschluss
        waitNav("Vollständigkeit")
        wait(elContaining("gut gemacht"), "Abschluss")
        wait(el("Kontivo erinnert dich vor jeder Frist"), "Liste Abschluss")
        shot("5-Ende")
        tap(button("vk.done"), "Fertig")
        waitUntil("Vollständigkeit geschlossen") { !self.navExists("Vollständigkeit") }

        // Stadtwerke hat jetzt eine Frist: keine Fristen-Frage mehr, Swisscom bleibt «ohne Logo»
        tap(button("more.completeness"), "Zeile Vollständigkeit erneut")
        waitNav("Vollständigkeit")
        tap(button("vk.go"), "Los geht’s")
        waitNav("Logos")
        XCTAssertFalse(button("vk.tile.Swisscom").exists, "Swisscom sollte bewusst ohne Logo sein")
        tap(button("vk.logoNext"), "Weiter")
        waitNav("Adresse")
        tapTop("Später")
        waitUntil("Vollständigkeit geschlossen") { !self.navExists("Adresse") }
    }
}
