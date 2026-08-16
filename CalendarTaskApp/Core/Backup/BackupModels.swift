import Foundation

struct BackupTask: Codable, Equatable { let value: TaskItem }
struct BackupCalendarEvent: Codable, Equatable { let value: CalendarEvent }
struct BackupDailyNote: Codable, Equatable { let value: DailyNote }
struct BackupProject: Codable, Equatable { let value: Project }
struct BackupTaskCompletion: Codable, Equatable { let value: TaskCompletion }

struct BackupSettings: Codable, Equatable {
    let initialTab: String; let showCompletedTasksToday: Bool; let showCompletedTaskListInitially: Bool; let hapticFeedbackEnabled: Bool
    let weekStartDay: String; let initialCalendarMode: String; let highlightToday: Bool; let showProjectColorDots: Bool
    let defaultTaskPriority: String; let newTasksAreAllDay: Bool; let completedTasksAtBottom: Bool
    let defaultTaskSort: String; let initialTaskSection: String; let defaultEventStartHour: Int; let defaultEventDurationMinutes: Int
    let quickAddDefaultType: String; let quickAddSaveImmediately: Bool; let quickAddAlwaysPreview: Bool
    let defaultReminder: String; let appearance: String
}

struct AppBackup: Codable, Equatable {
    static let currentSchemaVersion = 1
    let schemaVersion: Int
    let exportedAt: Date
    let appVersion: String
    let tasks: [BackupTask]
    let events: [BackupCalendarEvent]
    let dailyNotes: [BackupDailyNote]
    let projects: [BackupProject]
    let taskCompletions: [BackupTaskCompletion]
    let settings: BackupSettings
}

struct BackupDataSummary: Equatable {
    var tasks = 0, events = 0, notes = 0, projects = 0, completions = 0
}

enum BackupError: LocalizedError, Equatable {
    case corruptedFile, unsupportedSchema(Int), duplicateID(String), missingTask(UUID), missingProject(UUID), invalidSettings(String)
    var errorDescription: String? {
        switch self {
        case .corruptedFile: "バックアップファイルを読み込めません。"
        case .unsupportedSchema(let value): "未対応のschemaVersionです: \(value)"
        case .duplicateID(let type): "\(type)に重複したUUIDがあります。"
        case .missingTask: "完了履歴が存在しないタスクを参照しています。"
        case .missingProject: "存在しないProjectへの参照があります。"
        case .invalidSettings(let key): "設定値が不正です: \(key)"
        }
    }
}

extension SettingsStore {
    func backupSettings() -> BackupSettings {
        BackupSettings(initialTab: initialTab.rawValue, showCompletedTasksToday: showCompletedTasksToday,
                       showCompletedTaskListInitially: showCompletedTaskListInitially, hapticFeedbackEnabled: hapticFeedbackEnabled,
                       weekStartDay: weekStartDay.rawValue, initialCalendarMode: initialCalendarMode.rawValue,
                       highlightToday: highlightToday, showProjectColorDots: showProjectColorDots,
                       defaultTaskPriority: defaultTaskPriority.rawValue, newTasksAreAllDay: newTasksAreAllDay,
                       completedTasksAtBottom: completedTasksAtBottom, defaultTaskSort: defaultTaskSort.rawValue,
                       initialTaskSection: initialTaskSection.rawValue, defaultEventStartHour: defaultEventStartHour,
                       defaultEventDurationMinutes: defaultEventDurationMinutes, quickAddDefaultType: quickAddDefaultType.rawValue,
                       quickAddSaveImmediately: quickAddSaveImmediately, quickAddAlwaysPreview: quickAddAlwaysPreview,
                       defaultReminder: defaultReminder.rawValue, appearance: appearance.rawValue)
    }
    func validate(_ value: BackupSettings) throws {
        guard InitialAppTab(rawValue: value.initialTab) != nil else { throw BackupError.invalidSettings("initialTab") }
        guard WeekStartDay(rawValue: value.weekStartDay) != nil else { throw BackupError.invalidSettings("weekStartDay") }
        guard InitialCalendarMode(rawValue: value.initialCalendarMode) != nil else { throw BackupError.invalidSettings("initialCalendarMode") }
        guard TaskPriority(rawValue: value.defaultTaskPriority) != nil else { throw BackupError.invalidSettings("defaultTaskPriority") }
        guard SettingsTaskSort(rawValue: value.defaultTaskSort) != nil else { throw BackupError.invalidSettings("defaultTaskSort") }
        guard SettingsTaskSection(rawValue: value.initialTaskSection) != nil else { throw BackupError.invalidSettings("initialTaskSection") }
        guard QuickAddDefaultType(rawValue: value.quickAddDefaultType) != nil else { throw BackupError.invalidSettings("quickAddDefaultType") }
        guard DefaultReminderOption(rawValue: value.defaultReminder) != nil else { throw BackupError.invalidSettings("defaultReminder") }
        guard AppAppearance(rawValue: value.appearance) != nil, (0..<24).contains(value.defaultEventStartHour), value.defaultEventDurationMinutes > 0 else { throw BackupError.invalidSettings("appearance/event") }
    }
    func restore(_ value: BackupSettings) throws {
        try validate(value)
        initialTab = InitialAppTab(rawValue: value.initialTab)!; showCompletedTasksToday = value.showCompletedTasksToday
        showCompletedTaskListInitially = value.showCompletedTaskListInitially; hapticFeedbackEnabled = value.hapticFeedbackEnabled
        weekStartDay = WeekStartDay(rawValue: value.weekStartDay)!; initialCalendarMode = InitialCalendarMode(rawValue: value.initialCalendarMode)!
        highlightToday = value.highlightToday; showProjectColorDots = value.showProjectColorDots
        defaultTaskPriority = TaskPriority(rawValue: value.defaultTaskPriority)!; newTasksAreAllDay = value.newTasksAreAllDay
        completedTasksAtBottom = value.completedTasksAtBottom; defaultTaskSort = SettingsTaskSort(rawValue: value.defaultTaskSort)!
        initialTaskSection = SettingsTaskSection(rawValue: value.initialTaskSection)!; defaultEventStartHour = value.defaultEventStartHour
        defaultEventDurationMinutes = value.defaultEventDurationMinutes; quickAddDefaultType = QuickAddDefaultType(rawValue: value.quickAddDefaultType)!
        quickAddSaveImmediately = value.quickAddSaveImmediately; quickAddAlwaysPreview = value.quickAddAlwaysPreview
        defaultReminder = DefaultReminderOption(rawValue: value.defaultReminder)!; appearance = AppAppearance(rawValue: value.appearance)!
    }
}
