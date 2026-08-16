import Foundation

enum QuickAddItemType: String {
    case task = "タスク"
    case event = "予定"
    case note = "メモ"
}

struct QuickAddResult: Hashable {
    let type: QuickAddItemType
    let title: String
    let date: Date
    let hasExplicitTime: Bool

    func task(now: Date = .now) -> TaskItem {
        TaskItem(id: UUID(), title: title, note: "", startDate: date, dueDate: date,
                 isAllDay: !hasExplicitTime, isCompleted: false, completedAt: nil,
                 priority: .normal, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: now, updatedAt: now)
    }
    func event(calendar: Calendar = .current, now: Date = .now) -> CalendarEvent {
        let end = calendar.date(byAdding: hasExplicitTime ? .hour : .day, value: 1, to: date) ?? date
        return CalendarEvent(id: UUID(), title: title, note: "", startDate: date, endDate: end,
                             isAllDay: !hasExplicitTime, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, externalEventID: nil,
                             createdAt: now, updatedAt: now)
    }
    func note(existing: DailyNote?, now: Date = .now) -> DailyNote {
        DailyNote(id: existing?.id ?? UUID(), date: date, text: title,
                  createdAt: existing?.createdAt ?? now, updatedAt: now)
    }
}

struct QuickAddParser {
    private var calendar: Calendar
    init(calendar: Calendar = .current) { self.calendar = calendar }

    func parse(_ input: String, defaultDate: Date, defaultType: QuickAddItemType = .task) -> QuickAddResult {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let type = extractType(from: &text) ?? defaultType
        let day = extractDate(from: &text, defaultDate: defaultDate)
        let time = extractTime(from: &text)
        var date = calendar.startOfDay(for: day)
        if let time { date = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: date) ?? date }
        let title = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "、,")))
        return QuickAddResult(type: type, title: title.isEmpty ? input.trimmingCharacters(in: .whitespacesAndNewlines) : title,
                              date: date, hasExplicitTime: time != nil)
    }

    private func extractType(from text: inout String) -> QuickAddItemType? {
        let prefixes: [(String, QuickAddItemType)] = [("予定:", .event), ("予定：", .event), ("/event", .event),
                                                       ("タスク:", .task), ("タスク：", .task), ("/task", .task),
                                                       ("メモ:", .note), ("メモ：", .note), ("/note", .note)]
        for (prefix, type) in prefixes where text.lowercased().hasPrefix(prefix.lowercased()) {
            text.removeFirst(prefix.count); text = text.trimmingCharacters(in: .whitespaces); return type
        }
        return nil
    }

    private func extractDate(from text: inout String, defaultDate: Date) -> Date {
        let relative: [(String, Int)] = [("明後日", 2), ("明日", 1), ("今日", 0)]
        for (token, offset) in relative where text.contains(token) {
            text = text.replacingOccurrences(of: token, with: "")
            return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: defaultDate)) ?? defaultDate
        }
        let patterns = [#"(?<!\d)(\d{1,2})/(\d{1,2})(?!\d)"#, #"(\d{1,2})月(\d{1,2})日"#]
        for pattern in patterns {
            if let match = regexMatch(pattern, in: text), match.groups.count == 2,
               let month = Int(match.groups[0]), let day = Int(match.groups[1]) {
                var components = calendar.dateComponents([.year], from: defaultDate)
                components.month = month; components.day = day
                if let value = calendar.date(from: components) {
                    text.removeSubrange(match.range); return value
                }
            }
        }
        return defaultDate
    }

    private func extractTime(from text: inout String) -> (hour: Int, minute: Int)? {
        guard let match = regexMatch(#"(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?!\d)"#, in: text),
              match.groups.count == 2, let hour = Int(match.groups[0]), let minute = Int(match.groups[1]) else { return nil }
        text.removeSubrange(match.range); return (hour, minute)
    }

    private func regexMatch(_ pattern: String, in text: String) -> (range: Range<String.Index>, groups: [String])? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let groups = (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        return (range, groups)
    }
}
