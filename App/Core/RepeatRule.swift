import Foundation

/// How often a task comes back. A repeating task only ever has one copy, the next one, so
/// missed days never pile up into a list of overdue copies.
enum RepeatRule: String, CaseIterable, Identifiable {
    case daily, weekdays, weekly, monthly

    var id: String { rawValue }

    /// The next date after `date`, keeping the day of the week (weekly) or month (monthly).
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        let day = calendar.startOfDay(for: date)
        switch self {
        case .daily:
            return calendar.date(byAdding: .day, value: 1, to: day) ?? day
        case .weekdays:
            var next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            while calendar.isDateInWeekend(next) { next = calendar.date(byAdding: .day, value: 1, to: next) ?? next }
            return next
        case .weekly:
            return calendar.date(byAdding: .day, value: 7, to: day) ?? day
        case .monthly:
            return calendar.date(byAdding: .month, value: 1, to: day) ?? day
        }
    }

    /// "Every Monday" for weekly, using the task's date.
    func label(for due: Date?, calendar: Calendar = .current) -> String {
        switch self {
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .monthly: return "Every month"
        case .weekly:
            guard let due else { return "Every week" }
            return "Every " + calendar.weekdaySymbols[calendar.component(.weekday, from: due) - 1]
        }
    }

    /// Menu titles, where the weekday isn't known yet.
    var menuTitle: String {
        switch self {
        case .daily: "Every Day"
        case .weekdays: "Every Weekday"
        case .weekly: "Every Week"
        case .monthly: "Every Month"
        }
    }
}

extension TaskItem {
    var repeatRule: RepeatRule? {
        get { repeatName.flatMap(RepeatRule.init) }
        set { repeatName = newValue?.rawValue }
    }

    /// Hidden from every list: let go in a review or a fresh start, or a paused repeating task.
    var isSetAside: Bool { setAsideAt != nil }
}
