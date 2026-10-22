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
        VStack(alignment: .leading, spacing: 0) {
            WeekHeader(dates: dates, isToday: isToday, isSelected: isSelected,
                       hasEvent: hasEvent, hasTask: hasTask, projectIDs: projectIDs, select: select)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 4, alignment: .topLeading), count: 7), alignment: .leading, spacing: 0) {
                ForEach(dates, id: \.self) { date in
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(events(date).filter { $0.isAllDay }) { event in
                            Button { eventActions.edit(event) } label: {
                                marker(time: nil)
                            }
                            .accessibilityLabel("終日予定、\(event.title)")
                        }
                        ForEach(tasks(date).filter { $0.isAllDay }) { task in
                            Button { taskActions.edit(task) } label: {
                                marker(time: nil)
                            }
                            .accessibilityLabel("終日タスク、\(task.title)")
                        }
                        ForEach(timedItems(on: date)) { item in
                            Button {
                                switch item.source {
                                case let .event(event): eventActions.edit(event)
                                case let .task(task): taskActions.edit(task)
                                }
                            } label: {
                                marker(time: item.date)
                            }
                            .accessibilityLabel("\(item.date.formatted(date: .omitted, time: .shortened))、\(item.title)")
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                }
            }
            .buttonStyle(ThemedPressStyle())
        }
        .themedSurface(padding: 10)
    }

    private func marker(time: Date?) -> some View {
        HStack(spacing: 2) {
            Circle().fill(.primary).frame(width: 3, height: 3)
            Group {
                if let time {
                    Text(time, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                } else {
                    Text("終日")
                }
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func timedItems(on date: Date) -> [DailyTimelineItem] {
        timelineItems(date).filter { DailyTimelineItem.isWithinDisplayHours($0.date) }
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
