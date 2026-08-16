import Foundation
import SwiftData

@MainActor final class SwiftDataTaskRepository: TaskRepository, @unchecked Sendable {
    private let modelContext: ModelContext
    init(container: ModelContainer) { modelContext = ModelContext(container) }
    func fetchTasks() async throws -> [TaskItem] {
        try modelContext.fetch(FetchDescriptor<TaskEntity>(sortBy: [SortDescriptor(\.createdAt)])).map(\.domain)
    }
    func addTask(_ task: TaskItem) async throws { modelContext.insert(TaskEntity(task)); try modelContext.save() }
    func updateTask(_ task: TaskItem) async throws {
        let id = task.id
        var descriptor = FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let entity = try modelContext.fetch(descriptor).first { entity.update(from: task); try modelContext.save() }
    }
    func deleteTask(id: UUID) async throws {
        try modelContext.delete(model: TaskEntity.self, where: #Predicate { $0.id == id }); try modelContext.save()
    }
}

@MainActor final class SwiftDataCalendarRepository: CalendarRepository, @unchecked Sendable {
    private let modelContext: ModelContext
    init(container: ModelContainer) { modelContext = ModelContext(container) }
    func fetchEvents() async throws -> [CalendarEvent] {
        try modelContext.fetch(FetchDescriptor<CalendarEventEntity>(sortBy: [SortDescriptor(\.startDate)])).map(\.domain)
    }
    func addEvent(_ event: CalendarEvent) async throws { modelContext.insert(CalendarEventEntity(event)); try modelContext.save() }
    func updateEvent(_ event: CalendarEvent) async throws {
        let id = event.id
        var descriptor = FetchDescriptor<CalendarEventEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let entity = try modelContext.fetch(descriptor).first { entity.update(from: event); try modelContext.save() }
    }
    func deleteEvent(id: UUID) async throws {
        try modelContext.delete(model: CalendarEventEntity.self, where: #Predicate { $0.id == id }); try modelContext.save()
    }
}

@MainActor final class SwiftDataDailyNoteRepository: DailyNoteRepository, @unchecked Sendable {
    private let modelContext: ModelContext
    init(container: ModelContainer) { modelContext = ModelContext(container) }
    func fetchNote(for date: Date) async throws -> DailyNote? {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        var descriptor = FetchDescriptor<DailyNoteEntity>(predicate: #Predicate { $0.date >= start && $0.date < end })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first?.domain
    }
    func saveNote(_ note: DailyNote) async throws {
        let id = note.id
        var descriptor = FetchDescriptor<DailyNoteEntity>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let entity = try modelContext.fetch(descriptor).first {
            entity.date = note.date; entity.text = note.text; entity.updatedAt = note.updatedAt
        } else { modelContext.insert(DailyNoteEntity(note)) }
        try modelContext.save()
    }
    func deleteNote(id: UUID) async throws {
        try modelContext.delete(model: DailyNoteEntity.self, where: #Predicate { $0.id == id })
        try modelContext.save()
    }
}

@MainActor final class SwiftDataTaskCompletionRepository: TaskCompletionRepository, @unchecked Sendable {
    private let modelContext: ModelContext
    init(container: ModelContainer) { modelContext = ModelContext(container) }
    func fetchCompletions() async throws -> [TaskCompletion] {
        try modelContext.fetch(FetchDescriptor<TaskCompletionEntity>()).map(\.domain)
    }
    func addCompletion(_ completion: TaskCompletion) async throws { modelContext.insert(TaskCompletionEntity(completion)); try modelContext.save() }
    func deleteCompletion(id: UUID) async throws {
        try modelContext.delete(model: TaskCompletionEntity.self, where: #Predicate { $0.id == id }); try modelContext.save()
    }
    func deleteCompletions(taskID: UUID) async throws {
        try modelContext.delete(model: TaskCompletionEntity.self, where: #Predicate { $0.taskID == taskID }); try modelContext.save()
    }
}

@MainActor final class SwiftDataProjectRepository: ProjectRepository, @unchecked Sendable {
    private let modelContext: ModelContext
    init(container: ModelContainer) { modelContext = ModelContext(container) }
    func fetchProjects() async throws -> [Project] {
        try modelContext.fetch(FetchDescriptor<ProjectEntity>(sortBy: [SortDescriptor(\.name)])).map(\.domain)
    }
    func addProject(_ project: Project) async throws { modelContext.insert(ProjectEntity(project)); try modelContext.save() }
    func updateProject(_ project: Project) async throws {
        let id = project.id
        var descriptor = FetchDescriptor<ProjectEntity>(predicate: #Predicate { $0.id == id }); descriptor.fetchLimit = 1
        if let entity = try modelContext.fetch(descriptor).first { entity.update(from: project); try modelContext.save() }
    }
    func archiveProject(id: UUID, archived: Bool) async throws {
        var descriptor = FetchDescriptor<ProjectEntity>(predicate: #Predicate { $0.id == id }); descriptor.fetchLimit = 1
        if let entity = try modelContext.fetch(descriptor).first { entity.isArchived = archived; entity.updatedAt = .now; try modelContext.save() }
    }
    func deleteProject(id: UUID) async throws {
        let tasks = try modelContext.fetch(FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.projectID == id }))
        let events = try modelContext.fetch(FetchDescriptor<CalendarEventEntity>(predicate: #Predicate { $0.projectID == id }))
        tasks.forEach { $0.projectID = nil }; events.forEach { $0.projectID = nil }
        try modelContext.delete(model: ProjectEntity.self, where: #Predicate { $0.id == id }); try modelContext.save()
    }
}
