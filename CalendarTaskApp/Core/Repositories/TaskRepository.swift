import Foundation

protocol TaskRepository: Sendable {
    func fetchTasks() async throws -> [TaskItem]
    func addTask(_ task: TaskItem) async throws
    func updateTask(_ task: TaskItem) async throws
    func deleteTask(id: UUID) async throws
}
