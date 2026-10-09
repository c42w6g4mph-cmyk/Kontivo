import XCTest

/// Plus-Menü in «Verträge» (Bereich onb): «Vertrag erfassen» | «Aus Kontoauszug»
extension KontivoUITestCase {
    /// Plus antippen und einen Menüpunkt wählen (Beschriftung beginnt mit `item`; Menüpunkte haben eine zweite Zeile)
    func openPlusMenuItem(_ item: String, expect: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let plus = button("Hinzufügen")
        let entry = buttonStarting(item)
        tapOpen(plus, "Knopf +", expect: entry, file: file, line: line)
        tapOpen(entry, item, expect: expect, file: file, line: line)
    }
}

extension KontivoUITestCase {
    /// Bildschirmfoto als Anhang behalten (Name z.B. «onb-1-willkommen»)
    func keepShot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
