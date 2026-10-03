import XCTest
@testable import KontivoCore

final class DayTests: XCTestCase {
    func d(_ s: String) -> Day { Day(iso: s)! }

    func testOverflowConstructor() {
        XCTAssertEqual(Day(2026, 13, 1), d("2027-01-01"))
        XCTAssertEqual(Day(2026, 3, 0), d("2026-02-28"))
        XCTAssertEqual(Day(2024, 3, 0), d("2024-02-29"))
        XCTAssertEqual(Day(2026, 1, 0), d("2025-12-31"))
        XCTAssertEqual(Day(2026, 0, 1), d("2025-12-01"))
        XCTAssertEqual(Day(2026, -1, 15), d("2025-11-15"))
        XCTAssertEqual(Day(2026, 2, 31), d("2026-03-03"))
        XCTAssertEqual(Day(2026, 25, 1), d("2028-01-01"))
        XCTAssertEqual(Day(2026, 1, 366), d("2027-01-01"))
    }

    func testParse() {
        XCTAssertEqual(Day(iso: "2026-02-31"), Day(2026, 3, 3))
        XCTAssertEqual(Day(iso: "2026-10-03"), Day(2026, 10, 3))
        XCTAssertNil(Day(iso: ""))
        XCTAssertNil(Day(iso: "2026-10"))
        XCTAssertNil(Day(iso: "abc-1-1"))
        XCTAssertNil(Day(iso: "2026-10-03T00:00"))
        XCTAssertEqual(Day(2026, 10, 3).iso, "2026-10-03")
        XCTAssertEqual(Day(2026, 10, 3).description, "2026-10-03")
    }

    func testLeapYears() {
        XCTAssertTrue(Day(2024, 1, 1).isLeapYear)
        XCTAssertFalse(Day(2026, 1, 1).isLeapYear)
        XCTAssertFalse(Day(1900, 1, 1).isLeapYear)
        XCTAssertTrue(Day(2000, 1, 1).isLeapYear)
        XCTAssertEqual(Day(1900, 2, 29), d("1900-03-01"))
        XCTAssertEqual(Day(2028, 2, 1).daysInMonth, 29)
        XCTAssertEqual(Day(2027, 2, 1).daysInMonth, 28)
    }

    func testMonthEnds() {
        XCTAssertTrue(d("2028-02-29").isEndOfMonth)
        XCTAssertTrue(d("2027-02-28").isEndOfMonth)
        XCTAssertFalse(d("2028-02-28").isEndOfMonth)
        XCTAssertTrue(d("2026-04-30").isEndOfMonth)
        XCTAssertEqual(d("2026-02-10").lastDayOfMonth, d("2026-02-28"))
        XCTAssertEqual(d("2026-02-10").firstDayOfMonth, d("2026-02-01"))
    }

    func testAddingMonths() {
        XCTAssertEqual(d("2026-01-31").addingMonths(1), d("2026-02-28"))
        XCTAssertEqual(d("2024-01-31").addingMonths(1), d("2024-02-29"))
        XCTAssertEqual(d("2026-03-31").addingMonths(-1), d("2026-02-28"))
        XCTAssertEqual(d("2026-12-15").addingMonths(1), d("2027-01-15"))
        XCTAssertEqual(d("2026-01-15").addingMonths(-13), d("2024-12-15"))
        XCTAssertEqual(d("2026-01-31").addingMonths(2), d("2026-03-31"))
        XCTAssertEqual(d("2026-04-30").addingMonths(1), d("2026-05-30"))
    }

    func testAddingMonthsE() {
        XCTAssertEqual(d("2026-01-31").addingMonthsE(2), d("2026-03-31"))
        XCTAssertEqual(d("2026-04-30").addingMonthsE(1), d("2026-05-31"))
        XCTAssertEqual(d("2026-02-28").addingMonthsE(12), d("2027-02-28"))
        XCTAssertEqual(d("2024-02-29").addingMonthsE(12), d("2025-02-28"))
        XCTAssertEqual(d("2026-02-28").addingMonthsE(24), d("2028-02-29"))
        XCTAssertEqual(d("2026-11-30").addingMonthsE(-1), d("2026-10-31"))
        XCTAssertEqual(d("2026-10-15").addingMonthsE(1), d("2026-11-15"))
    }

    func testDays() {
        XCTAssertEqual(d("2026-10-02").days(to: d("2026-12-31")), 90)
        XCTAssertEqual(d("2026-12-31").days(to: d("2026-10-02")), -90)
        XCTAssertEqual(d("2028-02-28").addingDays(1), d("2028-02-29"))
        XCTAssertEqual(d("2027-02-28").addingDays(1), d("2027-03-01"))
        XCTAssertEqual(d("2026-01-01").addingDays(-1), d("2025-12-31"))
        XCTAssertEqual(Day(1970, 1, 1).ordinal, 0)
        XCTAssertEqual(Day(ordinal: 0), Day(1970, 1, 1))
        XCTAssertEqual(Day(2000, 3, 1).ordinal, 11017)
        XCTAssertEqual(Day(ordinal: Day(1969, 12, 31).ordinal), Day(1969, 12, 31))
        XCTAssertEqual(Day(1600, 2, 29).addingDays(1), Day(1600, 3, 1))
        XCTAssertEqual(d("2026-01-15").months(to: d("2027-03-01")), 14)
    }

    func testCompareAndCodable() throws {
        XCTAssertLessThan(d("2026-01-31"), d("2026-02-01"))
        XCTAssertLessThan(d("2025-12-31"), d("2026-01-01"))
        XCTAssertGreaterThan(d("2026-10-03"), d("2026-10-02"))
        let data = try JSONEncoder().encode([d("2026-10-03")])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"2026-10-03\"]")
        let back = try JSONDecoder().decode([Day].self, from: data)
        XCTAssertEqual(back, [d("2026-10-03")])
        XCTAssertThrowsError(try JSONDecoder().decode([Day].self, from: Data("[\"kein Datum\"]".utf8)))
    }

    func testTodayAndDate() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        let date = Day(2026, 10, 3).date(calendar: cal)
        XCTAssertEqual(Day(date: date, calendar: cal), Day(2026, 10, 3))
        // 23:30 UTC am 2.10. ist in Zürich schon der 3.10.
        let late = Date(timeIntervalSince1970: TimeInterval(Day(2026, 10, 2).ordinal) * 86_400 + 23.5 * 3600)
        XCTAssertEqual(Day.today(calendar: cal, now: late), Day(2026, 10, 3))
    }

    func testTimestamp() {
        XCTAssertEqual(Timestamp.isoString(Date(timeIntervalSince1970: 0)), "1970-01-01T00:00:00.000Z")
        XCTAssertEqual(Timestamp.isoString(Date(timeIntervalSince1970: 1_759_480_542.125)), "2025-10-03T08:35:42.125Z")
        let p = Timestamp.parse("2025-10-03T08:35:42.125Z")
        XCTAssertNotNil(p)
        XCTAssertEqual(p?.timeIntervalSince1970 ?? 0, 1_759_480_542.125, accuracy: 0.001)
        XCTAssertEqual(Timestamp.day(ofISO: "2026-10-03T08:15:42.123Z"), Day(2026, 10, 3))
    }
}
