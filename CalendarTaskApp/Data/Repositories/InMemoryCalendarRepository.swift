import Foundation

actor InMemoryCalendarRepository: CalendarRepository {
    private var events: [CalendarEvent]
    init(events: [CalendarEvent]) { self.events = events }
    func fetchEvents() async throws -> [CalendarEvent] { events }
    func addEvent(_ event: CalendarEvent) async throws { events.append(event) }
    func updateEvent(_ event: CalendarEvent) async throws {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[index] = event
    }
    func deleteEvent(id: UUID) async throws { events.removeAll { $0.id == id } }
}
