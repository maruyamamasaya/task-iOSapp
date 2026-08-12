import Foundation

struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var note: String
    var startDate: Date?
    var dueDate: Date?
    var isAllDay: Bool
    var isCompleted: Bool
    var completedAt: Date?
    var priority: TaskPriority
    var category: TaskCategory?
    var tags: [AppTag]
    let createdAt: Date
    var updatedAt: Date
}
