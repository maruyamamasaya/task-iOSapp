import Foundation
import Combine

@MainActor final class TaskCompletionStore: ObservableObject {
    @Published private(set) var completions: [TaskCompletion] = []
    private let repository: any TaskCompletionRepository
    private let notificationService: any NotificationService
    private let calendar: Calendar
    private let widgetRefreshService: any WidgetRefreshService
    init(repository: any TaskCompletionRepository, notificationService: any NotificationService = NoopNotificationService(), widgetRefreshService: any WidgetRefreshService = NoopWidgetRefreshService(), calendar: Calendar = .current) {
        self.repository = repository; self.notificationService = notificationService; self.widgetRefreshService = widgetRefreshService; self.calendar = calendar
    }
    func load() async { completions = (try? await repository.fetchCompletions()) ?? [] }
    func isCompleted(taskID: UUID, on date: Date) -> Bool {
        completions.contains { $0.taskID == taskID && calendar.isDate($0.occurrenceDate, inSameDayAs: date) }
    }
    func toggle(task: TaskItem, on date: Date) async {
        if let value = completions.first(where: { $0.taskID == task.id && calendar.isDate($0.occurrenceDate, inSameDayAs: date) }) {
            try? await repository.deleteCompletion(id: value.id)
            await notificationService.sync(task: task)
        } else {
            let value = TaskCompletion(id: UUID(), taskID: task.id, occurrenceDate: calendar.startOfDay(for: date), completedAt: .now)
            try? await repository.addCompletion(value)
            await notificationService.removeTaskOccurrenceNotification(taskID: task.id, occurrenceDate: date)
        }
        await load()
        widgetRefreshService.reloadTodayWidgets()
    }
    func deleteAll(taskID: UUID) async { try? await repository.deleteCompletions(taskID: taskID); await load(); widgetRefreshService.reloadTodayWidgets() }
}
