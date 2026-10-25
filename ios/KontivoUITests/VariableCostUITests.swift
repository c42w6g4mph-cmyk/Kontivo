import XCTest

/// Variable Kosten und Verträge-Tab mit Reitern (Web v226–v233, v238/v239, v256). Beispieldaten: Lebensmittel 900 (Sinan & Lara),
/// Benzin 180 (Sinan), Ferien 250 ab 01.12.2026 (noch nicht aktiv); Stichtag 03.10.2026.
final class VariableCostUITests: KontivoUITestCase {

    /// Reiter «Variabel»: Kopf, Status-Chip, «+» → Formular mit Vorschlag → Sichern → Liste → Ansicht → Löschen
    func testVariabelErfassenAnsichtLoeschen() {
        launch("-uiDemo", "-uiTab", "contracts")
        tap(button("listMode.v"), "Reiter Variabel", timeout: 12)
        waitUntil("Kopf «Variable Kosten pro Monat»") { self.elContaining("Variable Kosten pro Monat").exists }
        XCTAssertTrue(elContaining("1’080.00").exists, "Summe ohne noch nicht aktive Ferien")
        wait(buttonStarting("1 noch nicht aktiv"), "Status-Chip «noch nicht aktiv»")
        tap(buttonStarting("1 noch nicht aktiv"), "nur noch nicht aktive")
        waitUntil("Kopf «Noch nicht aktiv, pro Monat»") { self.elContaining("Noch nicht aktiv, pro Monat").exists }
        tap(button("Filter entfernen"), "Status-Filter entfernen")
        waitUntil("Kopf wieder «Variable Kosten pro Monat»") { self.elContaining("Variable Kosten pro Monat").exists }

        tap(button("Hinzufügen"), "+ (Variable Kosten erfassen)")
        wait(el("var.form.title"), "Formular «Variable Kosten»")
        XCTAssertFalse(button("var.sug.benzin").exists, "Benzin ist schon erfasst, kein Vorschlag")
        tap(button("var.sug.kleid"), "Vorschlag Kleidung")
        XCTAssertEqual(textField("var.label").value as? String, "Kleidung")
        enter(textField("var.amount"), "120", "Betrag")
        keepShot("v2-formular-variable-kosten")
        tapTop("Sichern")
        waitGone(el("var.form.title"), "Formular geschlossen")
        let row = buttonStarting("Kleidung")
        wait(row, "Kleidung in der Liste")
        XCTAssertTrue(row.label.contains("120.00"), "Betrag: \(row.label)")

        tap(row, "Kleidung öffnen")
        wait(el("varDetail.kz.month"), "Ansicht")
        XCTAssertTrue(elContaining("Budget (nicht in Kosten und Fristen)").exists, "Zeile «Zählt in»")
        tap(button("varDetail.menu"), "Menü •••")
        tap(button("Löschen"), "Löschen")
        tapAlertButton("Löschen")
        waitGone(el("varDetail.kz.month"), "Ansicht geschlossen")
        waitGone(buttonStarting("Kleidung"), "Kleidung gelöscht")
    }

    /// Reiter «Einnahmen»: Filter Person, Etikett entfernen, Sortierung «Betrag»
    func testEinnahmenFilterSortierung() {
        launch("-uiDemo", "-uiTab", "contracts", "-uiList", "i")
        waitUntil("Kopf «Einnahmen pro Monat»", timeout: 12) { self.elContaining("Einnahmen pro Monat").exists }
        tap(button("contracts.filter"), "Filter")
        tap(button("Person"), "Person")
        tap(button("Lara"), "Lara")
        let tag = button("Filter Lara entfernen")
        wait(tag, "Etikett Lara")
        XCTAssertTrue(el("hero.sub").label.contains("– Lara"), "Unterzeile mit Filter: \(el("hero.sub").label)")
        XCTAssertFalse(buttonStarting("Kinderzulage").exists, "Kinderzulage gehört Sinan")
        tap(tag, "Filter entfernen")
        wait(buttonStarting("Kinderzulage"), "wieder alle Einnahmen")
        tap(button("contracts.sort"), "Sortierung")
        tap(button("Betrag, höchster zuerst"), "nach Betrag")
        waitUntil("sortiert nach Betrag") { self.button("contracts.sort").label.hasSuffix("Betrag") }
    }

    /// Budget: Kostenart nur mit variablen Kosten (v256), «Alle Kosten» zeigt Variabel im Kopf, Liste und Rechnung (v238)
    func testBudgetKostenart() {
        launch("-uiDemo", "-uiTab", "budget")
        let kind = button("budget.kind")
        wait(kind, "Auswahl Kostenart", timeout: 12)
        XCTAssertEqual(kind.value as? String, "Fixkosten", "Standard Fixkosten (v239)")
        XCTAssertFalse(el("budget.variable").exists)
        tap(kind, "Kostenart")
        tap(buttonStarting("Alle Kosten"), "Alle Kosten")
        waitUntil("Alle Kosten gewählt") { (kind.value as? String) == "Alle Kosten" }
        wait(elContaining("verfügbar nach Fix- und variablen Kosten"), "Unterzeile")
        let list = el("budget.variable")
        scrollTo(list)
        wait(list, "Liste «Variable Kosten Oktober»")
        let sum = el("budget.sum")
        scrollTo(sum)
        XCTAssertTrue(sum.label.contains("Nach Fixkosten"), "Zwischensumme: \(sum.label)")
    }
}
