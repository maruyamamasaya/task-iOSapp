import Foundation

enum TaskPriority: String, CaseIterable, Codable, Hashable, Sendable {
    case low, normal, high

    var displayName: String {
        switch self { case .low: "低"; case .normal: "通常"; case .high: "高" }
    }
}
