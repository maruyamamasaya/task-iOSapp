import Foundation
import Combine

enum TaskListSection: String, CaseIterable, Identifiable {
    case week = "今週", all = "すべて", inbox = "Inbox", today = "今日", scheduled = "期限あり", noDeadline = "期限なし", completed = "完了済み"
    var id: Self { self }
    var emptyMessage: String {
        switch self { case .week: "今週のタスクはありません"; case .all: "タスクはありません"; case .inbox: "Inboxは空です"; case .today: "今日のタスクはありません"; case .scheduled: "期限のあるタスクはありません"; case .noDeadline: "期限なしのタスクはありません"; case .completed: "完了済みのタスクはありません" }
    }
}

enum TaskSortOption: String, CaseIterable, Identifiable {
    case date = "日付順", priority = "優先度順", createdAt = "作成日時順", tag = "タグ順"
    var id: Self { self }
}

enum TaskPriorityFilter: String, CaseIterable, Identifiable {
    case all = "すべて", high = "高", normal = "中", low = "低"
    var id: Self { self }
    var priority: TaskPriority? { switch self { case .all: nil; case .high: .high; case .normal: .normal; case .low: .low } }
}

enum TaskTagFilter: Hashable {
    case all, untagged, tag(UUID)
}

struct TaskDayGroup: Identifiable {
    let date: Date?
    let tasks: [TaskItem]
    var id: String { date.map { String($0.timeIntervalSinceReferenceDate) } ?? "undated" }
}

enum TaskProjectFilter: Hashable {
    case all, unassigned, project(UUID)
}

enum PlannerArea: String, CaseIterable, Identifiable {
    case all = "すべて", work = "仕事", personal = "私用", other = "その他"
    var id: Self { self }
    func matches(_ category: String) -> Bool {
        switch self { case .all: true; case .work: category == "work"; case .personal: category == "private"; case .other: category != "work" && category != "private" }
    }
}
enum PlannerKind: String, CaseIterable, Identifiable {
    case all = "すべて", event = "予定", task = "具体的タスク", idea = "やりたいこと", errand = "細々した用事", unspecified = "種別未設定"
    var id: Self { self }
    var wireValue: String? {
        switch self { case .event: "event"; case .task: "task"; case .idea: "idea"; case .errand: "errand"; default: nil }
    }
    static func classify(_ value: String?) -> Self {
        allCases.first { $0.wireValue != nil && $0.wireValue == value } ?? .unspecified
    }
}

enum PlannerStatus: String, CaseIterable, Identifiable {
    case all = "すべて", todo = "未着手", active = "進行中", held = "保留中", thinking = "考え中", completed = "完了", other = "その他の状態"
    var id: Self { self }
    static func classify(_ value: String?, completed: Bool) -> Self {
        if completed { return .completed }
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "未着手", "todo", "未完了": return .todo
        case "進行中", "着手中", "in_progress": return .active
        case "保留", "保留中", "pending": return .held
        case "考え中", "検討中": return .thinking
        default: return .other
        }
    }
}

// Display metadata only. AI context is deliberately absent; this never enters TaskItem/SwiftData.
struct PlannerTaskMetadata: Equatable {
    let category: String
    let status: String
    let projectName: String?
    let scheduleLabel: String
    let deadlineDay: String?
    let deadlineTime: String?
    let timeZone: String?
    var taskKind: String? = nil
    var isDeferred: Bool { ["保留中", "保留", "考え中", "検討中", "統合済み", "統合済"].contains(status) }
    var deadlineText: String? {
        deadlineDay.map { $0.replacingOccurrences(of: "-", with: "/") + (deadlineTime.map { " " + $0 } ?? "") + (deadlineTime == nil ? "" : timeZone.map { " (" + $0 + ")" } ?? "") }
    }
    func deadlineDate(calendar: Calendar) -> Date? {
        guard let deadlineDay else { return nil }
        let f = DateFormatter(); f.calendar = calendar; f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        return f.date(from: deadlineDay)
    }
}
struct TaskProjectGroup: Identifiable {
    let id: UUID?
    let name: String
    let tasks: [TaskItem]
}

@MainActor final class TaskListViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published var selectedSection = TaskListSection.today
    @Published var area = PlannerArea.all
    @Published var kind = PlannerKind.all
    @Published var status = PlannerStatus.all
    @Published var searchesAllTasks = true
    @Published private(set) var plannerMetadata: [UUID: PlannerTaskMetadata] = [:]
    @Published private(set) var completionUndoTask: TaskItem?
    @Published private(set) var isUndoingCompletion = false
    private var completionGeneration = 0
    private var metadataGeneration = 0
    private let metadataSource: @MainActor () async throws -> [UUID: PlannerTaskMetadata]
    private let dateProvider: any DateProviding
    @Published var searchText = ""
    @Published var sortOption = TaskSortOption.date
    @Published var priorityFilter = TaskPriorityFilter.all
    @Published var projectFilter = TaskProjectFilter.all
    @Published var tagFilter = TaskTagFilter.all
    @Published var groupsByDay = true
    @Published private(set) var projects: [Project] = []
    @Published private(set) var completions: [TaskCompletion] = []
    private let store: TaskStore
    private let calendar: Calendar
    private let completionStore: TaskCompletionStore
    private let projectStore: ProjectStore
    private var cancellables = Set<AnyCancellable>()
    private let haptics: any HapticService
    private let settingsStore: SettingsStore

    init(store: TaskStore, completionStore: TaskCompletionStore, projectStore: ProjectStore, settingsStore: SettingsStore? = nil, hapticService: (any HapticService)? = nil, calendar: Calendar = .current, dateProvider: any DateProviding = SystemDateProvider(), metadataSource: @escaping @MainActor () async throws -> [UUID: PlannerTaskMetadata] = { [:] }) {
        self.dateProvider = dateProvider; self.metadataSource = metadataSource
        let settingsStore = settingsStore ?? SettingsStore()
        self.store = store; self.completionStore = completionStore; self.projectStore = projectStore; self.settingsStore = settingsStore; self.haptics = hapticService ?? SystemHapticService(); self.calendar = calendar
        selectedSection = settingsStore.showCompletedTaskListInitially ? .completed : Self.section(from: settingsStore.initialTaskSection)
        sortOption = Self.sort(from: settingsStore.defaultTaskSort)
        store.$errorMessage.sink { [weak self] in self?.operationError = $0 }.store(in: &cancellables)
        store.$tasks.sink { [weak self] tasks in
            self?.tasks = tasks
            Task { await self?.refreshMetadata() }
        }.store(in: &cancellables)
        completionStore.$completions.sink { [weak self] in self?.completions = $0 }.store(in: &cancellables)
        projectStore.$projects.sink { [weak self] in self?.projects = $0 }.store(in: &cancellables)
        settingsStore.$completedTasksAtBottom.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }

    @Published private(set) var operationError: String?
    var visibleTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let globalSearch = !query.isEmpty && searchesAllTasks
        let categorized = tasks.filter {
            globalSearch || (matches($0, section: selectedSection) && area.matches(plannerMetadata[$0.id]?.category ?? "other")
                && (kind == .all || kind == PlannerKind.classify(plannerMetadata[$0.id]?.taskKind))
                && (status == .all || status == displayedStatus(for: $0)))
        }
        let projectFiltered = categorized.filter { task in
            if globalSearch { return true }
            return switch projectFilter {
            case .all: true
            case .unassigned: task.projectID == nil
            case .project(let id): task.projectID == id
            }
        }
        let filtered = projectFiltered.filter { task in
            guard !globalSearch, let priority = priorityFilter.priority else { return true }
            return task.priority == priority
        }
        let tagFiltered = filtered.filter { task in
            if globalSearch { return true }
            return switch tagFilter {
            case .all: true
            case .untagged: task.tags.isEmpty
            case .tag(let id): task.tags.contains { $0.id == id }
            }
        }
        return tagFiltered.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.note.localizedCaseInsensitiveContains(query) || $0.tags.contains { $0.name.localizedCaseInsensitiveContains(query) } || projectName(for: $0).localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                if settingsStore.completedTasksAtBottom, lhs.isCompleted != rhs.isCompleted { return !lhs.isCompleted }
                return areInIncreasingOrder(lhs, rhs)
            }
    }
    private func projectName(for task: TaskItem) -> String {
        plannerMetadata[task.id]?.projectName ?? projects.first { $0.id == task.projectID }?.name ?? ""
    }
    func displayedStatus(for task: TaskItem) -> PlannerStatus {
        PlannerStatus.classify(plannerMetadata[task.id]?.status, completed: task.isCompleted)
    }
    func statusLabel(for task: TaskItem) -> String {
        let value = displayedStatus(for: task)
        if value != .other { return value.rawValue }
        let original = plannerMetadata[task.id]?.status ?? ""
        if original == "完了" { return "未完了（工程: 完了）" }
        return original.isEmpty ? "状態未設定" : original
    }
    func kindLabel(for task: TaskItem) -> String {
        PlannerKind.classify(plannerMetadata[task.id]?.taskKind).rawValue
    }
    func selectKind(_ value: PlannerKind) { kind = value; selectedSection = .all }
    func selectStatus(_ value: PlannerStatus) { status = value; selectedSection = .all }
    var emptyMessage: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && priorityFilter == .all && projectFilter == .all && tagFilter == .all && area == .all && kind == .all && status == .all ? selectedSection.emptyMessage : "条件に一致するタスクはありません"
    }
    var availableTags: [AppTag] {
        var seen = Set<UUID>()
        return tasks.flatMap(\.tags).filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var tagFilterLabel: String {
        switch tagFilter {
        case .all: "すべてのタグ"
        case .untagged: "タグなし"
        case .tag(let id): availableTags.first { $0.id == id }?.name ?? "タグ"
        }
    }
    var dayGroups: [TaskDayGroup] {
        let grouped = Dictionary(grouping: visibleTasks) { task in
            (task.dueDate ?? task.startDate).map { calendar.startOfDay(for: $0) }
        }
        return grouped.keys.sorted { ($0 ?? .distantFuture) < ($1 ?? .distantFuture) }
            .map { TaskDayGroup(date: $0, tasks: grouped[$0] ?? []) }
    }
    func count(for section: TaskListSection) -> Int { tasks.filter { matches($0, section: section) }.count }
    func load() async { await store.load(); await completionStore.load(); await projectStore.load(); await refreshMetadata(); tasks = store.tasks }
    private func refreshMetadata() async {
        metadataGeneration += 1; let generation = metadataGeneration
        do {
            let value = try await metadataSource()
            guard generation == metadataGeneration else { return }
            plannerMetadata = value
        } catch {
            if generation == metadataGeneration { operationError = "分類・状態を読み取れません。保存データは保持しています。" }
        }
    }
    var weekInterval: DateInterval {
        let start = calendar.startOfDay(for: dateProvider.now)
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }
    var weekRangeLabel: String {
        let end = calendar.date(byAdding: .day, value: -1, to: weekInterval.end)!
        return weekInterval.start.formatted(.dateTime.month().day()) + "〜" + end.formatted(.dateTime.month().day())
    }
    var projectGroups: [TaskProjectGroup] {
        Dictionary(grouping: visibleTasks, by: \.projectID).map { id, rows in
            TaskProjectGroup(id: id, name: projects.first { $0.id == id }?.name ?? rows.compactMap { plannerMetadata[$0.id]?.projectName }.first ?? "プロジェクト未設定", tasks: rows)
        }.sorted {
            let left = $0.tasks.compactMap { $0.dueDate ?? $0.startDate }.min() ?? .distantFuture
            let right = $1.tasks.compactMap { $0.dueDate ?? $0.startDate }.min() ?? .distantFuture
            return left == right ? $0.name.localizedStandardCompare($1.name) == .orderedAscending : left < right
        }
    }
    func nextStep(for task: TaskItem) -> String? {
        PlannerTaskPresentation(task: task).note.components(separatedBy: "\n").first { $0.hasPrefix("次の一歩：") }.map { String($0.dropFirst(5)) }
    }
    func scheduleText(for task: TaskItem) -> String {
        if let label = plannerMetadata[task.id]?.scheduleLabel, !label.isEmpty { return label }
        guard let date = task.dueDate ?? task.startDate else { return "日程未定" }
        return date.formatted(task.isAllDay ? .dateTime.month().day() : .dateTime.month().day().hour().minute())
    }
    func undoCompletion(taskID: UUID) async {
        guard !isUndoingCompletion, let previous = completionUndoTask, previous.id == taskID else { return }
        completionGeneration += 1; let generation = completionGeneration
        isUndoingCompletion = true; defer { isUndoingCompletion = false }
        guard var task = store.tasks.first(where: { $0.id == taskID }), task.isCompleted else { completionUndoTask = nil; return }
        task.isCompleted = false; task.completedAt = nil; task.updatedAt = dateProvider.now
        if await store.update(task), generation == completionGeneration { completionUndoTask = nil }
    }
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
        completionGeneration += 1; let generation = completionGeneration
        var value = task; value.isCompleted.toggle(); value.completedAt = value.isCompleted ? dateProvider.now : nil; value.updatedAt = dateProvider.now
        if await store.update(value) {
            if generation == completionGeneration { completionUndoTask = value.isCompleted ? value : nil }
            haptics.completion()
        }
    }
    func displayedCompletion(for task: TaskItem) -> Bool {
        task.recurrenceRule == nil ? task.isCompleted : completionStore.isCompleted(taskID: task.id, on: .now)
    }

    private func matches(_ task: TaskItem, section: TaskListSection) -> Bool {
        if section == .week {
            guard !task.isCompleted, let metadata = plannerMetadata[task.id], !metadata.isDeferred,
                  !task.title.hasPrefix("【統合済") else { return false }
            let dates = [task.dueDate ?? task.startDate, metadata.deadlineDate(calendar: calendar)].compactMap { $0 }
            return dates.contains { $0 >= weekInterval.start && $0 < weekInterval.end }
        }
        if section == .all { return true }
        if section == .completed { return task.isCompleted }
        guard !task.isCompleted else { return false }
        let hasStart = task.startDate != nil, hasDue = task.dueDate != nil
        let isToday = [task.dueDate, task.startDate].compactMap { $0 }.contains { calendar.isDateInToday($0) }
        switch section {
        case .all, .week: return true
        case .inbox: return !hasStart && !hasDue
        case .today: return isToday
        case .scheduled: return hasDue && !isToday
        case .noDeadline: return hasStart && !hasDue && !isToday
        case .completed: return false
        }
    }
    private func areInIncreasingOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        switch sortOption {
        case .date:
            let left = lhs.dueDate ?? lhs.startDate ?? .distantFuture, right = rhs.dueDate ?? rhs.startDate ?? .distantFuture
            return left == right ? lhs.id.uuidString < rhs.id.uuidString : left < right
        case .priority:
            let rank: [TaskPriority: Int] = [.high: 0, .normal: 1, .low: 2]
            let left = rank[lhs.priority] ?? 1, right = rank[rhs.priority] ?? 1
            return left == right ? lhs.createdAt < rhs.createdAt : left < right
        case .createdAt: return lhs.createdAt > rhs.createdAt
        case .tag:
            let left = lhs.tags.map(\.name).sorted().joined(separator: " ")
            let right = rhs.tags.map(\.name).sorted().joined(separator: " ")
            if left.isEmpty != right.isEmpty { return !left.isEmpty }
            let comparison = left.localizedStandardCompare(right)
            return comparison == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : comparison == .orderedAscending
        }
    }
    private static func sort(from value: SettingsTaskSort) -> TaskSortOption { switch value { case .date: .date; case .priority: .priority; case .createdAt: .createdAt } }
    private static func section(from value: SettingsTaskSection) -> TaskListSection { switch value { case .inbox: .inbox; case .today: .today; case .scheduled: .scheduled; case .noDeadline: .noDeadline; case .completed: .completed } }
}
