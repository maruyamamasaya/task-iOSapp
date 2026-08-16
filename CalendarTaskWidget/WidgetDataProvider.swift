import Foundation
import SwiftData

struct WidgetDisplayItem: Identifiable, Hashable {
    enum Kind: Hashable { case event, task }
    let id: UUID
    let kind: Kind
    let title: String
    let date: Date
    let isAllDay: Bool
    let taskID: UUID?
    let isRecurring: Bool
    let occurrenceDate: Date?
    let isCompleted: Bool
    let projectColor: ProjectColor?
}

struct WidgetTodaySnapshot: Hashable {
    let date: Date
    let events: [WidgetDisplayItem]
    let tasks: [WidgetDisplayItem]
    static func placeholder(date: Date = .now) -> Self {
        let calendar = Calendar.current
        return Self(date: date,
                    events: [WidgetDisplayItem(id: UUID(), kind: .event, title: "打ち合わせ", date: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date, isAllDay: false, taskID: nil, isRecurring: false, occurrenceDate: nil, isCompleted: false, projectColor: .blue)],
                    tasks: [WidgetDisplayItem(id: UUID(), kind: .task, title: "資料を確認", date: calendar.date(bySettingHour: 11, minute: 0, second: 0, of: date) ?? date, isAllDay: false, taskID: UUID(), isRecurring: false, occurrenceDate: date, isCompleted: false, projectColor: .orange)])
    }
}

@MainActor final class WidgetDataProvider {
    private let container: ModelContainer
    private let calendar: Calendar
    private let recurrence: RecurrenceCalculator

    init(container: ModelContainer = SwiftDataPersistence.shared.container, calendar: Calendar = .current) {
        self.container = container; self.calendar = calendar; recurrence = RecurrenceCalculator(calendar: calendar)
    }

    func today(now: Date = .now) -> WidgetTodaySnapshot {
        let context = ModelContext(container)
        do {
            let tasks = try context.fetch(FetchDescriptor<TaskEntity>()).map(\.domain)
            let events = try context.fetch(FetchDescriptor<CalendarEventEntity>()).map(\.domain)
            let completions = try context.fetch(FetchDescriptor<TaskCompletionEntity>()).map(\.domain)
            let projects = try context.fetch(FetchDescriptor<ProjectEntity>()).map(\.domain)
            let colors = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.colorIdentifier) })
            let taskItems = tasks.compactMap { task -> WidgetDisplayItem? in
                guard let anchor = task.dueDate ?? task.startDate,
                      recurrence.occurs(anchor: anchor, rule: task.recurrenceRule, on: now) else { return nil }
                let occurrenceCompleted = task.recurrenceRule != nil && completions.contains {
                    $0.taskID == task.id && calendar.isDate($0.occurrenceDate, inSameDayAs: now)
                }
                guard !task.isCompleted && !occurrenceCompleted else { return nil }
                let date = recurrence.occurrenceDate(anchor: anchor, on: now)
                return WidgetDisplayItem(id: task.id, kind: .task, title: task.title, date: date, isAllDay: task.isAllDay,
                                         taskID: task.id, isRecurring: task.recurrenceRule != nil, occurrenceDate: now, isCompleted: false,
                                         projectColor: task.projectID.flatMap { colors[$0] })
            }.sorted { $0.date < $1.date }
            let eventItems = events.compactMap { event -> WidgetDisplayItem? in
                if let rule = event.recurrenceRule {
                    guard recurrence.occurs(anchor: event.startDate, rule: rule, on: now) else { return nil }
                    return WidgetDisplayItem(id: event.id, kind: .event, title: event.title,
                                             date: recurrence.occurrenceDate(anchor: event.startDate, on: now), isAllDay: event.isAllDay,
                                             taskID: nil, isRecurring: true, occurrenceDate: now, isCompleted: false,
                                             projectColor: event.projectID.flatMap { colors[$0] })
                }
                let day = calendar.dayInterval(containing: now)
                guard event.startDate < day.end && event.endDate > day.start else { return nil }
                return WidgetDisplayItem(id: event.id, kind: .event, title: event.title, date: event.startDate, isAllDay: event.isAllDay,
                                         taskID: nil, isRecurring: false, occurrenceDate: nil, isCompleted: false,
                                         projectColor: event.projectID.flatMap { colors[$0] })
            }.sorted { $0.date < $1.date }
            return WidgetTodaySnapshot(date: now, events: eventItems, tasks: taskItems)
        } catch {
            return WidgetTodaySnapshot(date: now, events: [], tasks: [])
        }
    }
}
