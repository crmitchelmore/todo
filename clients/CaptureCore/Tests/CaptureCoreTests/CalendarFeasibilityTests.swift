import XCTest
@testable import CaptureCore

private struct FakeCalendarProvider: CalendarProvider {
    let authorizationStatus: CalendarAccessStatus
    let calendarEvents: [CalendarEvent]

    func requestAccess() async -> CalendarAccessStatus {
        authorizationStatus
    }

    func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        calendarEvents.filter { event in
            event.interval.start < interval.end && event.interval.end > interval.start
        }
    }
}

final class CalendarFeasibilityTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    func testClearDayScoresClear() async throws {
        let dueAt = date(hour: 15)
        let scorer = CalendarFeasibility(
            provider: FakeCalendarProvider(authorizationStatus: .fullAccess, calendarEvents: []),
            configuration: configuration
        )

        let assessment = await scorer.assess(dueAt: dueAt)

        guard case let .assessed(score, evidence) = assessment else {
            return XCTFail("expected assessed result, got \(assessment)")
        }
        XCTAssertEqual(score, .clear)
        XCTAssertEqual(evidence.busyMinutes, BusyMinutes(0))
        XCTAssertEqual(evidence.overlappingEventCount, 0)
        XCTAssertEqual(evidence.nearbyEventCount, 0)
    }

    func testMeetingOverDueTimeScoresConflicted() async throws {
        let dueAt = date(hour: 15)
        let event = try XCTUnwrap(CalendarEvent(
            title: "Roadmap review",
            start: date(hour: 14, minute: 30),
            end: date(hour: 15, minute: 30)
        ))
        let scorer = CalendarFeasibility(
            provider: FakeCalendarProvider(authorizationStatus: .fullAccess, calendarEvents: [event]),
            configuration: configuration
        )

        let assessment = await scorer.assess(dueAt: dueAt)

        guard case let .assessed(score, evidence) = assessment else {
            return XCTFail("expected assessed result, got \(assessment)")
        }
        XCTAssertEqual(score, .conflicted)
        XCTAssertEqual(evidence.busyMinutes, BusyMinutes(30))
        XCTAssertEqual(evidence.overlappingEventTitles, ["Roadmap review"])
        XCTAssertEqual(evidence.nearbyEventTitles, ["Roadmap review"])
    }

    func testShortGapBeforeDueTimeScoresTight() async throws {
        let dueAt = date(hour: 15)
        let event = try XCTUnwrap(CalendarEvent(
            title: "Product sync",
            start: date(hour: 13),
            end: date(hour: 14, minute: 40)
        ))
        let scorer = CalendarFeasibility(
            provider: FakeCalendarProvider(authorizationStatus: .fullAccess, calendarEvents: [event]),
            configuration: configuration
        )

        let assessment = await scorer.assess(dueAt: dueAt)

        guard case let .assessed(score, evidence) = assessment else {
            return XCTFail("expected assessed result, got \(assessment)")
        }
        XCTAssertEqual(score, .tight)
        XCTAssertEqual(evidence.busyMinutes, BusyMinutes(100))
        XCTAssertEqual(evidence.overlappingEventTitles, ["Product sync"])
    }

    func testDeniedPermissionReturnsPermissionRequired() async {
        let scorer = CalendarFeasibility(
            provider: FakeCalendarProvider(authorizationStatus: .denied, calendarEvents: []),
            configuration: configuration
        )

        let assessment = await scorer.assess(dueAt: date(hour: 15))

        XCTAssertEqual(assessment, .permissionRequired(.denied))
    }

    private var configuration: CalendarFeasibilityConfiguration {
        CalendarFeasibilityConfiguration(calendar: calendar)
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: 2027,
            month: 1,
            day: 12,
            hour: hour,
            minute: minute
        ))!
    }
}
