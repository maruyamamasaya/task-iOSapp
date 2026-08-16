import WidgetKit
import SwiftUI

struct CalendarTaskWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetTodaySnapshot
}

struct CalendarTaskWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarTaskWidgetEntry { .init(date: .now, snapshot: .placeholder()) }
    func getSnapshot(in context: Context, completion: @escaping (CalendarTaskWidgetEntry) -> Void) {
        if context.isPreview { completion(.init(date: .now, snapshot: .placeholder())); return }
        Task { @MainActor in completion(.init(date: .now, snapshot: WidgetDataProvider().today())) }
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarTaskWidgetEntry>) -> Void) {
        Task { @MainActor in
            let now = Date.now, entry = CalendarTaskWidgetEntry(date: now, snapshot: WidgetDataProvider().today(now: now))
            let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
            completion(Timeline(entries: [entry], policy: .after(nextDay)))
        }
    }
}

struct CalendarTaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarTaskWidgetEntry
    var body: some View {
        Group { family == .systemSmall ? AnyView(small) : AnyView(medium) }
            .containerBackground(.background, for: .widget)
            .widgetURL(URL(string: "calendarTaskApp://today"))
    }
    private var small: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("今日").font(.headline)
            Text(entry.snapshot.date.formatted(.dateTime.month().day().weekday(.short))).font(.caption).foregroundStyle(.secondary)
            Divider()
            let items = Array((entry.snapshot.tasks + entry.snapshot.events).prefix(2))
            if items.isEmpty { Text("今日は予定なし").font(.caption).foregroundStyle(.secondary); Spacer() }
            else { ForEach(items) { itemRow($0) }; Spacer(minLength: 0) }
            let remaining = entry.snapshot.events.count + entry.snapshot.tasks.count - items.count
            if remaining > 0 { Text("あと\(remaining)件").font(.caption2).foregroundStyle(.secondary) }
        }.padding(2)
    }
    private var medium: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(entry.snapshot.date.formatted(.dateTime.month().day().weekday(.wide))).font(.headline)
            Divider()
            HStack(alignment: .top, spacing: 18) {
                widgetSection("予定", items: Array(entry.snapshot.events.prefix(3)), empty: "予定なし")
                Divider()
                widgetSection("タスク", items: Array(entry.snapshot.tasks.prefix(3)), empty: "タスクなし")
            }
        }.padding(2)
    }
    private func widgetSection(_ title: String, items: [WidgetDisplayItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if items.isEmpty { Text(empty).font(.caption2).foregroundStyle(.tertiary) }
            else { ForEach(items) { itemRow($0) } }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private func itemRow(_ item: WidgetDisplayItem) -> some View {
        if item.kind == .task, let taskID = item.taskID, let occurrenceDate = item.occurrenceDate {
            HStack(spacing: 5) {
                Button(intent: ToggleTaskCompletionIntent(taskID: taskID, occurrenceDate: occurrenceDate)) {
                    Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square").font(.caption)
                }.buttonStyle(.plain).accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
                if let color = item.projectColor { Circle().fill(color.color).frame(width: 5, height: 5) }
                Text(item.isAllDay ? "終日" : item.date.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Text(item.title).font(.caption).lineLimit(1)
                if item.isRecurring { Image(systemName: "repeat").font(.caption2).foregroundStyle(.secondary) }
            }
        } else {
            HStack(spacing: 5) {
                if let color = item.projectColor { Circle().fill(color.color).frame(width: 5, height: 5) }
                Text(item.isAllDay ? "終日" : item.date.formatted(date: .omitted, time: .shortened)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                Text(item.title).font(.caption).lineLimit(1)
            }
        }
    }
}

struct CalendarTaskTodayWidget: Widget {
    let kind = "CalendarTaskTodayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarTaskWidgetProvider()) { CalendarTaskWidgetView(entry: $0) }
            .configurationDisplayName("今日の手帳")
            .description("今日の予定とタスクを確認できます。")
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main struct CalendarTaskWidgetBundle: WidgetBundle {
    var body: some Widget { CalendarTaskTodayWidget() }
}

#Preview("予定とタスク", as: .systemSmall) { CalendarTaskTodayWidget() } timeline: {
    CalendarTaskWidgetEntry(date: .now, snapshot: .placeholder())
}
#Preview("Medium", as: .systemMedium) { CalendarTaskTodayWidget() } timeline: {
    CalendarTaskWidgetEntry(date: .now, snapshot: .placeholder())
}
#Preview("Empty", as: .systemSmall) { CalendarTaskTodayWidget() } timeline: {
    CalendarTaskWidgetEntry(date: .now, snapshot: WidgetTodaySnapshot(date: .now, events: [], tasks: []))
}
#Preview("Events", as: .systemMedium) { CalendarTaskTodayWidget() } timeline: {
    let sample = WidgetTodaySnapshot.placeholder()
    CalendarTaskWidgetEntry(date: .now, snapshot: WidgetTodaySnapshot(date: .now, events: sample.events, tasks: []))
}
#Preview("Tasks", as: .systemMedium) { CalendarTaskTodayWidget() } timeline: {
    let sample = WidgetTodaySnapshot.placeholder()
    CalendarTaskWidgetEntry(date: .now, snapshot: WidgetTodaySnapshot(date: .now, events: [], tasks: sample.tasks))
}
#Preview("Recurring Task", as: .systemSmall) { CalendarTaskTodayWidget() } timeline: {
    let id = UUID()
    let item = WidgetDisplayItem(id: id, kind: .task, title: "毎日の振り返り", date: .now, isAllDay: true,
                                 taskID: id, isRecurring: true, occurrenceDate: .now, isCompleted: false, projectColor: .teal)
    CalendarTaskWidgetEntry(date: .now, snapshot: WidgetTodaySnapshot(date: .now, events: [], tasks: [item]))
}
