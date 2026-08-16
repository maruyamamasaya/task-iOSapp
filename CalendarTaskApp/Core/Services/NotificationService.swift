import Foundation
import UserNotifications

enum NotificationPermissionStatus: String, Sendable {
    case notDetermined = "未設定", denied = "拒否", authorized = "許可"
}

protocol NotificationService: Sendable {
    func authorizationStatus() async -> NotificationPermissionStatus
    func requestAuthorization() async -> Bool
    func sync(task: TaskItem) async
    func sync(event: CalendarEvent) async
    func removeTaskNotification(id: UUID) async
    func removeEventNotification(id: UUID) async
    func removeTaskOccurrenceNotification(taskID: UUID, occurrenceDate: Date) async
}

final class UserNotificationService: NotificationService, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let now: @Sendable () -> Date
    init(center: UNUserNotificationCenter = .current(), now: @escaping @Sendable () -> Date = { .now }) {
        self.center = center; self.now = now
    }
    func authorizationStatus() async -> NotificationPermissionStatus {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .authorized
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
    func sync(task: TaskItem) async {
        await removeSeries(prefix: Self.taskIdentifier(task.id))
        guard !task.isCompleted, let reminder = task.reminderDate, await canSchedule() else { return }
        if let rule = task.recurrenceRule, let anchor = task.dueDate ?? task.startDate,
           let pair = nextReminder(anchor: anchor, reminder: reminder, rule: rule) {
            await schedule(identifier: Self.taskOccurrenceIdentifier(task.id, pair.occurrence), title: task.title, body: "タスクの時間です", date: pair.reminder)
        } else if reminder > now() {
            await schedule(identifier: Self.taskIdentifier(task.id), title: task.title, body: "タスクの時間です", date: reminder)
        }
    }
    func sync(event: CalendarEvent) async {
        await removeSeries(prefix: Self.eventIdentifier(event.id))
        guard let reminder = event.reminderDate, await canSchedule() else { return }
        if let rule = event.recurrenceRule, let pair = nextReminder(anchor: event.startDate, reminder: reminder, rule: rule) {
            await schedule(identifier: Self.eventOccurrenceIdentifier(event.id, pair.occurrence), title: event.title, body: "予定の時間です", date: pair.reminder)
        } else if reminder > now() {
            await schedule(identifier: Self.eventIdentifier(event.id), title: event.title, body: "予定の時間です", date: reminder)
        }
    }
    func removeTaskNotification(id: UUID) async { await removeSeries(prefix: Self.taskIdentifier(id)) }
    func removeEventNotification(id: UUID) async { await removeSeries(prefix: Self.eventIdentifier(id)) }
    func removeTaskOccurrenceNotification(taskID: UUID, occurrenceDate: Date) async { remove(Self.taskOccurrenceIdentifier(taskID, occurrenceDate)) }
    static func taskIdentifier(_ id: UUID) -> String { "task-\(id.uuidString.lowercased())" }
    static func eventIdentifier(_ id: UUID) -> String { "event-\(id.uuidString.lowercased())" }
    static func taskOccurrenceIdentifier(_ id: UUID, _ date: Date) -> String { "\(taskIdentifier(id))-\(dayStamp(date))" }
    static func eventOccurrenceIdentifier(_ id: UUID, _ date: Date) -> String { "\(eventIdentifier(id))-\(dayStamp(date))" }
    private static func dayStamp(_ date: Date) -> Int { Int(Calendar.current.startOfDay(for: date).timeIntervalSince1970) }

    private func canSchedule() async -> Bool {
        switch await authorizationStatus() { case .authorized: true; case .denied: false; case .notDetermined: await requestAuthorization() }
    }
    private func schedule(identifier: String, title: String, body: String, date: Date) async {
        let content = UNMutableNotificationContent(); content.title = title; content.body = body; content.sound = .default
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try? await center.add(request)
    }
    private func nextReminder(anchor: Date, reminder: Date, rule: RecurrenceRule) -> (occurrence: Date, reminder: Date)? {
        let offset = reminder.timeIntervalSince(anchor), calculator = RecurrenceCalculator()
        var reference = now().addingTimeInterval(-offset)
        for _ in 0..<2 {
            guard let occurrence = calculator.nextOccurrence(anchor: anchor, rule: rule, after: reference) else { return nil }
            let date = occurrence.addingTimeInterval(offset)
            if date > now() { return (occurrence, date) }
            reference = occurrence.addingTimeInterval(1)
        }
        return nil
    }
    private func removeSeries(prefix: String) async {
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0 == prefix || $0.hasPrefix(prefix + "-") }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let delivered = await center.deliveredNotifications().map { $0.request.identifier }.filter { $0 == prefix || $0.hasPrefix(prefix + "-") }
        center.removeDeliveredNotifications(withIdentifiers: delivered)
    }
    private func remove(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

struct NoopNotificationService: NotificationService {
    func authorizationStatus() async -> NotificationPermissionStatus { .notDetermined }
    func requestAuthorization() async -> Bool { false }
    func sync(task: TaskItem) async {}
    func sync(event: CalendarEvent) async {}
    func removeTaskNotification(id: UUID) async {}
    func removeEventNotification(id: UUID) async {}
    func removeTaskOccurrenceNotification(taskID: UUID, occurrenceDate: Date) async {}
}
