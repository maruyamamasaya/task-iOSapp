import Foundation

enum SampleData {
    static func tasks(now: Date, calendar: Calendar = .current) -> [TaskItem] {
        let work = TaskCategory(id: UUID(), name: "仕事", colorName: "blue")
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return [
            TaskItem(id: UUID(), title: "企画書を確認", note: "コメントをまとめる", startDate: now, dueDate: now, isAllDay: false, isCompleted: false, completedAt: nil, priority: .high, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: work, tags: [], createdAt: now, updatedAt: now),
            TaskItem(id: UUID(), title: "買い物リスト", note: "", startDate: tomorrow, dueDate: tomorrow, isAllDay: true, isCompleted: false, completedAt: nil, priority: .normal, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: now, updatedAt: now),
            TaskItem(id: UUID(), title: "週次レビュー", note: "", startDate: now, dueDate: now, isAllDay: false, isCompleted: true, completedAt: now, priority: .low, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: work, tags: [], createdAt: now, updatedAt: now)
        ]
    }

    static func events(now: Date, calendar: Calendar = .current) -> [CalendarEvent] {
        let end = calendar.date(byAdding: .hour, value: 1, to: now) ?? now
        let multiDay = calendar.date(byAdding: .day, value: 2, to: now) ?? now
        return [
            CalendarEvent(id: UUID(), title: "チームミーティング", note: "", startDate: now, endDate: end, isAllDay: false, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, externalEventID: nil, createdAt: now, updatedAt: now),
            CalendarEvent(id: UUID(), title: "カンファレンス", note: "複数日イベント", startDate: now, endDate: multiDay, isAllDay: true, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, externalEventID: nil, createdAt: now, updatedAt: now)
        ]
    }
}
