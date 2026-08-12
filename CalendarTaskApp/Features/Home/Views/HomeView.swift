import SwiftUI

struct HomeView: View {
    @StateObject var viewModel: HomeViewModel
    var body: some View {
        List {
            Section { Text(viewModel.today.formatted(date: .complete, time: .omitted)).font(.headline) }
            TodaySummaryCard(taskCount: viewModel.todayTasks.count, eventCount: viewModel.todayEvents.count)
            Section("未完了タスク") { ForEach(viewModel.incompleteTasks.prefix(3)) { TaskRow(task: $0) } }
            Section("次の予定") {
                if let event = viewModel.nextEvent { Label(event.title, systemImage: "calendar.badge.clock"); Text(event.startDate.formatted()).font(.caption) }
                else { Text("予定はありません").foregroundStyle(.secondary) }
            }
        }.navigationTitle("ホーム").task { await viewModel.load() }
    }
}
