import SwiftUI

struct SelectedDaySummaryView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let date: Date
    let events: [CalendarEvent]
    let tasks: [TaskItem]
    let note: DailyNote?
    let editEvent: (CalendarEvent) -> Void
    let editTask: (TaskItem) -> Void
    let editNote: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(date.formatted(.dateTime.month(.wide).day().weekday(.wide))).font(.headline)
            summarySection("予定") {
                if events.isEmpty { empty("予定はありません") }
                ForEach(events) { event in
                    Button { editEvent(event) } label: { HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(event.isAllDay ? "終日" : event.startDate.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                        if let project = projectStore.project(id: event.projectID) { Circle().fill(project.colorIdentifier.color).frame(width: 6, height: 6).accessibilityLabel(project.name) }
                        Text(event.title); if event.recurrenceRule != nil { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                }
            }
            summarySection("タスク") {
                if tasks.isEmpty { empty("タスクはありません") }
                ForEach(tasks) { task in
                    Button { editTask(task) } label: { HStack(spacing: 10) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(.secondary)
                        if let project = projectStore.project(id: task.projectID) { Circle().fill(project.colorIdentifier.color).frame(width: 6, height: 6).accessibilityLabel(project.name) }
                        Text(task.title).strikethrough(task.isCompleted).foregroundStyle(task.isCompleted ? .secondary : .primary)
                        if task.recurrenceRule != nil { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                }
            }
            summarySection("メモ") {
                Button(action: editNote) {
                    if let note, !note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note.text).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                    } else { empty("メモを書く") }
                }.buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func summarySection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(title).font(.subheadline.weight(.semibold)); content() }
    }
    private func empty(_ text: String) -> some View { Text(text).font(.subheadline).foregroundStyle(.tertiary) }
}
