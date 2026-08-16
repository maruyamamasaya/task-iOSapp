import Foundation
import SwiftData

@MainActor final class BackupService: ObservableObject {
    @Published private(set) var summary = BackupDataSummary()
    private let container: ModelContainer
    private let settingsStore: SettingsStore
    private let taskStore: TaskStore
    private let calendarStore: CalendarStore
    private let dailyNoteStore: DailyNoteStore
    private let projectStore: ProjectStore
    private let completionStore: TaskCompletionStore
    private let notificationService: any NotificationService
    private let widgetRefreshService: any WidgetRefreshService

    init(container: ModelContainer, settingsStore: SettingsStore, taskStore: TaskStore, calendarStore: CalendarStore,
         dailyNoteStore: DailyNoteStore, projectStore: ProjectStore, completionStore: TaskCompletionStore,
         notificationService: any NotificationService = NoopNotificationService(), widgetRefreshService: any WidgetRefreshService = NoopWidgetRefreshService()) {
        self.container = container; self.settingsStore = settingsStore; self.taskStore = taskStore; self.calendarStore = calendarStore
        self.dailyNoteStore = dailyNoteStore; self.projectStore = projectStore; self.completionStore = completionStore
        self.notificationService = notificationService; self.widgetRefreshService = widgetRefreshService
    }

    func refreshSummary() throws {
        let context = ModelContext(container)
        summary = BackupDataSummary(tasks: try context.fetchCount(FetchDescriptor<TaskEntity>()),
                                    events: try context.fetchCount(FetchDescriptor<CalendarEventEntity>()),
                                    notes: try context.fetchCount(FetchDescriptor<DailyNoteEntity>()),
                                    projects: try context.fetchCount(FetchDescriptor<ProjectEntity>()),
                                    completions: try context.fetchCount(FetchDescriptor<TaskCompletionEntity>()))
    }

    func exportData(now: Date = .now, bundle: Bundle = .main) throws -> Data {
        let context = ModelContext(container)
        let backup = AppBackup(schemaVersion: AppBackup.currentSchemaVersion, exportedAt: now,
                               appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                               tasks: try context.fetch(FetchDescriptor<TaskEntity>()).map { BackupTask(value: $0.domain) },
                               events: try context.fetch(FetchDescriptor<CalendarEventEntity>()).map { BackupCalendarEvent(value: $0.domain) },
                               dailyNotes: try context.fetch(FetchDescriptor<DailyNoteEntity>()).map { BackupDailyNote(value: $0.domain) },
                               projects: try context.fetch(FetchDescriptor<ProjectEntity>()).map { BackupProject(value: $0.domain) },
                               taskCompletions: try context.fetch(FetchDescriptor<TaskCompletionEntity>()).map { BackupTaskCompletion(value: $0.domain) },
                               settings: settingsStore.backupSettings())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(backup)
        try? refreshSummary()
        return data
    }
    func markBackupExported(at date: Date = .now) { settingsStore.lastBackupDate = date }

    func decodeAndValidate(_ data: Data) throws -> AppBackup {
        struct Envelope: Decodable { let schemaVersion: Int }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(Envelope.self, from: data) else { throw BackupError.corruptedFile }
        guard envelope.schemaVersion == AppBackup.currentSchemaVersion else { throw BackupError.unsupportedSchema(envelope.schemaVersion) }
        guard let backup = try? decoder.decode(AppBackup.self, from: data) else { throw BackupError.corruptedFile }
        try validate(backup)
        return backup
    }

    func restoreReplacing(with backup: AppBackup) async throws {
        try validate(backup)
        let context = ModelContext(container)
        let oldTasks = try context.fetch(FetchDescriptor<TaskEntity>()).map(\.domain)
        let oldEvents = try context.fetch(FetchDescriptor<CalendarEventEntity>()).map(\.domain)
        do {
            try context.fetch(FetchDescriptor<TaskCompletionEntity>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<TaskEntity>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<CalendarEventEntity>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<DailyNoteEntity>()).forEach(context.delete)
            try context.fetch(FetchDescriptor<ProjectEntity>()).forEach(context.delete)
            backup.projects.forEach { context.insert(ProjectEntity($0.value)) }
            backup.tasks.forEach { context.insert(TaskEntity($0.value)) }
            backup.events.forEach { context.insert(CalendarEventEntity($0.value)) }
            backup.dailyNotes.forEach { context.insert(DailyNoteEntity($0.value)) }
            backup.taskCompletions.forEach { context.insert(TaskCompletionEntity($0.value)) }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        try settingsStore.restore(backup.settings)
        for task in oldTasks { await notificationService.removeTaskNotification(id: task.id) }
        for event in oldEvents { await notificationService.removeEventNotification(id: event.id) }
        for task in backup.tasks.map(\.value) { await notificationService.sync(task: task) }
        for event in backup.events.map(\.value) { await notificationService.sync(event: event) }
        await taskStore.load(); await calendarStore.load(); await completionStore.load(); await projectStore.load(); await dailyNoteStore.load(for: .now)
        widgetRefreshService.reloadTodayWidgets(); try? refreshSummary()
    }

    private func validate(_ backup: AppBackup) throws {
        guard backup.schemaVersion == AppBackup.currentSchemaVersion else { throw BackupError.unsupportedSchema(backup.schemaVersion) }
        try unique(backup.tasks.map { $0.value.id }, "Task")
        try unique(backup.events.map { $0.value.id }, "Event")
        try unique(backup.dailyNotes.map { $0.value.id }, "DailyNote")
        try unique(backup.projects.map { $0.value.id }, "Project")
        try unique(backup.taskCompletions.map { $0.value.id }, "TaskCompletion")
        let taskIDs = Set(backup.tasks.map { $0.value.id }), projectIDs = Set(backup.projects.map { $0.value.id })
        for value in backup.taskCompletions.map(\.value) where !taskIDs.contains(value.taskID) { throw BackupError.missingTask(value.taskID) }
        for id in backup.tasks.compactMap({ $0.value.projectID }) + backup.events.compactMap({ $0.value.projectID }) where !projectIDs.contains(id) { throw BackupError.missingProject(id) }
        try settingsStore.validate(backup.settings)
    }
    private func unique(_ ids: [UUID], _ type: String) throws { if Set(ids).count != ids.count { throw BackupError.duplicateID(type) } }
}
