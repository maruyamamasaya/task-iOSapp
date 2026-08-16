import Foundation
import Combine

enum InitialAppTab: String, CaseIterable, Identifiable { case today = "今日", calendar = "カレンダー", tasks = "タスク"; var id: Self { self } }
enum WeekStartDay: String, CaseIterable, Identifiable { case monday = "月曜", sunday = "日曜"; var id: Self { self }; var calendarWeekday: Int { self == .monday ? 2 : 1 } }
enum InitialCalendarMode: String, CaseIterable, Identifiable { case month = "月", week = "週"; var id: Self { self } }
enum SettingsTaskSort: String, CaseIterable, Identifiable { case date = "日付順", priority = "優先度順", createdAt = "作成日時順"; var id: Self { self } }
enum SettingsTaskSection: String, CaseIterable, Identifiable { case inbox = "Inbox", today = "今日", scheduled = "期限あり", noDeadline = "期限なし", completed = "完了済み"; var id: Self { self } }
enum QuickAddDefaultType: String, CaseIterable, Identifiable { case task = "タスク", event = "予定"; var id: Self { self } }
enum DefaultReminderOption: String, CaseIterable, Identifiable {
    case none = "なし", atTime = "予定時刻", tenMinutes = "10分前", thirtyMinutes = "30分前", oneHour = "1時間前"
    var id: Self { self }
    func date(relativeTo date: Date) -> Date? {
        switch self { case .none: nil; case .atTime: date; case .tenMinutes: date.addingTimeInterval(-600); case .thirtyMinutes: date.addingTimeInterval(-1800); case .oneHour: date.addingTimeInterval(-3600) }
    }
}
enum AppAppearance: String, CaseIterable, Identifiable { case system = "システム", light = "ライト", dark = "ダーク"; var id: Self { self } }
struct TaskCreationDefaults { let priority: TaskPriority; let isAllDay: Bool; let reminderDate: Date? }
struct EventCreationDefaults { let startDate: Date; let endDate: Date; let reminderDate: Date? }

@MainActor final class SettingsStore: ObservableObject {
    private enum Key {
        static let initialTab = "settings.initialTab", showCompletedToday = "settings.showCompletedToday", showCompletedTaskList = "settings.showCompletedTaskList"
        static let haptics = "settings.haptics", weekStart = "settings.weekStart", calendarMode = "settings.calendarMode"
        static let highlightToday = "settings.highlightToday", projectDots = "settings.projectDots", defaultPriority = "settings.defaultPriority"
        static let taskAllDay = "settings.taskAllDay", completedAtBottom = "settings.completedAtBottom", taskSort = "settings.taskSort", taskSection = "settings.taskSection"
        static let eventHour = "settings.eventHour", eventDuration = "settings.eventDuration", quickType = "settings.quickType"
        static let quickSave = "settings.quickSave", quickPreview = "settings.quickPreview", reminder = "settings.reminder", appearance = "settings.appearance"
        static let lastBackupDate = "settings.lastBackupDate"
    }
    private let defaults: UserDefaults
    private var isLoading = true
    @Published var initialTab: InitialAppTab { didSet { save(initialTab.rawValue, Key.initialTab) } }
    @Published var showCompletedTasksToday: Bool { didSet { save(showCompletedTasksToday, Key.showCompletedToday) } }
    @Published var showCompletedTaskListInitially: Bool { didSet { save(showCompletedTaskListInitially, Key.showCompletedTaskList) } }
    @Published var hapticFeedbackEnabled: Bool { didSet { save(hapticFeedbackEnabled, Key.haptics) } }
    @Published var weekStartDay: WeekStartDay { didSet { save(weekStartDay.rawValue, Key.weekStart) } }
    @Published var initialCalendarMode: InitialCalendarMode { didSet { save(initialCalendarMode.rawValue, Key.calendarMode) } }
    @Published var highlightToday: Bool { didSet { save(highlightToday, Key.highlightToday) } }
    @Published var showProjectColorDots: Bool { didSet { save(showProjectColorDots, Key.projectDots) } }
    @Published var defaultTaskPriority: TaskPriority { didSet { save(defaultTaskPriority.rawValue, Key.defaultPriority) } }
    @Published var newTasksAreAllDay: Bool { didSet { save(newTasksAreAllDay, Key.taskAllDay) } }
    @Published var completedTasksAtBottom: Bool { didSet { save(completedTasksAtBottom, Key.completedAtBottom) } }
    @Published var defaultTaskSort: SettingsTaskSort { didSet { save(defaultTaskSort.rawValue, Key.taskSort) } }
    @Published var initialTaskSection: SettingsTaskSection { didSet { save(initialTaskSection.rawValue, Key.taskSection) } }
    @Published var defaultEventStartHour: Int { didSet { save(defaultEventStartHour, Key.eventHour) } }
    @Published var defaultEventDurationMinutes: Int { didSet { save(defaultEventDurationMinutes, Key.eventDuration) } }
    @Published var quickAddDefaultType: QuickAddDefaultType { didSet { save(quickAddDefaultType.rawValue, Key.quickType) } }
    @Published var quickAddSaveImmediately: Bool { didSet { save(quickAddSaveImmediately, Key.quickSave) } }
    @Published var quickAddAlwaysPreview: Bool { didSet { save(quickAddAlwaysPreview, Key.quickPreview) } }
    @Published var defaultReminder: DefaultReminderOption { didSet { save(defaultReminder.rawValue, Key.reminder) } }
    @Published var appearance: AppAppearance { didSet { save(appearance.rawValue, Key.appearance) } }
    @Published var lastBackupDate: Date? { didSet { if !isLoading { defaults.set(lastBackupDate, forKey: Key.lastBackupDate) } } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        initialTab = Self.value(defaults, Key.initialTab, .today); showCompletedTasksToday = Self.bool(defaults, Key.showCompletedToday, true)
        showCompletedTaskListInitially = Self.bool(defaults, Key.showCompletedTaskList, false); hapticFeedbackEnabled = Self.bool(defaults, Key.haptics, true)
        weekStartDay = Self.value(defaults, Key.weekStart, .monday); initialCalendarMode = Self.value(defaults, Key.calendarMode, .month)
        highlightToday = Self.bool(defaults, Key.highlightToday, true); showProjectColorDots = Self.bool(defaults, Key.projectDots, true)
        defaultTaskPriority = Self.value(defaults, Key.defaultPriority, .normal); newTasksAreAllDay = Self.bool(defaults, Key.taskAllDay, true)
        completedTasksAtBottom = Self.bool(defaults, Key.completedAtBottom, true); defaultTaskSort = Self.value(defaults, Key.taskSort, .date)
        initialTaskSection = Self.value(defaults, Key.taskSection, .today)
        defaultEventStartHour = defaults.object(forKey: Key.eventHour) == nil ? 10 : defaults.integer(forKey: Key.eventHour)
        defaultEventDurationMinutes = defaults.object(forKey: Key.eventDuration) == nil ? 60 : defaults.integer(forKey: Key.eventDuration)
        quickAddDefaultType = Self.value(defaults, Key.quickType, .task); quickAddSaveImmediately = Self.bool(defaults, Key.quickSave, false)
        quickAddAlwaysPreview = Self.bool(defaults, Key.quickPreview, true); defaultReminder = Self.value(defaults, Key.reminder, .none)
        appearance = Self.value(defaults, Key.appearance, .system); lastBackupDate = defaults.object(forKey: Key.lastBackupDate) as? Date; isLoading = false
    }
    func taskCreationDefaults(referenceDate: Date) -> TaskCreationDefaults {
        TaskCreationDefaults(priority: defaultTaskPriority, isAllDay: newTasksAreAllDay, reminderDate: defaultReminder.date(relativeTo: referenceDate))
    }
    func eventCreationDefaults(referenceDate: Date, calendar: Calendar = .current) -> EventCreationDefaults {
        let day = calendar.startOfDay(for: referenceDate)
        let start = calendar.date(byAdding: .hour, value: defaultEventStartHour, to: day) ?? referenceDate
        let end = calendar.date(byAdding: .minute, value: defaultEventDurationMinutes, to: start) ?? start
        return EventCreationDefaults(startDate: start, endDate: end, reminderDate: defaultReminder.date(relativeTo: start))
    }
    private func save(_ value: Any, _ key: String) { if !isLoading { defaults.set(value, forKey: key) } }
    private static func bool(_ defaults: UserDefaults, _ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key) }
    private static func value<T: RawRepresentable>(_ defaults: UserDefaults, _ key: String, _ fallback: T) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else { return fallback }; return value
    }
}
