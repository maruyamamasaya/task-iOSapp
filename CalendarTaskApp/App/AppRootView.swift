import SwiftUI

enum AppRoute: Hashable { case today, calendar, tasks, settings }

struct AppRootView: View {
    let dependencies: AppDependencies
    @ObservedObject private var settings: SettingsStore
    @State private var selectedRoute: AppRoute
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _settings = ObservedObject(wrappedValue: dependencies.settingsStore)
        _selectedRoute = State(initialValue: Self.route(for: dependencies.settingsStore.initialTab))
    }
    var body: some View {
        TabView(selection: $selectedRoute) {
            NavigationStack { HomeView(viewModel: HomeViewModel(taskStore: dependencies.taskStore, calendarStore: dependencies.calendarStore, dailyNoteStore: dependencies.dailyNoteStore, taskCompletionStore: dependencies.taskCompletionStore, dateProvider: dependencies.dateProvider, settingsStore: dependencies.settingsStore, hapticService: dependencies.hapticService)) }
                .tabItem { Label("今日", systemImage: "book.pages") }
                .tag(AppRoute.today)
            NavigationStack { CalendarView(viewModel: CalendarViewModel(taskStore: dependencies.taskStore, calendarStore: dependencies.calendarStore, dailyNoteStore: dependencies.dailyNoteStore, taskCompletionStore: dependencies.taskCompletionStore, dateProvider: dependencies.dateProvider, settingsStore: dependencies.settingsStore, hapticService: dependencies.hapticService)) }
                .tabItem { Label("カレンダー", systemImage: "calendar") }
                .tag(AppRoute.calendar)
            NavigationStack { TaskListView(viewModel: TaskListViewModel(store: dependencies.taskStore, completionStore: dependencies.taskCompletionStore, projectStore: dependencies.projectStore, settingsStore: dependencies.settingsStore, hapticService: dependencies.hapticService)) }
                .tabItem { Label("タスク", systemImage: "checklist") }
                .tag(AppRoute.tasks)
            NavigationStack { SettingsView(viewModel: SettingsViewModel(store: dependencies.settingsStore, notificationService: dependencies.notificationService), backupService: dependencies.backupService) }
                .tabItem { Label("設定", systemImage: "gearshape") }
                .tag(AppRoute.settings)
        }
        .environmentObject(dependencies.projectStore)
        .environmentObject(dependencies.settingsStore)
        .preferredColorScheme(colorScheme)
        .task { await dependencies.projectStore.load() }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "calendartaskapp" else { return }
            switch url.host?.lowercased() { case "today": selectedRoute = .today; case "calendar": selectedRoute = .calendar; case "tasks": selectedRoute = .tasks; default: break }
        }
    }
    private var colorScheme: ColorScheme? { switch settings.appearance { case .system: nil; case .light: .light; case .dark: .dark } }
    static func route(for tab: InitialAppTab) -> AppRoute { switch tab { case .today: .today; case .calendar: .calendar; case .tasks: .tasks } }
}
