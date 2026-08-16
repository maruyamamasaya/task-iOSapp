import XCTest
import SwiftData
@testable import CalendarTaskApp

private actor WidgetActionNotificationMock: NotificationService {
    private(set) var syncedTasks: [TaskItem] = []
    private(set) var removedOccurrences: [(UUID, Date)] = []
    func authorizationStatus() async -> NotificationPermissionStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func sync(task: TaskItem) async { syncedTasks.append(task) }
    func sync(event: CalendarEvent) async {}
    func removeTaskNotification(id: UUID) async {}
    func removeEventNotification(id: UUID) async {}
    func removeTaskOccurrenceNotification(taskID: UUID, occurrenceDate: Date) async { removedOccurrences.append((taskID, occurrenceDate)) }
    func syncedTaskCount() -> Int { syncedTasks.count }
    func removedOccurrenceCount() -> Int { removedOccurrences.count }
}

final class WidgetTaskActionServiceTests: XCTestCase {
    @MainActor func testNormalTaskCanCompleteAndReturnToIncomplete() async throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let context = ModelContext(persistence.container), notifications = WidgetActionNotificationMock()
        let task = makeTask(recurrence: nil); context.insert(TaskEntity(task)); try context.save()
        let service = WidgetTaskActionService(container: persistence.container, notificationService: notifications)

        let firstToggle = await service.toggle(taskID: task.id, occurrenceDate: task.dueDate!)
        XCTAssertTrue(firstToggle)
        XCTAssertTrue(try fetchTask(task.id, container: persistence.container).isCompleted)
        let secondToggle = await service.toggle(taskID: task.id, occurrenceDate: task.dueDate!)
        XCTAssertTrue(secondToggle)
        XCTAssertFalse(try fetchTask(task.id, container: persistence.container).isCompleted)
        let syncCount = await notifications.syncedTaskCount()
        XCTAssertEqual(syncCount, 2)
    }

    @MainActor func testRecurringTaskCompletesOnlySelectedOccurrence() async throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let context = ModelContext(persistence.container), notifications = WidgetActionNotificationMock()
        let task = makeTask(recurrence: RecurrenceRule(frequency: .daily)); context.insert(TaskEntity(task)); try context.save()
        let selected = task.dueDate!, next = Calendar.current.date(byAdding: .day, value: 1, to: selected)!
        let service = WidgetTaskActionService(container: persistence.container, notificationService: notifications)

        let didToggle = await service.toggle(taskID: task.id, occurrenceDate: selected)
        XCTAssertTrue(didToggle)
        let completions = try ModelContext(persistence.container).fetch(FetchDescriptor<TaskCompletionEntity>()).map(\.domain)
        XCTAssertTrue(completions.contains { Calendar.current.isDate($0.occurrenceDate, inSameDayAs: selected) })
        XCTAssertFalse(completions.contains { Calendar.current.isDate($0.occurrenceDate, inSameDayAs: next) })
        XCTAssertFalse(try fetchTask(task.id, container: persistence.container).isCompleted)
        let removedCount = await notifications.removedOccurrenceCount()
        XCTAssertEqual(removedCount, 1)
    }

    @MainActor private func fetchTask(_ id: UUID, container: ModelContainer) throws -> TaskItem {
        let descriptor = FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.id == id })
        return try XCTUnwrap(ModelContext(container).fetch(descriptor).first?.domain)
    }
    private func makeTask(recurrence: RecurrenceRule?) -> TaskItem {
        let date = Date.now.addingTimeInterval(3600)
        return TaskItem(id: UUID(), title: "Widgetタスク", note: "", startDate: date, dueDate: date,
                        isAllDay: false, isCompleted: false, completedAt: nil, priority: .normal,
                        reminderDate: date, recurrenceRule: recurrence, projectID: nil, category: nil, tags: [], createdAt: .now, updatedAt: .now)
    }
}
