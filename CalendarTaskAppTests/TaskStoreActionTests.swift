import XCTest
import DotLocalBridge
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

    func testTaskDetailSavePreservesHiddenPlanningFields() {
        var task = makeTask(date: date(2026, 8, 16, 14, 0), reminder: nil)
        task.startDate = nil
        task.projectID = UUID()
        task.recurrenceRule = RecurrenceRule(frequency: .daily)
        task.isCompleted = true
        task.completedAt = date(2026, 8, 16, 15, 0)
        let reminder = date(2026, 8, 16, 13, 0)
        let saved = TaskFormView.applyingDetails(to: task, title: "新しい名前", note: "新しい詳細", tags: task.tags,
                                               reminderDate: reminder, now: date(2026, 8, 16, 16, 0))
        XCTAssertEqual(saved.title, "新しい名前")
        XCTAssertEqual(saved.note, "新しい詳細")
        XCTAssertEqual(saved.reminderDate, reminder)
        XCTAssertEqual(saved.startDate, task.startDate)
        XCTAssertEqual(saved.dueDate, task.dueDate)
        XCTAssertEqual(saved.isAllDay, task.isAllDay)
        XCTAssertEqual(saved.recurrenceRule, task.recurrenceRule)
        XCTAssertEqual(saved.projectID, task.projectID)
        XCTAssertEqual(saved.priority, task.priority)
        XCTAssertEqual(saved.isCompleted, task.isCompleted)
        XCTAssertEqual(saved.completedAt, task.completedAt)
    }

    func testTaskDetailSavePreservesRelayMetadata() {
        var task = makeTask(date: date(2026, 8, 16, 14, 0), reminder: .now)
        task.title = "[dot] 元の名前"
        task.note = "dot: task-1\n未送信・端末保存済み\n元の詳細"
        let saved = TaskFormView.applyingDetails(to: task, title: "変更した名前", note: "変更した詳細", tags: task.tags,
                                               reminderDate: nil, now: .now)
        XCTAssertEqual(saved.title, "[dot] 変更した名前")
        XCTAssertEqual(saved.note, "dot: task-1\n未送信・端末保存済み\n変更した詳細")
        XCTAssertNil(saved.reminderDate)
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

final class PlannerTaskPresentationTests: XCTestCase {
    func testRelayMetadataIsQuietButPendingAndConflictRemainVisible() {
        var task = TaskItem(id: UUID(), title: "[dot] 長いタイトルの合成タスク", note: "", startDate: nil,
                            dueDate: nil, isAllDay: true, isCompleted: false, completedAt: nil,
                            priority: .normal, reminderDate: nil, recurrenceRule: nil, projectID: nil,
                            category: nil, tags: [], createdAt: .distantPast, updatedAt: .distantPast)
        for state in ["Mac取得済み（Web完了未照合）", "端末内保存済み（Web完了未照合）", "Macローカル反映済み（Web・dot確認は別）"] {
            task.note = "dot: synthetic-task\n\(state)\n本文\n続き"
            let presentation = PlannerTaskPresentation(task: task)
            XCTAssertEqual(presentation.title, "長いタイトルの合成タスク")
            XCTAssertEqual(presentation.note, "本文\n続き")
            XCTAssertNil(presentation.syncNotice)
        }
        for state in ["未送信・端末保存済み", "Mac受信済み・反映待ち", "競合・変更保持"] {
            task.note = "dot: synthetic-task\n\(state)\n本文"
            XCTAssertNotNil(PlannerTaskPresentation(task: task).syncNotice)
        }
        task.note = "dot: 本人のメモ\n未知の説明\n本文"
        XCTAssertEqual(PlannerTaskPresentation(task: task).note, task.note)
        XCTAssertEqual(PlannerTaskPresentation(task: task).title, task.title)
        task.title = "接頭辞なしのタスク"
        task.note = "dot: synthetic-task\n未送信・端末保存済み\n本文"
        XCTAssertEqual(PlannerTaskPresentation(task: task).title, task.title)
        XCTAssertEqual(PlannerTaskPresentation(task: task).note, "本文")
        XCTAssertNotNil(PlannerTaskPresentation(task: task).syncNotice)
    }
}

private final class UndoTestClock: DateProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ date: Date) { lock.lock(); defer { lock.unlock() }; value = date }
}
private actor UndoTestNotes: DailyNoteRepository {
    func fetchNote(for date: Date) async throws -> DailyNote? { nil }
    func saveNote(_ note: DailyNote) async throws {}
    func deleteNote(id: UUID) async throws {}
}
private actor UndoTestCompletions: TaskCompletionRepository {
    func fetchCompletions() async throws -> [TaskCompletion] { [] }
    func addCompletion(_ completion: TaskCompletion) async throws {}
    func deleteCompletion(id: UUID) async throws {}
    func deleteCompletions(taskID: UUID) async throws {}
}
private actor DelayedUndoTestRepository: TaskRepository {
    let old: TaskItem
    let latest: TaskItem
    private(set) var calls = 0
    var first: CheckedContinuation<[TaskItem], Never>?
    init(old: TaskItem, latest: TaskItem) { self.old = old; self.latest = latest }
    func fetchTasks() async throws -> [TaskItem] {
        calls += 1
        if calls == 1 { return await withCheckedContinuation { first = $0 } }
        return [latest]
    }
    func release() { first?.resume(returning: [old]); first = nil }
    func addTask(_ task: TaskItem) async throws {}
    func updateTask(_ task: TaskItem) async throws {}
    func deleteTask(id: UUID) async throws {}
}

private actor ReorderedUndoTestRepository: TaskRepository {
    var rows: [TaskItem]
    var held: CheckedContinuation<Void, Never>?
    private(set) var heldID: UUID?
    init(rows: [TaskItem]) { self.rows = rows }
    func fetchTasks() async throws -> [TaskItem] { rows.reversed() }
    func addTask(_ task: TaskItem) async throws { rows.append(task) }
    func deleteTask(id: UUID) async throws { rows.removeAll { $0.id == id } }
    func updateTask(_ task: TaskItem) async throws {
        if heldID == nil {
            heldID = task.id
            await withCheckedContinuation { held = $0 }
        }
        if let index = rows.firstIndex(where: { $0.id == task.id }) { rows[index] = task }
    }
    func release() { held?.resume(); held = nil }
}

@MainActor final class HomeCompletionUndoTests: XCTestCase {
    private func task(date: Date) -> TaskItem {
        TaskItem(id: UUID(), title: "synthetic", note: "", startDate: nil, dueDate: date, isAllDay: true,
                 isCompleted: false, completedAt: nil, priority: .normal, reminderDate: nil,
                 recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: date, updatedAt: date)
    }
    private func model(store: TaskStore, clock: UndoTestClock) -> HomeViewModel {
        HomeViewModel(taskStore: store, calendarStore: CalendarStore(repository: InMemoryCalendarRepository(events: [])),
                      dailyNoteStore: DailyNoteStore(repository: UndoTestNotes()),
                      taskCompletionStore: TaskCompletionStore(repository: UndoTestCompletions()),
                      dateProvider: clock, hapticService: SystemHapticService(isEnabled: { false }))
    }
    func testCompletedReviewSurvivesHiddenRowsAndTracksSelectedDay() async {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        var done = task(date: today); done.isCompleted = true
        var otherDay = task(date: tomorrow); otherDay.isCompleted = true
        let pending = task(date: today)
        let suite = "HomeCompletedReview-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, widgetDefaults: defaults)
        settings.showCompletedTasksToday = false
        let home = HomeViewModel(
            taskStore: TaskStore(repository: InMemoryTaskRepository(tasks: [done, otherDay, pending])),
            calendarStore: CalendarStore(repository: InMemoryCalendarRepository(events: [])),
            dailyNoteStore: DailyNoteStore(repository: UndoTestNotes()),
            taskCompletionStore: TaskCompletionStore(repository: UndoTestCompletions()),
            dateProvider: UndoTestClock(today), settingsStore: settings,
            hapticService: SystemHapticService(isEnabled: { false }))
        await home.load()
        XCTAssertEqual(home.completedDayTasks.map(\.id), [done.id])
        XCTAssertEqual(home.pendingUnscheduledTasks.map(\.id), [pending.id])
        await home.toggleCompletion(pending)
        XCTAssertEqual(Set(home.completedDayTasks.map(\.id)), Set([done.id, pending.id]))
        XCTAssertTrue(home.pendingUnscheduledTasks.isEmpty)
        await home.undoLastCompletion(taskID: pending.id)
        XCTAssertEqual(home.completedDayTasks.map(\.id), [done.id])
        XCTAssertEqual(home.pendingUnscheduledTasks.map(\.id), [pending.id])
        await home.moveDay(by: 1)
        XCTAssertEqual(home.completedDayTasks.map(\.id), [otherDay.id])
    }

    func testDailyBriefIncludesHiddenCompletionsAndRemovesRelayStatus() async {
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        var done = task(date: today); done.isCompleted = true
        done.note = "dot: synthetic\n未送信・端末保存済み\n次の一歩"
        var undated = task(date: today); undated.dueDate = nil
        let future = task(date: tomorrow)
        let suite = "DailyBriefContext-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = SettingsStore(defaults: defaults, widgetDefaults: defaults)
        settings.showCompletedTasksToday = false
        let event = CalendarEvent(id: UUID(), title: "終日予定", note: "非送信メモ", startDate: today,
                                  endDate: tomorrow, isAllDay: true, reminderDate: nil, recurrenceRule: nil,
                                  projectID: nil, category: nil, externalEventID: nil, createdAt: today, updatedAt: today)
        let home = HomeViewModel(taskStore: TaskStore(repository: InMemoryTaskRepository(tasks: [done, undated, future])),
            calendarStore: CalendarStore(repository: InMemoryCalendarRepository(events: [event])),
            dailyNoteStore: DailyNoteStore(repository: UndoTestNotes()),
            taskCompletionStore: TaskCompletionStore(repository: UndoTestCompletions()),
            dateProvider: UndoTestClock(today), settingsStore: settings,
            hapticService: SystemHapticService(isEnabled: { false }))
        await home.load()
        let input = home.dailyBriefContext
        XCTAssertEqual(Set(input.tasks.map(\.id)), Set([done.id, undated.id]))
        XCTAssertTrue(input.tasks.first { $0.id == done.id }!.completed)
        XCTAssertEqual(input.tasks.first { $0.id == done.id }!.details, "次の一歩")
        XCTAssertEqual(input.events.map(\.id), [event.id])
        XCTAssertTrue(input.events[0].allDay)
        let encoded = try! input.encodedInput()
        XCTAssertFalse(encoded.contains("非送信メモ"))
        XCTAssertFalse(encoded.contains("未送信"))
        await home.moveDay(by: 1)
        XCTAssertEqual(Set(home.dailyBriefContext.tasks.map(\.id)), Set([future.id, undated.id]))
        XCTAssertTrue(home.dailyBriefContext.events.isEmpty)
    }

    func testCompletionExposesUndoAndRestoresSavedState() async {
        let clock = UndoTestClock(Date()), row = task(date: Date())
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: [row]))
        let home = model(store: store, clock: clock)
        await home.load(); await home.toggleCompletion(row)
        XCTAssertTrue(home.tasks[0].isCompleted)
        XCTAssertEqual(home.completionUndoTask?.id, row.id)
        await home.undoLastCompletion(taskID: home.completionUndoTask!.id)
        XCTAssertFalse(home.tasks[0].isCompleted)
        XCTAssertNil(home.completionUndoTask)
    }
    func testTwoRowsReorderedAndCompletedRowFilteredKeepsUndoUUID() async {
        let first = task(date: Date()), second = task(date: Date())
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: [second, first]))
        let home = model(store: store, clock: UndoTestClock(Date()))
        await home.load()
        let captured = home.tasks.first { $0.id == first.id }!
        await home.toggleCompletion(captured)
        XCTAssertEqual(home.tasks.filter { !$0.isCompleted }.map(\.id), [second.id])
        XCTAssertEqual(home.completionUndoTask?.id, first.id)
        await home.undoLastCompletion(taskID: home.completionUndoTask!.id)
        XCTAssertEqual(Set(home.tasks.filter { !$0.isCompleted }.map(\.id)), Set([first.id, second.id]))
    }
    func testReversedSaveOrderKeepsLatestTappedUndoTarget() async {
        let first = task(date: Date()), second = task(date: Date())
        let repository = ReorderedUndoTestRepository(rows: [first, second])
        let store = TaskStore(repository: repository)
        let home = model(store: store, clock: UndoTestClock(Date()))
        await home.load()
        let slow = Task { await home.toggleCompletion(first) }
        while await repository.heldID == nil { await Task.yield() }
        await home.toggleCompletion(second)
        XCTAssertEqual(home.completionUndoTask?.id, second.id)
        await repository.release(); await slow.value
        XCTAssertEqual(home.completionUndoTask?.id, second.id)
        await home.undoLastCompletion(taskID: home.completionUndoTask!.id)
        XCTAssertEqual(home.tasks.first { $0.id == second.id }?.isCompleted, false)
        XCTAssertEqual(home.tasks.first { $0.id == first.id }?.isCompleted, true)
    }
    func testStaleRenderedUndoCannotCancelNewerTask() async {
        let first = task(date: Date()), second = task(date: Date())
        let store = TaskStore(repository: InMemoryTaskRepository(tasks: [first, second]))
        let home = model(store: store, clock: UndoTestClock(Date()))
        await home.load(); await home.toggleCompletion(first)
        let renderedID = home.completionUndoTask!.id
        await home.toggleCompletion(second)
        // Simulate an already captured button action starting after the banner changed.
        await home.undoLastCompletion(taskID: renderedID)
        XCTAssertTrue(home.tasks.first { $0.id == first.id }!.isCompleted)
        XCTAssertTrue(home.tasks.first { $0.id == second.id }!.isCompleted)
        XCTAssertEqual(home.completionUndoTask?.id, second.id)
    }
    func testMidnightFollowsTodayButDoesNotOverrideManuallySelectedDay() async {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        let clock = UndoTestClock(start.addingTimeInterval(600))
        let home = model(store: TaskStore(repository: InMemoryTaskRepository(tasks: [])), clock: clock)
        clock.set(tomorrow.addingTimeInterval(600))
        await home.refreshDayBoundary()
        XCTAssertTrue(calendar.isDate(home.selectedDate, inSameDayAs: clock.now))
        await home.moveDay(by: -1)
        let selected = home.selectedDate
        clock.set(calendar.date(byAdding: .day, value: 1, to: clock.now)!)
        await home.refreshDayBoundary()
        XCTAssertEqual(home.selectedDate, selected)
    }
    func testDelayedOlderLoadCannotRollBackNewerDisplay() async throws {
        let row = task(date: Date()); var latest = row; latest.isCompleted = true
        let repository = DelayedUndoTestRepository(old: row, latest: latest)
        let store = TaskStore(repository: repository)
        let older = Task { await store.load() }
        for _ in 0..<100 {
            if await repository.calls > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        await store.load(); await repository.release(); await older.value
        XCTAssertEqual(store.tasks, [latest])
    }
}

@MainActor final class RelayCompletionProjectionTests: XCTestCase {
    func testAcknowledgmentMetadataRaceDoesNotRejectUndoOrPermitContentEdits() {
        let date = Date()
        let original = TaskItem(id: UUID(), title: "[dot] synthetic", note: "dot: synthetic\nMacローカル反映済み（Web・dot確認は別）\n本文", startDate: nil, dueDate: date, isAllDay: true, isCompleted: true, completedAt: nil, priority: .normal, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: date, updatedAt: date)
        var undo = original
        undo.isCompleted = false
        undo.note = "dot: synthetic\n未送信・端末保存済み\n本文"
        XCTAssertTrue(DotRelayTaskRepository.isCompletionUpdate(undo, from: original))
        undo.note = "dot: synthetic\n未送信・端末保存済み\n別の本文"
        XCTAssertFalse(DotRelayTaskRepository.isCompletionUpdate(undo, from: original))
        undo.note = "dot: different-task\n未送信・端末保存済み\n本文"
        XCTAssertFalse(DotRelayTaskRepository.isCompletionUpdate(undo, from: original))
        undo.note = original.note; undo.title = "編集した名前"
        XCTAssertFalse(DotRelayTaskRepository.isCompletionUpdate(undo, from: original))
    }
}

private actor WeekProjects: ProjectRepository {
    func fetchProjects() async throws -> [Project] { [] }
    func addProject(_ project: Project) async throws {}
    func updateProject(_ project: Project) async throws {}
    func archiveProject(id: UUID, archived: Bool) async throws {}
    func deleteProject(id: UUID) async throws {}
}
@MainActor final class WeeklyPlannerTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "Asia/Tokyo")!; return c
    }
    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.date(from: DateComponents(year: 2026, month: 10, day: 22))!)!
    }
    private func row(_ title: String, offset: Int?, project: UUID? = nil) -> TaskItem {
        TaskItem(id: UUID(), title: title, note: "次の一歩：範囲を確認", startDate: nil, dueDate: offset.map(day), isAllDay: true,
                 isCompleted: false, completedAt: nil, priority: .normal, reminderDate: nil, recurrenceRule: nil,
                 projectID: project, category: nil, tags: [], createdAt: day(0), updatedAt: day(0))
    }
    private func meta(_ category: String = "work", status: String = "未着手", project: String? = "合成RAG", deadline: String? = nil) -> PlannerTaskMetadata {
        PlannerTaskMetadata(category: category, status: status, projectName: project, scheduleLabel: "10/22 仮枠", deadlineDay: deadline, deadlineTime: deadline == nil ? nil : "17:00", timeZone: "Asia/Tokyo")
    }
    private func model(_ tasks: [TaskItem], metadata: [UUID: PlannerTaskMetadata], cal: Calendar? = nil, now: Date? = nil) -> TaskListViewModel {
        let m = TaskListViewModel(store: TaskStore(repository: InMemoryTaskRepository(tasks: tasks)),
            completionStore: TaskCompletionStore(repository: UndoTestCompletions()), projectStore: ProjectStore(repository: WeekProjects()),
            hapticService: SystemHapticService(isEnabled: { false }), calendar: cal ?? calendar,
            dateProvider: FixedDateProvider(now: now ?? day(0)), metadataSource: { metadata })
        m.selectedSection = .week; return m
    }
    func testKindsStatusesAndGlobalProjectSearchShareRows() async {
        let held = row("合成の検討", offset:nil), active = row("合成の用事", offset:0)
        var done = row("合成の完了", offset:0); done.isCompleted = true
        var heldMeta = meta("other", status:"保留中", project:"合成案件"); heldMeta.taskKind = "idea"
        var activeMeta = meta(status:"進行中"); activeMeta.taskKind = "errand"
        let m = model([held,active,done], metadata:[held.id:heldMeta,active.id:activeMeta,done.id:meta(status:"考え中")])
        await m.load()
        m.selectKind(.idea); XCTAssertEqual(m.visibleTasks.map(\.id), [held.id])
        m.selectStatus(.held); XCTAssertEqual(m.visibleTasks.map(\.id), [held.id])
        m.selectKind(.all); m.selectStatus(.completed)
        XCTAssertEqual(m.visibleTasks.map(\.id), [done.id])
        XCTAssertEqual(m.statusLabel(for:done), "完了")
        XCTAssertEqual(m.kindLabel(for:done), "種別未設定")
        m.area = .work; m.kind = .errand; m.selectedSection = .week
        m.searchText = "合成案件"
        XCTAssertEqual(m.visibleTasks.map(\.id), [held.id])
        m.searchesAllTasks = false; XCTAssertTrue(m.visibleTasks.isEmpty)
        XCTAssertEqual(PlannerStatus.classify("保留",completed:false), .held)
        XCTAssertEqual(PlannerStatus.classify("検討中",completed:false), .thinking)
        XCTAssertEqual(PlannerStatus.classify("回答待ち",completed:false), .other)
        XCTAssertEqual(PlannerStatus.classify("完了",completed:false), .other)
        var inconsistent = heldMeta; inconsistent = PlannerTaskMetadata(category:"other",status:"完了",projectName:nil,scheduleLabel:"",deadlineDay:nil,deadlineTime:nil,timeZone:nil)
        let legacy = model([held],metadata:[held.id:inconsistent]); await legacy.load()
        XCTAssertEqual(legacy.statusLabel(for:held), "未完了（工程: 完了）")
        XCTAssertEqual(PlannerKind.classify(nil), .unspecified)
        XCTAssertEqual(PlannerKind.classify("future-kind"), .unspecified)
    }
    func testSevenDayBoundariesExcludeDeferredCompletedAndMerged() async {
        let first = row("先頭", offset: 0), last = row("末尾", offset: 6), before = row("昨日", offset: -1), after = row("次週", offset: 7)
        let held = row("保留", offset: 0), considering = row("検討", offset: 0), merged = row("【統合済】参照", offset: 0)
        var done = row("完了", offset: 0); done.isCompleted = true
        let deadline = row("期限のみ", offset: nil), unknown = row("情報未取得", offset: 0)
        var metadata = Dictionary(uniqueKeysWithValues: [first,last,before,after,held,considering,merged,done].map { ($0.id,meta()) })
        metadata[held.id] = meta(status: "保留"); metadata[considering.id] = meta(status: "考え中")
        metadata[deadline.id] = meta(deadline: "2026-10-28")
        let m = model([first,last,before,after,held,considering,merged,done,deadline,unknown], metadata: metadata)
        await m.load()
        XCTAssertEqual(Set(m.visibleTasks.map(\.id)), Set([first.id,last.id,deadline.id]))
        m.selectedSection = .all
        XCTAssertEqual(m.visibleTasks.count, 10)
    }
    func testAreaProjectGroupingSearchAndNextStep() async {
        let project = UUID()
        let work = row("仕事", offset: 0, project: project), personal = row("申込", offset: 2, project: UUID()), other = row("確認用", offset: 1)
        let m = model([work,personal,other], metadata: [work.id:meta(),personal.id:meta("private",project:"資格"),other.id:meta("other",project:nil)])
        await m.load(); XCTAssertEqual(m.projectGroups.count, 3)
        XCTAssertEqual(m.nextStep(for: work), "範囲を確認")
        m.area = .personal; XCTAssertEqual(m.visibleTasks.map(\.id), [personal.id])
        m.area = .work; XCTAssertEqual(m.projectGroups.first?.id, project)
        XCTAssertEqual(m.projectGroups.first?.name, "合成RAG")
        m.area = .other; XCTAssertEqual(m.visibleTasks.map(\.id), [other.id])
        m.area = .all; m.searchText = "申込"; XCTAssertEqual(m.visibleTasks.map(\.id), [personal.id])
        m.searchText = "不存在"; XCTAssertTrue(m.projectGroups.isEmpty)
    }
    func testCompletionDisappearsButUndoKeepsCapturedUUID() async {
        let a = row("A", offset: 0), b = row("B", offset: 0)
        let m = model([a,b], metadata: [a.id:meta(),b.id:meta()]); await m.load()
        await m.toggleCompletion(a); XCTAssertFalse(m.visibleTasks.contains { $0.id == a.id })
        await m.toggleCompletion(b)
        await m.undoCompletion(taskID: a.id) // A's stale rendered button cannot undo B.
        XCTAssertEqual(m.completionUndoTask?.id, b.id)
        XCTAssertTrue(m.tasks.first { $0.id == b.id }!.isCompleted)
        await m.undoCompletion(taskID: b.id)
        XCTAssertEqual(m.visibleTasks.map(\.id), [b.id])
    }
    func testDSTAndYearBoundaryUseCalendarDays() async {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let start = c.date(from: DateComponents(year:2026,month:3,day:7))!
        let m = model([],metadata:[:],cal:c,now:start); await m.load()
        XCTAssertEqual(m.weekInterval.duration, 167 * 3600)
        XCTAssertEqual(c.component(.day, from:m.weekInterval.end),14)
        let dec = c.date(from: DateComponents(year:2026,month:12,day:29))!
        let year = model([],metadata:[:],cal:c,now:dec)
        XCTAssertEqual(c.component(.year,from:year.weekInterval.end),2027)
        XCTAssertEqual(c.component(.day,from:year.weekInterval.end),5)
    }
    func testWeekCompletionAndUndoUseDurableRelayOutboxWithoutChangingWireMetadata() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let wire = WireTask(id:"synthetic-week",title:"合成",date:"2026-10-22",dateLabel:"仮",status:"未着手",details:"次の一歩：確認",category:"work",completed:false,revision:1,aiContext:"AI_ONLY")
        let bridge = try LocalBridgeStore(file:folder.appending(path:"state.json"),bridgeID:"fixture")
        try await bridge.merge(BridgeFeed(bridgeID:"fixture",tasks:[wire]))
        let initial = await bridge.snapshot, id = initial.tasks[0].id
        let repository = DotRelayTaskRepository(native:InMemoryTaskRepository(tasks:[]),cache:DotRelayTaskCache(store:bridge))
        let m = TaskListViewModel(store:TaskStore(repository:repository),completionStore:TaskCompletionStore(repository:UndoTestCompletions()),projectStore:ProjectStore(repository:WeekProjects()),hapticService:SystemHapticService(isEnabled:{false}),calendar:calendar,dateProvider:FixedDateProvider(now:day(0)),metadataSource:{[id:self.meta()]})
        m.selectedSection = .week; await m.load(); let task = try XCTUnwrap(m.visibleTasks.first)
        await m.toggleCompletion(task); let queued = await bridge.snapshot
        XCTAssertEqual(queued.outbox.count,1); XCTAssertEqual(queued.outbox[0].operation.taskId,wire.id)
        await m.undoCompletion(taskID:id); let final = await bridge.snapshot
        XCTAssertTrue(final.outbox.isEmpty); XCTAssertEqual(final.tasks,initial.tasks)
        XCTAssertFalse(m.tasks[0].note.contains("AI_ONLY"))
    }
}
