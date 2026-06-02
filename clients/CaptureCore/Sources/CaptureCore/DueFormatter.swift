import Foundation

/// Human-friendly relative due-date formatting shared by all native clients.
public enum DueFormatter {
    public static func short(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm"
        let hasTime = !(calendar.component(.hour, from: date) == 0 && calendar.component(.minute, from: date) == 0)
        let time = timeFmt.string(from: date)

        if calendar.isDateInToday(date) { return hasTime ? "Today \(time)" : "Today" }
        if calendar.isDateInTomorrow(date) { return hasTime ? "Tomorrow \(time)" : "Tomorrow" }
        if calendar.isDateInYesterday(date) { return hasTime ? "Yesterday \(time)" : "Yesterday" }

        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "EEE d MMM"
        let day = dateFmt.string(from: date)
        return hasTime ? "\(day) \(time)" : day
    }
}
