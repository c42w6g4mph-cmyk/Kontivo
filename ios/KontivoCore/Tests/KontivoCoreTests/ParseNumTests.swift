import XCTest
@testable import KontivoCore

/// Erwartungen = Ergebnisse von parseNum der Web-App (mit node geprüft)
final class ParseNumTests: XCTestCase {
    func testWebParity() {
        let cases: [(String, Double?)] = [
            ("59.90", 59.9), ("59,90", 59.9), ("1’234.50", 1234.5), ("1'234.50", 1234.5), ("1 234,50", 1234.5),
            ("1.234,50", 1234.5), ("1,234.50", 1234.5), ("1.234.567", 1234567), ("6’500", 6500), ("12abc", nil),
            ("", nil), ("-12,90", -12.9), ("−5", -5), (".5", 0.5), ("5.", 5), ("1.2.3,4", 123.4),
            ("abc", nil), ("1,2,3", 123),
        ]
        for (s, e) in cases {
            let v = Format.parseNum(s)
            if let e { XCTAssertEqual(v ?? .nan, e, accuracy: 1e-9, s) } else { XCTAssertNil(v, s) }
        }
    }
}
