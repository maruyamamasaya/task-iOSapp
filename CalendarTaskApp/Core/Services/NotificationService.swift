import Foundation

// The SDK-independent seam for a future UserNotifications implementation.
protocol NotificationService: Sendable {
    func removeNotification(for id: UUID) async
}

struct NoopNotificationService: NotificationService {
    func removeNotification(for id: UUID) async {}
}
