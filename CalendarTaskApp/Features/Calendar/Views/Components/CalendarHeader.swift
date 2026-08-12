import SwiftUI

struct CalendarHeader: View {
    let month: Date; let previous: () -> Void; let next: () -> Void
    var body: some View { HStack { Button(action: previous) { Image(systemName: "chevron.left") }; Spacer(); Text(month.formatted(.dateTime.year().month(.wide))).font(.headline); Spacer(); Button(action: next) { Image(systemName: "chevron.right") } } }
}
