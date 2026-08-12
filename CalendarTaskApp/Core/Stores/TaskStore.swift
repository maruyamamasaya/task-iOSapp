import Foundation
import Combine

@MainActor final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var errorMessage: String?
    private let repository: any TaskRepository
    init(repository: any TaskRepository) { self.repository = repository }
    func load() async {
        do { tasks = try await repository.fetchTasks(); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
