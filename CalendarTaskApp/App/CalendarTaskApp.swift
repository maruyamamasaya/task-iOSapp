import SwiftUI

@main struct CalendarTaskApp: App {
    @StateObject private var dependencies = AppDependencies.live()
    var body: some Scene { WindowGroup { AppRootView(dependencies: dependencies) } }
}
