import Foundation
import Combine

enum CalendarDisplayMode: String, CaseIterable, Identifiable {
    case month = "月"
    case week = "週"
    var id: Self { self }
}

@MainActor final class CalendarViewModel: ObservableObject {
    @Published var displayedMonth: Date
    @Published var selectedDate: Date
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var selectedNote: DailyNote?
    @Published private(set) var completions: [TaskCompletion] = []
    @Published var displayMode = CalendarDisplayMode.month
    private let taskStore: TaskStore
    private let calendarStore: CalendarStore
    private let dailyNoteStore: DailyNoteStore
    private let taskCompletionStore: TaskCompletionStore
    private let recurrenceCalculator: RecurrenceCalculator
    private let dateProvider: any DateProviding
    private let settingsStore: SettingsStore
    private var calendar: Calendar
    private var cancellables = Set<AnyCancellable>()
    private let haptics: any HapticService

    init(taskStore: TaskStore, calendarStore: CalendarStore, dailyNoteStore: DailyNoteStore, taskCompletionStore: TaskCompletionStore, dateProvider: any DateProviding, settingsStore: SettingsStore? = nil, hapticService: (any HapticService)? = nil, calendar: Calendar = .current) {
        let settingsStore = settingsStore ?? SettingsStore()
        self.taskStore = taskStore; self.calendarStore = calendarStore
        self.dailyNoteStore = dailyNoteStore; self.taskCompletionStore = taskCompletionStore
        self.recurrenceCalculator = RecurrenceCalculator(calendar: calendar); self.dateProvider = dateProvider; self.settingsStore = settingsStore; self.haptics = hapticService ?? SystemHapticService()
        var configuredCalendar = calendar; configuredCalendar.firstWeekday = settingsStore.weekStartDay.calendarWeekday; self.calendar = configuredCalendar
        displayMode = settingsStore.initialCalendarMode == .month ? .month : .week
        displayedMonth = dateProvider.now; selectedDate = dateProvider.now
        taskStore.$tasks.sink { [weak self] in self?.tasks = $0 }.store(in: &cancellables)
        calendarStore.$events.sink { [weak self] in self?.events = $0 }.store(in: &cancellables)
        taskCompletionStore.$completions.sink { [weak self] in self?.completions = $0 }.store(in: &cancellables)
        settingsStore.$weekStartDay.dropFirst().sink { [weak self] value in self?.calendar.firstWeekday = value.calendarWeekday; self?.objectWillChange.send() }.store(in: &cancellables)
        settingsStore.$initialCalendarMode.dropFirst().sink { [weak self] value in self?.displayMode = value == .month ? .month : .week }.store(in: &cancellables)
    }
    var monthDates: [Date] { calendar.monthGridDates(containing: displayedMonth) }
    var weekDates: [Date] { calendar.weekDates(containing: selectedDate) }
    var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(start + $0) % 7] }
    }
    var selectedTasks: [TaskItem] { tasks(for: selectedDate) }
    var selectedEvents: [CalendarEvent] { events(for: selectedDate) }
    var now: Date { dateProvider.now }
    var selectedAllDayEvents: [CalendarEvent] { selectedEvents.filter(\.isAllDay) }
    var selectedAllDayTasks: [TaskItem] { selectedTasks.filter(\.isAllDay) }
    var selectedUnscheduledTasks: [TaskItem] {
        selectedTasks.filter { task in
            guard !task.isAllDay, let date = task.dueDate ?? task.startDate else { return false }
            return calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
        }
    }
    var selectedTimelineItems: [DailyTimelineItem] {
        let eventItems = selectedEvents.filter { !$0.isAllDay }.map(DailyTimelineItem.init(event:))
        let taskItems = selectedTasks.filter { task in
            guard !task.isAllDay, let date = task.dueDate ?? task.startDate else { return false }
            return !calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .minute)
        }.map(DailyTimelineItem.init(task:))
        return (eventItems + taskItems).sorted { $0.date < $1.date }
    }
    var weekTitle: String {
        guard let first = weekDates.first, let last = weekDates.last else { return selectedDate.formatted(.dateTime.year().month()) }
        if calendar.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(first.formatted(.dateTime.year().month(.wide))) \(first.formatted(.dateTime.day()))–\(last.formatted(.dateTime.day()))"
        }
        return "\(first.formatted(.dateTime.month().day())) – \(last.formatted(.dateTime.month().day()))"
    }

    func isToday(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: dateProvider.now) }
    func isSelected(_ date: Date) -> Bool { calendar.isDate(date, inSameDayAs: selectedDate) }
    func isInDisplayedMonth(_ date: Date) -> Bool { calendar.isDate(date, inSameMonthAs: displayedMonth) }
    func hasEvents(on date: Date) -> Bool { !events(for: date).isEmpty }
    func hasIncompleteTasks(on date: Date) -> Bool { tasks(for: date).contains { !$0.isCompleted } }
    func projectIDs(on date: Date) -> [UUID?] {
        let values = events(for: date).map(\.projectID) + tasks(for: date).filter { !$0.isCompleted }.map(\.projectID)
        return values.reduce(into: [UUID?]()) { result, value in
            if !result.contains(where: { $0 == value }) && result.count < 3 { result.append(value) }
        }
    }

    func events(for date: Date) -> [CalendarEvent] {
        events.compactMap { projectedEvent($0, on: date) }.sorted { $0.startDate < $1.startDate }
    }
    func tasks(for date: Date) -> [TaskItem] {
        tasks.compactMap { projectedTask($0, on: date) }
            .sorted { ($0.dueDate ?? $0.startDate ?? .distantFuture) < ($1.dueDate ?? $1.startDate ?? .distantFuture) }
    }
    func moveMonth(by value: Int) async {
        displayedMonth = calendar.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth
        selectedDate = calendar.dateInterval(of: .month, for: displayedMonth)?.start ?? displayedMonth
        await loadSelectedNote()
    }
    func moveWeek(by value: Int) async {
        selectedDate = calendar.date(byAdding: .weekOfYear, value: value, to: selectedDate) ?? selectedDate
        displayedMonth = selectedDate
        await loadSelectedNote()
    }
    func returnToToday() async {
        displayedMonth = dateProvider.now; selectedDate = dateProvider.now; await loadSelectedNote()
    }
    func select(_ date: Date) async {
        selectedDate = date
        if !calendar.isDate(date, inSameMonthAs: displayedMonth) { displayedMonth = date }
        await loadSelectedNote()
    }
    func load() async {
        await taskStore.load(); await calendarStore.load(); await taskCompletionStore.load()
        tasks = taskStore.tasks; events = calendarStore.events
        await loadSelectedNote()
    }
    func saveTask(_ task: TaskItem) async -> Bool {
        let saved = tasks.contains(where: { $0.id == task.id }) ? await taskStore.update(task) : await taskStore.add(task)
        await refresh()
        return saved
    }
    func deleteTask(id: UUID) async { await taskStore.delete(id: id); await taskCompletionStore.deleteAll(taskID: id); await refresh() }
    func saveEvent(_ event: CalendarEvent) async -> Bool {
        let saved = events.contains(where: { $0.id == event.id }) ? await calendarStore.update(event) : await calendarStore.add(event)
        await refresh()
        return saved
    }
    func deleteEvent(id: UUID) async { await calendarStore.delete(id: id); await refresh() }
    func toggleCompletion(_ task: TaskItem) async {
        if task.recurrenceRule != nil {
            await taskCompletionStore.toggle(task: sourceTask(for: task), on: selectedDate)
        } else {
            var value = sourceTask(for: task); value.isCompleted.toggle(); value.completedAt = value.isCompleted ? dateProvider.now : nil; value.updatedAt = dateProvider.now
            _ = await taskStore.update(value)
        }
        haptics.completion(); await refresh()
    }
    func moveTaskToToday(_ task: TaskItem) async { await taskStore.moveToToday(sourceTask(for: task), now: dateProvider.now); haptics.action(); await refresh() }
    func moveTaskToTomorrow(_ task: TaskItem) async { await taskStore.moveToTomorrow(sourceTask(for: task), now: selectedDate); haptics.action(); await refresh() }
    func rescheduleTask(_ task: TaskItem, to date: Date) async { await taskStore.reschedule(sourceTask(for: task), to: date); haptics.action(); await refresh() }
    func duplicateTask(_ task: TaskItem) async { await taskStore.duplicate(sourceTask(for: task)); haptics.action(); await refresh() }
    func rescheduleEvent(_ event: CalendarEvent, to date: Date) async { await calendarStore.reschedule(sourceEvent(for: event), to: date); haptics.action(); await refresh() }
    func duplicateEvent(_ event: CalendarEvent) async { await calendarStore.duplicate(sourceEvent(for: event)); haptics.action(); await refresh() }
    func saveQuickAdd(_ result: QuickAddResult) async {
        switch result.type {
        case .task: _ = await saveTask(result.task(now: dateProvider.now))
        case .event: _ = await saveEvent(result.event(now: dateProvider.now))
        case .note: await saveNote(result.note(existing: note(for: result.date), now: dateProvider.now))
        }
        haptics.action()
    }
    func saveNote(_ note: DailyNote) async { await dailyNoteStore.save(note); selectedNote = dailyNoteStore.note }
    func deleteNote(id: UUID) async { await dailyNoteStore.delete(id: id); selectedNote = nil }
    func note(for date: Date) -> DailyNote? { calendar.isDate(date, inSameDayAs: selectedDate) ? selectedNote : nil }
    func sourceTask(for task: TaskItem) -> TaskItem { tasks.first { $0.id == task.id } ?? task }
    func sourceEvent(for event: CalendarEvent) -> CalendarEvent { events.first { $0.id == event.id } ?? event }
    private func loadSelectedNote() async {
        await dailyNoteStore.load(for: selectedDate); selectedNote = dailyNoteStore.note
    }
    private func refresh() async {
        await taskStore.load(); await calendarStore.load(); tasks = taskStore.tasks; events = calendarStore.events
    }
    private func projectedTask(_ task: TaskItem, on day: Date) -> TaskItem? {
        guard let anchor = task.dueDate ?? task.startDate,
              recurrenceCalculator.occurs(anchor: anchor, rule: task.recurrenceRule, on: day) else { return nil }
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
            let interval = calendar.dayInterval(containing: day)
            return event.startDate < interval.end && event.endDate > interval.start ? event : nil
        }
        guard recurrenceCalculator.occurs(anchor: event.startDate, rule: event.recurrenceRule, on: day) else { return nil }
        var value = event; let duration = event.endDate.timeIntervalSince(event.startDate)
        value.startDate = recurrenceCalculator.occurrenceDate(anchor: event.startDate, on: day)
        value.endDate = value.startDate.addingTimeInterval(duration); return value
    }
}
