import Foundation
import SwiftData

@Model final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var startDate: Date?
    var dueDate: Date?
    var isAllDay: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var priorityRawValue: String
    var reminderDate: Date?
    var recurrenceData: Data?
    var projectID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ task: TaskItem) {
        id = task.id; title = task.title; note = task.note; startDate = task.startDate
        dueDate = task.dueDate; isAllDay = task.isAllDay; isCompleted = task.isCompleted
        completedAt = task.completedAt; priorityRawValue = task.priority.rawValue; reminderDate = task.reminderDate
        recurrenceData = try? JSONEncoder().encode(task.recurrenceRule)
        projectID = task.projectID
        createdAt = task.createdAt; updatedAt = task.updatedAt
    }

    var domain: TaskItem {
        TaskItem(id: id, title: title, note: note, startDate: startDate, dueDate: dueDate,
                 isAllDay: isAllDay, isCompleted: isCompleted, completedAt: completedAt,
                 priority: TaskPriority(rawValue: priorityRawValue) ?? .normal, reminderDate: reminderDate,
                 recurrenceRule: recurrenceData.flatMap { try? JSONDecoder().decode(RecurrenceRule.self, from: $0) },
                 projectID: projectID,
                 category: nil, tags: [], createdAt: createdAt, updatedAt: updatedAt)
    }

    func update(from task: TaskItem) {
        title = task.title; note = task.note; startDate = task.startDate; dueDate = task.dueDate
        isAllDay = task.isAllDay; isCompleted = task.isCompleted; completedAt = task.completedAt
        priorityRawValue = task.priority.rawValue; reminderDate = task.reminderDate
        recurrenceData = try? JSONEncoder().encode(task.recurrenceRule); updatedAt = task.updatedAt
        projectID = task.projectID
    }
}

@Model final class CalendarEventEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var note: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var reminderDate: Date?
    var recurrenceData: Data?
    var projectID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(_ event: CalendarEvent) {
        id = event.id; title = event.title; note = event.note; startDate = event.startDate
        endDate = event.endDate; isAllDay = event.isAllDay; reminderDate = event.reminderDate
        recurrenceData = try? JSONEncoder().encode(event.recurrenceRule)
        projectID = event.projectID
        createdAt = event.createdAt; updatedAt = event.updatedAt
    }
    var domain: CalendarEvent {
        CalendarEvent(id: id, title: title, note: note, startDate: startDate, endDate: endDate,
                      isAllDay: isAllDay, reminderDate: reminderDate,
                      recurrenceRule: recurrenceData.flatMap { try? JSONDecoder().decode(RecurrenceRule.self, from: $0) },
                      projectID: projectID,
                      category: nil, externalEventID: nil,
                      createdAt: createdAt, updatedAt: updatedAt)
    }
    func update(from event: CalendarEvent) {
        title = event.title; note = event.note; startDate = event.startDate
        endDate = event.endDate; isAllDay = event.isAllDay; reminderDate = event.reminderDate
        recurrenceData = try? JSONEncoder().encode(event.recurrenceRule); updatedAt = event.updatedAt
        projectID = event.projectID
    }
}

@Model final class DailyNoteEntity {
    @Attribute(.unique) var id: UUID
    var date: Date
    var text: String
    var createdAt: Date
    var updatedAt: Date
    init(_ note: DailyNote) {
        id = note.id; date = note.date; text = note.text
        createdAt = note.createdAt; updatedAt = note.updatedAt
    }
    var domain: DailyNote { DailyNote(id: id, date: date, text: text, createdAt: createdAt, updatedAt: updatedAt) }
}

@Model final class TaskCompletionEntity {
    @Attribute(.unique) var id: UUID
    var taskID: UUID
    var occurrenceDate: Date
    var completedAt: Date
    init(_ completion: TaskCompletion) {
        id = completion.id; taskID = completion.taskID; occurrenceDate = completion.occurrenceDate; completedAt = completion.completedAt
    }
    var domain: TaskCompletion { TaskCompletion(id: id, taskID: taskID, occurrenceDate: occurrenceDate, completedAt: completedAt) }
}

@Model final class ProjectEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorIdentifier: String
    var iconName: String
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date
    init(_ project: Project) {
        id = project.id; name = project.name; colorIdentifier = project.colorIdentifier.rawValue; iconName = project.iconName
        isArchived = project.isArchived; createdAt = project.createdAt; updatedAt = project.updatedAt
    }
    var domain: Project { Project(id: id, name: name, colorIdentifier: ProjectColor(rawValue: colorIdentifier) ?? .gray, iconName: iconName, isArchived: isArchived, createdAt: createdAt, updatedAt: updatedAt) }
    func update(from project: Project) {
        name = project.name; colorIdentifier = project.colorIdentifier.rawValue; iconName = project.iconName
        isArchived = project.isArchived; updatedAt = project.updatedAt
    }
}

final class SwiftDataPersistence {
    static let shared = SwiftDataPersistence()
    let container: ModelContainer
    init(inMemory: Bool = false, bundle: Bundle = .main, fileManager: FileManager = .default) {
        do {
            let schema = Schema([TaskEntity.self, CalendarEventEntity.self, DailyNoteEntity.self, TaskCompletionEntity.self, ProjectEntity.self])
            let configuration: ModelConfiguration
            if inMemory {
                configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            } else if let identifier = bundle.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
                      !identifier.isEmpty, let directory = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) {
                let sharedURL = directory.appending(path: "CalendarTaskApp.store")
                let previousURL = ModelConfiguration(schema: schema).url
                Self.migrateStoreIfNeeded(from: previousURL, to: sharedURL, fileManager: fileManager)
                configuration = ModelConfiguration(schema: schema, url: sharedURL)
            } else {
                configuration = ModelConfiguration(schema: schema)
            }
            container = try ModelContainer(for: schema, configurations: [configuration])
        }
        catch { fatalError("SwiftData store could not be created: \(error)") }
    }

    private static func migrateStoreIfNeeded(from source: URL, to destination: URL, fileManager: FileManager) {
        guard !fileManager.fileExists(atPath: destination.path), fileManager.fileExists(atPath: source.path) else { return }
        for suffix in ["", "-wal", "-shm"] {
            let sourceFile = URL(fileURLWithPath: source.path + suffix)
            let destinationFile = URL(fileURLWithPath: destination.path + suffix)
            if fileManager.fileExists(atPath: sourceFile.path) { try? fileManager.copyItem(at: sourceFile, to: destinationFile) }
        }
    }
}
