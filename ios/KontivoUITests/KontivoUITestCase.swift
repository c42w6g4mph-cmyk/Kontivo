import XCTest

/// Grundlage aller UI-Tests: Start mit Beispieldaten (Debug-Startargumente, siehe App/UITestHooks.swift),
/// Hilfen zum Finden und Antippen über sichtbare deutsche Texte, Bildschirmfoto und Elementbaum bei Fehlern.
class KontivoUITestCase: XCTestCase {
    var app: XCUIApplication!
    /// Erster Start im frisch gebooteten Simulator ist langsam (erster Tipp ging verloren): einmal länger warten
    private static var warmedUp = false

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if let app, let run = testRun, run.totalFailureCount > 0 {
            print("APP-ZUSTAND \(name): \(app.state.rawValue) (4 = läuft, 1 = beendet/abgestürzt)")
            if app.state == .runningForeground {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "Fehler"
                shot.lifetime = .keepAlways
                add(shot)
                let lines = app.debugDescription.split(separator: "\n", omittingEmptySubsequences: false)
                print("=== UI-HIERARCHIE \(name) (\(lines.count) Zeilen) ===")
                print(lines.prefix(260).joined(separator: "\n"))
                print("=== ENDE UI-HIERARCHIE ===")
            } else {
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.name = "Fehler-Bildschirm"
                shot.lifetime = .keepAlways
                add(shot)
            }
        }
        app?.terminate()
        app = nil
        try super.tearDownWithError()
    }

    // MARK: Start

    /// App mit Startargumenten starten (z.B. "-uiDemo", "-uiTab", "costs")
    @discardableResult
    func launch(_ args: String...) -> XCUIApplication {
        let a = XCUIApplication()
        a.launchArguments = args + ["-AppleLanguages", "(de)"]
        a.launch()
        app = a
        XCTAssertTrue(a.wait(for: .runningForeground, timeout: 30), "App startet nicht")
        // bereit, sobald die Tab-Leiste oder die Einführung da ist
        let ready = a.tabBars.firstMatch.waitForExistence(timeout: 40) || a.buttons.firstMatch.waitForExistence(timeout: 5)
        XCTAssertTrue(ready, "App zeigt nichts an")
        if !KontivoUITestCase.warmedUp {
            KontivoUITestCase.warmedUp = true
            sleep(4)
        }
        return a
    }

    // MARK: Abfragen

    func pred(_ format: String, _ args: CVarArg...) -> NSPredicate {
        NSPredicate(format: format, argumentArray: args)
    }

    /// Beliebiges Element mit genau dieser Beschriftung (oder Kennung)
    func el(_ label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(pred("label == %@ OR identifier == %@", label, label)).firstMatch
    }

    /// Beliebiges Element, dessen Beschriftung den Text enthält
    func elContaining(_ s: String) -> XCUIElement {
        app.descendants(matching: .any).matching(pred("label CONTAINS %@", s)).firstMatch
    }

    func button(_ label: String) -> XCUIElement {
        app.buttons.matching(pred("label == %@ OR identifier == %@", label, label)).firstMatch
    }

    func buttons(_ label: String) -> XCUIElementQuery {
        app.buttons.matching(pred("label == %@", label))
    }

    func buttonStarting(_ s: String) -> XCUIElement {
        app.buttons.matching(pred("label BEGINSWITH %@", s)).firstMatch
    }

    func buttonContaining(_ s: String) -> XCUIElement {
        app.buttons.matching(pred("label CONTAINS %@", s)).firstMatch
    }

    func textField(_ idOrLabel: String) -> XCUIElement {
        let q = app.descendants(matching: .textField).matching(pred("identifier == %@ OR label == %@ OR placeholderValue == %@",
                                                                       idOrLabel, idOrLabel, idOrLabel))
        return q.firstMatch
    }

    /// Erstes antippbares Element einer Abfrage (z.B. «Weiter» auf mehreren Seiten der Einführung)
    func firstHittable(_ q: XCUIElementQuery, timeout: TimeInterval = 8) -> XCUIElement? {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            for e in q.allElementsBoundByIndex where e.exists && e.isHittable { return e }
            usleep(250_000)
        } while Date() < end
        return nil
    }

    // MARK: Warten

    @discardableResult
    func wait(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "Nicht gefunden: \(what)", file: file, line: line)
        return e
    }

    func waitGone(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let exp = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: e)
        let r = XCTWaiter().wait(for: [exp], timeout: timeout)
        XCTAssertEqual(r, .completed, "Sollte verschwinden: \(what)", file: file, line: line)
    }

    /// Wartet, bis die Bedingung gilt (fragt alle 0.3 s ab)
    func waitUntil(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line, _ cond: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if cond() { return }
            usleep(300_000)
        }
        XCTAssertTrue(cond(), "Bedingung nicht erfüllt: \(what)", file: file, line: line)
    }

    // MARK: Bedienen

    /// Wartet auf das Element, scrollt bei Bedarf (Listen laden Zeilen erst beim Scrollen), schliesst eine verdeckende Tastatur.
    func reveal(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        if !e.waitForExistence(timeout: min(timeout, 4)) {
            scrollTo(e, timeout: timeout)
        }
        XCTAssertTrue(e.exists, "Nicht gefunden: \(what)", file: file, line: line)
        dismissKeyboardIfCovering(e)
        if !e.isHittable {
            // unterhalb des sichtbaren Bereichs: etwas scrollen (sonst scrollt XCUITest beim Antippen selbst)
            let bottom = app.windows.firstMatch.frame.maxY
            var n = 0
            while !e.isHittable && e.frame.minY > bottom - 90 && n < 8 {
                app.swipeUp(velocity: .slow)
                n += 1
            }
        }
    }

    /// Wartet auf das Element (siehe reveal) und tippt es an.
    func tap(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        reveal(e, what, timeout: timeout, file: file, line: line)
        e.tap()
    }

    /// Knopf im Inhalt antippen (nicht die gleich beschriftete Taste der Bildschirmtastatur)
    func tapContent(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let q = buttons(label)
        XCTAssertTrue(q.firstMatch.waitForExistence(timeout: 8), "Kein Knopf «\(label)»", file: file, line: line)
        let top = keyboardTop() ?? .greatestFiniteMagnitude
        let candidates = q.allElementsBoundByIndex.filter { $0.exists && $0.frame.minY < top - 1 }
        if let b = candidates.first(where: { $0.isHittable }) ?? candidates.first {
            tap(b, label, file: file, line: line)
        } else {
            XCTFail("Knopf «\(label)» nur auf der Tastatur gefunden", file: file, line: line)
        }
    }

    /// Hat das Feld den Tastaturfokus?
    func hasFocus(_ e: XCUIElement) -> Bool {
        (e.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Tippt an und prüft, dass sich etwas öffnet; sonst ein zweiter Versuch (Tipp ging verloren)
    func tapOpen(_ e: XCUIElement, _ what: String, expect: XCUIElement, timeout: TimeInterval = 8,
                 file: StaticString = #filePath, line: UInt = #line) {
        tap(e, what, file: file, line: line)
        if expect.waitForExistence(timeout: timeout) { return }
        print("HINWEIS: \(what) – nichts geöffnet, zweiter Versuch")
        if e.exists && e.isHittable { e.tap() }
        XCTAssertTrue(expect.waitForExistence(timeout: timeout), "Nach «\(what)» nicht erschienen", file: file, line: line)
    }

    /// Oberkante der Bildschirmtastatur (nil = keine Tastatur sichtbar)
    func keyboardTop() -> CGFloat? {
        let kb = app.keyboards.firstMatch
        guard kb.exists else { return nil }
        let f = kb.frame
        return f.height > 0 ? f.minY : nil
    }

    /// Verdeckt die Tastatur (samt Leiste «Fertig») das Element: Tastatur schliessen bzw. Inhalt hochschieben
    func dismissKeyboardIfCovering(_ e: XCUIElement) {
        for _ in 0..<3 {
            guard let top = keyboardTop(), e.exists, e.frame.maxY > top - 64 else { return }
            let done = buttons("Fertig").allElementsBoundByIndex.first { $0.exists && $0.isHittable && $0.frame.midY > top - 130 }
            if let d = done {
                d.tap()
            } else {
                let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42))
                from.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)))
            }
            usleep(600_000)
        }
    }

    /// Tippt den obersten Knopf mit dieser Beschriftung an – bei gestapelten Fenstern gibt es z.B. «Schliessen»
    /// mehrfach. Bevorzugt den zuletzt im Baum stehenden antippbaren Knopf (oberstes Fenster); sonst den letzten
    /// (XCUITest scrollt ihn beim Antippen in den sichtbaren Bereich).
    func tapTop(_ label: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let q = buttons(label)
        guard q.firstMatch.waitForExistence(timeout: timeout) else {
            XCTFail("Kein Knopf «\(label)»", file: file, line: line)
            return
        }
        usleep(300_000)
        let all = q.allElementsBoundByIndex.filter { $0.exists }
        if let h = all.last(where: { $0.isHittable }) {
            h.tap()
        } else if let l = all.last {
            l.tap()
        } else {
            XCTFail("Knopf «\(label)» verschwunden", file: file, line: line)
        }
    }

    /// Scrollt nach unten, bis das Element existiert
    func scrollTo(_ e: XCUIElement, timeout: TimeInterval = 10, maxSwipes: Int = 10) {
        var n = 0
        while !e.exists && n < maxSwipes {
            app.swipeUp(velocity: .slow)
            n += 1
            _ = e.waitForExistence(timeout: 0.8)
        }
    }

    /// Text eingeben (vorher antippen)
    func enter(_ field: XCUIElement, _ text: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        tap(field, what, file: file, line: line)
        usleep(300_000)
        field.typeText(text)
    }

    /// Feld leeren und neuen Text eingeben. Tippt rechts ins Feld (Schreibmarke ans Ende), ohne zweiten Tipp
    /// (der könnte die Leiste «Fertig» über der Tastatur treffen).
    func replace(_ field: XCUIElement, _ text: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(field, what, file: file, line: line)
        let old = (field.value as? String) ?? ""
        let hasText = !old.isEmpty && old != field.placeholderValue
        field.coordinate(withNormalizedOffset: CGVector(dx: hasText ? 0.96 : 0.5, dy: 0.5)).tap()
        usleep(500_000)
        if !hasFocus(field) {
            field.tap()
            usleep(500_000)
        }
        if hasText {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count + 2))
        }
        field.typeText(text)
    }

    /// Tab wechseln
    func tapTab(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
        let inBar = app.tabBars.buttons[name].firstMatch
        if inBar.waitForExistence(timeout: 5) {
            inBar.tap()
            return
        }
        tap(button(name), "Tab \(name)", file: file, line: line)
    }

    /// Knopf in einer Rückfrage (Alert oder Aktionsblatt)
    func tapAlertButton(_ label: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(timeout)
        repeat {
            let inAlert = app.alerts.buttons[label].firstMatch
            if inAlert.exists {
                inAlert.tap()
                return
            }
            let inSheet = app.sheets.buttons[label].firstMatch
            if inSheet.exists {
                inSheet.tap()
                return
            }
            usleep(250_000)
        } while Date() < end
        tap(button(label), "Rückfrage-Knopf \(label)", file: file, line: line)
    }

    /// Wartet auf einen Fenstertitel (Navigationsleiste)
    func waitNav(_ title: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) {
        let bar = app.navigationBars.matching(pred("identifier == %@", title)).firstMatch
        let text = app.navigationBars.staticTexts.matching(pred("label == %@", title)).firstMatch
        waitUntil("Fenstertitel «\(title)»", timeout: timeout, file: file, line: line) { bar.exists || text.exists }
    }

    /// Fenstertitel sichtbar?
    func navExists(_ title: String) -> Bool {
        app.navigationBars.matching(pred("identifier == %@", title)).firstMatch.exists
            || app.navigationBars.staticTexts.matching(pred("label == %@", title)).firstMatch.exists
    }

    /// Eine Seite zurück (Navigationsstapel)
    func goBack(file: StaticString = #filePath, line: UInt = #line) {
        let byID = app.navigationBars.buttons.matching(identifier: "BackButton")
        if let b = firstHittable(byID, timeout: 2) {
            b.tap()
            return
        }
        if let b = firstHittable(app.navigationBars.buttons.matching(pred("label == 'Zurück'")), timeout: 1) {
            b.tap()
            return
        }
        // Wischen vom linken Rand
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
    }

    /// Aktuelles Jahr (wie die App)
    var currentYear: Int { Calendar(identifier: .gregorian).component(.year, from: Date()) }
}
