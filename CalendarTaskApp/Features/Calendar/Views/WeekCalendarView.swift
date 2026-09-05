import SwiftUI

struct WeekCalendarView: View {
    let dates: [Date]
    let selectedDate: Date
    let allDayEvents: [CalendarEvent]
    let allDayTasks: [TaskItem]
    let timelineItems: [DailyTimelineItem]
    let unscheduledTasks: [TaskItem]
    let now: Date
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
        VStack(alignment: .leading, spacing: 24) {
            WeekHeader(dates: dates, isToday: isToday, isSelected: isSelected,
                       hasEvent: hasEvent, hasTask: hasTask, projectIDs: projectIDs, select: select)
            Divider()
            AllDaySection(events: allDayEvents, tasks: allDayTasks,
                          editEvent: eventActions.edit, editTask: taskActions.edit, toggleTask: taskActions.toggle,
                          taskActions: taskActions, eventActions: eventActions)
            DailyTimelineView(items: timelineItems, showsNow: isToday(selectedDate), now: now,
                              editEvent: eventActions.edit, editTask: taskActions.edit, toggleTask: taskActions.toggle,
                              taskActions: taskActions, eventActions: eventActions)
            UnscheduledTasksSection(tasks: unscheduledTasks, edit: taskActions.edit, toggle: taskActions.toggle, actions: taskActions)
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

    var body: some View {
        HStack(spacing: 4) {
            ForEach(dates, id: \.self) { date in
                VStack(spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
                    CalendarDayCell(date: date, isToday: settings.highlightToday && isToday(date),
                                    isSelected: isSelected(date), isInDisplayedMonth: true,
                                    hasEvent: hasEvent(date), hasIncompleteTask: hasTask(date),
                                    projectColors: colors(for: date)) { select(date) }
                }
            }
        }
    }

    private func colors(for date: Date) -> [Color] {
        let colors = (settings.showProjectColorDots ? projectIDs(date) : []).map { projectStore.project(id: $0)?.colorIdentifier.color ?? .secondary }
        return colors
    }
}
