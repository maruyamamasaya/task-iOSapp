import Foundation
import Combine
import SwiftData

@MainActor final class AppDependencies: ObservableObject {
    let relayActivity: @MainActor (Bool) async -> Void
    let retryRelay: @MainActor () async -> Void
    let dotLocalRelayFactory: DotLocalRelayFactory
    let runApprovedOverdueMove: @MainActor () async -> Void
    let dotTaskStore: DotTaskStore?
    let plannerTaskStore: TaskStore
    let plannerTaskMetadata: @MainActor () async throws -> [UUID: PlannerTaskMetadata]
    private var dotPlannerObservation: AnyCancellable?
    private var dotWidgetObservation: AnyCancellable?
    let taskStore: TaskStore
    let calendarStore: CalendarStore
    let settingsStore: SettingsStore
    let dailyBriefStore: DailyBriefStore
    let dailyNoteStore: DailyNoteStore
    let dateProvider: any DateProviding
    let notificationService: any NotificationService
    let taskCompletionStore: TaskCompletionStore
    let projectStore: ProjectStore
    let tagStore: TagStore
    let hapticService: any HapticService
    let backupService: BackupService

    init(modelContainer: ModelContainer, taskRepository: any TaskRepository, calendarRepository: any CalendarRepository, dailyNoteRepository: any DailyNoteRepository, taskCompletionRepository: any TaskCompletionRepository, projectRepository: any ProjectRepository, tagRepository: any TagRepository, dateProvider: any DateProviding, settingsStore: SettingsStore? = nil, notificationService: any NotificationService = NoopNotificationService(), widgetRefreshService: any WidgetRefreshService = NoopWidgetRefreshService(), dotTaskStore: DotTaskStore? = nil, dotWidgetCache: DotWidgetTaskCache? = nil, dotRelayCache: DotRelayTaskCache? = nil, dailyBriefRepository: (any DailyBriefRepository)? = nil) {
        self.dotTaskStore = dotTaskStore
        let settingsStore = settingsStore ?? SettingsStore()
        let relayCache = dotRelayCache ?? DotRelayTaskCache()
        relayActivity = { await relayCache.setActive($0) }
        retryRelay = { await relayCache.retry() }
        let combinedRepository = DotRelayTaskRepository(native: taskRepository, cache: relayCache)
        taskStore = TaskStore(repository: combinedRepository, notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        let plannerRepository = DotPlannerTaskRepository(imported: {
            dotTaskStore?.load()
            return dotTaskStore?.snapshot?.tasks ?? []
        }, relay: { try await combinedRepository.plannerTasks() },
           updateRelay: { try await combinedRepository.updateTask($0) })
        plannerTaskMetadata = {
            let snapshot = await (try relayCache.store()).snapshot
            var values: [UUID: PlannerTaskMetadata] = [:]
            let relaySlugs = Set(snapshot.tasks.map { $0.value.id })
            for row in snapshot.tasks {
                let t = row.value
                values[row.id] = PlannerTaskMetadata(category: t.category, status: t.status, projectName: t.project?.name,
                    scheduleLabel: t.dateLabel, deadlineDay: t.deadlineDate, deadlineTime: t.deadlineTime, timeZone: t.timeZone, taskKind: t.taskKind)
            }
            dotTaskStore?.load()
            for row in dotTaskStore?.snapshot?.tasks ?? [] where !relaySlugs.contains(row.slug) {
                values[row.id] = PlannerTaskMetadata(category: row.category, status: row.status, projectName: nil,
                    scheduleLabel: row.dateLabel, deadlineDay: row.deadlineDate, deadlineTime: row.deadlineTime, timeZone: row.timeZone, taskKind: row.taskKind)
            }
            return values
        }
        plannerTaskStore = TaskStore(repository: plannerRepository, notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        let sharedPlannerStore = plannerTaskStore
        let sharedTaskStore = taskStore
        let relayProjects = ProjectStore(repository: DotRelayProjectRepository(native: projectRepository, cache: relayCache))
        let relayTags = TagStore(repository: DotRelayTagRepository(native: tagRepository, cache: relayCache))
        let relayNotifications = DotRelayNotificationSync(service: notificationService)
        relayCache.onChange = {
            await relayProjects.load(); await relayTags.load()
            await sharedPlannerStore.load(); await sharedTaskStore.load()
            if let tasks = try? await combinedRepository.plannerTasks() {
                await relayNotifications.synchronize(tasks.map(\.task))
            }
        }
        self.runApprovedOverdueMove = { await ApprovedOverdueMove.run(native: taskRepository, tasks: sharedTaskStore, cache: relayCache) }
        self.dotLocalRelayFactory = .local(dotTaskStore: dotTaskStore, cache: relayCache, onChange: { await sharedTaskStore.load(); await sharedPlannerStore.load() })
        calendarStore = CalendarStore(repository: calendarRepository, notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        self.settingsStore = settingsStore
        dailyNoteStore = DailyNoteStore(repository: dailyNoteRepository)
        dailyBriefStore = DailyBriefStore(repository: dailyBriefRepository ?? DotDailyBriefRepository())
        self.dateProvider = dateProvider
        self.notificationService = notificationService
        taskCompletionStore = TaskCompletionStore(repository: taskCompletionRepository, notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        projectStore = relayProjects
        tagStore = relayTags
        hapticService = SystemHapticService(isEnabled: { settingsStore.hapticFeedbackEnabled })
        backupService = BackupService(container: modelContainer, settingsStore: settingsStore, taskStore: taskStore, calendarStore: calendarStore,
                                      dailyNoteStore: dailyNoteStore, projectStore: projectStore, tagStore: tagStore, completionStore: taskCompletionStore,
                                      notificationService: notificationService, widgetRefreshService: widgetRefreshService)
        dotWidgetObservation = plannerTaskStore.$tasks.dropFirst().sink { tasks in
            guard let dotWidgetCache else { return }
            do {
                if try dotWidgetCache.save(tasks) { widgetRefreshService.reloadTodayWidgets() }
                let rows = try dotWidgetCache.load()
                let matches = rows.count == tasks.count && zip(rows, tasks).allSatisfy {
                    $0.id == $1.id && $0.title == $1.title && $0.date == ($1.dueDate ?? $1.startDate)
                        && $0.isAllDay == $1.isAllDay && $0.isCompleted == $1.isCompleted
                }
                print("Dot Widget readback: rows=\(rows.count), matchesPlanner=\(matches)")
            } catch {
                print("Dot Widget projection save failed: \(error)")
            }
        }
        dotPlannerObservation = dotTaskStore?.$snapshot.sink { _ in
            Task { await sharedPlannerStore.load() }
        }
    }

    static func live() -> AppDependencies {
        let dates = SystemDateProvider()
        let persistence = SwiftDataPersistence.shared
        let notifications = UserNotificationService()
        let widgetRefresh = LiveWidgetRefreshService()
        let dotCache = DotTaskFileCache(url: URL.applicationSupportDirectory.appending(path: "DotTasks/local-v1.json"))
        return AppDependencies(
            modelContainer: persistence.container,
            taskRepository: SwiftDataTaskRepository(container: persistence.container),
            calendarRepository: SwiftDataCalendarRepository(container: persistence.container),
            dailyNoteRepository: SwiftDataDailyNoteRepository(container: persistence.container),
            taskCompletionRepository: SwiftDataTaskCompletionRepository(container: persistence.container),
            projectRepository: SwiftDataProjectRepository(container: persistence.container),
            tagRepository: SwiftDataTagRepository(container: persistence.container),
            dateProvider: dates,
            notificationService: notifications,
            widgetRefreshService: widgetRefresh,
            dotTaskStore: DotTaskStore(source: LocalDotTaskSource(cache: dotCache), cache: dotCache,
                                       importer: DotTaskJSONFileImporter()),
            dotWidgetCache: DotWidgetTaskCache.shared()
        )
    }

    func rescheduleNotificationsIfAuthorized() async {
        await plannerTaskStore.load()
        guard await notificationService.authorizationStatus() == .authorized else { return }
        await taskStore.load()
        await calendarStore.load()
        for task in taskStore.tasks { await notificationService.sync(task: task) }
        for event in calendarStore.events { await notificationService.sync(event: event) }
    }
}
