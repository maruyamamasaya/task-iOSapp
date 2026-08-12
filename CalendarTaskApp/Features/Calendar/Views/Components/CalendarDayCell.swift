import SwiftUI

struct CalendarDayCell: View {
    let date: Date?; let isSelected: Bool; let select: () -> Void
    var body: some View { Button(action: select) { Text(date.map { String(Calendar.current.component(.day, from: $0)) } ?? " ").frame(maxWidth: .infinity).padding(.vertical, 8).background(isSelected ? Color.accentColor : .clear).foregroundStyle(isSelected ? .white : .primary).clipShape(Circle()) }.disabled(date == nil) }
}
