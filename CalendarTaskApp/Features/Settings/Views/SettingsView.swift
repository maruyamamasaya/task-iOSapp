import SwiftUI

struct SettingsView: View {
    @StateObject var viewModel: SettingsViewModel
    @ObservedObject var backupService: BackupService
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section("設定") {
                NavigationLink("一般") { GeneralSettingsView() }
                NavigationLink("カレンダー") { CalendarSettingsView() }
                NavigationLink("タスク") { TaskSettingsView() }
                NavigationLink("予定") { EventSettingsView() }
                NavigationLink("Quick Add") { QuickAddSettingsView() }
                NavigationLink("通知") { NotificationSettingsView(viewModel: viewModel) }
                NavigationLink("外観") { AppearanceSettingsView() }
            }
            Section("整理") {
                NavigationLink("プロジェクト") { ProjectManagementView() }
                LabeledContent("タグ", value: "今後対応").foregroundStyle(.secondary)
            }
            Section("情報") {
                NavigationLink("データ") { DataSettingsView(service: backupService) }
                NavigationLink("Widget") { WidgetSettingsView() }
                NavigationLink("このアプリについて") { AboutView() }
            }
        }.themedScreen().navigationTitle("設定").task { await viewModel.loadNotificationStatus() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await viewModel.loadNotificationStatus() } } }
    }
}
