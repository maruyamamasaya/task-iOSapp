import Foundation
import Combine

enum TaskListSection: String, CaseIterable, Identifiable {
    case inbox = "Inbox", today = "今日", scheduled = "期限あり", noDeadline = "期限なし", completed = "完了済み"
    var id: Self { self }
    var emptyMessage: String {
        switch self { case .inbox: "Inboxは空です"; case .today: "今日のタスクはありません"; case .scheduled: "期限のあるタスクはありません"; case .noDeadline: "期限なしのタスクはありません"; case .completed: "完了済みのタスクはありません" }
    }
}

enum TaskSortOption: String, CaseIterable, Identifiable {
    case date = "日付順", priority = "優先度順", createdAt = "作成日時順"
    var id: Self { self }
}

enum TaskPriorityFilter: String, CaseIterable, Identifiable {
    case all = "すべて", high = "高", normal = "中", low = "低"
    var id: Self { self }
    var priority: TaskPriority? { switch self { case .all: nil; case .high: .high; case .normal: .normal; case .low: .low } }
}

enum TaskProjectFilter: Hashable {
    case all, unassigned, project(UUID)
}

@MainActor final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var selectedSection = TaskListSection.today
    @Published var searchText = ""
    @Published var sortOption = TaskSortOption.date
    @Published var priorityFilter = TaskPriorityFilter.all
    @Published var projectFilter = TaskProjectFilter.all
    @Published private(set) var projects: [Project] = []
    @Published private(set) var completions: [TaskCompletion] = []
    private let store: TaskStore
    private let calendar: Calendar
    private let completionStore: TaskCompletionStore
    private let projectStore: ProjectStore
    private var cancellables = Set<AnyCancellable>()
    private let haptics: any HapticService
    private let settingsStore: SettingsStore

    init(store: TaskStore, completionStore: TaskCompletionStore, projectStore: ProjectStore, settingsStore: SettingsStore? = nil, hapticService: (any HapticService)? = nil, calendar: Calendar = .current) {
        let settingsStore = settingsStore ?? SettingsStore()
        self.store = store; self.completionStore = completionStore; self.projectStore = projectStore; self.settingsStore = settingsStore; self.haptics = hapticService ?? SystemHapticService(); self.calendar = calendar
        selectedSection = settingsStore.showCompletedTaskListInitially ? .completed : Self.section(from: settingsStore.initialTaskSection)
        sortOption = Self.sort(from: settingsStore.defaultTaskSort)
        store.$tasks.sink { [weak self] in self?.tasks = $0 }.store(in: &cancellables)
        completionStore.$completions.sink { [weak self] in self?.completions = $0 }.store(in: &cancellables)
        projectStore.$projects.sink { [weak self] in self?.projects = $0 }.store(in: &cancellables)
        settingsStore.$completedTasksAtBottom.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    var visibleTasks: [TaskItem] {
        let categorized = tasks.filter { matches($0, section: selectedSection) }
        let projectFiltered = categorized.filter { task in
            switch projectFilter {
            case .all: true
            case .unassigned: task.projectID == nil
            case .project(let id): task.projectID == id
            }
        }
        let filtered = projectFiltered.filter { task in
            guard let priority = priorityFilter.priority else { return true }
            return task.priority == priority
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return filtered.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                if settingsStore.completedTasksAtBottom, lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                return areInIncreasingOrder(lhs, rhs)
            }
    }
    var emptyMessage: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && priorityFilter == .all ? selectedSection.emptyMessage : "条件に一致するタスクはありません"
    }
    func count(for section: TaskListSection) -> Int { tasks.filter { matches($0, section: section) }.count }
    func load() async { await store.load(); await completionStore.load(); await projectStore.load(); tasks = store.tasks }
    var projectFilterLabel: String {
        switch projectFilter {
        case .all: "すべてのプロジェクト"
        case .unassigned: "プロジェクトなし"
        case .project(let id): projects.first(where: { $0.id == id })?.name ?? "プロジェクト"
        }
    }
    func save(_ task: TaskItem) async -> Bool { let saved = await store.update(task); await load(); return saved }
    func delete(id: UUID) async { await store.delete(id: id); await completionStore.deleteAll(taskID: id); haptics.deletion(); await load() }
    func moveToToday(_ task: TaskItem) async { await store.moveToToday(task); haptics.action() }
    func moveToTomorrow(_ task: TaskItem) async { await store.moveToTomorrow(task); haptics.action() }
    func reschedule(_ task: TaskItem, to date: Date) async { await store.reschedule(task, to: date); haptics.action() }
    func duplicate(_ task: TaskItem) async { await store.duplicate(task); haptics.action() }
    func assign(_ task: TaskItem, to projectID: UUID?) async {
        var value = task; value.projectID = projectID; value.updatedAt = .now; await store.update(value)
    }
    func toggleCompletion(_ task: TaskItem) async {
        if let rule = task.recurrenceRule, let anchor = task.dueDate ?? task.startDate,
           RecurrenceCalculator(calendar: calendar).occurs(anchor: anchor, rule: rule, on: .now) {
            await completionStore.toggle(task: task, on: .now); haptics.completion(); return
        } else if task.recurrenceRule != nil { return }
        var value = task; value.isCompleted.toggle(); value.completedAt = value.isCompleted ? .now : nil; value.updatedAt = .now
        await store.update(value)
        haptics.completion()
    }
    func displayedCompletion(for task: TaskItem) -> Bool {
        task.recurrenceRule == nil ? task.isCompleted : completionStore.isCompleted(taskID: task.id, on: .now)
    }

    private func matches(_ task: TaskItem, section: TaskListSection) -> Bool {
        if section == .completed { return task.isCompleted }
        guard !task.isCompleted else { return false }
        let hasStart = task.startDate != nil, hasDue = task.dueDate != nil
        let isToday = [task.dueDate, task.startDate].compactMap { $0 }.contains { calendar.isDateInToday($0) }
        switch section {
        case .inbox: return !hasStart && !hasDue
        case .today: return isToday
        case .scheduled: return hasDue && !isToday
        case .noDeadline: return hasStart && !hasDue && !isToday
        case .completed: return false
        }
    }
    private func areInIncreasingOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch sortOption {
        case .date: return (lhs.dueDate ?? lhs.startDate ?? .distantFuture) < (rhs.dueDate ?? rhs.startDate ?? .distantFuture)
        case .priority:
            let rank: [TaskPriority: Int] = [.high: 0, .normal: 1, .low: 2]
            let left = rank[lhs.priority] ?? 1, right = rank[rhs.priority] ?? 1
            return left == right ? lhs.createdAt < rhs.createdAt : left < right
        case .createdAt: return lhs.createdAt > rhs.createdAt
        }
    }
    private static func sort(from value: SettingsTaskSort) -> TaskSortOption { switch value { case .date: .date; case .priority: .priority; case .createdAt: .createdAt } }
    private static func section(from value: SettingsTaskSection) -> TaskListSection { switch value { case .inbox: .inbox; case .today: .today; case .scheduled: .scheduled; case .noDeadline: .noDeadline; case .completed: .completed } }
}
