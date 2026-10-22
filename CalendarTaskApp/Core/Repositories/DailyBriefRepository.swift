import Foundation
import CryptoKit

struct DailyBriefContext: Codable, Equatable, Sendable {
    struct Task: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let details: String
        let scheduledAt: Date?
        let completed: Bool
    }
    struct Event: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let start: Date
        let end: Date
        let allDay: Bool
    }
    let date: String
    let timeZone: String
    let tasks: [Task]
    let events: [Event]

    func encodedInput() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var ordered = self
        ordered = Self(date: date, timeZone: timeZone,
                       tasks: tasks.sorted { $0.id.uuidString < $1.id.uuidString },
                       events: events.sorted { $0.id.uuidString < $1.id.uuidString })
        return String(decoding: try encoder.encode(ordered), as: UTF8.self)
    }
    var id: String {
        guard let input = try? encodedInput() else { return "invalid" }
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

struct DailyBrief: Codable, Equatable, Sendable {
    let date: String
    let timeZone: String
    let contextID: String
    let kind: String
    let text: String
    let generatedAt: Date
}

@MainActor protocol DailyBriefRepository {
    func cached(for context: DailyBriefContext) throws -> DailyBrief?
    func exchange(_ context: DailyBriefContext) async throws -> DailyBrief?
}
