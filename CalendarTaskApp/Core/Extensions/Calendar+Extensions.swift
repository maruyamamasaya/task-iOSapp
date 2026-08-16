import Foundation

extension Calendar {
    func replacingDate(of original: Date, with day: Date) -> Date {
        let time = dateComponents([.hour, .minute, .second, .nanosecond], from: original)
        return date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? startOfDay(for: day)
    }
    /// Month-only dates retained for callers that do not need a full grid.
    func monthDates(containing date: Date) -> [Date?] {
        guard let month = dateInterval(of: .month, for: date),
              let days = range(of: .day, in: .month, for: date) else { return [] }
        let weekdayOffset = component(.weekday, from: month.start) - firstWeekday
        let leading = (weekdayOffset + 7) % 7
        return Array(repeating: nil, count: leading) + days.compactMap {
            self.date(byAdding: .day, value: $0 - 1, to: month.start)
        }
    }

    /// Six complete Monday-first weeks. Adjacent-month dates are included so the
    /// grid remains stable and month boundaries are easy to understand.
    func monthGridDates(containing date: Date) -> [Date] {
        let configuredCalendar = self
        guard let month = configuredCalendar.dateInterval(of: .month, for: date) else { return [] }
        let weekdayOffset = configuredCalendar.component(.weekday, from: month.start) - configuredCalendar.firstWeekday
        let leading = (weekdayOffset + 7) % 7
        guard let gridStart = configuredCalendar.date(byAdding: .day, value: -leading, to: month.start) else { return [] }
        return (0..<42).compactMap {
            configuredCalendar.date(byAdding: .day, value: $0, to: gridStart)
        }
    }

    /// Seven calendar days in the Monday-first week containing `date`.
    func weekDates(containing date: Date) -> [Date] {
        let value = self
        let day = value.startOfDay(for: date)
        let offset = (value.component(.weekday, from: day) - value.firstWeekday + 7) % 7
        guard let monday = value.date(byAdding: .day, value: -offset, to: day) else { return [] }
        return (0..<7).compactMap { value.date(byAdding: .day, value: $0, to: monday) }
    }

    func mondayWeekDates(containing date: Date) -> [Date] {
        var value = self; value.firstWeekday = 2; return value.weekDates(containing: date)
    }

    func isDate(_ date: Date, inSameMonthAs other: Date) -> Bool {
        isDate(date, equalTo: other, toGranularity: .month)
    }

    func dayInterval(containing date: Date) -> DateInterval {
        let start = startOfDay(for: date)
        return DateInterval(start: start, end: self.date(byAdding: .day, value: 1, to: start) ?? start)
    }
}
