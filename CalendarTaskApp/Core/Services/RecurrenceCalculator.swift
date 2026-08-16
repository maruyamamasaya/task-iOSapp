import Foundation

struct RecurrenceCalculator: Sendable {
    var calendar: Calendar
    init(calendar: Calendar = .current) { self.calendar = calendar }

    func occurs(anchor: Date, rule: RecurrenceRule?, on date: Date) -> Bool {
        let target = calendar.startOfDay(for: date), start = calendar.startOfDay(for: anchor)
        guard target >= start else { return false }
        guard let rule else { return calendar.isDate(target, inSameDayAs: start) }
        if let end = rule.endDate, target > calendar.startOfDay(for: end) { return false }
        if !rule.weekdays.isEmpty && !rule.weekdays.contains(calendar.component(.weekday, from: target)) { return false }
        switch rule.frequency {
        case .daily:
            return (calendar.dateComponents([.day], from: start, to: target).day ?? -1) % rule.interval == 0
        case .weekly:
            let startWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? start
            let targetWeek = calendar.dateInterval(of: .weekOfYear, for: target)?.start ?? target
            let weeks = (calendar.dateComponents([.day], from: startWeek, to: targetWeek).day ?? -7) / 7
            let allowed = rule.weekdays.isEmpty ? Set([calendar.component(.weekday, from: start)]) : rule.weekdays
            return weeks % rule.interval == 0 && allowed.contains(calendar.component(.weekday, from: target))
        case .monthly:
            let startParts = calendar.dateComponents([.year, .month], from: start)
            let targetParts = calendar.dateComponents([.year, .month], from: target)
            let months = (targetParts.year ?? 0) * 12 + (targetParts.month ?? 0) - ((startParts.year ?? 0) * 12 + (startParts.month ?? 0))
            guard months % rule.interval == 0 else { return false }
            let anchorDay = calendar.component(.day, from: start)
            let lastDay = calendar.range(of: .day, in: .month, for: target)?.count ?? anchorDay
            return calendar.component(.day, from: target) == min(anchorDay, lastDay)
        case .yearly:
            let years = calendar.component(.year, from: target) - calendar.component(.year, from: start)
            return years % rule.interval == 0 && calendar.component(.month, from: target) == calendar.component(.month, from: start)
                && calendar.component(.day, from: target) == min(calendar.component(.day, from: start), calendar.range(of: .day, in: .month, for: target)?.count ?? 31)
        }
    }

    func occurrenceDate(anchor: Date, on day: Date) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: anchor)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }

    func nextOccurrence(anchor: Date, rule: RecurrenceRule, after reference: Date) -> Date? {
        var day = calendar.startOfDay(for: max(anchor, reference))
        for _ in 0..<3660 {
            if occurs(anchor: anchor, rule: rule, on: day) {
                let candidate = occurrenceDate(anchor: anchor, on: day)
                if candidate >= reference { return candidate }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }; day = next
        }
        return nil
    }
}
