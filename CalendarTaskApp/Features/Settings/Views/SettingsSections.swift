import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View { Form {
        Section("起動") { Picker("初期タブ", selection: $settings.initialTab) { ForEach(InitialAppTab.allCases) { Text($0.rawValue).tag($0) } } }
        Section("表示と操作") {
            Toggle("今日に完了済みタスクを表示", isOn: $settings.showCompletedTasksToday)
            Toggle("完了済みタスクを初期表示", isOn: $settings.showCompletedTaskListInitially)
            Toggle("Haptic Feedback", isOn: $settings.hapticFeedbackEnabled)
        }
    }.navigationTitle("一般") }
}

struct CalendarSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View { Form {
        Section("週") { Picker("週の開始", selection: $settings.weekStartDay) { ForEach(WeekStartDay.allCases) { Text($0.rawValue).tag($0) } } }
        Section("初期表示") { Picker("表示", selection: $settings.initialCalendarMode) { ForEach(InitialCalendarMode.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented) }
        Section("表示") { Toggle("今日を強調", isOn: $settings.highlightToday); Toggle("Project色ドット", isOn: $settings.showProjectColorDots) }
    }.navigationTitle("カレンダー") }
}

struct TaskSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View { Form {
        Section("新規タスク") {
            Picker("優先度", selection: $settings.defaultTaskPriority) { ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) } }
            Toggle("終日として作成", isOn: $settings.newTasksAreAllDay)
        }
        Section("一覧") {
            Toggle("完了タスクを下へ移動", isOn: $settings.completedTasksAtBottom)
            Picker("並び替え", selection: $settings.defaultTaskSort) { ForEach(SettingsTaskSort.allCases) { Text($0.rawValue).tag($0) } }
            Picker("初期分類", selection: $settings.initialTaskSection) { ForEach(SettingsTaskSection.allCases) { Text($0.rawValue).tag($0) } }
        }
    }.navigationTitle("タスク") }
}

struct EventSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View { Form {
        Section("新規予定") {
            Picker("開始時刻", selection: $settings.defaultEventStartHour) { ForEach(0..<24, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) } }
            Picker("所要時間", selection: $settings.defaultEventDurationMinutes) { ForEach([15, 30, 45, 60, 90, 120], id: \.self) { Text("\($0)分").tag($0) } }
        }
    }.navigationTitle("予定") }
}

struct QuickAddSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View { Form {
        Section("入力") { Picker("デフォルト種類", selection: $settings.quickAddDefaultType) { ForEach(QuickAddDefaultType.allCases) { Text($0.rawValue).tag($0) } } }
        Section("解析後") {
            Toggle("解析後すぐ保存", isOn: $settings.quickAddSaveImmediately)
            Toggle("解析結果を必ず確認", isOn: $settings.quickAddAlwaysPreview)
            Text("確認が有効な場合はPreviewを優先します。").font(.caption).foregroundStyle(.secondary)
        }
    }.navigationTitle("Quick Add") }
}

struct NotificationSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openURL) private var openURL
    var body: some View { Form {
        Section("権限") {
            LabeledContent("状態", value: viewModel.notificationStatus.rawValue)
            if viewModel.notificationStatus == .notDetermined { Button("通知を許可") { Task { await viewModel.requestNotificationPermission() } } }
            Button("iOS設定を開く") { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }
        }
        Section("新規項目のデフォルト") { Picker("通知", selection: $settings.defaultReminder) { ForEach(DefaultReminderOption.allCases) { Text($0.rawValue).tag($0) } } }
    }.navigationTitle("通知").task { await viewModel.loadNotificationStatus() } }
}

struct AppearanceSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("明るさ").font(.headline)
                    Picker("外観", selection: $settings.appearance) { ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("手帳テーマ").font(.headline)
                    ForEach(AppTheme.allCases) { theme in
                        Button { settings.theme = theme } label: { ThemePreviewCard(theme: theme, isSelected: settings.theme == theme) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(theme.rawValue)、\(theme.subtitle)")
                            .accessibilityAddTraits(settings.theme == theme ? .isSelected : [])
                    }
                }
            }.padding(20)
        }.themedScreen().navigationTitle("外観")
    }
}

private struct ThemePreviewCard: View {
    let theme: AppTheme
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        ZStack {
            AppThemeBackground(theme: theme)
            HStack(spacing: 14) {
                Image(systemName: theme.symbol).font(.title2).foregroundStyle(theme.accent)
                    .frame(width: 42, height: 42).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.rawValue).font(.headline)
                    Text(theme.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.title3).foregroundStyle(isSelected ? theme.accent : .secondary)
            }
            .padding(16)
            .background(theme.surfaceColor(for: colorScheme).opacity(theme.surfaceOpacity), in: RoundedRectangle(cornerRadius: theme.cornerRadius, style: .continuous))
            .padding(7)
        }
        .frame(minHeight: 82)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isSelected ? theme.accent : Color.secondary.opacity(0.16), lineWidth: isSelected ? 2 : 0.7) }
        .shadow(color: isSelected ? theme.accent.opacity(0.13) : .black.opacity(0.05), radius: isSelected ? 12 : 6, y: 4)
    }
}

struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct DataSettingsView: View {
    @ObservedObject var service: BackupService
    @EnvironmentObject private var settings: SettingsStore
    @State private var document: BackupJSONDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingBackup: AppBackup?
    @State private var confirmsRestore = false
    @State private var message: String?
    @State private var exportedAt = Date.now
    var body: some View { List {
        Section("データ概要") {
            LabeledContent("タスク", value: "\(service.summary.tasks)件"); LabeledContent("予定", value: "\(service.summary.events)件")
            LabeledContent("メモ", value: "\(service.summary.notes)件"); LabeledContent("Project", value: "\(service.summary.projects)件")
            LabeledContent("完了履歴", value: "\(service.summary.completions)件")
        }
        Section("バックアップ") {
            Button { exportBackup() } label: { Label("JSONを書き出す", systemImage: "square.and.arrow.up") }
            Button { isImporting = true } label: { Label("JSONから復元", systemImage: "square.and.arrow.down") }
            LabeledContent("最終バックアップ", value: settings.lastBackupDate?.formatted(date: .abbreviated, time: .shortened) ?? "なし")
        }
        Section("プライバシー") { Text("バックアップには予定・タスク・メモの内容が含まれます。共有先と保管場所にご注意ください。").font(.subheadline).foregroundStyle(.secondary) }
    }
    .navigationTitle("データ").task { try? service.refreshSummary() }
    .fileExporter(isPresented: $isExporting, document: document, contentType: .json, defaultFilename: filename) { result in
        if case .success = result { service.markBackupExported(at: exportedAt); message = "バックアップを書き出しました。" }
        else if case .failure(let error) = result { message = error.localizedDescription }
    }
    .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
        do {
            let url = try result.get(), accessed = url.startAccessingSecurityScopedResource(); defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            pendingBackup = try service.decodeAndValidate(Data(contentsOf: url)); confirmsRestore = true
        } catch { message = error.localizedDescription }
    }
    .confirmationDialog("現在のデータを置き換えますか？", isPresented: $confirmsRestore, titleVisibility: .visible) {
        Button("置き換えて復元", role: .destructive) { guard let backup = pendingBackup else { return }; Task { do { try await service.restoreReplacing(with: backup); message = "復元しました。" } catch { message = error.localizedDescription } } }
        Button("キャンセル", role: .cancel) { pendingBackup = nil }
    } message: { Text("現在のデータを削除し、バックアップの内容へ置き換えます。この操作は元に戻せません。") }
    .alert("データ", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("OK", role: .cancel) {} } message: { Text(message ?? "") }
    }
    private var filename: String { "CalendarTaskApp_Backup_\(exportedAt.formatted(.iso8601.year().month().day().dateSeparator(.dash)))" }
    private func exportBackup() {
        do { exportedAt = .now; document = BackupJSONDocument(data: try service.exportData(now: exportedAt)); isExporting = true }
        catch { message = error.localizedDescription }
    }
}

struct WidgetSettingsView: View {
    private var appGroupAvailable: Bool {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String else { return false }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) != nil
    }
    var body: some View { Form {
        Section("更新") { Text("タスク・予定・完了状態を変更すると、WidgetのTimelineを自動更新します。").font(.subheadline).foregroundStyle(.secondary) }
        Section("診断") { LabeledContent("共有データ", value: appGroupAvailable ? "利用可能" : "要確認") }
    }.navigationTitle("Widget") }
}

struct AboutView: View {
    private var name: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "" }
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—" }
    private var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—" }
    var body: some View { Form { Section { LabeledContent("アプリ", value: name); LabeledContent("バージョン", value: version); LabeledContent("Build", value: build) } }.navigationTitle("このアプリについて") }
}
