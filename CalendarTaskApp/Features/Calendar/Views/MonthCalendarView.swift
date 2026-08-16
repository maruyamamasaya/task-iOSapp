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
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 7) }
                ForEach(dates, id: \.self) { date in
                    CalendarDayCell(date: date, isToday: settings.highlightToday && isToday(date), isSelected: isSelected(date),
                                    isInDisplayedMonth: isInDisplayedMonth(date), hasEvent: hasEvent(date),
                                    hasIncompleteTask: hasIncompleteTask(date), projectColors: (settings.showProjectColorDots ? projectIDs(date) : []).map { id in
                                        projectStore.project(id: id)?.colorIdentifier.color ?? .secondary
                                    }) { select(date) }
                        .overlay(alignment: .top) { Divider() }
                }
            }
            Text("ドットは予定・未完了タスクのプロジェクト色です")
                .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
