import Foundation
import Combine

@MainActor final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var showCompleted = true
    private let store: TaskStore
    init(store: TaskStore) { self.store = store }
    var visibleTasks: [TaskItem] { showCompleted ? tasks : tasks.filter { !$0.isCompleted } }
    func load() async { await store.load(); tasks = store.tasks }
}
