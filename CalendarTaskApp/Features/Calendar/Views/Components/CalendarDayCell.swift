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
    var showsItemIndicator = true
    var centersDayNumber = false

    var body: some View {
        Button(action: select) {
            VStack(alignment: centersDayNumber ? .center : .leading, spacing: centersDayNumber ? 1 : 4) {
                Text(String(Calendar.current.component(.day, from: date)))
                    .font(.system(.subheadline, design: settings.theme.headingDesign,
                                  weight: isToday || isSelected ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(dayNumberColor)
                    .frame(minWidth: centersDayNumber ? 28 : 32, minHeight: centersDayNumber ? 28 : 32)
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
                if showsItemIndicator {
                    Circle()
                        .fill(hasEvent || hasIncompleteTask ? palette.ink : .clear)
                        .frame(width: 5, height: 5)
                        .padding(.leading, centersDayNumber ? 0 : 13)
                }
            }
            .padding(.top, centersDayNumber ? 0 : 3)
            .padding(.leading, centersDayNumber ? 0 : 2)
            .frame(maxWidth: .infinity, minHeight: centersDayNumber ? 0 : (showsItemIndicator ? 60 : 36),
                   maxHeight: centersDayNumber ? .infinity : nil, alignment: centersDayNumber ? .center : .topLeading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ThemedPressStyle())
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue([isToday ? "今日" : nil, isHoliday ? "祝日" : nil, hasEvent ? "予定あり" : nil, hasIncompleteTask ? "未完了タスクあり" : nil].compactMap { $0 }.joined(separator: "、"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isHoliday: Bool { Calendar.current.isJapaneseHoliday(date) }

    private var dayNumberColor: Color {
        if isSelected { return palette.selectionInk }
        guard isInDisplayedMonth else { return palette.mutedInk }
        let weekday = Calendar.current.component(.weekday, from: date)
        if isHoliday || weekday == 1 { return colorScheme == .dark ? Color(red: 1, green: 0.55, blue: 0.58) : Color(red: 0.68, green: 0.08, blue: 0.12) }
        if weekday == 7 { return colorScheme == .dark ? Color(red: 0.48, green: 0.72, blue: 1) : Color(red: 0.05, green: 0.27, blue: 0.62) }
        return palette.ink
    }
}
