import Foundation

#if canImport(EventKit)
import EventKit
#endif

public enum CalendarAccessStatus: Equatable, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case fullAccess
    case writeOnly
    case unavailable

    public var canReadEvents: Bool {
        switch self {
        case .authorized, .fullAccess:
            return true
        case .notDetermined, .restricted, .denied, .writeOnly, .unavailable:
            return false
        }
    }
}

public struct CalendarEvent: Equatable, Sendable {
    public let title: String
    public let interval: DateInterval

    public init?(title: String, start: Date, end: Date) {
        guard end > start else { return nil }
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Busy" : title
        self.interval = DateInterval(start: start, end: end)
    }
}

public protocol CalendarProvider: Sendable {
    var authorizationStatus: CalendarAccessStatus { get }
    func requestAccess() async -> CalendarAccessStatus
    func events(in interval: DateInterval) async throws -> [CalendarEvent]
}

public struct FeasibilityDuration: Equatable, Sendable {
    public let seconds: TimeInterval

    public init?(seconds: TimeInterval) {
        guard seconds > 0 else { return nil }
        self.seconds = seconds
    }

    public static func minutes(_ value: Double) -> FeasibilityDuration {
        FeasibilityDuration(seconds: value * 60)!
    }

    public static func hours(_ value: Double) -> FeasibilityDuration {
        FeasibilityDuration(seconds: value * 60 * 60)!
    }
}

public struct BusyMinutes: Equatable, Comparable, Sendable {
    public let value: Int

    public init(_ value: Int) {
        self.value = max(0, value)
    }

    public static func < (lhs: BusyMinutes, rhs: BusyMinutes) -> Bool {
        lhs.value < rhs.value
    }
}

public struct CalendarFeasibilityConfiguration: Equatable, Sendable {
    public let calendar: Calendar
    public let focusWindowBeforeDue: FeasibilityDuration
    public let tightGapThreshold: FeasibilityDuration
    public let tightBusyThreshold: BusyMinutes
    public let tightEventCountThreshold: Int

    public init(
        calendar: Calendar = .current,
        focusWindowBeforeDue: FeasibilityDuration = .hours(4),
        tightGapThreshold: FeasibilityDuration = .minutes(30),
        tightBusyThreshold: BusyMinutes = BusyMinutes(60),
        tightEventCountThreshold: Int = 2
    ) {
        self.calendar = calendar
        self.focusWindowBeforeDue = focusWindowBeforeDue
        self.tightGapThreshold = tightGapThreshold
        self.tightBusyThreshold = tightBusyThreshold
        self.tightEventCountThreshold = max(1, tightEventCountThreshold)
    }
}

public enum FeasibilityScore: Equatable, Sendable {
    case clear
    case tight
    case conflicted
}

public struct CalendarEventSummary: Equatable, Sendable {
    public let title: String
    public let interval: DateInterval

    public init(title: String, interval: DateInterval) {
        self.title = title
        self.interval = interval
    }
}

public struct FeasibilityEvidence: Equatable, Sendable {
    public let focusWindow: DateInterval
    public let calendarDay: DateInterval
    public let busyMinutes: BusyMinutes
    public let overlappingEvents: [CalendarEventSummary]
    public let nearbyEvents: [CalendarEventSummary]

    public var overlappingEventCount: Int { overlappingEvents.count }
    public var nearbyEventCount: Int { nearbyEvents.count }
    public var overlappingEventTitles: [String] { overlappingEvents.map(\.title) }
    public var nearbyEventTitles: [String] { nearbyEvents.map(\.title) }
}

public enum CalendarFeasibilityUnavailableReason: Equatable, Sendable {
    case calendarUnavailable
    case eventReadFailed
}

public enum FeasibilityAssessment: Equatable, Sendable {
    case permissionRequired(CalendarAccessStatus)
    case unavailable(CalendarFeasibilityUnavailableReason)
    case assessed(FeasibilityScore, FeasibilityEvidence)
}

public struct CalendarFeasibility: Sendable {
    private let provider: any CalendarProvider
    private let configuration: CalendarFeasibilityConfiguration

    public init(provider: any CalendarProvider, configuration: CalendarFeasibilityConfiguration = CalendarFeasibilityConfiguration()) {
        self.provider = provider
        self.configuration = configuration
    }

    public var authorizationStatus: CalendarAccessStatus {
        provider.authorizationStatus
    }

    public func requestAccess() async -> CalendarAccessStatus {
        await provider.requestAccess()
    }

    public func assess(dueAt dueDate: Date) async -> FeasibilityAssessment {
        let status = provider.authorizationStatus
        guard status.canReadEvents else {
            return status == .unavailable || status == .restricted
                ? .unavailable(.calendarUnavailable)
                : .permissionRequired(status)
        }

        guard let dayInterval = configuration.calendar.dateInterval(of: .day, for: dueDate) else {
            return .unavailable(.calendarUnavailable)
        }

        let requestedFocusStart = dueDate.addingTimeInterval(-configuration.focusWindowBeforeDue.seconds)
        let focusStart = max(dayInterval.start, requestedFocusStart)
        guard dueDate > focusStart else {
            return .unavailable(.calendarUnavailable)
        }
        let focusWindow = DateInterval(start: focusStart, end: dueDate)

        do {
            let dayEvents = try await provider.events(in: dayInterval)
                .sorted { $0.interval.start < $1.interval.start }
            let nearbyEvents = dayEvents.map(CalendarEventSummary.init)
            let overlappingEvents = dayEvents
                .filter { $0.interval.intersects(focusWindow) || $0.interval.contains(dueDate) }
                .map(CalendarEventSummary.init)
            let dueConflicts = dayEvents.filter { $0.interval.containsInstant(dueDate) }
            let busyMinutes = BusyMinutes.busyMinutes(from: dayEvents, clippedTo: focusWindow)
            let score = score(
                dueDate: dueDate,
                dueConflicts: dueConflicts,
                relevantEvents: overlappingEvents,
                busyMinutes: busyMinutes
            )

            return .assessed(
                score,
                FeasibilityEvidence(
                    focusWindow: focusWindow,
                    calendarDay: dayInterval,
                    busyMinutes: busyMinutes,
                    overlappingEvents: overlappingEvents,
                    nearbyEvents: nearbyEvents
                )
            )
        } catch {
            return .unavailable(.eventReadFailed)
        }
    }

    private func score(
        dueDate: Date,
        dueConflicts: [CalendarEvent],
        relevantEvents: [CalendarEventSummary],
        busyMinutes: BusyMinutes
    ) -> FeasibilityScore {
        if !dueConflicts.isEmpty {
            return .conflicted
        }

        let latestEventBeforeDue = relevantEvents
            .filter { $0.interval.end <= dueDate }
            .map(\.interval.end)
            .max()
        let hasTightGap = latestEventBeforeDue.map {
            dueDate.timeIntervalSince($0) < configuration.tightGapThreshold.seconds
        } ?? false

        if hasTightGap
            || busyMinutes >= configuration.tightBusyThreshold
            || relevantEvents.count >= configuration.tightEventCountThreshold {
            return .tight
        }

        return .clear
    }
}

private extension CalendarEventSummary {
    init(event: CalendarEvent) {
        self.init(title: event.title, interval: event.interval)
    }
}

private extension DateInterval {
    func intersects(_ other: DateInterval) -> Bool {
        start < other.end && end > other.start
    }

    func containsInstant(_ date: Date) -> Bool {
        start <= date && date < end
    }
}

private extension BusyMinutes {
    static func busyMinutes(from events: [CalendarEvent], clippedTo window: DateInterval) -> BusyMinutes {
        let clippedIntervals = events.compactMap { event -> DateInterval? in
            let start = max(event.interval.start, window.start)
            let end = min(event.interval.end, window.end)
            guard end > start else { return nil }
            return DateInterval(start: start, end: end)
        }.sorted { $0.start < $1.start }

        var merged: [DateInterval] = []
        for interval in clippedIntervals {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, interval.end))
            } else {
                merged.append(interval)
            }
        }

        let seconds = merged.reduce(0) { $0 + $1.duration }
        return BusyMinutes(Int((seconds / 60).rounded(.up)))
    }
}

#if canImport(EventKit)
public final class EventKitCalendarProvider: @unchecked Sendable, CalendarProvider {
    private let eventStore: EKEventStore

    public init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    public var authorizationStatus: CalendarAccessStatus {
        CalendarAccessStatus(eventKitStatus: EKEventStore.authorizationStatus(for: .event))
    }

    public func requestAccess() async -> CalendarAccessStatus {
        if #available(iOS 17.0, macOS 14.0, *) {
            do {
                let granted = try await eventStore.requestFullAccessToEvents()
                return granted ? .fullAccess : authorizationStatus
            } catch {
                return authorizationStatus
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { _, _ in
                    continuation.resume(returning: self.authorizationStatus)
                }
            }
        }
    }

    public func events(in interval: DateInterval) async throws -> [CalendarEvent] {
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: nil
        )

        return eventStore.events(matching: predicate).compactMap { event in
            guard let startDate = event.startDate, let endDate = event.endDate else { return nil }
            return CalendarEvent(title: event.title ?? "Busy", start: startDate, end: endDate)
        }
    }
}

private extension CalendarAccessStatus {
    init(eventKitStatus: EKAuthorizationStatus) {
        switch eventKitStatus {
        case .notDetermined:
            self = .notDetermined
        case .restricted:
            self = .restricted
        case .denied:
            self = .denied
        case .authorized:
            self = .authorized
        case .fullAccess:
            self = .fullAccess
        case .writeOnly:
            self = .writeOnly
        @unknown default:
            self = .unavailable
        }
    }
}
#endif
