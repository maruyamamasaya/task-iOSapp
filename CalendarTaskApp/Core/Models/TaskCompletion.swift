import Foundation

struct TaskCompletion: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let taskID: UUID
    let occurrenceDate: Date
    let completedAt: Date
}
