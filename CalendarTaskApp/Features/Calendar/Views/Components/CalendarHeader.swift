import SwiftUI

struct CalendarHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: SettingsStore
    let month: Date
    var title: String? = nil
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: previous) { Image(systemName: "chevron.left") }
                .accessibilityLabel("前月")
            Text(title ?? month.formatted(.dateTime.year().month(.wide)))
                .font(settings.theme.headingFont(.title3, for: colorScheme))
                .tracking(settings.theme.appearance(for: colorScheme).headingTracking)
                .foregroundStyle(settings.theme.appearance(for: colorScheme).ink)
                .frame(maxWidth: .infinity)
            Button("今日", action: today).font(.subheadline)
            Button(action: next) { Image(systemName: "chevron.right") }
                .accessibilityLabel("翌月")
        }
        .buttonStyle(ThemedControlStyle())
    }
}
