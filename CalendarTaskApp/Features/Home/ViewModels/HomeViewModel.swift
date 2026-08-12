import Foundation
import Combine

@MainActor final class HomeViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var events: [CalendarEvent] = []
    let today: Date
    private let taskStore: TaskStore
    private let calendarStore: CalendarStore
    init(taskStore: TaskStore, calendarStore: CalendarStore, dateProvider: any DateProviding) {
        self.taskStore = taskStore; self.calendarStore = calendarStore; today = dateProvider.now
    }
    var todayTasks: [TaskItem] { tasks.filter { $0.dueDate.map { Calendar.current.isDate($0, inSameDayAs: today) } ?? false } }
    var todayEvents: [CalendarEvent] { events.filter { Calendar.current.isDate($0.startDate, inSameDayAs: today) } }
    var incompleteTasks: [TaskItem] { tasks.filter { !$0.isCompleted } }
    var nextEvent: CalendarEvent? { events.filter { $0.endDate >= today }.sorted { $0.startDate < $1.startDate }.first }
    func load() async {
        await taskStore.load(); await calendarStore.load()
        tasks = taskStore.tasks; events = calendarStore.events
    }
}
