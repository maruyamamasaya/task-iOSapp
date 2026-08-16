import XCTest
@testable import CalendarTaskApp

@MainActor final class SettingsStoreTests: XCTestCase {
    private var suiteName: String { "SettingsStoreTests.\(UUID().uuidString)" }

    func testSafeDefaultsAndInitialRoute() {
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.initialTab, .today)
        XCTAssertEqual(AppRootView.route(for: store.initialTab), .today)
        XCTAssertEqual(store.weekStartDay, .monday)
        XCTAssertEqual(store.initialCalendarMode, .month)
        XCTAssertEqual(store.defaultTaskPriority, .normal)
        XCTAssertEqual(store.appearance, .system)
    }

    func testSettingsPersistAndReload() {
        let name = suiteName, defaults = UserDefaults(suiteName: name)!
        var store = SettingsStore(defaults: defaults)
        store.initialTab = .tasks; store.weekStartDay = .sunday; store.appearance = .dark
        store.defaultTaskPriority = .high; store.defaultEventDurationMinutes = 90
        store = SettingsStore(defaults: defaults)
        XCTAssertEqual(store.initialTab, .tasks); XCTAssertEqual(AppRootView.route(for: store.initialTab), .tasks)
        XCTAssertEqual(store.weekStartDay, .sunday); XCTAssertEqual(store.appearance, .dark)
        XCTAssertEqual(store.defaultTaskPriority, .high); XCTAssertEqual(store.defaultEventDurationMinutes, 90)
        defaults.removePersistentDomain(forName: name)
    }

    func testTaskAndEventCreationDefaults() throws {
        let store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        store.defaultTaskPriority = .low; store.newTasksAreAllDay = false; store.defaultReminder = .thirtyMinutes
        store.defaultEventStartHour = 10; store.defaultEventDurationMinutes = 60
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 18)))
        let task = store.taskCreationDefaults(referenceDate: reference)
        XCTAssertEqual(task.priority, .low); XCTAssertFalse(task.isAllDay)
        XCTAssertEqual(task.reminderDate, reference.addingTimeInterval(-1800))
        let event = store.eventCreationDefaults(referenceDate: reference, calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: event.startDate), 10)
        XCTAssertEqual(event.endDate.timeIntervalSince(event.startDate), 3600)
    }

    func testHapticOffDoesNotEmitFeedback() {
        var count = 0
        let service = SystemHapticService(isEnabled: { false }, completionFeedback: { count += 1 }, actionFeedback: { count += 1 }, deletionFeedback: { count += 1 })
        service.completion(); service.action(); service.deletion()
        XCTAssertEqual(count, 0)
    }
}
