import XCTest
@testable import CaptureCore

final class DateGroupingTests: XCTestCase {
    // Fixed "now": Wed 3 Jun 2026 14:30 local.
    private var cal = Calendar.current
    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: day, hour: h, minute: min))!
    }

    func testNilIsNoDate() {
        XCTAssertEqual(DateGrouping.bucket(for: nil, now: d(2026, 6, 3)), .noDate)
    }

    func testLocalMidnightTodayIsToday() {
        let now = d(2026, 6, 3, 14, 30)
        let midnight = d(2026, 6, 3, 0, 0)
        XCTAssertEqual(DateGrouping.bucket(for: midnight, now: now), .today)
    }

    func testBoundaries() {
        let now = d(2026, 6, 3, 9, 0) // Wed
        XCTAssertEqual(DateGrouping.bucket(for: d(2026, 6, 2), now: now), .overdue)
        XCTAssertEqual(DateGrouping.bucket(for: d(2026, 6, 4), now: now), .tomorrow)
        XCTAssertEqual(DateGrouping.bucket(for: d(2026, 6, 5), now: now), .thisWeek)
        XCTAssertEqual(DateGrouping.bucket(for: d(2026, 6, 10), now: now), .thisWeek) // +7
        XCTAssertEqual(DateGrouping.bucket(for: d(2026, 6, 11), now: now), .later)    // +8
    }

    func testLocalDayDiffIgnoresTime() {
        let now = d(2026, 6, 3, 23, 30)
        let earlyTomorrow = d(2026, 6, 4, 0, 30)
        XCTAssertEqual(DateGrouping.localDayDiff(earlyTomorrow, now), 1)
    }

    func testPresetsLandInExpectedBuckets() {
        let now = d(2026, 6, 3, 9, 0) // Wed
        XCTAssertNil(DatePreset.clear.date(now: now))
        XCTAssertEqual(DateGrouping.bucket(for: DatePreset.today.date(now: now), now: now), .today)
        XCTAssertEqual(DateGrouping.bucket(for: DatePreset.tomorrow.date(now: now), now: now), .tomorrow)
        // weekend = Saturday (weekday 7)
        let weekend = DatePreset.weekend.date(now: now)!
        XCTAssertEqual(cal.component(.weekday, from: weekend), 7)
        // next week = Monday (weekday 2)
        let nextWeek = DatePreset.nextWeek.date(now: now)!
        XCTAssertEqual(cal.component(.weekday, from: nextWeek), 2)
    }
}
