import SwiftUI

struct AppRootView: View {
    let dependencies: AppDependencies
    var body: some View {
        TabView {
            NavigationStack { HomeView(viewModel: HomeViewModel(taskStore: dependencies.taskStore, calendarStore: dependencies.calendarStore, dateProvider: dependencies.dateProvider)) }
                .tabItem { Label("ホーム", systemImage: "house") }
            NavigationStack { CalendarView(viewModel: CalendarViewModel(taskStore: dependencies.taskStore, calendarStore: dependencies.calendarStore, dateProvider: dependencies.dateProvider)) }
                .tabItem { Label("カレンダー", systemImage: "calendar") }
            NavigationStack { TaskListView(viewModel: TaskListViewModel(store: dependencies.taskStore)) }
                .tabItem { Label("タスク", systemImage: "checklist") }
            NavigationStack { SettingsView(viewModel: SettingsViewModel(store: dependencies.settingsStore)) }
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
