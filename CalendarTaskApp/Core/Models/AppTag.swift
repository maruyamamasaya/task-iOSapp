import Foundation

struct AppTag: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
}
