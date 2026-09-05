import SwiftUI

struct CalendarDayCell: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ThemeAppearance { settings.theme.appearance(for: colorScheme) }
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
            VStack(spacing: 4) {
                Text(date, format: .dateTime.day())
                    .font(.system(.subheadline, design: settings.theme.headingDesign,
                                  weight: isToday || isSelected ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? palette.selectionInk : isInDisplayedMonth ? palette.ink : palette.mutedInk)
                    .frame(minWidth: 32, minHeight: 32)
                    .background {
                        RoundedRectangle(cornerRadius: palette.controlRadius)
                            .fill(isSelected ? palette.accent : .clear)
                    }
                    .overlay(alignment: .bottom) {
                        if isToday {
                            Capsule().fill(isSelected ? palette.selectionInk : palette.accent)
                                .frame(width: 12, height: 2).padding(.bottom, 3)
                        }
                    }
                HStack(spacing: 4) {
                    Circle().fill(hasEvent ? palette.ink : .clear).frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(hasIncompleteTask ? palette.ink : .clear, lineWidth: 1.3)
                        .frame(width: 5, height: 5)
                }.frame(height: 6)
                HStack(spacing: 3) {
                    ForEach(Array(projectColors.prefix(3).enumerated()), id: \.offset) { _, color in
                        indicator(visible: true, color: color)
                    }
                }.frame(height: 4)
            }
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(ThemedPressStyle())
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue([isToday ? "今日" : nil, hasEvent ? "予定あり" : nil, hasIncompleteTask ? "未完了タスクあり" : nil].compactMap { $0 }.joined(separator: "、"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func indicator(visible: Bool, color: Color) -> some View {
        Circle().fill(visible ? color : .clear).frame(width: 4, height: 4)
    }
}
