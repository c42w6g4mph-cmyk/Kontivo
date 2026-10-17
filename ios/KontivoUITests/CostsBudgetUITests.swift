import XCTest

/// e) Kosten: Monat per Antippen der Balken, Jahr mit Pfeilen, Personen-Chip. Budget: «+ Einnahme» → erscheint.
final class CostsBudgetUITests: KontivoUITestCase {

    private func chart(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(pred("label BEGINSWITH %@", prefix)).firstMatch
    }

    private func value(_ e: XCUIElement) -> String { (e.value as? String) ?? "" }

    func testKostenMonatJahrPerson() {
        launch("-uiDemo", "-uiTab", "costs")
        let y = currentYear
        let c = chart("Zahlungen pro Monat")
        wait(c, "Diagramm «Zahlungen pro Monat»", timeout: 12)
        XCTAssertTrue(c.label.contains(String(y)), "Diagramm zeigt nicht das aktuelle Jahr: \(c.label)")

        // Januar antippen
        c.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.45)).tap()
        waitUntil("Januar gewählt (\(value(c)))") { self.value(c).hasPrefix("Januar") }
        wait(el("Januar \(y)"), "Kopf «Januar \(y)» (ohne Versalien, v166)")
        wait(elContaining("Fällig im Januar"), "Liste «Fällig im Januar»")

        // Dezember antippen
        c.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.45)).tap()
        waitUntil("Dezember gewählt (\(value(c)))") { self.value(c).hasPrefix("Dezember") }

        // Jahr zurück und vor
        tap(button("Vorjahr"), "Vorjahr")
        wait(el("Jahr \(y - 1)"), "Jahr \(y - 1)")
        waitUntil("Diagramm im Vorjahr") { self.chart("Zahlungen pro Monat").label.contains(String(y - 1)) }
        tap(button("Folgejahr"), "Folgejahr")
        wait(el("Jahr \(y)"), "Jahr \(y)")

        // Personen-Chip
        let lara = button("Lara")
        tap(lara, "Chip Lara")
        waitUntil("Lara gewählt") { lara.isSelected }
        XCTAssertFalse(button("Alle").isSelected)
        tap(button("Alle"), "Chip Alle")
        waitUntil("Alle gewählt") { self.button("Alle").isSelected }
    }

    /// Web v190–v192: «Entwicklung und Preistreiber» – Säulen mit Jahrestotal, Treiber je Kategorie aufklappen, Säule setzt das Jahr
    func testKostenEntwicklungPreistreiber() {
        launch("-uiDemo", "-uiTab", "costs")
        wait(chart("Zahlungen pro Monat"), "Monatskarte", timeout: 12)
        let cat = button("costs.drivers.cat.Abos & Medien")
        reveal(cat, "Treiber «Abos & Medien»")
        XCTAssertTrue(cat.label.contains("Wechsel: TV → Musik"), "Wechsel heben sich auf: \(cat.label)")
        XCTAssertTrue(elContaining("Was sich verändert hat · \(currentYear - 1) → \(currentYear)").exists, "Titel der Treiberliste")
        tap(cat, "Abos & Medien aufklappen")
        wait(elContaining("beendet im Juni"), "Vertrag mit Grund (TV)")
        wait(button("Nur Abos & Medien anzeigen ›"), "Filter-Link")
        keepShot("costs-preistreiber")
        let next = button("costs.drivers.year.\(currentYear + 1)")
        reveal(next, "Säule Folgejahr")
        XCTAssertTrue(next.label.contains("Prognose"), "Säule Folgejahr = Prognose: \(next.label)")
        tap(next, "Säule Folgejahr")
        wait(el("Jahr \(currentYear + 1)"), "Seite im Folgejahr")
        wait(elContaining("Prognose · \(currentYear) → \(currentYear + 1)"), "Treiber als Prognose")
        XCTAssertTrue(next.isHittable, "Bereich bleibt sichtbar (Säule an derselben Stelle)")
    }

    /// Web v220: Teilen-Symbol in «Kosten» → Auswahl → «PDF erstellen» → PDF in der Dokumentansicht
    func testKostenFixkostenBericht() {
        launch("-uiDemo", "-uiTab", "costs")
        let rep = button("costs.report")
        wait(rep, "Teilen-Symbol «Fixkosten-Bericht als PDF»", timeout: 12)
        tap(rep, "Bericht")
        wait(elContaining("12-Monats-Vorschau"), "Hinweis im Fenster «Fixkosten-Bericht»")
        XCTAssertTrue(el("Kunden- und Vertragsnummern").exists || elContaining("Kunden- und Vertragsnummern").exists, "Schalter Nummern")
        XCTAssertTrue(button("Lara").exists, "Personenwahl")
        keepShot("costs-bericht-auswahl")
        tap(button("report.create"), "PDF erstellen")
        waitNav("Fixkosten-Bericht", timeout: 15)
        keepShot("costs-bericht-pdf")
    }

    func testBudgetEinnahmeErfassen() {
        launch("-uiDemo", "-uiTab", "budget")
        wait(chart("Verfügbar pro Monat"), "Budget-Karte", timeout: 12)
        tap(button("Einnahme erfassen"), "+ Einnahme")
        waitIncomeForm("Neue Einnahme")
        enter(textField("income.label"), "QA Nebenjob", "Bezeichnung")
        enter(textField("income.amount"), "800", "Betrag")
        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.incomeFormOpen("Neue Einnahme") }
        let row = buttonStarting("QA Nebenjob")
        wait(row, "Einnahme in der Liste")
        XCTAssertTrue(row.label.contains("800.00"), "Betrag der Einnahme: \(row.label)")
        // Beispieldaten: 5 Einnahmen (Lohn ×2, Kinderzulage, Steuerrückerstattung, Unterstützung) + neue
        wait(buttonContaining("Alle Einnahmen (6)"), "Alle Einnahmen (6)")

        // Einnahme öffnen (Ansicht, Web v155) → Bearbeiten (Formular «Bearbeiten», Web v154) → Abbrechen → Schliessen
        tap(row, "Einnahme öffnen")
        wait(el("incomeDetail.kz.month"), "Ansicht der Einnahme")
        tapTop("Bearbeiten")
        waitIncomeForm("Bearbeiten")
        XCTAssertEqual(textField("income.amount").value as? String, "800.00")
        tapTop("Abbrechen")
        waitUntil("Formular geschlossen") { !self.incomeFormOpen("Bearbeiten") }
        tapTop("Schliessen")
        waitGone(el("incomeDetail.kz.month"), "Ansicht geschlossen")
    }
}

/// Review-Paket 06.10.2026: Budget-Info «Was dir bleibt», «Fair geteilt?», Aufteilung im Detail und im Formular
final class ReviewPackageUITests: KontivoUITestCase {
    private func chart(_ prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(pred("label BEGINSWITH %@", prefix)).firstMatch
    }

    func testBudgetInfoFenster() {
        launch("-uiDemo", "-uiTab", "budget")
        wait(chart("Verfügbar pro Monat"), "Budget-Karte", timeout: 12)
        let share = button("budget.share")
        scrollTo(share)
        tap(share, "«% der Einnahmen» Info")
        waitNav("Was dir bleibt")
        wait(elContaining("deiner Einnahmen bleiben nach den Fixkosten"), "Erklärung im Fenster")
        wait(elContaining("Richtwerte von Budgetberatungen"), "Fussnote")
        tapTop("Schliessen")
        waitUntil("Fenster zu") { !self.navExists("Was dir bleibt") }
        // «Fair geteilt?» (Miete 70/30 gemeinsam, zwei Einkommen)
        let fair = el("budget.fair")
        scrollTo(fair)
        wait(fair, "Karte «Fair geteilt?»")
        XCTAssertTrue(elContaining("Fixkosten").exists)
    }

    func testAufteilungDetailUndFormular() {
        launch("-uiDemo", "-uiTab", "contracts")
        let row = buttonStarting("Miete")
        scrollTo(row)
        tap(row, "Miete öffnen")
        wait(elContaining("Sinan 70"), "Inhaber mit Anteilen", timeout: 12)
        XCTAssertTrue(elContaining("Lara 30").exists)
        wait(elContaining("bisher bezahlt (ca.)"), "Kachel «bisher bezahlt (ca.)» (Detail-Kennzahlen, Web v156)")
        tapTop("Bearbeiten")
        waitNav("Bearbeiten")
        let seg = el("form.split")
        scrollTo(seg)
        wait(seg, "Segment Aufteilung")
        XCTAssertTrue(seg.buttons["Individuell"].isSelected, "Individuell gewählt")
        tapTop("Abbrechen")
    }
}
