import SwiftUI

struct CalendarHeader: View {
    let month: Date
    var title: String? = nil
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: previous) { Image(systemName: "chevron.left") }
                .accessibilityLabel("前月")
            Text(title ?? month.formatted(.dateTime.year().month(.wide)))
                .font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
            Button("今日", action: today).font(.subheadline)
            Button(action: next) { Image(systemName: "chevron.right") }
                .accessibilityLabel("翌月")
        }
        .buttonStyle(.plain)
    }
}
