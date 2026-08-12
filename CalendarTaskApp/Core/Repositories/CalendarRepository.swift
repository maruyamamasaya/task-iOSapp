import Foundation

protocol CalendarRepository: Sendable {
    func fetchEvents() async throws -> [CalendarEvent]
    func addEvent(_ event: CalendarEvent) async throws
    func updateEvent(_ event: CalendarEvent) async throws
    func deleteEvent(id: UUID) async throws
}
