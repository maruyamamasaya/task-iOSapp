import SwiftUI

struct CalendarDayCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let isInDisplayedMonth: Bool
    let hasEvent: Bool
    let hasIncompleteTask: Bool
    let projectColors: [Color]
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                Text(date, format: .dateTime.day())
                    .font(.subheadline.weight(isToday ? .semibold : .regular))
                    .frame(width: 29, height: 29)
                    .background { if isToday { Circle().fill(Color.primary.opacity(0.09)) } }
                    .overlay { if isSelected { Circle().stroke(Color.accentColor, lineWidth: 1.5) } }
                HStack(spacing: 3) {
                    ForEach(Array(projectColors.prefix(3).enumerated()), id: \.offset) { _, color in
                        indicator(visible: true, color: color)
                    }
                    if projectColors.isEmpty { indicator(visible: hasEvent || hasIncompleteTask, color: .secondary) }
                }.frame(height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
            .foregroundStyle(isInDisplayedMonth ? Color.primary : Color.secondary.opacity(0.45))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func indicator(visible: Bool, color: Color) -> some View {
        Circle().fill(visible ? color : .clear).frame(width: 4, height: 4)
    }
}
