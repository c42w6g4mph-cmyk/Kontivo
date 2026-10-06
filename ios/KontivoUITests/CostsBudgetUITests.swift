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
        wait(el("JANUAR \(y)"), "Kopf «JANUAR \(y)»")
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

    func testBudgetEinnahmeErfassen() {
        launch("-uiDemo", "-uiTab", "budget")
        wait(chart("Verfügbar pro Monat"), "Budget-Karte", timeout: 12)
        tap(button("Einnahme erfassen"), "+ Einnahme")
        waitNav("Neue Einnahme")
        enter(textField("income.label"), "QA Nebenjob", "Bezeichnung")
        enter(textField("income.amount"), "800", "Betrag")
        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.navExists("Neue Einnahme") }
        let row = buttonStarting("QA Nebenjob")
        wait(row, "Einnahme in der Liste")
        XCTAssertTrue(row.label.contains("800.00"), "Betrag der Einnahme: \(row.label)")
        wait(buttonContaining("Alle Einnahmen (3)"), "Alle Einnahmen (3)")

        // Einnahme öffnen und wieder schliessen (Formular «Einnahme bearbeiten»)
        tap(row, "Einnahme öffnen")
        waitNav("Einnahme bearbeiten")
        XCTAssertEqual(textField("income.amount").value as? String, "800.00")
        tapTop("Abbrechen")
        waitUntil("Formular geschlossen") { !self.navExists("Einnahme bearbeiten") }
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
        wait(elContaining("Bisher bezahlt"), "Zeile «Bisher bezahlt»")
        tapTop("Bearbeiten")
        waitNav("Vertrag bearbeiten")
        let seg = el("form.split")
        scrollTo(seg)
        wait(seg, "Segment Aufteilung")
        XCTAssertTrue(seg.buttons["Individuell"].isSelected, "Individuell gewählt")
        tapTop("Abbrechen")
    }
}
