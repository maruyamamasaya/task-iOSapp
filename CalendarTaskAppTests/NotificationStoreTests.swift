import XCTest
@testable import CalendarTaskApp

private actor MockNotificationService: NotificationService {
    enum Action: Equatable { case syncTask(UUID, Bool), syncEvent(UUID), removeTask(UUID), removeEvent(UUID) }
    private(set) var actions: [Action] = []
    func authorizationStatus() async -> NotificationPermissionStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func sync(task: TaskItem) async { actions.append(.syncTask(task.id, task.isCompleted)) }
    func sync(event: CalendarEvent) async { actions.append(.syncEvent(event.id)) }
    func removeTaskNotification(id: UUID) async { actions.append(.removeTask(id)) }
    func removeEventNotification(id: UUID) async { actions.append(.removeEvent(id)) }
    func removeTaskOccurrenceNotification(taskID: UUID, occurrenceDate: Date) async { actions.append(.removeTask(taskID)) }
}

final class NotificationStoreTests: XCTestCase {
    @MainActor func testTaskAddCompletionAndDeleteSynchronizeNotification() async {
        let notifications = MockNotificationService()
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: []), notificationService: notifications)
        let now = Date.now
        var task = TaskItem(id: UUID(), title: "通知テスト", note: "", startDate: now, dueDate: now,
                            isAllDay: false, isCompleted: false, completedAt: nil, priority: .normal,
                            reminderDate: now.addingTimeInterval(3600), recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: now, updatedAt: now)
        await store.add(task)
        task.isCompleted = true; task.completedAt = now; await store.update(task)
        await store.delete(id: task.id)
        let actions = await notifications.actions
        XCTAssertEqual(actions, [.syncTask(task.id, false), .syncTask(task.id, true), .removeTask(task.id)])
    }

    @MainActor func testEventAddAndDeleteSynchronizeNotification() async {
        let notifications = MockNotificationService()
        let store = CalendarStore(repository: InMemoryCalendarRepository(events: []), notificationService: notifications)
        let now = Date.now
        let event = CalendarEvent(id: UUID(), title: "予定", note: "", startDate: now, endDate: now.addingTimeInterval(3600),
                                  isAllDay: false, reminderDate: now.addingTimeInterval(600), recurrenceRule: nil, projectID: nil, category: nil,
                                  externalEventID: nil, createdAt: now, updatedAt: now)
        await store.add(event); await store.delete(id: event.id)
        let actions = await notifications.actions
        XCTAssertEqual(actions, [.syncEvent(event.id), .removeEvent(event.id)])
    }
}
