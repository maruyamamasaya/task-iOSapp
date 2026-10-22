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
            let now = Date.now, provider = WidgetDataProvider()
            let entries = provider.timelineDates(now: now).map { date in
                CalendarTaskWidgetEntry(date: date, snapshot: provider.today(now: date))
            }
            completion(Timeline(entries: entries, policy: .atEnd))
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
                Image(systemName: item.kind == .task ? "circle" : "calendar")
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

    private var preferences: WidgetAppearancePreferences { .current }
    private var effectiveColorScheme: ColorScheme {
        switch preferences.appearance {
        case "ライト": .light
        case "ダーク": .dark
        default: colorScheme
        }
    }
    private var palette: WidgetPalette { WidgetPalette(theme: preferences.theme, colorScheme: effectiveColorScheme) }
}

private struct WidgetAppearancePreferences {
    let appearance: String
    let theme: String

    static var current: Self {
        guard let identifier = Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String,
              let defaults = UserDefaults(suiteName: identifier) else {
            return Self(appearance: "システム", theme: "クラシック手帳")
        }
        return Self(appearance: defaults.string(forKey: "settings.appearance") ?? "システム",
                    theme: defaults.string(forKey: "settings.theme") ?? "クラシック手帳")
    }
}

private struct WidgetPalette {
    let background: Color
    let accent: Color
    let ink: Color
    let mutedInk: Color
    let border: Color
    let ornament: Color
    let control: Color

    init(theme: String, colorScheme: ColorScheme) {
        switch (theme, colorScheme) {
        case ("さくら日和", .light):
            background = Color(widgetHex: 0xFFFAFB)
            accent = Color(widgetHex: 0xA6395C)
            ink = Color(widgetHex: 0x432D38)
            mutedInk = Color(widgetHex: 0x79606D)
            border = Color(widgetHex: 0xEDD1DC)
            ornament = Color(widgetHex: 0xD583A0)
            control = Color(widgetHex: 0xF8E3EB)
        case ("さくら日和", _):
            background = Color(widgetHex: 0x302536)
            accent = Color(widgetHex: 0xF0AAC7)
            ink = Color(widgetHex: 0xF8EAF2)
            mutedInk = Color(widgetHex: 0xCFB3C5)
            border = Color(widgetHex: 0x695066)
            ornament = Color(widgetHex: 0xB78FCA)
            control = Color(widgetHex: 0x473346)
        case ("ナチュラルリネン", .light):
            background = Color(widgetHex: 0xF8F3E7)
            accent = Color(widgetHex: 0x52613C)
            ink = Color(widgetHex: 0x36382D)
            mutedInk = Color(widgetHex: 0x62634F)
            border = Color(widgetHex: 0xCEC4AE)
            ornament = Color(widgetHex: 0x988360)
            control = Color(widgetHex: 0xE7E6D7)
        case ("ナチュラルリネン", _):
            background = Color(widgetHex: 0x362C24)
            accent = Color(widgetHex: 0xD9B28B)
            ink = Color(widgetHex: 0xF1E6D6)
            mutedInk = Color(widgetHex: 0xC9B59D)
            border = Color(widgetHex: 0x6E5946)
            ornament = Color(widgetHex: 0xB7936A)
            control = Color(widgetHex: 0x4B3D30)
        case ("ミッドナイト", .light):
            background = Color(widgetHex: 0xF7FAFD)
            accent = Color(widgetHex: 0x285E82)
            ink = Color(widgetHex: 0x223747)
            mutedInk = Color(widgetHex: 0x566D80)
            border = Color(widgetHex: 0xBECDD9)
            ornament = Color(widgetHex: 0x688DA8)
            control = Color(widgetHex: 0xE0EAF2)
        case ("ミッドナイト", _):
            background = Color(widgetHex: 0x1B2C40)
            accent = Color(widgetHex: 0x96CAE7)
            ink = Color(widgetHex: 0xE4EEF8)
            mutedInk = Color(widgetHex: 0xADC1D5)
            border = Color(widgetHex: 0x465E76)
            ornament = Color(widgetHex: 0x83B7D8)
            control = Color(widgetHex: 0x2B4055)
        case ("モダンノート", .light):
            background = Color(widgetHex: 0xFFFFFF)
            accent = Color(widgetHex: 0x5C42B5)
            ink = Color(widgetHex: 0x282833)
            mutedInk = Color(widgetHex: 0x666575)
            border = Color(widgetHex: 0xDEDEE8)
            ornament = Color(widgetHex: 0xB0A3D7)
            control = Color(widgetHex: 0xEEEAF9)
        case ("モダンノート", _):
            background = Color(widgetHex: 0x29292F)
            accent = Color(widgetHex: 0xC1B4F6)
            ink = Color(widgetHex: 0xF0F0F5)
            mutedInk = Color(widgetHex: 0xBCBAC8)
            border = Color(widgetHex: 0x515158)
            ornament = Color(widgetHex: 0x9A96B0)
            control = Color(widgetHex: 0x3B374A)
        case ("クラシック手帳", .dark):
            background = Color(widgetHex: 0x232C36)
            accent = Color(widgetHex: 0xD8BB83)
            ink = Color(widgetHex: 0xF1EBDD)
            mutedInk = Color(widgetHex: 0xBDB9AE)
            border = Color(widgetHex: 0x59606A)
            ornament = Color(widgetHex: 0xB99A61)
            control = Color(widgetHex: 0x343B43)
        default:
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
    var body: some Widget {
        CalendarTaskTodayWidget()
        CalendarTaskMonthWidget()
    }
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


struct CalendarTaskMonthWidget: Widget {
    let kind = "CalendarTaskMonthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarTaskWidgetProvider()) {
            CalendarTaskMonthWidgetView(entry: $0)
        }
        .configurationDisplayName("月の手帳")
        .description("月間カレンダーと今日の予定・タスクを、手帳のようにすっきりと。")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct CalendarTaskMonthWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: CalendarTaskWidgetEntry

    private var calendar: Calendar { .current }
    private var palette: WidgetPalette {
        let preferences = WidgetAppearancePreferences.current
        let scheme: ColorScheme = preferences.appearance == "ライト" ? .light
            : preferences.appearance == "ダーク" ? .dark : colorScheme
        return WidgetPalette(theme: preferences.theme, colorScheme: scheme)
    }

    var body: some View {
        Group {
            if family == .systemSmall {
                month(entry.date)
            } else {
                GeometryReader { geometry in
                    let columnWidth = max(0, (geometry.size.width - 24.5) / 2)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 12) {
                            month(entry.date)
                            if family == .systemLarge,
                               let next = calendar.date(byAdding: .month, value: 1, to: entry.date) {
                                Rectangle().fill(palette.border).frame(height: 0.5)
                                month(next)
                            }
                        }
                        .frame(width: columnWidth)
                        Rectangle().fill(palette.border).frame(width: 0.5)
                        agenda.frame(width: columnWidth, alignment: .topLeading)
                            .frame(maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [palette.background, palette.control.opacity(0.45)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(URL(string: "calendarTaskApp://today"))
    }

    private func month(_ date: Date) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(date.formatted(.dateTime.month(.wide)))
                    .font(.system(size: family == .systemSmall ? 18 : 16, weight: .medium, design: .serif))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
                Text(date.formatted(.dateTime.year()))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.mutedInk)
            }
            Grid(horizontalSpacing: 0, verticalSpacing: 1) {
                GridRow {
                    ForEach(0..<7, id: \.self) { index in
                        let weekday = (calendar.firstWeekday - 1 + index) % 7
                        Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(weekday == 0 ? Color.red : weekday == 6 ? Color.blue : palette.mutedInk)
                            .frame(maxWidth: .infinity)
                    }
                }
                let dates = calendar.monthGridDates(containing: date)
                ForEach(0..<6, id: \.self) { week in
                    GridRow {
                        ForEach(Array(dates.dropFirst(week * 7).prefix(7)), id: \.self) { day in
                            dayCell(day, month: date)
                        }
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date, month: Date) -> some View {
        let today = calendar.isDate(day, inSameDayAs: entry.date)
        let inMonth = calendar.isDate(day, inSameMonthAs: month)
        let weekday = calendar.component(.weekday, from: day)
        let isHoliday = calendar.isJapaneseHoliday(day)
        let tint: Color = isHoliday || weekday == 1 ? .red : weekday == 7 ? .blue : palette.ink
        return Text("\(calendar.component(.day, from: day))")
            .font(.system(size: family == .systemSmall ? 10.5 : family == .systemLarge ? 11 : 9, weight: today ? .bold : .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(today ? palette.background : tint.opacity(inMonth ? 1 : 0.3))
            .frame(maxWidth: .infinity)
            .frame(height: family == .systemLarge ? 17 : 14)
            .background {
                if today { Circle().fill(isHoliday || weekday == 1 || weekday == 7 ? tint : palette.accent)
                    .frame(width: family == .systemSmall ? 18 : family == .systemLarge ? 19 : 16,
                           height: family == .systemSmall ? 18 : family == .systemLarge ? 19 : 16) }
            }
            .accessibilityLabel(day.formatted(date: .complete, time: .omitted) + (today ? "、今日" : "") + (isHoliday ? "、祝日" : ""))
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TODAY")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(palette.accent)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(entry.date.formatted(.dateTime.day()))
                    .font(.system(size: 32, weight: .regular, design: .serif))
                Text(entry.date.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 9))
                    .foregroundStyle(palette.mutedInk)
            }
            .foregroundStyle(palette.ink)
            Rectangle().fill(palette.border).frame(height: 0.5)
            let items = (entry.snapshot.events + entry.snapshot.tasks).sorted {
                if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
                return $0.date < $1.date
            }
            if items.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Image(systemName: "leaf").font(.system(size: 18, weight: .light))
                        .foregroundStyle(palette.ornament)
                    Text("余白を楽しむ一日")
                        .font(.system(size: 11, weight: .medium, design: .serif))
                        .foregroundStyle(palette.ink)
                    Text("予定もタスクもありません")
                        .font(.system(size: 9)).foregroundStyle(palette.mutedInk)
                }
            } else {
                ForEach(Array(items.prefix(family == .systemLarge ? 5 : 1))) { item in
                    HStack(alignment: .top, spacing: 6) {
                        Capsule().fill(item.projectColor?.color ?? palette.accent)
                            .frame(width: 2, height: 27)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.isAllDay ? "終日" : item.date.formatted(date: .omitted, time: .shortened))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(palette.mutedInk)
                            Text(item.title).font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.ink).lineLimit(1)
                        }
                    }
                }
                let remaining = items.count - (family == .systemLarge ? 5 : 1)
                if remaining > 0 {
                    Text("ほか \(remaining)件")
                        .font(.system(size: 9)).foregroundStyle(palette.mutedInk)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("月の手帳・小", as: .systemSmall) { CalendarTaskMonthWidget() } timeline: {
    CalendarTaskWidgetEntry(date: .now, snapshot: .placeholder())
}
#Preview("月の手帳・中", as: .systemMedium) { CalendarTaskMonthWidget() } timeline: {
    CalendarTaskWidgetEntry(date: .now, snapshot: .placeholder())
}
#Preview("月の手帳・大", as: .systemLarge) { CalendarTaskMonthWidget() } timeline: {
    CalendarTaskWidgetEntry(date: .now, snapshot: .placeholder())
}
#Preview("月の手帳・空", as: .systemLarge) { CalendarTaskMonthWidget() } timeline: {
    CalendarTaskWidgetEntry(date: .now, snapshot: WidgetTodaySnapshot(date: .now, events: [], tasks: []))
}
