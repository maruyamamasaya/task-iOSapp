import Foundation
import Combine

@MainActor final class DailyNoteStore: ObservableObject {
    @Published private(set) var note: DailyNote?
    @Published private(set) var errorMessage: String?
    private let repository: any DailyNoteRepository

    init(repository: any DailyNoteRepository) { self.repository = repository }

    func load(for date: Date) async {
        do { note = try await repository.fetchNote(for: date); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }

    func save(text: String, for date: Date, now: Date = .now) async {
        let value = DailyNote(id: note?.id ?? UUID(), date: date, text: text,
                              createdAt: note?.createdAt ?? now, updatedAt: now)
        do { try await repository.saveNote(value); note = value; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func save(_ value: DailyNote) async {
        do { try await repository.saveNote(value); note = value; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    func delete(id: UUID) async {
        do { try await repository.deleteNote(id: id); note = nil; errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
