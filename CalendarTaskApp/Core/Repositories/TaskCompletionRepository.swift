import Foundation

protocol TaskCompletionRepository: Sendable {
    func fetchCompletions() async throws -> [TaskCompletion]
    func addCompletion(_ completion: TaskCompletion) async throws
    func deleteCompletion(id: UUID) async throws
    func deleteCompletions(taskID: UUID) async throws
}
