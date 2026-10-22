import Foundation

struct DailyTimelineItem: Identifiable, Hashable {
    enum Source: Hashable {
        case event(CalendarEvent)
        case task(TaskItem)
    }

    let id: UUID
    let date: Date
    let title: String
    let note: String
    let isCompleted: Bool
    let source: Source

    static func isWithinDisplayHours(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date),
              let end = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: date) else { return false }
        return (start...end).contains(date)
    }

    init(event: CalendarEvent) {
        id = event.id; date = event.startDate; title = event.title; note = event.note
        isCompleted = false; source = .event(event)
    }

    init(task: TaskItem) {
        id = task.id; date = task.dueDate ?? task.startDate ?? task.createdAt
        title = task.title; note = task.note; isCompleted = task.isCompleted; source = .task(task)
    }
}
