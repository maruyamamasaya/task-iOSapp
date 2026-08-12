import SwiftUI

struct MonthCalendarView: View {
    let dates: [Date?]; @Binding var selectedDate: Date
    private let columns = Array(repeating: GridItem(.flexible()), count: 7)
    var body: some View {
        VStack { HStack { ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { Text($0).font(.caption).frame(maxWidth: .infinity) } }; LazyVGrid(columns: columns) { ForEach(Array(dates.enumerated()), id: \.offset) { _, date in CalendarDayCell(date: date, isSelected: date.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } ?? false) { if let date { selectedDate = date } } } } }
    }
}
