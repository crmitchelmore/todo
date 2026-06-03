import Foundation

/// Shared "view by date" logic: classify a due date into a bucket on the user's LOCAL calendar
/// day (not raw timestamps), so a task due "today at 00:00" reads as Today, never Overdue.
/// Mirrors the web `dates.ts`.
public enum DateBucket: Int, CaseIterable, Sendable {
    case overdue = 0
    case today = 1
    case tomorrow = 2
    case thisWeek = 3
    case later = 4
    case noDate = 5

    public var label: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This week"
        case .later: return "Later"
        case .noDate: return "No date"
        }
    }
}

public enum DateGrouping {
    /// Whole-day difference (due - now) measured on the local calendar.
    public static func localDayDiff(_ due: Date, _ now: Date, calendar: Calendar = .current) -> Int {
        let a = calendar.startOfDay(for: due)
        let b = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: b, to: a).day ?? 0
    }

    public static func bucket(for due: Date?, now: Date = Date(), calendar: Calendar = .current) -> DateBucket {
        guard let due else { return .noDate }
        let diff = localDayDiff(due, now, calendar: calendar)
        if diff < 0 { return .overdue }
        if diff == 0 { return .today }
        if diff == 1 { return .tomorrow }
        if diff <= 7 { return .thisWeek }
        return .later
    }
}

public enum DatePreset: String, CaseIterable, Sendable {
    case today, tomorrow, weekend, nextWeek, clear

    public var label: String {
        switch self {
        case .today: return "Today"
        case .tomorrow: return "Tomorrow"
        case .weekend: return "Weekend"
        case .nextWeek: return "Next week"
        case .clear: return "Clear"
        }
    }

    /// Concrete date for a preset (day-level semantics; the time is a sensible default).
    /// Mirrors the web `presetDate`.
    public func date(now: Date = Date(), calendar: Calendar = .current) -> Date? {
        if self == .clear { return nil }
        let start = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ day: Date) -> Date {
            calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        switch self {
        case .today:
            return at(17, start)
        case .tomorrow:
            return at(9, calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        case .weekend:
            // next Saturday (weekday 7 in Gregorian), or today if already Saturday
            let wd = calendar.component(.weekday, from: start)
            let delta = (7 - wd + 7) % 7
            return at(9, calendar.date(byAdding: .day, value: delta, to: start) ?? start)
        case .nextWeek:
            // next Monday (weekday 2)
            let wd = calendar.component(.weekday, from: start)
            let delta = ((2 - wd + 7) % 7) == 0 ? 7 : ((2 - wd + 7) % 7)
            return at(9, calendar.date(byAdding: .day, value: delta, to: start) ?? start)
        case .clear:
            return nil
        }
    }

    /// Presets that set a date (excludes `.clear`), for building quick-pick rows.
    public static var settable: [DatePreset] { [.today, .tomorrow, .weekend, .nextWeek] }
}
