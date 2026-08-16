import Foundation

enum ProjectColor: String, CaseIterable, Codable, Hashable, Sendable {
    case blue, green, orange, purple, pink, red, teal, gray
}

struct Project: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var colorIdentifier: ProjectColor
    var iconName: String
    var isArchived: Bool
    let createdAt: Date
    var updatedAt: Date
}

enum ProjectIcon {
    static let presets = ["briefcase", "person", "book", "cart", "house", "heart"]
}
