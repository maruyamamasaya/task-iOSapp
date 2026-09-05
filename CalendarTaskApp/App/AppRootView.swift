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
        Color(uiColor: UIColor { traits in
            UIColor(self.appearance(for: traits.userInterfaceStyle == .dark ? .dark : .light).accent)
        })
    }
    var cornerRadius: CGFloat { appearance(for: .light).surfaceRadius }
    var surfaceOpacity: Double { 1 }
    func surfaceColor(for scheme: ColorScheme) -> Color { appearance(for: scheme).surface }
    func baseColor(for scheme: ColorScheme) -> Color { appearance(for: scheme).background }

}

struct AppThemeBackground: View {
    let theme: AppTheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let palette = theme.appearance(for: colorScheme)
        ZStack {
            palette.background
            if !reduceTransparency {
                if theme == .sakura {
                    RadialGradient(colors: [palette.ornament.opacity(colorScheme == .dark ? 0.16 : 0.12), .clear],
                                   center: .topTrailing, startRadius: 0, endRadius: colorScheme == .dark ? 280 : 420)
                }
                Canvas { context, size in
                    let ink = palette.ornament
                    switch (theme, colorScheme) {
                    case (.classic, .light):
                        for y in stride(from: 28.0, through: size.height, by: 30) {
                            line(&context, from: CGPoint(x: 0, y: y), to: CGPoint(x: size.width, y: y), color: ink.opacity(0.13))
                        }
                        line(&context, from: CGPoint(x: 22, y: 0), to: CGPoint(x: 22, y: size.height), color: Color.red.opacity(0.10))
                    case (.classic, _):
                        // A restrained gold spine and inset cover frame, rather than luminous ruled paper.
                        for x in [9.0, 13.0] {
                            line(&context, from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: size.height), color: ink.opacity(0.27))
                        }
                        context.stroke(Path(roundedRect: CGRect(x: 20, y: 12, width: max(0, size.width - 32), height: max(0, size.height - 24)), cornerRadius: 5), with: .color(ink.opacity(0.12)), lineWidth: 0.7)
                    case (.sakura, .light):
                        petals(&context, size: size, color: ink.opacity(0.19), night: false)
                    case (.sakura, _):
                        context.fill(Path(ellipseIn: CGRect(x: size.width - 92, y: 28, width: 48, height: 48)), with: .color(Color.white.opacity(0.08)))
                        petals(&context, size: size, color: ink.opacity(0.25), night: true)
                    case (.linen, .light):
                        for x in stride(from: 0.0, through: size.width, by: 7) {
                            line(&context, from: CGPoint(x: x, y: 0), to: CGPoint(x: x + 2, y: size.height), color: ink.opacity(0.08), width: 0.5)
                        }
                        for y in stride(from: 0.0, through: size.height, by: 9) {
                            line(&context, from: CGPoint(x: 0, y: y), to: CGPoint(x: size.width, y: y + 1), color: Color.white.opacity(0.26), width: 0.5)
                        }
                    case (.linen, _):
                        for index in 0..<500 {
                            let x = CGFloat((index * 67) % 997) / 997 * size.width
                            let y = CGFloat((index * 113) % 991) / 991 * size.height
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 0.8)), with: .color(ink.opacity(0.075)))
                        }
                        var seam = Path()
                        seam.move(to: CGPoint(x: 11, y: 0)); seam.addLine(to: CGPoint(x: 11, y: size.height))
                        context.stroke(seam, with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
                    case (.midnight, .light):
                        for x in stride(from: 0.0, through: size.width, by: 28) {
                            line(&context, from: CGPoint(x: x, y: 0), to: CGPoint(x: x, y: size.height), color: ink.opacity(0.10), width: 0.5)
                        }
                        for y in stride(from: 0.0, through: size.height, by: 28) {
                            line(&context, from: CGPoint(x: 0, y: y), to: CGPoint(x: size.width, y: y), color: ink.opacity(0.10), width: 0.5)
                        }
                    case (.midnight, _):
                        for radius in [150.0, 230.0, 310.0] {
                            context.stroke(Path(ellipseIn: CGRect(x: size.width - radius, y: -radius, width: radius * 2, height: radius * 2)), with: .color(ink.opacity(0.085)), lineWidth: 0.5)
                        }
                        for index in 0..<40 {
                            let x = CGFloat((index * 83) % 379) / 379 * size.width
                            let y = CGFloat((index * 137) % 521) / 521 * size.height
                            context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(ink.opacity(0.30)))
                        }
                    case (.modern, .light):
                        context.fill(Path(ellipseIn: CGRect(x: size.width - 145, y: -95, width: 240, height: 240)), with: .color(ink.opacity(0.10)))
                        context.fill(Path(roundedRect: CGRect(x: -70, y: size.height * 0.75, width: 180, height: 180), cornerRadius: 40), with: .color(ink.opacity(0.055)))
                    case (.modern, _):
                        // Architectural edge lighting on charcoal; no decorative grain.
                        let rect = CGRect(x: size.width * 0.65, y: -50, width: size.width * 0.65, height: size.height * 0.5)
                        context.stroke(Path(roundedRect: rect, cornerRadius: 32), with: .color(ink.opacity(0.14)), lineWidth: 1)
                        line(&context, from: CGPoint(x: 0, y: size.height * 0.84), to: CGPoint(x: size.width * 0.32, y: size.height * 0.84), color: ink.opacity(0.12))
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func line(_ context: inout GraphicsContext, from: CGPoint, to: CGPoint, color: Color, width: CGFloat = 0.7) {
        var path = Path(); path.move(to: from); path.addLine(to: to)
        context.stroke(path, with: .color(color), lineWidth: width)
    }

    private func petals(_ context: inout GraphicsContext, size: CGSize, color: Color, night: Bool) {
        // Keep blossoms at the edges, away from titles and reading surfaces.
        for index in 0..<(night ? 14 : 22) {
            let right = index.isMultiple(of: 2)
            let x = right ? size.width - CGFloat(12 + (index * 17) % 52) : CGFloat((index * 13) % 36)
            let y = CGFloat((index * 97) % 701) / 701 * size.height
            var petal = Path()
            petal.move(to: CGPoint(x: x, y: y))
            petal.addQuadCurve(to: CGPoint(x: x + 9, y: y + 8), control: CGPoint(x: x + 12, y: y - 2))
            petal.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x - 3, y: y + 10))
            context.fill(petal, with: .color(color))
        }
    }
}

struct ThemedScreenModifier: ViewModifier {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    func body(content: Content) -> some View {
        let palette = settings.theme.appearance(for: colorScheme)
        content
            .fontDesign(settings.theme == .sakura ? .rounded : .default)
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
            .accentColor(palette.accent)
            .scrollContentBackground(.hidden)
            .background { AppThemeBackground(theme: settings.theme) }
    }
}

struct ThemedSurfaceModifier: ViewModifier {
    @EnvironmentObject private var settings: SettingsStore
    let padding: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(padding + (settings.theme.contentSpacing - 14) / 2)
            .background { ThemeSurface(theme: settings.theme) }
    }
}

extension View {
    func themedScreen() -> some View { modifier(ThemedScreenModifier()) }
    func themedSurface(padding: CGFloat = 16) -> some View { modifier(ThemedSurfaceModifier(padding: padding)) }
}
