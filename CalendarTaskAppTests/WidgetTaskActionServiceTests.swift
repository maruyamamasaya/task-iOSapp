import XCTest
import SwiftData
import DotLocalBridge
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

@MainActor final class DotWidgetDataTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 21))! }
    private func task(_ title: String, date: Date?) -> TaskItem {
        TaskItem(id: UUID(), title: title, note: "", startDate: nil, dueDate: date,
                 isAllDay: true, isCompleted: false, completedAt: nil, priority: .normal,
                 reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil,
                 tags: [], createdAt: today, updatedAt: today)
    }
    func testOnlyIncompleteDotTasksForTodayAndNativeEventsAreDisplayed() throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let context = ModelContext(persistence.container)
        context.insert(TaskEntity(task("native must not appear", date: today)))
        let event = CalendarEvent(id: UUID(), title: "予定", note: "", startDate: today,
            endDate: today.addingTimeInterval(3600), isAllDay: false, reminderDate: nil,
            recurrenceRule: nil, projectID: nil, category: nil, externalEventID: nil,
            createdAt: today, updatedAt: today)
        context.insert(CalendarEventEntity(event)); try context.save()
        let dot = DotWidgetTask(id: UUID(), title: "Dot", date: today, isAllDay: true, isCompleted: false)
        let rows = [dot,
            DotWidgetTask(id: UUID(), title: "done", date: today, isAllDay: true, isCompleted: true),
            DotWidgetTask(id: UUID(), title: "tomorrow", date: today.addingTimeInterval(86400), isAllDay: true, isCompleted: false),
            DotWidgetTask(id: UUID(), title: "undated", date: nil, isAllDay: true, isCompleted: false)]
        let provider = WidgetDataProvider(container: persistence.container, calendar: calendar, dotTasks: { rows })
        let snapshot = provider.today(now: today.addingTimeInterval(600))
        XCTAssertEqual(snapshot.tasks.map(\.id), [dot.id])
        XCTAssertEqual(snapshot.events.map(\.id), [event.id])
        XCTAssertNil(snapshot.tasks.first?.taskID, "Dot must never invoke native SwiftData completion")
        XCTAssertNil(snapshot.tasks.first?.occurrenceDate)
    }
    func testMissingOrCorruptCacheDoesNotFallBackToNativeTasks() throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let context = ModelContext(persistence.container)
        context.insert(TaskEntity(task("native", date: today))); try context.save()
        let empty = WidgetDataProvider(container: persistence.container, calendar: calendar, dotTasks: { [] })
        XCTAssertTrue(empty.today(now: today).tasks.isEmpty)
        let failed = WidgetDataProvider(container: persistence.container, calendar: calendar,
                                       dotTasks: { throw CocoaError(.coderReadCorrupt) })
        XCTAssertTrue(failed.today(now: today).tasks.isEmpty)
    }
    func testSharedProjectionSurvivesRestartAndEmptyUpdateClearsOldRows() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DotWidgetTaskCache(url: directory.appendingPathComponent("widget.json"))
        XCTAssertTrue(try cache.load().isEmpty)
        let row = task("Dot", date: today)
        XCTAssertTrue(try cache.save([row]))
        XCTAssertFalse(try cache.save([row]))
        let reopened = DotWidgetTaskCache(url: cache.url)
        XCTAssertEqual(try reopened.load().map(\.id), [row.id])
        XCTAssertTrue(try reopened.save([]))
        XCTAssertTrue(try cache.load().isEmpty)
        try Data("broken".utf8).write(to: cache.url)
        XCTAssertThrowsError(try reopened.load())
    }
}

extension DotWidgetDataTests {
    func testTimelineKeepsMidnightsAcrossDSTAndCalendarRollover() {
        let cases: [(String, Int, Int, Int, TimeInterval)] = [
            ("America/Los_Angeles",2026,3,8,23*3600),
            ("America/Los_Angeles",2026,11,1,25*3600),
            ("Asia/Tokyo",2026,12,31,24*3600),
            ("Asia/Tokyo",2028,2,29,24*3600)]
        for (zone,year,month,day,hours) in cases {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: zone)!
            let start = calendar.date(from: DateComponents(year: year, month: month, day: day))!
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
            let horizon = calendar.date(byAdding: .day, value: 2, to: start)!
            let provider = WidgetDataProvider(container: SwiftDataPersistence(inMemory: true).container, calendar: calendar, dotTasks: { [] })
            let now = start.addingTimeInterval(600), dates = provider.timelineDates(now: start.addingTimeInterval(600))
            XCTAssertEqual(dates, [now, tomorrow, horizon])
            XCTAssertEqual(tomorrow.timeIntervalSince(start), hours)
        }
    }
    func testDenseTimelinePreservesCalendarBoundariesAndNextDaySnapshot() {
        let persistence = SwiftDataPersistence(inMemory: true)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let horizon = calendar.date(byAdding: .day, value: 2, to: today)!
        let rows = (0..<100).map { index in
            DotWidgetTask(id: UUID(), title: "synthetic", date: today.addingTimeInterval(Double(index + 1) * 600), isAllDay: false, isCompleted: false)
        } + [DotWidgetTask(id: UUID(), title: "tomorrow", date: tomorrow, isAllDay: true, isCompleted: false)]
        let provider = WidgetDataProvider(container: persistence.container, calendar: calendar, dotTasks: { rows })
        let dates = provider.timelineDates(now: today)
        XCTAssertLessThanOrEqual(dates.count, 64)
        XCTAssertEqual(dates, Array(Set(dates)).sorted())
        XCTAssertTrue(dates.contains(tomorrow)); XCTAssertEqual(dates.last, horizon)
        XCTAssertEqual(provider.today(now: tomorrow).tasks.map(\.title), ["tomorrow"])
    }
    func testEventStartAndEndArePrecomputed() throws {
        let persistence = SwiftDataPersistence(inMemory: true)
        let context = ModelContext(persistence.container)
        let start = today.addingTimeInterval(9*3600), end = today.addingTimeInterval(10*3600)
        context.insert(CalendarEventEntity(CalendarEvent(id: UUID(), title: "synthetic", note: "", startDate: start, endDate: end, isAllDay: false, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, externalEventID: nil, createdAt: today, updatedAt: today)))
        try context.save()
        let provider = WidgetDataProvider(container: persistence.container, calendar: calendar, dotTasks: { [] })
        let dates = provider.timelineDates(now: today.addingTimeInterval(8*3600))
        XCTAssertTrue(dates.contains(start)); XCTAssertTrue(dates.contains(end))
    }
    func testAllDayProjectionPreservesCalendarDateWhenTimezoneChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = DotWidgetTaskCache(url: directory.appendingPathComponent("widget.json"))
        let row = task("synthetic", date: today)
        try cache.save([row], calendar: calendar)
        var honolulu = Calendar(identifier: .gregorian); honolulu.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        let localToday = honolulu.date(from: DateComponents(year:2026, month:10, day:21, hour:12))!
        let provider = WidgetDataProvider(container: SwiftDataPersistence(inMemory: true).container, calendar: honolulu, dotTasks: { try cache.load() })
        XCTAssertEqual(provider.today(now: localToday).tasks.map(\.id), [row.id])
        var completed = row; completed.isCompleted = true
        try cache.save([completed], calendar: calendar)
        XCTAssertTrue(provider.today(now: localToday).tasks.isEmpty)
        try cache.save([row], calendar: calendar)
        XCTAssertEqual(provider.today(now: localToday).tasks.map(\.id), [row.id])
    }
}

private actor WidgetProjectionNotes: DailyNoteRepository {
    func fetchNote(for date: Date) async throws -> DailyNote? { nil }
    func saveNote(_ note: DailyNote) async throws {}
    func deleteNote(id: UUID) async throws {}
}
private actor WidgetProjectionCompletions: TaskCompletionRepository {
    func fetchCompletions() async throws -> [TaskCompletion] { [] }
    func addCompletion(_ completion: TaskCompletion) async throws {}
    func deleteCompletion(id: UUID) async throws {}
    func deleteCompletions(taskID: UUID) async throws {}
}
private actor WidgetProjectionProjects: ProjectRepository, TagRepository {
    func fetchProjects() async throws -> [Project] { [] }
    func addProject(_ project: Project) async throws {}
    func updateProject(_ project: Project) async throws {}
    func archiveProject(id: UUID, archived: Bool) async throws {}
    func deleteProject(id: UUID) async throws {}
    func fetchTags() async throws -> [AppTag] { [] }
    func saveTag(_ tag: AppTag) async throws {}
    func deleteTag(id: UUID) async throws {}
}
private final class WidgetProjectionRefresh: WidgetRefreshService, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func reloadTodayWidgets() { lock.lock(); count += 1; lock.unlock() }
    var reloads: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@MainActor final class WidgetProjectionIntegrationTests: XCTestCase {
    func testDurableRelayChangesPublishPlannerAndWidgetBeforeAnyMacAcknowledgment() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let relay = try LocalBridgeStore(file: directory.appendingPathComponent("relay.json"), bridgeID: "fixture")
        let row = WireTask(id: "synthetic", title: "synthetic", date: "2026-10-21", dateLabel: "", status: "", details: "", category: "", completed: false, revision: 1)
        try await relay.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let shared = DotWidgetTaskCache(url: directory.appendingPathComponent("widget.json"))
        let refresh = WidgetProjectionRefresh(), projects = WidgetProjectionProjects()
        let dependencies = AppDependencies(modelContainer: SwiftDataPersistence(inMemory: true).container,
            taskRepository: InMemoryTaskRepository(tasks: []), calendarRepository: InMemoryCalendarRepository(events: []),
            dailyNoteRepository: WidgetProjectionNotes(), taskCompletionRepository: WidgetProjectionCompletions(),
            projectRepository: projects, tagRepository: projects, dateProvider: FixedDateProvider(now: .now),
            widgetRefreshService: refresh, dotWidgetCache: shared, dotRelayCache: DotRelayTaskCache(store: relay))
        await dependencies.plannerTaskStore.load()
        _ = try await relay.queueCompletion(slug: row.id, completed: true)
        for _ in 0..<100 {
            if dependencies.plannerTaskStore.tasks.first?.isCompleted == true,
               (try? shared.load().first?.isCompleted) == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(dependencies.plannerTaskStore.tasks.first?.isCompleted, true)
        XCTAssertEqual(try shared.load().first?.isCompleted, true)
        _ = try await relay.queueCompletion(slug: row.id, completed: false)
        for _ in 0..<100 {
            if dependencies.plannerTaskStore.tasks.first?.isCompleted == false,
               (try? shared.load().first?.isCompleted) == false { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(dependencies.plannerTaskStore.tasks.first?.isCompleted, false)
        XCTAssertEqual(try shared.load().first?.isCompleted, false)
        XCTAssertGreaterThan(refresh.reloads, 0)
        let snapshot = await relay.snapshot
        XCTAssertTrue(snapshot.outbox.isEmpty)
    }
}

private actor RelayMetadataNotifications: NotificationService {
    private(set) var tasks: [TaskItem] = []
    private(set) var removed: [UUID] = []
    func authorizationStatus() async -> NotificationPermissionStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func sync(task: TaskItem) async { tasks.append(task) }
    func sync(event: CalendarEvent) async {}
    func removeTaskNotification(id: UUID) async { removed.append(id) }
    func removeEventNotification(id: UUID) async {}
    func removeTaskOccurrenceNotification(taskID: UUID, occurrenceDate: Date) async {}
}

@MainActor final class RelayMetadataIntegrationTests: XCTestCase {
    func testMacMetadataPublishesCatalogsAndReschedulesNotifications() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let relay = try LocalBridgeStore(file: directory.appendingPathComponent("relay.json"), bridgeID: "fixture")
        let project = WireReference(id: UUID(), name: "仕事"), tag = WireReference(id: UUID(), name: "請求")
        var row = WireTask(id: "synthetic", title: "請求書", date: "2026-10-23", dateLabel: "10月23日", status: "todo", details: "", category: "仕事", completed: false, revision: 1,
                           project: project, tags: [tag], reminderAt: "2026-10-23T09:00:00+09:00")
        try await relay.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let catalogs = WidgetProjectionProjects(), notifications = RelayMetadataNotifications()
        let cache = DotRelayTaskCache(store: relay)
        let dependencies = AppDependencies(modelContainer: SwiftDataPersistence(inMemory: true).container,
            taskRepository: InMemoryTaskRepository(tasks: []), calendarRepository: InMemoryCalendarRepository(events: []),
            dailyNoteRepository: WidgetProjectionNotes(), taskCompletionRepository: WidgetProjectionCompletions(),
            projectRepository: catalogs, tagRepository: catalogs, dateProvider: FixedDateProvider(now: .now),
            notificationService: notifications, dotRelayCache: cache)
        for _ in 0..<100 {
            if await notifications.tasks.last?.reminderDate == row.reminderDate { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(dependencies.projectStore.project(id: project.id)?.name, "仕事")
        XCTAssertEqual(dependencies.tagStore.tags, [AppTag(id: tag.id, name: tag.name)])
        let task = try XCTUnwrap(dependencies.plannerTaskStore.tasks.first)
        XCTAssertEqual(task.projectID, project.id)
        XCTAssertEqual(task.tags.first?.id, tag.id)
        XCTAssertEqual(task.reminderDate, row.reminderDate)
        var nativeCopy = task
        nativeCopy = TaskItem(id: UUID(), title: "native", note: "", startDate: nil, dueDate: nil, isAllDay: true,
                              isCompleted: false, completedAt: nil, priority: .normal, reminderDate: nil,
                              recurrenceRule: nil, projectID: project.id, category: nil, tags: task.tags,
                              createdAt: .now, updatedAt: .now)
        let nativeSaved = await dependencies.taskStore.add(nativeCopy)
        XCTAssertFalse(nativeSaved)
        // Device edits cannot mutate Mac-owned definitions.
        await dependencies.projectStore.delete(id: project.id)
        XCTAssertNotNil(dependencies.projectStore.errorMessage)
        await dependencies.tagStore.delete(id: tag.id)
        XCTAssertNotNil(dependencies.tagStore.errorMessage)
        _ = try await relay.queueCompletion(slug: row.id, completed: true)
        for _ in 0..<100 {
            if await notifications.tasks.last?.isCompleted == true { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let completed = await notifications.tasks.last
        XCTAssertEqual(completed?.isCompleted, true)
        _ = try await relay.queueCompletion(slug: row.id, completed: false)
        for _ in 0..<100 {
            if await notifications.tasks.last?.isCompleted == false { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let undone = await notifications.tasks.last
        XCTAssertEqual(undone?.reminderDate, row.reminderDate)
        XCTAssertEqual(undone?.isCompleted, false)
        row.revision = 2; row.project = nil; row.tags = []; row.reminderAt = nil
        try await relay.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        for _ in 0..<100 {
            if await notifications.tasks.last?.reminderDate == nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let cleared = await notifications.tasks.last
        XCTAssertEqual(cleared?.id, task.id)
        XCTAssertNil(cleared?.reminderDate)
        XCTAssertNil(cleared?.projectID)
        XCTAssertEqual(cleared?.tags, [])
    }
}
