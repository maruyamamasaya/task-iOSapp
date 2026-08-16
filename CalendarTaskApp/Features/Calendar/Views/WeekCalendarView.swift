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
                Button { select(date) } label: {
                    VStack(spacing: 6) {
                        Text(date.formatted(.dateTime.weekday(.narrow))).font(.caption2).foregroundStyle(.secondary)
                        Text(date.formatted(.dateTime.day())).font(.subheadline.weight(settings.highlightToday && isToday(date) ? .semibold : .regular))
                            .frame(width: 30, height: 30)
                            .background { if settings.highlightToday && isToday(date) { Circle().fill(Color.primary.opacity(0.09)) } }
                            .overlay { if isSelected(date) { Circle().stroke(Color.accentColor, lineWidth: 1.5) } }
                        HStack(spacing: 2) {
                            ForEach(Array(colors(for: date).prefix(3).enumerated()), id: \.offset) { _, color in
                                Circle().fill(color).frame(width: 4, height: 4)
                            }
                        }.frame(height: 5)
                    }.frame(maxWidth: .infinity)
                }.buttonStyle(.plain).accessibilityLabel(date.formatted(date: .complete, time: .omitted))
            }
        }
    }

    private func colors(for date: Date) -> [Color] {
        let colors = (settings.showProjectColorDots ? projectIDs(date) : []).map { projectStore.project(id: $0)?.colorIdentifier.color ?? .secondary }
        if colors.isEmpty, hasEvent(date) || hasTask(date) { return [.secondary] }
        return colors
    }
}
