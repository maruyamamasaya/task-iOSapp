import Foundation
import Combine

@MainActor final class CalendarStore: ObservableObject {
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var errorMessage: String?
    private let repository: any CalendarRepository
    init(repository: any CalendarRepository) { self.repository = repository }
    func load() async {
        do { events = try await repository.fetchEvents(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
