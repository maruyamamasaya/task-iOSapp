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

    init(event: CalendarEvent) {
        id = event.id; date = event.startDate; title = event.title; note = event.note
        isCompleted = false; source = .event(event)
    }

    init(task: TaskItem) {
        id = task.id; date = task.dueDate ?? task.startDate ?? task.createdAt
        title = task.title; note = task.note; isCompleted = task.isCompleted; source = .task(task)
    }
}
