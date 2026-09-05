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
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalendarTaskWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall: AnyView(small)
            case .systemLarge: AnyView(large)
            default: AnyView(medium)
            }
        }
            .containerBackground(palette.background, for: .widget)
            .widgetURL(URL(string: "calendarTaskApp://today"))
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: true)
            rule.padding(.vertical, 12)
            let items = Array(allItems.prefix(2))
            if items.isEmpty { emptyState; Spacer(minLength: 0) }
            else { VStack(alignment: .leading, spacing: 11) { ForEach(items) { itemRow($0) } }; Spacer(minLength: 10) }
            let remaining = entry.snapshot.events.count + entry.snapshot.tasks.count - items.count
            if remaining > 0 {
                Text("ほか \(remaining)件をアプリで見る")
                    .font(.system(.caption2, design: .rounded, weight: .semibold))
                    .foregroundStyle(palette.accent)
            }
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: false)
            rule.padding(.vertical, 12)
            HStack(alignment: .top, spacing: 18) {
                widgetSection("予定", symbol: "calendar", items: Array(entry.snapshot.events.prefix(2)), empty: "予定はありません")
                Rectangle().fill(palette.border).frame(width: 1)
                widgetSection("タスク", symbol: "checkmark.circle", items: Array(entry.snapshot.tasks.prefix(2)), empty: "タスクはありません")
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: false)
            HStack(spacing: 10) {
                summaryCard(title: "予定", count: entry.snapshot.events.count, symbol: "calendar", tint: palette.accent)
                summaryCard(title: "タスク", count: entry.snapshot.tasks.count, symbol: "checkmark.circle", tint: palette.ornament)
            }
            .padding(.top, 18)

            HStack {
                Label("今日の流れ", systemImage: "clock")
                    .font(.system(.subheadline, design: .serif, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer()
                Text("時刻順")
                    .font(.caption2)
                    .foregroundStyle(palette.mutedInk)
            }
            .padding(.top, 22)
            rule.padding(.top, 9).padding(.bottom, 13)

            let items = Array(allItems.prefix(5))
            if items.isEmpty {
                largeEmptyState
            } else {
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(items) { largeItemRow($0) }
                }
                Spacer(minLength: 10)
                let remaining = allItems.count - items.count
                if remaining > 0 {
                    Text("ほか \(remaining)件")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.snapshot.date.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(palette.accent)
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(entry.snapshot.date.formatted(.dateTime.day()))
                        .font(.system(size: compact ? 28 : 31, weight: .semibold, design: .serif))
                        .foregroundStyle(palette.ink)
                    Text(entry.snapshot.date.formatted(.dateTime.weekday(.wide)))
                        .font(.caption)
                        .foregroundStyle(palette.mutedInk)
                }
            }
            Spacer(minLength: 4)
            Text("今日の手帳")
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(palette.mutedInk)
        }
    }

    private var rule: some View {
        Rectangle().fill(palette.border).frame(height: 1)
    }

    private func widgetSection(_ title: String, symbol: String, items: [WidgetDisplayItem], empty: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(palette.accent)
            if items.isEmpty {
                Text(empty).font(.caption2).foregroundStyle(palette.mutedInk).padding(.top, 2)
            } else {
                ForEach(items) { itemRow($0) }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func itemRow(_ item: WidgetDisplayItem) -> some View {
        if item.kind == .task, let taskID = item.taskID, let occurrenceDate = item.occurrenceDate {
            HStack(spacing: 6) {
                Button(intent: ToggleTaskCompletionIntent(taskID: taskID, occurrenceDate: occurrenceDate)) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.isCompleted ? "未完了に戻す" : "完了にする")
                rowText(item)
            }
        } else {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(item.projectColor?.color ?? palette.ornament)
                    .frame(width: 3, height: 17)
                rowText(item)
            }
        }
    }

    private func rowText(_ item: WidgetDisplayItem) -> some View {
        HStack(spacing: 5) {
            if item.kind == .task, let color = item.projectColor {
                Circle().fill(color.color).frame(width: 5, height: 5)
            }
            Text(item.isAllDay ? "終日" : item.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedInk)
                .frame(minWidth: 29, alignment: .leading)
            Text(item.title)
                .font(.caption)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            if item.isRecurring {
                Image(systemName: "repeat").font(.system(size: 8, weight: .semibold)).foregroundStyle(palette.mutedInk)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: "sun.max").font(.title3).foregroundStyle(palette.ornament).padding(.bottom, 2)
            Text("今日はゆったり")
                .font(.system(.caption, design: .serif, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text("予定もタスクもありません").font(.caption2).foregroundStyle(palette.mutedInk)
        }
        .padding(.top, 2)
    }

    private func summaryCard(title: String, count: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption2).foregroundStyle(palette.mutedInk)
                Text("\(count)件").font(.system(.headline, design: .rounded, weight: .semibold)).foregroundStyle(palette.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(palette.control.opacity(0.68), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.border.opacity(0.8), lineWidth: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title) \(count)件")
    }

    @ViewBuilder private func largeItemRow(_ item: WidgetDisplayItem) -> some View {
        HStack(spacing: 0) {
            Text(item.isAllDay ? "終日" : item.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.mutedInk)
                .frame(width: 46, alignment: .leading)
            Circle().fill(item.projectColor?.color ?? (item.kind == .task ? palette.accent : palette.ornament))
                .frame(width: 6, height: 6)
                .frame(width: 20)
            if item.kind == .task, let taskID = item.taskID, let occurrenceDate = item.occurrenceDate {
                Button(intent: ToggleTaskCompletionIntent(taskID: taskID, occurrenceDate: occurrenceDate)) {
                    Image(systemName: "circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .accessibilityLabel("完了にする")
            } else {
                Image(systemName: "calendar")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.mutedInk)
                    .frame(width: 22, alignment: .leading)
                    .padding(.trailing, 4)
            }
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(palette.ink)
                .lineLimit(1)
            if item.isRecurring {
                Image(systemName: "repeat").font(.caption2).foregroundStyle(palette.mutedInk).padding(.leading, 6)
            }
            Spacer(minLength: 0)
        }
    }

    private var largeEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sun.max").font(.system(size: 27, weight: .light)).foregroundStyle(palette.ornament)
            Text("今日はゆったり過ごせそうです")
                .font(.system(.subheadline, design: .serif, weight: .semibold))
                .foregroundStyle(palette.ink)
            Text("予定もタスクもありません").font(.caption).foregroundStyle(palette.mutedInk)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allItems: [WidgetDisplayItem] {
        (entry.snapshot.events + entry.snapshot.tasks).sorted { lhs, rhs in
            if lhs.isAllDay != rhs.isAllDay { return lhs.isAllDay }
            return lhs.date < rhs.date
        }
    }

    private var palette: WidgetPalette { WidgetPalette(colorScheme: colorScheme) }
}

private struct WidgetPalette {
    let background: Color
    let accent: Color
    let ink: Color
    let mutedInk: Color
    let border: Color
    let ornament: Color
    let control: Color

    init(colorScheme: ColorScheme) {
        if colorScheme == .dark {
            background = Color(widgetHex: 0x232C36)
            accent = Color(widgetHex: 0xD8BB83)
            ink = Color(widgetHex: 0xF1EBDD)
            mutedInk = Color(widgetHex: 0xBDB9AE)
            border = Color(widgetHex: 0x59606A)
            ornament = Color(widgetHex: 0xB99A61)
            control = Color(widgetHex: 0x343B43)
        } else {
            background = Color(widgetHex: 0xFFFCF4)
            accent = Color(widgetHex: 0x315D88)
            ink = Color(widgetHex: 0x292D32)
            mutedInk = Color(widgetHex: 0x626975)
            border = Color(widgetHex: 0xD8D2C3)
            ornament = Color(widgetHex: 0x6987A0)
            control = Color(widgetHex: 0xE8EDF0)
        }
    }
}

private extension Color {
    init(widgetHex: UInt32) {
        self.init(.sRGB,
                  red: Double((widgetHex >> 16) & 255) / 255,
                  green: Double((widgetHex >> 8) & 255) / 255,
                  blue: Double(widgetHex & 255) / 255,
                  opacity: 1)
    }
}

struct CalendarTaskTodayWidget: Widget {
    let kind = "CalendarTaskTodayWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarTaskWidgetProvider()) { CalendarTaskWidgetView(entry: $0) }
            .configurationDisplayName("今日の手帳")
            .description("今日の予定とタスクを確認できます。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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
#Preview("Large", as: .systemLarge) { CalendarTaskTodayWidget() } timeline: {
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
