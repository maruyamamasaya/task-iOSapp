import SwiftUI

struct DailyScheduleList: View {
    let date: Date; let events: [CalendarEvent]; let tasks: [TaskItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(date.formatted(date: .long, time: .omitted)).font(.headline)
            Text("予定").font(.subheadline.bold()); if events.isEmpty { Text("予定はありません").foregroundStyle(.secondary) }; ForEach(events) { Label($0.title, systemImage: "calendar") }
            Divider(); Text("タスク").font(.subheadline.bold()); if tasks.isEmpty { Text("タスクはありません").foregroundStyle(.secondary) }; ForEach(tasks) { TaskRow(task: $0) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
