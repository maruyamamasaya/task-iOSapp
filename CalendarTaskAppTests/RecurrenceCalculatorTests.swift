import XCTest
@testable import CalendarTaskApp

private actor InMemoryCompletionRepository: TaskCompletionRepository {
    var values: [TaskCompletion] = []
    func fetchCompletions() async throws -> [TaskCompletion] { values }
    func addCompletion(_ completion: TaskCompletion) async throws { values.append(completion) }
    func deleteCompletion(id: UUID) async throws { values.removeAll { $0.id == id } }
    func deleteCompletions(taskID: UUID) async throws { values.removeAll { $0.taskID == taskID } }
}

final class RecurrenceCalculatorTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = TimeZone(identifier: "Asia/Tokyo")!; value.firstWeekday = 2; return value
    }
    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    func testDaily() {
        let calculator = RecurrenceCalculator(calendar: calendar), anchor = date(2026, 8, 16)
        XCTAssertTrue(calculator.occurs(anchor: anchor, rule: RecurrenceRule(frequency: .daily), on: date(2026, 8, 17)))
    }
    func testWeekdaysExcludeWeekend() {
        let calculator = RecurrenceCalculator(calendar: calendar), anchor = date(2026, 8, 14)
        let rule = RecurrenceRule(frequency: .daily, weekdays: Set(2...6))
        XCTAssertFalse(calculator.occurs(anchor: anchor, rule: rule, on: date(2026, 8, 16)))
        XCTAssertTrue(calculator.occurs(anchor: anchor, rule: rule, on: date(2026, 8, 17)))
    }
    func testWeeklyUsesAnchorWeekday() {
        let calculator = RecurrenceCalculator(calendar: calendar), anchor = date(2026, 8, 17)
        XCTAssertTrue(calculator.occurs(anchor: anchor, rule: RecurrenceRule(frequency: .weekly), on: date(2026, 8, 24)))
        XCTAssertFalse(calculator.occurs(anchor: anchor, rule: RecurrenceRule(frequency: .weekly), on: date(2026, 8, 25)))
    }
    func testMonthlyAndMonthEnd() {
        let calculator = RecurrenceCalculator(calendar: calendar), anchor = date(2026, 1, 31)
        let rule = RecurrenceRule(frequency: .monthly)
        XCTAssertTrue(calculator.occurs(anchor: anchor, rule: rule, on: date(2026, 2, 28)))
        XCTAssertTrue(calculator.occurs(anchor: anchor, rule: rule, on: date(2026, 3, 31)))
    }
    func testLeapYearMonthEnd() {
        let calculator = RecurrenceCalculator(calendar: calendar), anchor = date(2028, 1, 31)
        XCTAssertTrue(calculator.occurs(anchor: anchor, rule: RecurrenceRule(frequency: .monthly), on: date(2028, 2, 29)))
    }
    func testTimeZonePreservesLocalTime() {
        let calculator = RecurrenceCalculator(calendar: calendar), anchor = date(2026, 8, 17, 23)
        let occurrence = calculator.occurrenceDate(anchor: anchor, on: date(2026, 8, 18))
        XCTAssertEqual(calendar.component(.hour, from: occurrence), 23)
    }

    @MainActor func testOccurrenceCompletionDoesNotAffectNextDay() async {
        let repository = InMemoryCompletionRepository()
        let store = TaskCompletionStore(repository: repository, calendar: calendar)
        let anchor = date(2026, 8, 17), next = date(2026, 8, 18)
        let task = TaskItem(id: UUID(), title: "習慣", note: "", startDate: anchor, dueDate: anchor,
                            isAllDay: true, isCompleted: false, completedAt: nil, priority: .normal,
                            reminderDate: nil, recurrenceRule: RecurrenceRule(frequency: .daily), projectID: nil, category: nil,
                            tags: [], createdAt: anchor, updatedAt: anchor)
        await store.toggle(task: task, on: anchor)
        XCTAssertTrue(store.isCompleted(taskID: task.id, on: anchor))
        XCTAssertFalse(store.isCompleted(taskID: task.id, on: next))
    }
}
