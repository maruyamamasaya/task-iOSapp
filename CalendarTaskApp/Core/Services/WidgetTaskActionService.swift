import Foundation
import SwiftData

@MainActor final class WidgetTaskActionService {
    private let container: ModelContainer
    private let notificationService: any NotificationService
    private let calendar: Calendar

    init(container: ModelContainer = SwiftDataPersistence.shared.container,
         notificationService: any NotificationService = UserNotificationService(),
         calendar: Calendar = .current) {
        self.container = container; self.notificationService = notificationService; self.calendar = calendar
    }

    @discardableResult
    func toggle(taskID: UUID, occurrenceDate: Date, now: Date = .now) async -> Bool {
        let context = ModelContext(container)
        do {
            var descriptor = FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.id == taskID })
            descriptor.fetchLimit = 1
            guard let entity = try context.fetch(descriptor).first else { return false }
            var task = entity.domain
            if task.recurrenceRule != nil {
                let completions = try context.fetch(FetchDescriptor<TaskCompletionEntity>(predicate: #Predicate { $0.taskID == taskID }))
                if let existing = completions.first(where: { calendar.isDate($0.occurrenceDate, inSameDayAs: occurrenceDate) }) {
                    context.delete(existing)
                    try context.save()
                    await notificationService.sync(task: task)
                } else {
                    context.insert(TaskCompletionEntity(TaskCompletion(id: UUID(), taskID: taskID,
                                                                       occurrenceDate: calendar.startOfDay(for: occurrenceDate), completedAt: now)))
                    try context.save()
                    await notificationService.removeTaskOccurrenceNotification(taskID: taskID, occurrenceDate: occurrenceDate)
                }
            } else {
                task.isCompleted.toggle(); task.completedAt = task.isCompleted ? now : nil; task.updatedAt = now
                entity.update(from: task); try context.save()
                await notificationService.sync(task: task)
            }
            return true
        } catch {
            return false
        }
    }
}
