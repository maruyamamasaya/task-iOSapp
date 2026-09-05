import SwiftUI

struct TaskRow: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let task: TaskItem
    var displayedCompletion: Bool? = nil
    let toggle: () -> Void
    let edit: () -> Void
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: toggle) { Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(isCompleted ? .secondary : .primary).frame(width: 44, height: 44) }.buttonStyle(ThemedPressStyle())
            Button(action: edit) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        if let project = projectStore.project(id: task.projectID) { Circle().fill(project.colorIdentifier.color).frame(width: 6, height: 6) }
                        Text(task.title).font(.body.weight(.medium)).strikethrough(isCompleted).foregroundStyle(isCompleted ? .secondary : .primary)
                        if task.recurrenceRule != nil { Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary) }
                    }
                    HStack(spacing: 8) {
                        if let date = task.dueDate ?? task.startDate { Text(date.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened)) } else { Text("日付なし") }
                        Text(task.priority.displayName)
                        if let project = projectStore.project(id: task.projectID) { Text(project.name) }
                        if !task.note.isEmpty { Text(task.note).lineLimit(1) }
                    }.font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(ThemedPressStyle())
        }
        .padding(.vertical, 8)
    }
    private var isCompleted: Bool { displayedCompletion ?? task.isCompleted }
}
