import SwiftUI

struct WeekCalendarView: View {
    let dates: [Date]
    let events: (Date) -> [CalendarEvent]
    let tasks: (Date) -> [TaskItem]
    let timelineItems: (Date) -> [DailyTimelineItem]
    let isToday: (Date) -> Bool
    let isSelected: (Date) -> Bool
    let hasEvent: (Date) -> Bool
    let hasTask: (Date) -> Bool
    let projectIDs: (Date) -> [UUID?]
    let select: (Date) -> Void
    let taskActions: TaskRowActions
    let eventActions: EventRowActions
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(stride(from: 0, to: dates.count, by: 7)), id: \.self) { start in
                if start > 0 { Divider() }
                weekRow(Array(dates.dropFirst(start).prefix(7)))
            }
        }
        .themedSurface(padding: 10)
    }

    private func weekRow(_ weekDates: [Date]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WeekHeader(dates: weekDates, isToday: isToday, isSelected: isSelected,
                       hasEvent: hasEvent, hasTask: hasTask, projectIDs: projectIDs, select: select)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7), spacing: 0) {
                ForEach(weekDates, id: \.self) { date in
                    let count = events(date).count + tasks(date).count
                    Button { select(date) } label: {
                        Text("\(count)件")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(count == 0 ? .secondary : .primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 24)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("\(date.formatted(.dateTime.month().day()))、予定とタスク\(count)件、日表示を開く")
                }
            }
            .buttonStyle(ThemedPressStyle())
        }
    }

}

private struct WeekHeader: View {
    let dates: [Date]
    let isToday: (Date) -> Bool
    let isSelected: (Date) -> Bool
    let hasEvent: (Date) -> Bool
    let hasTask: (Date) -> Bool
    let projectIDs: (Date) -> [UUID?]
    let select: (Date) -> Void
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4), count: 7), spacing: 0) {
            ForEach(dates, id: \.self) { date in
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.medium)).foregroundStyle(weekdayColor(for: date))
                    CalendarDayCell(date: date, isToday: settings.highlightToday && isToday(date),
                                    isSelected: isSelected(date), isInDisplayedMonth: true,
                                    hasEvent: hasEvent(date), hasIncompleteTask: hasTask(date),
                                    projectColors: colors(for: date), select: { select(date) }, showsItemIndicator: false)
                }
            }
        }
    }

    private func colors(for date: Date) -> [Color] {
        let colors = (settings.showProjectColorDots ? projectIDs(date) : []).map { projectStore.project(id: $0)?.colorIdentifier.color ?? .secondary }
        return colors
    }

    private func weekdayColor(for date: Date) -> Color {
        let weekday = Calendar.current.component(.weekday, from: date)
        if Calendar.current.isJapaneseHoliday(date) || weekday == 1 {
            return colorScheme == .dark ? Color(red: 1, green: 0.55, blue: 0.58) : Color(red: 0.68, green: 0.08, blue: 0.12)
        }
        if weekday == 7 {
            return colorScheme == .dark ? Color(red: 0.48, green: 0.72, blue: 1) : Color(red: 0.05, green: 0.27, blue: 0.62)
        }
        return .secondary
    }
}
