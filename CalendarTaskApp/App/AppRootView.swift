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
    var cornerRadius: CGFloat {
        switch self { case .classic: 8; case .sakura: 22; case .linen: 12; case .midnight: 14; case .modern: 24 }
    }
    var surfaceOpacity: Double {
        switch self { case .classic: 0.97; case .sakura: 0.96; case .linen: 0.97; case .midnight: 0.97; case .modern: 1.0 }
    }
    func surfaceColor(for scheme: ColorScheme) -> Color {
        switch (self, scheme) {
        case (.classic, .dark): Color(red: 0.16, green: 0.17, blue: 0.18); case (.classic, _): Color(red: 1, green: 0.995, blue: 0.96)
        case (.sakura, .dark): Color(red: 0.22, green: 0.14, blue: 0.17); case (.sakura, _): Color.white
        case (.linen, .dark): Color(red: 0.19, green: 0.18, blue: 0.14); case (.linen, _): Color(red: 0.985, green: 0.965, blue: 0.90)
        case (.midnight, .dark): Color(red: 0.09, green: 0.12, blue: 0.20); case (.midnight, _): Color(red: 0.97, green: 0.98, blue: 1)
        case (.modern, .dark): Color(red: 0.16, green: 0.15, blue: 0.20); case (.modern, _): Color.white
        @unknown default: Color(.secondarySystemBackground)
        }
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
                        var margin = Path(); margin.move(to: CGPoint(x: 22, y: 0)); margin.addLine(to: CGPoint(x: 22, y: size.height)); context.stroke(margin, with: .color(Color.red.opacity(0.09)), lineWidth: 1)
                        for y in stride(from: 22.0, through: size.height, by: 72) { context.fill(Path(ellipseIn: CGRect(x: 7, y: y, width: 6, height: 6)), with: .color(Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08))) }
                    case .sakura:
                        context.fill(Path(ellipseIn: CGRect(x: size.width - 155, y: -70, width: 230, height: 190)), with: .color(theme.accent.opacity(0.075)))
                        context.fill(Path(ellipseIn: CGRect(x: -90, y: size.height * 0.7, width: 190, height: 230)), with: .color(Color.orange.opacity(0.035)))
                        for x in stride(from: 24.0, through: size.width, by: 78) { for y in stride(from: 28.0, through: size.height, by: 82) { let offset = Int(y / 82).isMultiple(of: 2) ? 0.0 : 24.0; context.fill(Path(ellipseIn: CGRect(x: x + offset, y: y, width: 8, height: 4)), with: .color(theme.accent.opacity(0.11))) } }
                    case .linen:
                        for x in stride(from: 0.0, through: size.width, by: 7) { var path = Path(); path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + 2, y: size.height)); context.stroke(path, with: .color(Color.brown.opacity(0.035)), lineWidth: 0.55) }
                        for y in stride(from: 0.0, through: size.height, by: 9) { var path = Path(); path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y + 1)); context.stroke(path, with: .color(Color.white.opacity(0.10)), lineWidth: 0.5) }
                    case .midnight:
                        for x in stride(from: 0.0, through: size.width, by: 28) { context.stroke(Path(CGRect(x: x, y: 0, width: 0, height: size.height)), with: .color(theme.accent.opacity(0.07)), lineWidth: 0.6) }
                        for y in stride(from: 0.0, through: size.height, by: 28) { context.stroke(Path(CGRect(x: 0, y: y, width: size.width, height: 0)), with: .color(theme.accent.opacity(0.07)), lineWidth: 0.6) }
                        for index in 0..<34 { let x = CGFloat((index * 83) % 379) / 379 * size.width; let y = CGFloat((index * 137) % 521) / 521 * size.height; context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(theme.accent.opacity(0.22))) }
                    case .modern:
                        context.fill(Path(ellipseIn: CGRect(x: size.width * 0.64, y: -80, width: 210, height: 210)), with: .color(theme.accent.opacity(0.08)))
                        context.fill(Path(roundedRect: CGRect(x: -55, y: size.height * 0.68, width: 170, height: 170), cornerRadius: 42), with: .color(Color.cyan.opacity(0.055)))
                        var slash = Path(); slash.move(to: CGPoint(x: size.width * 0.72, y: 0)); slash.addLine(to: CGPoint(x: size.width, y: size.height * 0.18)); context.stroke(slash, with: .color(theme.accent.opacity(0.10)), lineWidth: 22)
                    }
                    for index in 0..<120 {
                        let x = CGFloat((index * 47) % 997) / 997 * size.width
                        let y = CGFloat((index * 89) % 991) / 991 * size.height
                        context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 0.8, height: 0.8)), with: .color(Color.primary.opacity(0.028)))
                    }
                }
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }.ignoresSafeArea()
    }
}

struct ThemedScreenModifier: ViewModifier {
    @EnvironmentObject private var settings: SettingsStore
    func body(content: Content) -> some View { content.fontDesign(settings.theme == .sakura ? .rounded : .default).scrollContentBackground(.hidden).background { AppThemeBackground(theme: settings.theme) } }
}

struct ThemedSurfaceModifier: ViewModifier {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding + (settings.theme.contentSpacing - 14) / 2)
            .background(settings.theme.surfaceColor(for: colorScheme).opacity(settings.theme.surfaceOpacity), in: RoundedRectangle(cornerRadius: settings.theme.cornerRadius, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: settings.theme.cornerRadius, style: .continuous).stroke(borderColor, lineWidth: settings.theme == .classic ? 0.8 : 0.55) }
            .shadow(color: shadowColor, radius: shadowRadius, y: shadowY)
    }
    private var borderColor: Color { settings.theme == .linen ? Color.brown.opacity(0.16) : settings.theme.accent.opacity(settings.theme == .midnight ? 0.18 : 0.11) }
    private var shadowColor: Color { settings.theme == .modern ? settings.theme.accent.opacity(0.10) : Color.black.opacity(colorScheme == .dark ? 0.18 : 0.07) }
    private var shadowRadius: CGFloat { settings.theme == .classic ? 2 : settings.theme == .modern ? 10 : settings.theme == .linen ? 2 : 6 }
    private var shadowY: CGFloat { settings.theme == .classic || settings.theme == .linen ? 1 : 3 }
}

extension View {
    func themedScreen() -> some View { modifier(ThemedScreenModifier()) }
    func themedSurface(padding: CGFloat = 16) -> some View { modifier(ThemedSurfaceModifier(padding: padding)) }
}
