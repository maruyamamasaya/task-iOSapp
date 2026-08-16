import SwiftUI

struct TaskListView: View {
    @StateObject var viewModel: TaskListViewModel
    @State private var route: EditorRoute?
    var body: some View {
        VStack(spacing: 0) {
            sectionBar
            Divider()
            filterBar
            if viewModel.visibleTasks.isEmpty {
                ContentUnavailableView(viewModel.emptyMessage, systemImage: "checklist").foregroundStyle(.secondary).frame(maxHeight: .infinity)
            } else {
                List(viewModel.visibleTasks) { task in
                    TaskRow(task: task, displayedCompletion: viewModel.displayedCompletion(for: task), toggle: { Task { await viewModel.toggleCompletion(task) } }, edit: { route = .task(task) })
                        .modifier(TaskQuickActionsModifier(task: task, projects: viewModel.projects.filter { !$0.isArchived },
                                                         edit: { route = .task(task) }, toggle: { Task { await viewModel.toggleCompletion(task) } },
                                                         moveToday: { Task { await viewModel.moveToToday(task) } },
                                                         moveTomorrow: { Task { await viewModel.moveToTomorrow(task) } },
                                                         reschedule: { date in Task { await viewModel.reschedule(task, to: date) } },
                                                         duplicate: { Task { await viewModel.duplicate(task) } },
                                                         assignProject: { id in Task { await viewModel.assign(task, to: id) } },
                                                         delete: { Task { await viewModel.delete(id: task.id) } }))
                        .listRowSeparatorTint(.secondary.opacity(0.25))
                }.listStyle(.plain)
            }
        }
        .navigationTitle("タスク")
        .searchable(text: $viewModel.searchText, prompt: "タイトル・メモを検索")
        .task { await viewModel.load() }
        .sheet(item: $route) { route in
            if case let .task(item) = route {
                TaskFormView(item: item, defaultDate: item.dueDate ?? item.startDate ?? .now, onSave: viewModel.save, onDelete: viewModel.delete)
            }
        }
    }
    private var sectionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TaskListSection.allCases) { section in
                    Button { viewModel.selectedSection = section } label: {
                        HStack(spacing: 5) { Text(section.rawValue); Text("\(viewModel.count(for: section))").font(.caption2).foregroundStyle(.secondary) }
                            .font(.subheadline.weight(viewModel.selectedSection == section ? .semibold : .regular))
                            .padding(.horizontal, 11).padding(.vertical, 7)
                            .background(viewModel.selectedSection == section ? Color.primary.opacity(0.08) : .clear, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
    private var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Menu { Picker("優先度", selection: $viewModel.priorityFilter) { ForEach(TaskPriorityFilter.allCases) { Text($0.rawValue).tag($0) } } }
                    label: { Label("優先度: \(viewModel.priorityFilter.rawValue)", systemImage: "line.3.horizontal.decrease") }
                Spacer()
                Menu { Picker("並び替え", selection: $viewModel.sortOption) { ForEach(TaskSortOption.allCases) { Text($0.rawValue).tag($0) } } }
                    label: { Label(viewModel.sortOption.rawValue, systemImage: "arrow.up.arrow.down") }
            }
            Menu {
                Picker("プロジェクト", selection: $viewModel.projectFilter) {
                    Text("すべてのプロジェクト").tag(TaskProjectFilter.all)
                    Text("プロジェクトなし").tag(TaskProjectFilter.unassigned)
                    ForEach(viewModel.projects.filter { !$0.isArchived }) { project in
                        Label(project.name, systemImage: project.iconName).tag(TaskProjectFilter.project(project.id))
                    }
                }
            } label: {
                Label(viewModel.projectFilterLabel, systemImage: "folder")
            }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 10)
    }
}
