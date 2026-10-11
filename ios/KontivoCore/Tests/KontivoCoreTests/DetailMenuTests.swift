import XCTest
@testable import KontivoCore

/// `Calc.detailMenu(_:)` (Menü ••• allein, für Vertragskarten) = `detailInfo(_:).menu` für alle Zustände der v160-Fixtures.
extension WebSync160Tests {
    func testDetailMenuGleichWieDetailInfo() {
        let f = fixture()
        let calc = Calc(data: f.data, today: today)
        XCTAssertFalse(f.data.contracts.isEmpty)
        for c in f.data.contracts {
            XCTAssertEqual(calc.detailMenu(c), calc.detailInfo(c).menu, "Menü \(c.label)")
        }
        // Stichproben: Pflichtvertrag «Wechseln», nicht kündbar «Beendet …», gekündigt per ohne «Schon gekündigt …»
        var d = f.data
        if let i = d.contracts.firstIndex(where: { $0.label == "Musik" }) { d.contracts[i].mandatory = true }
        let calc2 = Calc(data: d, today: today)
        let m = calc2.detailMenu(d.contracts.first { $0.label == "Musik" }!)
        XCTAssertEqual(m.cancel?.title, "Wechseln")
        XCTAssertNil(m.pause)
        XCTAssertEqual(calc.detailMenu(f.c("tx")).alreadyCancelled?.title, "Beendet …")
        XCTAssertNil(calc.detailMenu(f.c("tx")).cancel)
        XCTAssertNil(calc.detailMenu(f.c("cp")).alreadyCancelled)
        XCTAssertTrue(calc.detailMenu(f.c("cp")).uncancel)
    }
}
