import SwiftUI

struct TaskRow: View {
    @EnvironmentObject private var projectStore: ProjectStore
    let task: TaskItem
    var displayedCompletion: Bool? = nil
    let toggle: () -> Void
    let edit: () -> Void
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: toggle) { Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(isCompleted ? .secondary : .primary).frame(width: 44, height: 44) }.buttonStyle(ThemedPressStyle())
            Button(action: edit) {
                HStack(spacing: 8) {
                    if let project = projectStore.project(id: task.projectID) {
                        Circle().fill(project.colorIdentifier.color).frame(width: 6, height: 6)
                    }
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(isCompleted)
                        .foregroundStyle(isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                    if task.recurrenceRule != nil {
                        Image(systemName: "repeat").font(.caption).foregroundStyle(.secondary)
                    }
                    Text(metadataText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.buttonStyle(ThemedPressStyle())
        }
        .padding(.vertical, 8)
    }
    private var isCompleted: Bool { displayedCompletion ?? task.isCompleted }

    private var metadataText: String {
        var values = [(task.dueDate ?? task.startDate)?.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened) ?? "日付なし",
                      task.priority.displayName]
        if let project = projectStore.project(id: task.projectID) { values.append(project.name) }
        if !task.note.isEmpty { values.append(task.note) }
        return values.joined(separator: " · ")
    }
}
