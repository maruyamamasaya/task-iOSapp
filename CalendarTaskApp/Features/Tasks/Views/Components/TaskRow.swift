import SwiftUI

struct TaskRow: View {
    let task: TaskItem
    var body: some View {
        HStack {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle").foregroundStyle(task.isCompleted ? .green : .secondary)
            VStack(alignment: .leading) {
                Text(task.title).strikethrough(task.isCompleted)
                if let due = task.dueDate { Text(due.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened)).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(); Text(task.priority.displayName).font(.caption).foregroundStyle(task.priority == .high ? .red : .secondary)
        }
    }
}
