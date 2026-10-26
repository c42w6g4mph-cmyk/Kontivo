import XCTest

/// Einnahmen (Web v154–v159): Ansicht wie beim Vertrag, Formular im Vertragsstil mit «Zahlung am» als Tagesraster,
/// Plus-Menü «Einnahme erfassen», Duplizieren/Löschen. Beispieldaten: «Lohn» (Pharma AG) mit zwei Lohnerhöhungen,
/// «Unterstützung» quartalsweise am 15. (Stichtag 03.10.2026).
final class IncomeUITests: KontivoUITestCase {

    /// Budget: Zeile «Lohn» (Sinan) antippen → Ansicht → Bearbeiten → «Zahlung am» Tagesraster → 12. → Sichern
    func testEinnahmeAnsichtBearbeitenZahlungAm() {
        launch("-uiDemo", "-uiTab", "budget")
        let row = app.buttons.matching(pred("label BEGINSWITH %@ AND label CONTAINS %@", "Lohn", "Sinan")).firstMatch
        wait(row, "Zeile Lohn (Sinan)", timeout: 12)
        tap(row, "Lohn öffnen")

        // Ansicht: Kachel mit Anteil, Verlauf «mehr», nächste Zahlung, Angaben
        let month = el("incomeDetail.kz.month")
        wait(month, "Kachel «pro Monat»")
        XCTAssertTrue(month.label.contains("deiner Einnahmen"), "Anteil an allen Einnahmen: \(month.label)")
        let chart = el("income.chart")
        wait(chart, "Verlauf")
        XCTAssertTrue(chart.label.contains("6 % mehr"), "Plakette «↑ 6 % mehr»: \(chart.label)")
        XCTAssertTrue(el("incomeDetail.kz.next").label.contains("25.10.26"), "nächste Zahlung 25.10.26")
        XCTAssertTrue(elContaining("monatlich am 25.").exists, "Zeile Zahlung")
        keepShot("inc-1-ansicht")

        // Bearbeiten: Formular im Vertragsstil, Änderungsliste mit % und «aktuell»
        tapTop("Bearbeiten")
        waitIncomeForm("Bearbeiten")
        // Web v316: Betragsfelder mit Tausendertrennung
        XCTAssertEqual(textField("income.amount").value as? String, "7\u{2019}200.00")
        // Zeitstrahl (Web v314–v320): Stufe ab 01.01.26 «aktuell · +2 %», Betrag direkt in der Zeile
        let current = elContaining("aktuell · +2 %")
        reveal(current, "Stufe ab 01.01.26 «aktuell · +2 %»")
        XCTAssertTrue(textField("income.priceAmt.0").exists, "Betrag der neuesten Stufe als Feld")
        XCTAssertTrue(textField("Anfangsbetrag").exists, "Startzeile «Anfangsbetrag»")
        keepShot("inc-2-formular")

        // Zahlung am: Tagesraster (monatlich ohne Monatsreihe), Tag antippen übernimmt und klappt zu
        let due = button("income.due")
        tap(due, "Zahlung am")
        let d12 = button("income.due.day.12")
        reveal(d12, "Tag 12 im Raster")
        XCTAssertFalse(button("income.due.month.1").exists, "monatlich: keine Monatsreihe")
        keepShot("inc-3-tagesraster")
        tap(d12, "Tag 12")
        waitGone(d12, "Raster klappt zu")
        waitUntil("Zahlung am 12. (\((due.value as? String) ?? ""))") { (due.value as? String) == "12. im Monat" }

        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.incomeFormOpen("Bearbeiten") }
        waitUntil("Nächste Zahlung 12.10.26") { self.el("incomeDetail.kz.next").label.contains("12.10.26") }
        tapTop("Schliessen")
        waitGone(month, "Ansicht geschlossen")
    }

    /// Rhythmus quartalsweise: Monatsreihe markiert, Monat antippen bleibt offen, Tag übernimmt
    func testZahlungAmQuartalMonatsreihe() {
        launch("-uiDemo", "-uiTab", "budget")
        let row = buttonStarting("Unterstützung")
        wait(row, "Zeile Unterstützung", timeout: 12)
        XCTAssertTrue(row.label.contains("quartalsweise"), "Zweitzeile Person · Rhythmus: \(row.label)")
        tap(row, "Unterstützung öffnen")
        wait(el("incomeDetail.kz.month"), "Ansicht")
        tapTop("Bearbeiten")
        waitIncomeForm("Bearbeiten")
        let due = button("income.due")
        reveal(due, "Zahlung am")
        XCTAssertEqual(due.value as? String, "15. Jan, Apr, Jul, Okt")
        tap(due, "Zahlung am")
        let feb = button("income.due.month.2")
        reveal(feb, "Monatsreihe")
        XCTAssertTrue(button("income.due.month.10").isSelected, "Okt markiert")
        tap(feb, "Februar")
        waitUntil("Reihe Feb/Mai/Aug/Nov") { (due.value as? String) == "15. Feb, Mai, Aug, Nov" }
        XCTAssertTrue(button("income.due.day.3").exists, "Raster bleibt nach Monat offen")
        keepShot("inc-4-monatsreihe")
        tap(button("income.due.day.3"), "Tag 3")
        waitUntil("3. Feb, Mai, Aug, Nov") { (due.value as? String) == "3. Feb, Mai, Aug, Nov" }
        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.incomeFormOpen("Bearbeiten") }
        waitUntil("Nächste Zahlung 03.11.26") { self.el("incomeDetail.kz.next").label.contains("03.11.26") }
    }

    /// Plus-Menü in «Verträge»: «Einnahme erfassen · Lohn, Rente, Stipendium …» → Formular «Neue Einnahme»
    func testPlusMenueEinnahmeErfassen() {
        launch("-uiDemo", "-uiTab", "contracts")
        let plus = button("Hinzufügen")
        let entry = buttonStarting("Einnahme erfassen")
        tapOpen(plus, "Knopf +", expect: entry)
        // Untertitel («Einzeln, mit Vorlagen-Katalog», «Lohn, Rente, Stipendium …») sind in iOS-26-Menüs nicht abfragbar → Foto
        print("Menüpunkte: \(buttonStarting("Vertrag erfassen").label) | \(entry.label)")
        keepShot("inc-5-plusmenue")
        tap(entry, "Einnahme erfassen")
        waitIncomeForm("Neue Einnahme")
        enter(textField("income.label"), "QA Rente", "Bezeichnung")
        enter(textField("income.amount"), "1500", "Betrag")
        closeKeyboard()
        // Art: neue Arten (Web v156) im Menü
        tap(button("income.kind"), "Art")
        let zulagen = buttonStarting("Zulagen")
        wait(zulagen, "Art Zulagen im Menü")
        XCTAssertTrue(buttonStarting("Rückerstattung").exists, "Art Rückerstattung")
        tap(buttonStarting("Rente"), "Art Rente")
        waitUntil("Art Rente") { (self.button("income.kind").value as? String) == "Rente" }
        tapTop("Sichern")
        waitUntil("Formular geschlossen") { !self.incomeFormOpen("Neue Einnahme") }
        tapTab("Budget")
        wait(buttonStarting("QA Rente"), "Neue Einnahme im Budget")
    }

    /// Menü ••• der Ansicht: Duplizieren öffnet das Formular der Kopie; «Einnahme löschen» entfernt sie wieder
    /// (Liste: Verträge-Tab, Reiter «Einnahmen», Web v231)
    func testDuplizierenUndLoeschen() {
        launch("-uiDemo", "-uiTab", "contracts", "-uiList", "i", "-uiSheet", "incomeDetail")
        wait(el("incomeDetail.kz.month"), "Ansicht Lohn", timeout: 12)
        tap(button("incomeDetail.menu"), "Menü •••")
        tap(button("Duplizieren"), "Duplizieren")
        waitIncomeForm("Bearbeiten")
        XCTAssertEqual(textField("income.label").value as? String, "Lohn")
        tapTop("Abbrechen")
        waitUntil("Formular geschlossen") { !self.incomeFormOpen("Bearbeiten") }
        let copies = app.buttons.matching(pred("label BEGINSWITH %@ AND label CONTAINS %@", "Lohn", "7’600.00"))
        waitUntil("zwei Zeilen «Lohn 7’600.00» in «Einnahmen»") { copies.count >= 2 }

        // Kopie wieder löschen: Zeile → Ansicht → Bearbeiten → Einnahme löschen
        tap(copies.element(boundBy: 1), "Kopie öffnen")
        wait(el("incomeDetail.kz.month"), "Ansicht Kopie")
        tapTop("Bearbeiten")
        waitIncomeForm("Bearbeiten")
        tap(button("income.delete"), "Einnahme löschen")
        tapAlertButton("Löschen")
        waitUntil("Formular und Ansicht geschlossen") { !self.incomeFormOpen("Bearbeiten") && !self.el("incomeDetail.kz.month").exists }
        waitUntil("Kopie gelöscht") { copies.count == 1 }
    }

    /// Web v314–v320 bei Einnahmen: «+ Änderung» öffnet eine neue Zeile (Datum heute), Betrag fertig → Stufe; Betrag in der Zeile
    /// ändern; Stufe per Wischen löschen; kein Diagramm im Formular
    func testEinnahmeZeitstrahl() {
        launch("-uiDemo", "-uiTab", "budget")
        let row = app.buttons.matching(pred("label BEGINSWITH %@ AND label CONTAINS %@", "Lohn", "Sinan")).firstMatch
        wait(row, "Zeile Lohn (Sinan)", timeout: 12)
        tap(row, "Lohn öffnen")
        wait(el("incomeDetail.kz.month"), "Ansicht")
        tapTop("Bearbeiten")
        waitIncomeForm("Bearbeiten")
        XCTAssertFalse(el("income.form.chart").exists, "Kein Diagramm im Formular (Web v314)")
        wait(el("income.currency"), "Zeile Währung")
        let add = button("income.addChange")
        reveal(add, "+ Änderung")
        tap(add, "+ Änderung")
        let amt = textField("income.priceAmount")
        wait(amt, "Neue Zeile")
        keepShot("inc-5-neue-aenderung")
        enter(amt, "8000", "Neuer Betrag")
        closeKeyboard()
        if app.keyboards.count > 0 { closeKeyboard() }
        waitUntil("Neue Stufe «aktuell · +5 %»") { self.elContaining("aktuell · +5 %").exists }
        XCTAssertTrue(textField("income.priceAmt.2").exists, "Drei Stufen")
        keepShot("inc-6-zeitstrahl")
        // neueste Stufe per Wischen löschen
        let top = textField("income.priceAmt.0")
        let a = top.coordinate(withNormalizedOffset: CGVector(dx: -0.6, dy: 0.5))
        a.press(forDuration: 0.05, thenDragTo: a.withOffset(CGVector(dx: -300, dy: 0)))
        usleep(500_000)
        let del = app.buttons.matching(pred("label == %@", "Löschen")).firstMatch
        if textField("income.priceAmt.2").exists && del.exists && del.isHittable { del.tap() }
        waitGone(textField("income.priceAmt.2"), "Stufe nach dem Wischen")
        tapTop("Abbrechen")
    }
}

extension KontivoUITestCase {
    /// Formular der Einnahme (eigene Kopfleiste wie Web `.shbar`, ohne Navigationsleiste): Titel «Neue Einnahme» / «Bearbeiten»
    func incomeFormOpen(_ title: String) -> Bool {
        // eine Abfrage (kein späteres Lesen von .label: beim Schliessen kann das Element dazwischen verschwinden)
        app.descendants(matching: .any).matching(pred("identifier == %@ AND label == %@", "income.form.title", title)).firstMatch.exists
    }

    func waitIncomeForm(_ title: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        waitUntil("Formular «\(title)»", timeout: timeout, file: file, line: line) { self.incomeFormOpen(title) }
    }
}
