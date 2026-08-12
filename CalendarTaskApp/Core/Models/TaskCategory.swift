import Foundation

struct TaskCategory: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var colorName: String
}
