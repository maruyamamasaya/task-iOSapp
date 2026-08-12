import Foundation

actor InMemoryTaskRepository: TaskRepository {
    private var tasks: [TaskItem]
    init(tasks: [TaskItem]) { self.tasks = tasks }
    func fetchTasks() async throws -> [TaskItem] { tasks }
    func addTask(_ task: TaskItem) async throws { tasks.append(task) }
    func updateTask(_ task: TaskItem) async throws {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = task
    }
    func deleteTask(id: UUID) async throws { tasks.removeAll { $0.id == id } }
}
