import Foundation

struct CalendarEvent: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var title: String
    var note: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var reminderDate: Date?
    var recurrenceRule: RecurrenceRule?
    var projectID: UUID?
    var category: TaskCategory?
    var externalEventID: String?
    let createdAt: Date
    var updatedAt: Date
}
