import Foundation
import Combine

@MainActor final class AppDependencies: ObservableObject {
    let taskStore: TaskStore
    let calendarStore: CalendarStore
    let settingsStore: SettingsStore
    let dateProvider: any DateProviding

    init(taskRepository: any TaskRepository, calendarRepository: any CalendarRepository, dateProvider: any DateProviding) {
        taskStore = TaskStore(repository: taskRepository)
        calendarStore = CalendarStore(repository: calendarRepository)
        settingsStore = SettingsStore()
        self.dateProvider = dateProvider
    }

    static func live() -> AppDependencies {
        let dates = SystemDateProvider()
        return AppDependencies(
            taskRepository: InMemoryTaskRepository(tasks: SampleData.tasks(now: dates.now)),
            calendarRepository: InMemoryCalendarRepository(events: SampleData.events(now: dates.now)),
            dateProvider: dates
        )
    }
}
