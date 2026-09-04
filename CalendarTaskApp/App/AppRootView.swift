import SwiftUI

enum AppRoute: Hashable { case today, calendar, tasks, settings }

struct AppRootView: View {
    let dependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
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
        .tint(settings.theme.accent)
        .preferredColorScheme(colorScheme)
        .task {
            await dependencies.projectStore.load()
            await dependencies.rescheduleNotificationsIfAuthorized()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await dependencies.rescheduleNotificationsIfAuthorized() }
        }
        .onOpenURL { url in
            guard url.scheme?.lowercased() == "calendartaskapp" else { return }
            switch url.host?.lowercased() { case "today": selectedRoute = .today; case "calendar": selectedRoute = .calendar; case "tasks": selectedRoute = .tasks; default: break }
        }
    }
    private var colorScheme: ColorScheme? { switch settings.appearance { case .system: nil; case .light: .light; case .dark: .dark } }
    static func route(for tab: InitialAppTab) -> AppRoute { switch tab { case .today: .today; case .calendar: .calendar; case .tasks: .tasks } }
}

extension AppTheme {
    var subtitle: String {
        switch self { case .classic: "落ち着いた紙とブルーの罫線"; case .sakura: "淡いピンクと花びらのアクセント"; case .linen: "温かい生成りと繊維の風合い"; case .midnight: "深いネイビーの静かなグリッド"; case .modern: "余白を活かした都会的な幾何学" }
    }
    var symbol: String {
        switch self { case .classic: "book.closed"; case .sakura: "camera.macro"; case .linen: "leaf"; case .midnight: "moon.stars"; case .modern: "square.on.circle" }
    }
    var accent: Color {
        switch self { case .classic: Color(red: 0.22, green: 0.43, blue: 0.66); case .sakura: Color(red: 0.82, green: 0.35, blue: 0.48); case .linen: Color(red: 0.43, green: 0.49, blue: 0.30); case .midnight: Color(red: 0.42, green: 0.72, blue: 0.94); case .modern: Color(red: 0.39, green: 0.29, blue: 0.82) }
    }
    func baseColor(for scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.classic, .dark): Color(red: 0.10, green: 0.12, blue: 0.15); case (.classic, _): Color(red: 0.98, green: 0.97, blue: 0.92)
        case (.sakura, .dark): Color(red: 0.16, green: 0.10, blue: 0.13); case (.sakura, _): Color(red: 1.0, green: 0.95, blue: 0.96)
        case (.linen, .dark): Color(red: 0.13, green: 0.13, blue: 0.10); case (.linen, _): Color(red: 0.94, green: 0.91, blue: 0.82)
        case (.midnight, .dark): Color(red: 0.055, green: 0.075, blue: 0.13); case (.midnight, _): Color(red: 0.91, green: 0.93, blue: 0.97)
        case (.modern, .dark): Color(red: 0.09, green: 0.09, blue: 0.12); case (.modern, _): Color(red: 0.95, green: 0.95, blue: 0.98)
        @unknown default: Color(.systemBackground)
        }
    }
}

struct AppThemeBackground: View {
    let theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.baseColor(for: colorScheme)
                Canvas { context, size in
                    switch theme {
                    case .classic:
                        for y in stride(from: 34.0, through: size.height, by: 30) { context.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0)), with: .color(theme.accent.opacity(0.11)), lineWidth: 0.7) }
                    case .sakura:
                        for x in stride(from: 24.0, through: size.width, by: 78) { for y in stride(from: 28.0, through: size.height, by: 82) { let offset = Int(y / 82).isMultiple(of: 2) ? 0.0 : 24.0; context.fill(Path(ellipseIn: CGRect(x: x + offset, y: y, width: 7, height: 4)), with: .color(theme.accent.opacity(0.10))) } }
                    case .linen:
                        for x in stride(from: -size.height, through: size.width, by: 18) { var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + size.height, y: size.height)); context.stroke(path, with: .color(Color.brown.opacity(0.055)), lineWidth: 0.6) }
                    case .midnight:
                        for x in stride(from: 0.0, through: size.width, by: 28) { context.stroke(Path(CGRect(x: x, y: 0, width: 0, height: size.height)), with: .color(theme.accent.opacity(0.07)), lineWidth: 0.6) }
                        for y in stride(from: 0.0, through: size.height, by: 28) { context.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0)), with: .color(theme.accent.opacity(0.07)), lineWidth: 0.6) }
                    case .modern:
                        context.fill(Path(ellipseIn: CGRect(x: size.width * 0.64, y: -80, width: 210, height: 210)), with: .color(theme.accent.opacity(0.08)))
                        context.fill(Path(roundedRect: CGRect(x: -55, y: size.height * 0.68, width: 170, height: 170), cornerRadius: 42), with: .color(Color.cyan.opacity(0.055)))
                    }
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.ignoresSafeArea()
    }
}

struct ThemedScreenModifier: ViewModifier {
    @EnvironmentObject private var settings: SettingsStore
    func body(content: Content) -> some View { content.scrollContentBackground(.hidden).background { AppThemeBackground(theme: settings.theme) } }
}

extension View {
    func themedScreen() -> some View { modifier(ThemedScreenModifier()) }
}
