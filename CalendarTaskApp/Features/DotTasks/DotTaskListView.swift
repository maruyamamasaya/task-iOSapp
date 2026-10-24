import SwiftUI
import Combine
import UniformTypeIdentifiers

@MainActor final class DotTaskListViewModel: ObservableObject {
    let store: DotTaskStore
    @Published var searchText = ""
    private var observation: AnyCancellable?
    init(store: DotTaskStore) {
        self.store = store
        observation = store.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }
    var tasks: [DotTaskRecord] {
        (store.snapshot?.tasks ?? []).filter {
            searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.details.localizedCaseInsensitiveContains(searchText)
        }
    }
    func load() { store.load() }
    func refresh() async { await store.refresh() }
    func importFile(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url): store.importFile(from: url)
        case .failure: store.reportImportFailure()
        }
    }
}

struct DotTaskListView: View {
    @StateObject var viewModel: DotTaskListViewModel
    @State private var showsFileImporter = false
    var body: some View {
        List { Group {
            Section {
                Label("端末内の JSON", systemImage: "internaldrive")
                Text("dot のタスク JSON を選んで端末に保存します。Web との自動同期はありません。更新するときは新しい JSON を読み込んでください。")
                    .font(.caption).foregroundStyle(.secondary)
                if let snapshot = viewModel.store.snapshot {
                    Text("端末への保存: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                    Text("元データの更新: \(snapshot.updatedAt)").font(.caption)
                }
                Button("JSON を読み込む・更新") { showsFileImporter = true }
                    .disabled(viewModel.store.isRefreshing || !viewModel.store.canImport)
                if viewModel.store.isRefreshing { ProgressView("読み込み中") }
                if let error = viewModel.store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Text("保存済みデータは保持しています。JSON ファイルを確認してください。")
                        .font(.caption)
                }
            }
            if viewModel.tasks.isEmpty {
                ContentUnavailableView(viewModel.store.snapshot == nil ? "JSON を読み込んで表示" : "該当するタスクはありません", systemImage: "checklist")
            }
            ForEach(viewModel.tasks) { task in
                NavigationLink {
                    Form { Group {
                        Section("タスク") {
                            Text(task.title)
                            Text(task.details)
                        }
                        Section("dot の情報") {
                            LabeledContent("日付", value: task.date ?? "未定")
                            LabeledContent("日付ラベル", value: task.dateLabel)
                            LabeledContent("状態", value: task.status)
                            LabeledContent("分類", value: task.category)
                            if let subcategory = task.subcategory { LabeledContent("小分類", value: subcategory) }
                            if let parent = task.parentId { LabeledContent("親タスク", value: parent) }
                        }
                    }.themedListRows()
                    }.themedScreen().navigationTitle("タスク詳細")
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(task.title)
                        Text("\(task.date ?? "日付未定") ・ \(task.category) ・ \(task.status)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }.themedListRows()
        }
        .themedScreen()
        .navigationTitle("タスク")
        .searchable(text: $viewModel.searchText, prompt: "タイトル・詳細を検索")
        .task { viewModel.load() }
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.json], onCompletion: viewModel.importFile)
    }
}

struct DotPlannerListView: View {
    @StateObject var viewModel: TaskListViewModel
    @Binding var showsSearch: Bool
    @Binding var showsTagSettings: Bool
    @FocusState private var searchFocused: Bool
    var body: some View {
        VStack(spacing: 0) {
            if showsSearch {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("タスク名・詳細・タグを検索", text: $viewModel.searchText)
                        .focused($searchFocused)
                        .submitLabel(.search)
                    Button("閉じる") {
                        viewModel.searchText = ""
                        showsSearch = false
                    }
                }
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            if viewModel.selectedSection == .week {
                HStack {
                    Text(!viewModel.searchText.isEmpty && viewModel.searchesAllTasks ? "全体検索" : "今週").font(.headline)
                    Spacer()
                    if viewModel.searchText.isEmpty || !viewModel.searchesAllTasks {
                        Text(viewModel.weekRangeLabel).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                    .padding(.horizontal, 16).padding(.top, 8)
            }
            controls
            if !viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Toggle("全体から検索", isOn: $viewModel.searchesAllTasks)
                    .font(.caption).padding(.horizontal, 16)
            }
            List {
                Group {
                    if let error = viewModel.operationError {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    if viewModel.visibleTasks.isEmpty {
                        ContentUnavailableView(viewModel.emptyMessage, systemImage: "checklist")
                    }
                    if viewModel.selectedSection == .week {
                        ForEach(viewModel.projectGroups) { group in
                            Section {
                                ForEach(group.tasks) { task in taskRow(task) }
                            } header: {
                                HStack { Text(group.name); Spacer(); Text("\(group.tasks.count)件") }
                            }
                        }
                    } else if viewModel.groupsByDay {
                        ForEach(viewModel.dayGroups) { group in
                            Section {
                                ForEach(group.tasks) { task in taskRow(task) }
                            } header: {
                                HStack {
                                    Text(group.date?.formatted(.dateTime.year().month().day().weekday(.short)) ?? "日付なし")
                                    Spacer()
                                    Text("\(group.tasks.count)件")
                                }
                            }
                        }
                    } else {
                        ForEach(viewModel.visibleTasks) { task in taskRow(task) }
                    }
                }.themedListRows()
            }
            .listStyle(.plain)
        }
        .safeAreaInset(edge: .bottom) {
            if let task = viewModel.completionUndoTask {
                HStack {
                    Text(PlannerTaskPresentation(task: task).title).font(.caption).lineLimit(1)
                    Spacer()
                    Button("完了を取り消す") { Task { await viewModel.undoCompletion(taskID: task.id) } }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44).disabled(viewModel.isUndoingCompletion)
                }.padding(.horizontal, 16).background(.regularMaterial)
            }
        }
        .themedScreen()
        .navigationTitle("タスク")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: showsSearch) { _, visible in searchFocused = visible }
        .navigationDestination(isPresented: $showsTagSettings) {
            Form {
                Picker("タグ", selection: $viewModel.tagFilter) {
                    Text("すべてのタグ").tag(TaskTagFilter.all)
                    Text("タグなし").tag(TaskTagFilter.untagged)
                    ForEach(viewModel.availableTags) { tag in Text(tag.name).tag(TaskTagFilter.tag(tag.id)) }
                }
                .pickerStyle(.inline)
            }
            .navigationTitle("タグ設定")
            .navigationBarTitleDisplayMode(.inline)
            .themedScreen()
        }
        .task { await viewModel.load() }
    }
    private var controls: some View {
        HStack(spacing: 6) {
            Menu {
                Picker("大分類", selection: $viewModel.area) {
                    ForEach(PlannerArea.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: { filterControlLabel(viewModel.area.rawValue) }
            Menu {
                ForEach(PlannerKind.allCases) { value in
                    Button(value.rawValue) { viewModel.selectKind(value) }
                }
            } label: { filterControlLabel("種別: " + viewModel.kind.rawValue) }
            Menu {
                ForEach(PlannerStatus.allCases) { value in
                    Button(value.rawValue) { viewModel.selectStatus(value) }
                }
            } label: { filterControlLabel("状態: " + viewModel.status.rawValue) }
            Menu {
                Picker("表示対象", selection: $viewModel.selectedSection) {
                    ForEach(TaskListSection.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("優先度", selection: $viewModel.priorityFilter) {
                    ForEach(TaskPriorityFilter.allCases) { Text("優先度: " + $0.rawValue).tag($0) }
                }
                Picker("プロジェクト", selection: $viewModel.projectFilter) {
                    Text("すべてのプロジェクト").tag(TaskProjectFilter.all)
                    Text("プロジェクトなし").tag(TaskProjectFilter.unassigned)
                    ForEach(viewModel.projects) { Text($0.name).tag(TaskProjectFilter.project($0.id)) }
                }
                Toggle("日付ごとにまとめる", isOn: $viewModel.groupsByDay)
                Picker("並び替え", selection: $viewModel.sortOption) {
                    ForEach(TaskSortOption.allCases) { Text($0.rawValue).tag($0) }
                }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
                    .frame(width: 48, height: 48)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("表示対象・優先度・プロジェクト・並び替え")
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
    private func filterControlLabel(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
    }
    private func taskRow(_ task: TaskItem) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await viewModel.toggleCompletion(task) }
            } label: {
                Image(systemName: viewModel.displayedCompletion(for: task) ? "checkmark.circle.fill" : "circle")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(PlannerTaskPresentation(task: task).title + (viewModel.displayedCompletion(for: task) ? "を未完了に戻す" : "を完了にする"))
            NavigationLink {
                TaskFormView(item: task, defaultDate: task.dueDate ?? task.startDate ?? .now,
                             onSave: viewModel.save, onDelete: viewModel.delete)
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(PlannerTaskPresentation(task: task).title)
                        .font(.body.weight(.medium)).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .strikethrough(viewModel.displayedCompletion(for: task))
                    Text(viewModel.kindLabel(for: task) + " · " + viewModel.statusLabel(for: task))
                        .font(.caption).foregroundStyle(.secondary)
                    if viewModel.selectedSection == .week {
                        if let step = viewModel.nextStep(for: task), !step.isEmpty {
                            Text(step).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                        }
                        Text(viewModel.scheduleText(for: task)).font(.caption).foregroundStyle(.secondary)
                        if let deadline = viewModel.plannerMetadata[task.id]?.deadlineText {
                            Label("固定期限 " + deadline, systemImage: "flag")
                                .font(.caption.weight(.semibold)).foregroundStyle(.primary)
                        }
                        if let notice = PlannerTaskPresentation(task: task).syncNotice {
                            Text(notice).font(.caption2).foregroundStyle(.secondary)
                        }
                    } else if !viewModel.groupsByDay {
                        Text((task.dueDate ?? task.startDate)?.formatted(.dateTime.month().day()) ?? "日付なし")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let tag = task.tags.first {
                        Text("#" + tag.name + (task.tags.count > 1 ? " +\(task.tags.count - 1)" : ""))
                            .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 16))
    }
}
