import UIKit

@MainActor protocol HapticService {
    func completion()
    func action()
    func deletion()
}

@MainActor struct SystemHapticService: HapticService {
    var isEnabled: @MainActor () -> Bool = { true }
    var completionFeedback: @MainActor () -> Void = { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    var actionFeedback: @MainActor () -> Void = { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    var deletionFeedback: @MainActor () -> Void = { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    func completion() { if isEnabled() { completionFeedback() } }
    func action() { if isEnabled() { actionFeedback() } }
    func deletion() { if isEnabled() { deletionFeedback() } }
}
