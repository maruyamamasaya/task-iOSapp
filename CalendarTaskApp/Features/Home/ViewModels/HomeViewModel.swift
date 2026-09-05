import Foundation
import Combine

@MainActor final class HomeViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var events: [CalendarEvent] = []
    @Published var selectedDate: Date
    @Published var memoText = ""
    @Published private(set) var errorMessage: String?
    @Published private(set) var completions: [TaskCompletion] = []
    private let taskStore: TaskStore
    private let calendarStore: CalendarStore
    private let dailyNoteStore: DailyNoteStore
    private let taskCompletionStore: TaskCompletionStore
    private let recurrenceCalculator: RecurrenceCalculator
    private let dateProvider: any DateProviding
    private let settingsStore: SettingsStore
    private var memoSaveTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private let haptics: any HapticService

    init(taskStore: TaskStore, calendarStore: CalendarStore, dailyNoteStore: DailyNoteStore, taskCompletionStore: TaskCompletionStore, dateProvider: any DateProviding, settingsStore: SettingsStore? = nil, hapticService: (any HapticService)? = nil, calendar: Calendar = .current) {
        let settingsStore = settingsStore ?? SettingsStore()
        self.taskStore = taskStore; self.calendarStore = calendarStore
        self.dailyNoteStore = dailyNoteStore; self.taskCompletionStore = taskCompletionStore
        self.recurrenceCalculator = RecurrenceCalculator(calendar: calendar); self.dateProvider = dateProvider; self.settingsStore = settingsStore; self.haptics = hapticService ?? SystemHapticService()
        selectedDate = dateProvider.now
        taskStore.$tasks.sink { [weak self] in self?.tasks = $0 }.store(in: &cancellables)
        calendarStore.$events.sink { [weak self] in self?.events = $0 }.store(in: &cancellables)
        taskCompletionStore.$completions.sink { [weak self] in self?.completions = $0 }.store(in: &cancellables)
        settingsStore.$showCompletedTasksToday.dropFirst().sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
    }
    var dayTasks: [TaskItem] {
        tasks.compactMap { projectedTask($0, on: selectedDate) }.filter { settingsStore.showCompletedTasksToday || !$0.isCompleted }
            .sorted { ($0.dueDate ?? $0.startDate ?? .distantFuture) < ($1.dueDate ?? $1.startDate ?? .distantFuture) }
    }
    var dayEvents: [CalendarEvent] {
        events.compactMap { projectedEvent($0, on: selectedDate) }.sorted { $0.startDate < $1.startDate }
    }
    var isToday: Bool { Calendar.current.isDate(selectedDate, inSameDayAs: dateProvider.now) }
    var now: Date { dateProvider.now }
    var allDayEvents: [CalendarEvent] { dayEvents.filter(\.isAllDay) }
    var allDayTasks: [TaskItem] { dayTasks.filter(\.isAllDay) }
    var unscheduledTasks: [TaskItem] {
        dayTasks.filter { task in
            guard !task.isAllDay, let date = taskDate(task) else { return false }
            return Calendar.current.isDate(date, equalTo: Calendar.current.startOfDay(for: date), toGranularity: .minute)
        }
    }
    var timelineItems: [DailyTimelineItem] {
        let eventItems = dayEvents.filter { !$0.isAllDay }.map(DailyTimelineItem.init(event:))
        let taskItems = dayTasks.filter { task in
            guard !task.isAllDay, let date = taskDate(task) else { return false }
            return !Calendar.current.isDate(date, equalTo: Calendar.current.startOfDay(for: date), toGranularity: .minute)
        }.map(DailyTimelineItem.init(task:))
        return (eventItems + taskItems).sorted { lhs, rhs in
            lhs.date == rhs.date ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending : lhs.date < rhs.date
        }
    }
    func load() async {
        await taskStore.load(); await calendarStore.load(); await taskCompletionStore.load()
        tasks = taskStore.tasks; events = calendarStore.events
        await loadMemo()
        errorMessage = taskStore.errorMessage ?? calendarStore.errorMessage ?? dailyNoteStore.errorMessage
    }
    func moveDay(by value: Int) async {
        selectedDate = Calendar.current.date(byAdding: .day, value: value, to: selectedDate) ?? selectedDate
        await loadMemo()
    }
    func returnToToday() async { selectedDate = dateProvider.now; await loadMemo() }
    func addTask(title: String, note: String, dueDate: Date, priority: TaskPriority) async {
        let now = dateProvider.now
        let task = TaskItem(id: UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), note: note,
                            startDate: dueDate, dueDate: dueDate, isAllDay: true, isCompleted: false,
                            completedAt: nil, priority: priority, reminderDate: nil, recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: now, updatedAt: now)
        await taskStore.add(task); tasks = taskStore.tasks; errorMessage = taskStore.errorMessage
    }
    func saveTask(_ task: TaskItem) async -> Bool {
        let saved = tasks.contains(where: { $0.id == task.id }) ? await taskStore.update(task) : await taskStore.add(task)
        await refresh()
        return saved
    }
    func deleteTask(id: UUID) async { await taskStore.delete(id: id); await taskCompletionStore.deleteAll(taskID: id); haptics.deletion(); await refresh() }
    func saveEvent(_ event: CalendarEvent) async -> Bool {
        let saved = events.contains(where: { $0.id == event.id }) ? await calendarStore.update(event) : await calendarStore.add(event)
        await refresh()
        return saved
    }
    func deleteEvent(id: UUID) async { await calendarStore.delete(id: id); haptics.deletion(); await refresh() }
    func moveTaskToToday(_ task: TaskItem) async { await taskStore.moveToToday(sourceTask(for: task), now: dateProvider.now); haptics.action(); await refresh() }
    func moveTaskToTomorrow(_ task: TaskItem) async { await taskStore.moveToTomorrow(sourceTask(for: task), now: selectedDate); haptics.action(); await refresh() }
    func rescheduleTask(_ task: TaskItem, to date: Date) async { await taskStore.reschedule(sourceTask(for: task), to: date); haptics.action(); await refresh() }
    func duplicateTask(_ task: TaskItem) async { await taskStore.duplicate(sourceTask(for: task)); haptics.action(); await refresh() }
    func rescheduleEvent(_ event: CalendarEvent, to date: Date) async { await calendarStore.reschedule(sourceEvent(for: event), to: date); haptics.action(); await refresh() }
    func duplicateEvent(_ event: CalendarEvent) async { await calendarStore.duplicate(sourceEvent(for: event)); haptics.action(); await refresh() }
    func saveNote(_ note: DailyNote) async { await dailyNoteStore.save(note); await loadMemo() }
    func deleteNote(id: UUID) async { await dailyNoteStore.delete(id: id); memoText = "" }
    func saveQuickAdd(_ result: QuickAddResult) async -> Bool {
        let saved: Bool
        switch result.type {
        case .task: saved = await saveTask(result.task(now: dateProvider.now))
        case .event: saved = await saveEvent(result.event(now: dateProvider.now))
        case .note:
            await dailyNoteStore.load(for: result.date)
            guard dailyNoteStore.errorMessage == nil else { return false }
            await dailyNoteStore.save(result.note(existing: dailyNoteStore.note, now: dateProvider.now))
            saved = dailyNoteStore.errorMessage == nil
            await loadMemo()
        }
        if saved { haptics.action() }
        return saved
    }

    func note(for date: Date) -> DailyNote? {
        guard Calendar.current.isDate(date, inSameDayAs: selectedDate) else { return nil }
        return dailyNoteStore.note
    }
    func toggleCompletion(_ task: TaskItem) async {
        if task.recurrenceRule != nil {
            await taskCompletionStore.toggle(task: sourceTask(for: task), on: selectedDate)
            haptics.completion()
            return
        }
        var updated = task; updated.isCompleted.toggle()
        updated.completedAt = updated.isCompleted ? dateProvider.now : nil; updated.updatedAt = dateProvider.now
        await taskStore.update(updated); tasks = taskStore.tasks; errorMessage = taskStore.errorMessage
        haptics.completion()
    }
    func scheduleMemoSave() {
        memoSaveTask?.cancel()
        let text = memoText; let date = selectedDate
        memoSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }
            await self.dailyNoteStore.save(text: text, for: date)
            self.errorMessage = self.dailyNoteStore.errorMessage
        }
    }
    func flushMemo() async {
        memoSaveTask?.cancel(); await dailyNoteStore.save(text: memoText, for: selectedDate)
    }
    private func loadMemo() async {
        await dailyNoteStore.load(for: selectedDate); memoText = dailyNoteStore.note?.text ?? ""
    }
    private func refresh() async {
        await taskStore.load(); await calendarStore.load(); tasks = taskStore.tasks; events = calendarStore.events
        errorMessage = taskStore.errorMessage ?? calendarStore.errorMessage
    }
    private func taskDate(_ task: TaskItem) -> Date? { task.dueDate ?? task.startDate }
    func sourceTask(for task: TaskItem) -> TaskItem { tasks.first { $0.id == task.id } ?? task }
    func sourceEvent(for event: CalendarEvent) -> CalendarEvent { events.first { $0.id == event.id } ?? event }
    private func projectedTask(_ task: TaskItem, on day: Date) -> TaskItem? {
        guard let anchor = taskDate(task), recurrenceCalculator.occurs(anchor: anchor, rule: task.recurrenceRule, on: day) else { return nil }
        var value = task
        if task.recurrenceRule != nil {
            if let due = task.dueDate { value.dueDate = recurrenceCalculator.occurrenceDate(anchor: due, on: day) }
            if let start = task.startDate { value.startDate = recurrenceCalculator.occurrenceDate(anchor: start, on: day) }
            value.isCompleted = taskCompletionStore.isCompleted(taskID: task.id, on: day)
        }
        return value
    }
    private func projectedEvent(_ event: CalendarEvent, on day: Date) -> CalendarEvent? {
        if event.recurrenceRule == nil {
            let interval = Calendar.current.dayInterval(containing: day)
            return event.startDate < interval.end && event.endDate > interval.start ? event : nil
        }
        guard recurrenceCalculator.occurs(anchor: event.startDate, rule: event.recurrenceRule, on: day) else { return nil }
        var value = event; let duration = event.endDate.timeIntervalSince(event.startDate)
        value.startDate = recurrenceCalculator.occurrenceDate(anchor: event.startDate, on: day)
        value.endDate = value.startDate.addingTimeInterval(duration); return value
    }
}
