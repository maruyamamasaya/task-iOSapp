import SwiftUI

struct CalendarView: View {
    @StateObject var viewModel: CalendarViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                CalendarHeader(month: viewModel.displayedMonth, previous: { viewModel.moveMonth(by: -1) }, next: { viewModel.moveMonth(by: 1) })
                MonthCalendarView(dates: viewModel.monthDates, selectedDate: $viewModel.selectedDate)
                DailyScheduleList(date: viewModel.selectedDate, events: viewModel.selectedEvents, tasks: viewModel.selectedTasks)
            }.padding()
        }.navigationTitle("カレンダー").task { await viewModel.load() }
    }
}
