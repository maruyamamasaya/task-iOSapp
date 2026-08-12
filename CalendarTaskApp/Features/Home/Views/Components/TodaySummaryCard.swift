import SwiftUI

struct TodaySummaryCard: View {
    let taskCount: Int; let eventCount: Int
    var body: some View {
        Section("今日") {
            LabeledContent("タスク", value: "\(taskCount) 件")
            LabeledContent("予定", value: "\(eventCount) 件")
        }
    }
}
