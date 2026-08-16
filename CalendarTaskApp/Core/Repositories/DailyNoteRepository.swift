import Foundation

protocol DailyNoteRepository: Sendable {
    func fetchNote(for date: Date) async throws -> DailyNote?
    func saveNote(_ note: DailyNote) async throws
    func deleteNote(id: UUID) async throws
}
