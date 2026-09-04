import XCTest
import SwiftData
@testable import CalendarTaskApp

@MainActor final class BackupServiceTests: XCTestCase {
    func testFullRoundTripPreservesModelsRelationshipsAndSettings() async throws {
        let fixture = makeFixture(), now = Date.now, projectID = UUID(), taskID = UUID()
        let project = Project(id: projectID, name: "仕事", colorIdentifier: .orange, iconName: "briefcase", isArchived: false, createdAt: now, updatedAt: now)
        let task = TaskItem(id: taskID, title: "定例準備", note: "資料", startDate: now, dueDate: now,
                            isAllDay: false, isCompleted: false, completedAt: nil, priority: .high,
                            reminderDate: now.addingTimeInterval(1800), recurrenceRule: RecurrenceRule(frequency: .weekly),
                            projectID: projectID, category: nil, tags: [], createdAt: now, updatedAt: now)
        let event = CalendarEvent(id: UUID(), title: "定例", note: "会議", startDate: now, endDate: now.addingTimeInterval(3600),
                                  isAllDay: false, reminderDate: now.addingTimeInterval(-600), recurrenceRule: RecurrenceRule(frequency: .weekly),
                                  projectID: projectID, category: nil, externalEventID: nil, createdAt: now, updatedAt: now)
        let note = DailyNote(id: UUID(), date: now, text: "メモ本文", createdAt: now, updatedAt: now)
        let completion = TaskCompletion(id: UUID(), taskID: taskID, occurrenceDate: now, completedAt: now)
        let context = ModelContext(fixture.persistence.container)
        context.insert(ProjectEntity(project)); context.insert(TaskEntity(task)); context.insert(CalendarEventEntity(event))
        context.insert(DailyNoteEntity(note)); context.insert(TaskCompletionEntity(completion)); try context.save()
        fixture.settings.appearance = .dark; fixture.settings.theme = .linen; fixture.settings.weekStartDay = .sunday; fixture.settings.defaultTaskPriority = .low

        let data = try fixture.service.exportData(now: now)
        let backup = try fixture.service.decodeAndValidate(data)
        fixture.settings.appearance = .light
        try await fixture.service.restoreReplacing(with: backup)

        let restored = ModelContext(fixture.persistence.container)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<TaskEntity>()).first?.domain, task)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<CalendarEventEntity>()).first?.domain, event)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<DailyNoteEntity>()).first?.domain, note)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<ProjectEntity>()).first?.domain, project)
        XCTAssertEqual(try restored.fetch(FetchDescriptor<TaskCompletionEntity>()).first?.domain.taskID, taskID)
        XCTAssertEqual(fixture.settings.appearance, .dark); XCTAssertEqual(fixture.settings.weekStartDay, .sunday)
        XCTAssertEqual(fixture.settings.theme, .linen)
    }

    func testCorruptedAndUnknownSchemaAreRejected() throws {
        let fixture = makeFixture()
        XCTAssertThrowsError(try fixture.service.decodeAndValidate(Data("not-json".utf8)))
        XCTAssertThrowsError(try fixture.service.decodeAndValidate(Data("{\"schemaVersion\":999}".utf8))) { error in
            XCTAssertEqual(error as? BackupError, .unsupportedSchema(999))
        }
    }

    func testDuplicateUUIDIsRejectedBeforeExistingDataChanges() async throws {
        let fixture = makeFixture(), now = Date.now
        let task = TaskItem(id: UUID(), title: "保持", note: "", startDate: now, dueDate: now, isAllDay: true,
                            isCompleted: false, completedAt: nil, priority: .normal, reminderDate: nil, recurrenceRule: nil,
                            projectID: nil, category: nil, tags: [], createdAt: now, updatedAt: now)
        let context = ModelContext(fixture.persistence.container); context.insert(TaskEntity(task)); try context.save()
        let original = try fixture.service.decodeAndValidate(fixture.service.exportData(now: now))
        let invalid = AppBackup(schemaVersion: original.schemaVersion, exportedAt: original.exportedAt, appVersion: original.appVersion,
                                tasks: original.tasks + original.tasks, events: original.events, dailyNotes: original.dailyNotes,
                                projects: original.projects, taskCompletions: original.taskCompletions, settings: original.settings)
        do { try await fixture.service.restoreReplacing(with: invalid); XCTFail("重複UUIDを拒否する必要があります") } catch {}
        XCTAssertEqual(try ModelContext(fixture.persistence.container).fetchCount(FetchDescriptor<TaskEntity>()), 1)
        XCTAssertEqual(try ModelContext(fixture.persistence.container).fetch(FetchDescriptor<TaskEntity>()).first?.domain.title, "保持")
    }

    private func makeFixture() -> (persistence: SwiftDataPersistence, settings: SettingsStore, service: BackupService) {
        let persistence = SwiftDataPersistence(inMemory: true)
        let defaults = UserDefaults(suiteName: "BackupServiceTests.\(UUID().uuidString)")!, settings = SettingsStore(defaults: defaults)
        let tasks = TaskStore(repository: SwiftDataTaskRepository(container: persistence.container))
        let events = CalendarStore(repository: SwiftDataCalendarRepository(container: persistence.container))
        let notes = DailyNoteStore(repository: SwiftDataDailyNoteRepository(container: persistence.container))
        let projects = ProjectStore(repository: SwiftDataProjectRepository(container: persistence.container))
        let completions = TaskCompletionStore(repository: SwiftDataTaskCompletionRepository(container: persistence.container))
        let service = BackupService(container: persistence.container, settingsStore: settings, taskStore: tasks, calendarStore: events,
                                    dailyNoteStore: notes, projectStore: projects, completionStore: completions)
        return (persistence, settings, service)
    }
}
