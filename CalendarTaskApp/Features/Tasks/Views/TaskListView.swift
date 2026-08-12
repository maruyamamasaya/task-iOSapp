import SwiftUI

struct TaskListView: View {
    @StateObject var viewModel: TaskListViewModel
    var body: some View {
        List {
            Toggle("完了済みを表示", isOn: $viewModel.showCompleted)
            ForEach(viewModel.visibleTasks) { TaskRow(task: $0) }
        }.navigationTitle("タスク").task { await viewModel.load() }
    }
}
