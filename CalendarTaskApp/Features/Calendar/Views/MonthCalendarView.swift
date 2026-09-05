import SwiftUI

struct MonthCalendarView: View {
    let dates: [Date]
    let weekdaySymbols: [String]
    let isToday: (Date) -> Bool
    let isSelected: (Date) -> Bool
    let isInDisplayedMonth: (Date) -> Bool
    let hasEvent: (Date) -> Bool
    let hasIncompleteTask: (Date) -> Bool
    let projectIDs: (Date) -> [UUID?]
    let select: (Date) -> Void
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol).font(.caption2.weight(.medium))
                        .foregroundStyle(weekdayHeaderColor(at: index))
                        .frame(maxWidth: .infinity).padding(.bottom, 7)
                }
                ForEach(dates, id: \.self) { date in
                    CalendarDayCell(date: date, isToday: settings.highlightToday && isToday(date), isSelected: isSelected(date),
                                    isInDisplayedMonth: isInDisplayedMonth(date), hasEvent: hasEvent(date),
                                    hasIncompleteTask: hasIncompleteTask(date), projectColors: (settings.showProjectColorDots ? projectIDs(date) : []).map { id in
                                        projectStore.project(id: id)?.colorIdentifier.color ?? .secondary
                                    }) { select(date) }
                        .overlay(alignment: .top) { Divider() }
                }
            }
            Text("● 予定  ▫ 未完了タスク · 下段のドットはプロジェクト色")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func weekdayHeaderColor(at index: Int) -> Color {
        let weekday = ((settings.weekStartDay.calendarWeekday - 1 + index) % 7) + 1
        if weekday == 1 { return colorScheme == .dark ? Color(red: 1, green: 0.55, blue: 0.58) : Color(red: 0.68, green: 0.08, blue: 0.12) }
        if weekday == 7 { return colorScheme == .dark ? Color(red: 0.48, green: 0.72, blue: 1) : Color(red: 0.05, green: 0.27, blue: 0.62) }
        return .secondary
    }
}
