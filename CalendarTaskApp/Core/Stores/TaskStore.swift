import Foundation
import Combine

@MainActor final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var errorMessage: String?
    private let repository: any TaskRepository
    private let notificationService: any NotificationService
    private let widgetRefreshService: any WidgetRefreshService
    init(repository: any TaskRepository, notificationService: any NotificationService = NoopNotificationService(), widgetRefreshService: any WidgetRefreshService = NoopWidgetRefreshService()) {
        self.repository = repository; self.notificationService = notificationService; self.widgetRefreshService = widgetRefreshService
    }
    func load() async {
        do { tasks = try await repository.fetchTasks(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func add(_ task: TaskItem) async -> Bool {
        do { try await repository.addTask(task); await notificationService.sync(task: task); widgetRefreshService.reloadTodayWidgets(); await load(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func update(_ task: TaskItem) async -> Bool {
        do { try await repository.updateTask(task); await notificationService.sync(task: task); widgetRefreshService.reloadTodayWidgets(); await load(); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    func delete(id: UUID) async {
        do { try await repository.deleteTask(id: id); await notificationService.removeTaskNotification(id: id); widgetRefreshService.reloadTodayWidgets(); await load() }
        catch { errorMessage = error.localizedDescription }
    }

    func moveToToday(_ task: TaskItem, calendar: Calendar = .current, now: Date = .now) async {
        guard task.recurrenceRule == nil else { return }
        await reschedule(task, to: now, calendar: calendar)
    }

    func moveToTomorrow(_ task: TaskItem, calendar: Calendar = .current, now: Date = .now) async {
        guard task.recurrenceRule == nil,
              let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) else { return }
        await reschedule(task, to: tomorrow, calendar: calendar)
    }

    func reschedule(_ task: TaskItem, to day: Date, calendar: Calendar = .current) async {
        guard task.recurrenceRule == nil else { return }
        var value = task
        let oldReference = task.dueDate ?? task.startDate
        value.startDate = task.startDate.map { calendar.replacingDate(of: $0, with: day) }
        value.dueDate = task.dueDate.map { calendar.replacingDate(of: $0, with: day) }
        if value.startDate == nil && value.dueDate == nil {
            let moved = calendar.replacingDate(of: day, with: day)
            value.startDate = moved; value.dueDate = moved
        }
        if let reminder = task.reminderDate, let oldReference,
           let newReference = value.dueDate ?? value.startDate {
            value.reminderDate = reminder.addingTimeInterval(newReference.timeIntervalSince(oldReference))
        }
        value.updatedAt = .now
        await update(value)
    }

    func duplicate(_ task: TaskItem) async {
        let now = Date.now
        let copy = TaskItem(id: UUID(), title: task.title, note: task.note, startDate: task.startDate, dueDate: task.dueDate,
                            isAllDay: task.isAllDay, isCompleted: false, completedAt: nil, priority: task.priority,
                            reminderDate: nil, recurrenceRule: task.recurrenceRule, projectID: task.projectID,
                            category: task.category, tags: task.tags, createdAt: now, updatedAt: now)
        _ = await add(copy)
    }
}
