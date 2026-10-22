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
    private let dotTasks: () throws -> [DotWidgetTask]

    init(container: ModelContainer = SwiftDataPersistence.shared.container, calendar: Calendar = .current,
         dotTasks: @escaping () throws -> [DotWidgetTask] = { try DotWidgetTaskCache.shared()?.load() ?? [] }) {
        self.dotTasks = dotTasks
        self.container = container; self.calendar = calendar; recurrence = RecurrenceCalculator(calendar: calendar)
    }

    // Precompute local calendar-day and event boundaries. No high-frequency polling.
    func timelineDates(now: Date) -> [Date] {
        let start = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: start),
              let horizon = calendar.date(byAdding: .day, value: 2, to: start) else { return [now] }
        var dates: Set<Date> = [now, tomorrow, horizon]
        func add(_ date: Date) { if date > now, date < horizon { dates.insert(date) } }
        let context = ModelContext(container)
        let events = (try? context.fetch(FetchDescriptor<CalendarEventEntity>()).map(\.domain)) ?? []
        for event in events where !event.isAllDay {
            if let rule = event.recurrenceRule {
                for day in [start, tomorrow] where recurrence.occurs(anchor: event.startDate, rule: rule, on: day) {
                    let occurrence = recurrence.occurrenceDate(anchor: event.startDate, on: day)
                    add(occurrence); add(occurrence.addingTimeInterval(event.endDate.timeIntervalSince(event.startDate)))
                }
            } else { add(event.startDate); add(event.endDate) }
        }
        for task in (try? dotTasks()) ?? [] where !task.isAllDay && !task.isCompleted {
            if let date = task.resolvedDate(calendar: calendar) { add(date) }
        }
        let required: Set<Date> = [now, tomorrow, horizon]
        return required.union(dates.subtracting(required).sorted().prefix(61)).sorted()
    }

    func today(now: Date = .now) -> WidgetTodaySnapshot {
        let context = ModelContext(container)
        do {
            let tasks = (try? dotTasks()) ?? []
            let events = try context.fetch(FetchDescriptor<CalendarEventEntity>()).map(\.domain)
            let projects = try context.fetch(FetchDescriptor<ProjectEntity>()).map(\.domain)
            let colors = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.colorIdentifier) })
            let taskItems = tasks.compactMap { task -> WidgetDisplayItem? in
                guard let date = task.resolvedDate(calendar: calendar), calendar.isDate(date, inSameDayAs: now),
                      !task.isCompleted else { return nil }
                // Dot actions must go through the app's relay, never the native SwiftData intent.
                return WidgetDisplayItem(id: task.id, kind: .task, title: task.title, date: date, isAllDay: task.isAllDay,
                                         taskID: nil, isRecurring: false, occurrenceDate: nil, isCompleted: false,
                                         projectColor: nil)
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
