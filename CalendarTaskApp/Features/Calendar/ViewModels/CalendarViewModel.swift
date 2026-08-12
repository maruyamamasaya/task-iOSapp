import Foundation
import Combine

@MainActor final class CalendarViewModel: ObservableObject {
    @Published var displayedMonth: Date
    @Published var selectedDate: Date
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var events: [CalendarEvent] = []
    private let taskStore: TaskStore; private let calendarStore: CalendarStore
    init(taskStore: TaskStore, calendarStore: CalendarStore, dateProvider: any DateProviding) {
        self.taskStore = taskStore; self.calendarStore = calendarStore
        displayedMonth = dateProvider.now; selectedDate = dateProvider.now
    }
    var monthDates: [Date?] { Calendar.current.monthDates(containing: displayedMonth) }
    var selectedTasks: [TaskItem] { tasks.filter { task in task.dueDate.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } ?? false } }
    var selectedEvents: [CalendarEvent] { events.filter { $0.startDate <= (Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate) && $0.endDate >= Calendar.current.startOfDay(for: selectedDate) } }
    func moveMonth(by value: Int) { displayedMonth = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) ?? displayedMonth }
    func load() async { await taskStore.load(); await calendarStore.load(); tasks = taskStore.tasks; events = calendarStore.events }
}
