import Foundation
import Combine

@MainActor final class SettingsViewModel: ObservableObject {
    @Published private(set) var notificationStatus = NotificationPermissionStatus.notDetermined
    private let store: SettingsStore
    private let notificationService: any NotificationService
    init(store: SettingsStore, notificationService: any NotificationService = NoopNotificationService()) {
        self.store = store; self.notificationService = notificationService
    }
    func loadNotificationStatus() async { notificationStatus = await notificationService.authorizationStatus() }
    func requestNotificationPermission() async {
        _ = await notificationService.requestAuthorization(); await loadNotificationStatus()
    }
}
