import XCTest
@testable import KontivoCore

/// Kontoauszug als Excel/OpenDocument/ZIP (Web v261/v272 `bankZip`): Swift gegen BankFixtures/zip/expected.json
/// (erzeugt mit BankFixtures/make_zip.py über window.KontivoBank().readFile).
final class BankZipTests: XCTestCase {
    typealias J = [String: Any]

    static let dir: URL? = BankParityTests.fixtures?.appendingPathComponent("zip")

    func testFilesLikeWeb() throws {
        let dir = try XCTUnwrap(BankZipTests.dir)
        let d = try Data(contentsOf: dir.appendingPathComponent("expected.json"))
        let exp = try XCTUnwrap(try JSONSerialization.jsonObject(with: d) as? J)
        XCTAssertGreaterThanOrEqual(exp.count, 7)
        for name in exp.keys.sorted() {
            let e = try XCTUnwrap(exp[name] as? J)
            let data = try Data(contentsOf: dir.appendingPathComponent(name))
            if let diag = e["diag"] as? String {
                XCTAssertThrowsError(try BankImport.read(data), name) { err in
                    XCTAssertEqual(err as? BankReadError, .notRecognized(BankReadDiag(rawValue: diag) ?? .none), name)
                }
                continue
            }
            let D = BankParityTests.Diff("ZIP " + name)
            do {
                let f = try BankImport.read(data)
                BankParityTests.compareRead(f, e, D, tx: true)
            } catch {
                D.errs.append("nicht gelesen: \(error)")
            }
            D.report()
        }
    }

    /// Deflate: gespeicherter Block (Stufe 0) und feste Huffman-Codes (Stufe 1/9), wie zlib mit wbits −15.
    func testInflate() throws {
        let text = String(repeating: "Kontivo Kontivo Kontivo - Deine Vertraege, ganz entspannt. ", count: 3)
        let vectors = [
            "AbEATv9Lb250aXZvIEtvbnRpdm8gS29udGl2byAtIERlaW5lIFZlcnRyYWVnZSwgZ2FueiBlbnRzcGFubnQuIEtvbnRpdm8gS29udGl2byBLb250aXZvIC0gRGVpbmUgVmVydHJhZWdlLCBnYW56IGVudHNwYW5udC4gS29udGl2byBLb250aXZvIEtvbnRpdm8gLSBEZWluZSBWZXJ0cmFlZ2UsIGdhbnogZW50c3Bhbm50LiA=",
            "887PK8ksy1fwRqN1FVxSM/NSFcJSi0qKElPTU3UU0hPzqhRS80qKCxLz8kr0MLTAjKCtVgA=",
            "887PK8ksy1fwRqN1FVxSM/NSFcJSi0qKElPTU3UU0hPzqhRS80qKCxLz8kr0MLTQRysA",
        ]
        for v in vectors {
            let raw = try XCTUnwrap(Data(base64Encoded: v))
            let out = try XCTUnwrap(Inflate.raw([UInt8](raw)), v)
            XCTAssertEqual(String(decoding: out, as: UTF8.self), text)
        }
        // beschädigt → nil statt Absturz
        XCTAssertNil(Inflate.raw([0xFF, 0xFF, 0xFF]))
        XCTAssertNil(Inflate.raw([]))
    }

    /// Altes Excel und PDF am Dateianfang erkannt (eigene Meldung).
    func testSignatures() {
        XCTAssertThrowsError(try BankImport.read(Data([0xD0, 0xCF, 0x11, 0xE0, 0, 0]))) { XCTAssertEqual($0 as? BankReadError, .notRecognized(.oldExcel)) }
        XCTAssertThrowsError(try BankImport.read(Data("%PDF-1.7".utf8))) { XCTAssertEqual($0 as? BankReadError, .notRecognized(.pdf)) }
        XCTAssertThrowsError(try BankImport.read(Data([0x50, 0x4B, 3, 4, 1, 2, 3]))) { XCTAssertEqual($0 as? BankReadError, .notRecognized(.zip)) }
    }

    /// Weitere Datumsformate und Grund «Datum nicht erkannt» (Web v272).
    func testDatesAndDiag() {
        XCTAssertEqual(BankReader.date("2025/10/03"), Day(2025, 10, 3))
        XCTAssertEqual(BankReader.date("2025.10.03"), Day(2025, 10, 3))
        XCTAssertNil(BankReader.date("2025/13/03"))
        XCTAssertEqual(BankReader.date("3. Okt. 2025"), Day(2025, 10, 3))
        XCTAssertEqual(BankReader.date("3 October 2025"), Day(2025, 10, 3))
        XCTAssertEqual(BankReader.date("3. März 2025"), Day(2025, 3, 3))
        XCTAssertEqual(BankReader.date("Oct 3, 2025"), Day(2025, 10, 3))
        XCTAssertNil(BankReader.date("3. Foo 2025"))
        let csv = "Datum;Text;Betrag\n31/31/2025;Miete;-1000\n30/31/2025;Strom;-80\n"
        XCTAssertThrowsError(try BankImport.read(Data(csv.utf8))) { XCTAssertEqual($0 as? BankReadError, .notRecognized(.dateFormat)) }
    }

    /// Nächste Zahlung am üblichen Zahltag (Web v272 `bankNextDue`).
    func testNextDue() {
        let today = Day(2026, 10, 8)
        // 25., 25., 23. (Wochenende), 24. → 25.
        XCTAssertEqual(BankImport.nextDue([Day(2026, 6, 25), Day(2026, 7, 25), Day(2026, 8, 23), Day(2026, 9, 24)], cycle: 1, today: today), Day(2026, 10, 25))
        // meist ≥ 28. → Monatsende
        XCTAssertEqual(BankImport.nextDue([Day(2026, 7, 31), Day(2026, 8, 28), Day(2026, 9, 30)], cycle: 1, today: today), Day(2026, 10, 31))
        // weniger als 3 Buchungen: Tag der letzten
        XCTAssertEqual(BankImport.nextDue([Day(2026, 3, 15)], cycle: 12, today: today), Day(2027, 3, 15))
        XCTAssertEqual(BankImport.nextDue([], cycle: 1, today: today), today)
    }
}
