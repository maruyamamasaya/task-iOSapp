import Foundation

extension Calendar {
    func monthDates(containing date: Date) -> [Date?] {
        guard let interval = dateInterval(of: .month, for: date),
              let days = range(of: .day, in: .month, for: date) else { return [] }
        let weekdayOffset = component(.weekday, from: interval.start) - firstWeekday
        let leading = (weekdayOffset + 7) % 7
        return Array(repeating: nil, count: leading) + days.compactMap {
            self.date(byAdding: .day, value: $0 - 1, to: interval.start)
        }
    }
}
