import SwiftUI

struct DayCalendarView: View {
    let date: Date
    let allDayEvents: [CalendarEvent]
    let allDayTasks: [TaskItem]
    let timelineItems: [DailyTimelineItem]
    let unscheduledTasks: [TaskItem]
    let note: DailyNote?
    let now: Date
    let isToday: Bool
    let editNote: () -> Void
    let taskActions: TaskRowActions
    let eventActions: EventRowActions

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            AllDaySection(events: allDayEvents, tasks: allDayTasks,
                          editEvent: eventActions.edit, editTask: taskActions.edit, toggleTask: taskActions.toggle,
                          taskActions: taskActions, eventActions: eventActions)
            DailyTimelineView(items: timelineItems, showsNow: isToday, now: now,
                              editEvent: eventActions.edit, editTask: taskActions.edit, toggleTask: taskActions.toggle,
                              taskActions: taskActions, eventActions: eventActions)
            UnscheduledTasksSection(tasks: unscheduledTasks, edit: taskActions.edit, toggle: taskActions.toggle, actions: taskActions)
            VStack(alignment: .leading, spacing: 10) {
                Label("メモ", systemImage: "pencil.line").font(.headline)
                Button(action: editNote) {
                    Text(noteText)
                        .font(.subheadline)
                        .foregroundStyle(hasNote ? .secondary : .tertiary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
            .themedSurface()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(date.formatted(.dateTime.year().month().day().weekday(.wide)))
    }

    private var hasNote: Bool { !noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && note != nil }
    private var noteText: String {
        let text = note?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "メモを書く" : text
    }
}
