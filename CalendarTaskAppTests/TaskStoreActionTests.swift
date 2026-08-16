import XCTest
@testable import CalendarTaskApp

@MainActor final class TaskStoreActionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }

    func testMoveToTomorrowPreservesTimeAndReminderOffset() async throws {
        let source = date(2026, 8, 16, 14, 0), reminder = date(2026, 8, 16, 13, 30)
        let task = makeTask(date: source, reminder: reminder)
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: [task]))
        await store.load()
        await store.moveToTomorrow(task, calendar: calendar, now: date(2026, 8, 16, 8, 0))

        let moved = try XCTUnwrap(store.tasks.first)
        XCTAssertEqual(calendar.component(.day, from: moved.dueDate!), 17)
        XCTAssertEqual(calendar.component(.hour, from: moved.dueDate!), 14)
        XCTAssertEqual(calendar.component(.hour, from: moved.reminderDate!), 13)
        XCTAssertEqual(calendar.component(.minute, from: moved.reminderDate!), 30)
    }

    func testDuplicateResetsCompletionAndReminderButKeepsPlanningData() async throws {
        var task = makeTask(date: date(2026, 8, 16, 14, 0), reminder: date(2026, 8, 16, 13, 30))
        task.isCompleted = true; task.completedAt = .now
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: [task]))
        await store.load(); await store.duplicate(task)
        let copy = try XCTUnwrap(store.tasks.first { $0.id != task.id })
        XCTAssertFalse(copy.isCompleted); XCTAssertNil(copy.completedAt); XCTAssertNil(copy.reminderDate)
        XCTAssertEqual(copy.projectID, task.projectID); XCTAssertEqual(copy.priority, task.priority)
    }

    func testRecurringTaskCannotBeRescheduled() async throws {
        var task = makeTask(date: date(2026, 8, 16, 14, 0), reminder: nil)
        task.recurrenceRule = RecurrenceRule(frequency: .daily)
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: [task]))
        await store.load(); await store.moveToTomorrow(task, calendar: calendar, now: task.dueDate!)
        XCTAssertEqual(store.tasks.first?.dueDate, task.dueDate)
        XCTAssertEqual(store.tasks.first?.recurrenceRule, task.recurrenceRule)
    }

    private func makeTask(date: Date, reminder: Date?) -> TaskItem {
        TaskItem(id: UUID(), title: "資料作成", note: "確認", startDate: date, dueDate: date,
                 isAllDay: false, isCompleted: false, completedAt: nil, priority: .high,
                 reminderDate: reminder, recurrenceRule: nil, projectID: UUID(), category: nil,
                 tags: [], createdAt: date, updatedAt: date)
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
