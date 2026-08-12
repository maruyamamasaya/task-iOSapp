import Foundation
import Combine

@MainActor final class SettingsViewModel: ObservableObject {
    @Published var useSystemAppearance: Bool
    private let store: SettingsStore
    init(store: SettingsStore) { self.store = store; useSystemAppearance = store.useSystemAppearance }
    func updateAppearance() { store.useSystemAppearance = useSystemAppearance }
}
