import SwiftUI
import UserNotifications
import Combine

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let content = response.notification.request.content
        if let target = NotificationItemTarget(identifier: content.userInfo["itemTarget"] as? String ?? response.notification.request.identifier) {
            await MainActor.run { NotificationItemRouter.shared.request = target }
            return
        }
        guard let id = response.notification.request.content.userInfo["dailyBriefID"] as? String,
              let bridge = response.notification.request.content.userInfo["bridgeID"] as? String else { return }
        await MainActor.run { BriefPlaybackRouter.shared.open(briefID: id, bridgeID: bridge) }
    }
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound, .badge]
    }
}

@main struct CalendarTaskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dependencies = AppDependencies.live()
    var body: some Scene { WindowGroup { AppRootView(dependencies: dependencies) } }
}

@MainActor final class NotificationItemRouter: ObservableObject {
    static let shared = NotificationItemRouter()
    @Published var request: NotificationItemTarget?
}
