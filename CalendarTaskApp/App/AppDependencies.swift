import Foundation
import Combine
import SwiftData

@MainActor final class AppDependencies: ObservableObject {
    let taskStore: TaskStore
    let calendarStore: CalendarStore
    let settingsStore: SettingsStore
    let dailyNoteStore: DailyNoteStore
    let dateProvider: any DateProviding
    let notificationService: any NotificationService
    let taskCompletionStore: TaskCompletionStore
    let projectStore: ProjectStore
    let hapticService: any HapticService
    let backupService: BackupService

    init(modelContainer: ModelContainer, taskRepository: any TaskRepository, calendarRepository: any CalendarRepository, dailyNoteRepository: any DailyNoteRepository, taskCompletionRepository: any TaskCompletionRepository, projectRepository: any ProjectRepository, dateProvider: any DateProviding, settingsStore: SettingsStore? = nil, notificationService: any NotificationService = NoopNotificationService(), widgetRefreshService: any WidgetRefreshService = NoopWidgetRefreshService()) {
        let settingsStore = settingsStore ?? SettingsStore()
        taskStore = TaskStore(repository: taskRepository, notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        calendarStore = CalendarStore(repository: calendarRepository, notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        self.settingsStore = settingsStore
        dailyNoteStore = DailyNoteStore(repository: dailyNoteRepository)
        self.dateProvider = dateProvider
        self.notificationService = notificationService
        taskCompletionStore = TaskCompletionStore(repository: taskCompletionRepository, notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        projectStore = ProjectStore(repository: projectRepository)
        hapticService = SystemHapticService(isEnabled: { settingsStore.hapticFeedbackEnabled })
        backupService = BackupService(container: modelContainer, settingsStore: settingsStore, taskStore: taskStore, calendarStore: calendarStore,
                                      dailyNoteStore: dailyNoteStore, projectStore: projectStore, completionStore: taskCompletionStore,
                                      notificationService: notificationService, widgetRefreshService: widgetRefreshService)
    }

    static func live() -> AppDependencies {
        let dates = SystemDateProvider()
        let persistence = SwiftDataPersistence.shared
        let notifications = UserNotificationService()
        let widgetRefresh = LiveWidgetRefreshService()
        return AppDependencies(
            modelContainer: persistence.container,
            taskRepository: SwiftDataTaskRepository(container: persistence.container),
            calendarRepository: SwiftDataCalendarRepository(container: persistence.container),
            dailyNoteRepository: SwiftDataDailyNoteRepository(container: persistence.container),
            taskCompletionRepository: SwiftDataTaskCompletionRepository(container: persistence.container),
            projectRepository: SwiftDataProjectRepository(container: persistence.container),
            dateProvider: dates,
            notificationService: notifications,
            widgetRefreshService: widgetRefresh
        )
    }
}
