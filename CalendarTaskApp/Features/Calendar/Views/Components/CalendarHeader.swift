import SwiftUI

struct CalendarHeader: View {
    @Binding var displayMode: CalendarDisplayMode
    let previous: () -> Void
    let next: () -> Void
    let today: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("表示", selection: $displayMode) {
                ForEach(CalendarDisplayMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 144)
            Spacer(minLength: 0)
            Button(action: previous) { Image(systemName: "chevron.left") }
                .accessibilityLabel(displayMode == .month ? "前月" : displayMode == .week ? "前週" : "前日")
            Button("今日", action: today).font(.subheadline)
            Button(action: next) { Image(systemName: "chevron.right") }
                .accessibilityLabel(displayMode == .month ? "翌月" : displayMode == .week ? "翌週" : "翌日")
        }
        .buttonStyle(ThemedControlStyle())
    }
}
