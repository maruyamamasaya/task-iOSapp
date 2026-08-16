import Foundation

struct DailyNote: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var date: Date
    var text: String
    let createdAt: Date
    var updatedAt: Date
}
