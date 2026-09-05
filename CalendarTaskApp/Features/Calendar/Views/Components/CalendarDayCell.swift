import SwiftUI

struct CalendarDayCell: View {
    @EnvironmentObject private var settings: SettingsStore
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
                    .foregroundStyle(isSelected ? selectionForeground : isInDisplayedMonth ? Color.primary : Color.secondary)
                    .frame(minWidth: 32, minHeight: 32)
                    .background {
                        RoundedRectangle(cornerRadius: settings.theme.controlRadius)
                            .fill(isSelected ? settings.theme.accent : .clear)
                    }
                    .overlay(alignment: .bottom) {
                        if isToday {
                            Capsule().fill(isSelected ? selectionForeground : settings.theme.accent)
                                .frame(width: 12, height: 2).padding(.bottom, 3)
                        }
                    }
                HStack(spacing: 4) {
                    Circle().fill(hasEvent ? Color.primary : .clear).frame(width: 5, height: 5)
                    RoundedRectangle(cornerRadius: 1)
                        .stroke(hasIncompleteTask ? Color.primary : .clear, lineWidth: 1.3)
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

    private var selectionForeground: Color {
        settings.theme == .midnight ? Color(red: 0.055, green: 0.075, blue: 0.13) : .white
    }

    private func indicator(visible: Bool, color: Color) -> some View {
        Circle().fill(visible ? color : .clear).frame(width: 4, height: 4)
    }
}
