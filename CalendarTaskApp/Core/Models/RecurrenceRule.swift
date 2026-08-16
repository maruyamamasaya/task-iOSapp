import Foundation

struct RecurrenceRule: Codable, Hashable, Sendable {
    enum Frequency: String, Codable, Hashable, Sendable { case daily, weekly, monthly, yearly }
    var frequency: Frequency
    var interval: Int
    var weekdays: Set<Int>
    var endDate: Date?

    init(frequency: Frequency, interval: Int = 1, weekdays: Set<Int> = [], endDate: Date? = nil) {
        self.frequency = frequency; self.interval = max(1, interval); self.weekdays = weekdays; self.endDate = endDate
    }
}

enum RecurrenceOption: String, CaseIterable, Identifiable {
    case none = "なし", daily = "毎日", weekdays = "平日", weekly = "毎週", monthly = "毎月"
    var id: Self { self }
    init(rule: RecurrenceRule?) {
        guard let rule else { self = .none; return }
        if rule.frequency == .daily && rule.weekdays == Set(2...6) { self = .weekdays }
        else { switch rule.frequency { case .daily: self = .daily; case .weekly: self = .weekly; case .monthly: self = .monthly; case .yearly: self = .none } }
    }
    var rule: RecurrenceRule? {
        switch self { case .none: nil; case .daily: RecurrenceRule(frequency: .daily); case .weekdays: RecurrenceRule(frequency: .daily, weekdays: Set(2...6)); case .weekly: RecurrenceRule(frequency: .weekly); case .monthly: RecurrenceRule(frequency: .monthly) }
    }
}
