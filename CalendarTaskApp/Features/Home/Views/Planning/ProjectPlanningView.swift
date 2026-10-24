import SwiftUI

enum ProjectPlanningMode: String, CaseIterable, Identifiable {
    case wbs = "WBS", gantt = "ガント"
    var id: Self { self }
}

// A screen-local draft for reviewing the UI. Never written to task storage or the relay.
struct PlanningDraftItem: Identifiable {
    let id: UUID
    var parentID: UUID?
    var title: String
    var start: Date
    var end: Date
    var progress: Double

    init(id: UUID = UUID(), parentID: UUID? = nil, title: String, start: Date, end: Date, progress: Double = 0) {
        self.id = id; self.parentID = parentID; self.title = title
        self.start = start; self.end = end; self.progress = progress
    }
}

struct PlanningDraftRow: Identifiable {
    let item: PlanningDraftItem
    let code: String
    let depth: Int
    let hasChildren: Bool
    var id: UUID { item.id }

    static func flatten(_ items: [PlanningDraftItem], collapsed: Set<UUID> = []) -> [Self] {
        var visited = Set<UUID>()
        func children(of parent: UUID?, prefix: String, depth: Int) -> [Self] {
            var result: [Self] = []
            for (index, item) in items.filter({ $0.parentID == parent }).enumerated() {
                guard visited.insert(item.id).inserted else { continue }
                let code = prefix.isEmpty ? "\(index + 1)" : "\(prefix).\(index + 1)"
                result.append(Self(item: item, code: code, depth: depth,
                                   hasChildren: items.contains { $0.parentID == item.id }))
                if !collapsed.contains(item.id) {
                    result += children(of: item.id, prefix: code, depth: depth + 1)
                }
            }
            return result
        }
        return children(of: nil, prefix: "", depth: 0)
    }
}

struct ProjectPlanningProjectListView: View {
    @EnvironmentObject private var projects: ProjectStore
    let mode: ProjectPlanningMode

    var body: some View {
        List {
            if let error = projects.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
            Section {
                if projects.activeProjects.isEmpty {
                    ContentUnavailableView("プロジェクトがありません", systemImage: "folder",
                                           description: Text("プロジェクトを登録すると、ここから計画を開けます。"))
                } else {
                    ForEach(projects.activeProjects) { project in
                        NavigationLink {
                            ProjectPlanningView(mode: mode, project: project)
                        } label: {
                            Label(project.name, systemImage: project.iconName)
                                .font(.body.weight(.medium))
                                .padding(.vertical, 8)
                        }
                    }
                }
            } header: {
                Text("プロジェクトを選択")
            } footer: {
                Text("計画はプレビューです。工程の変更は保存されません。")
            }
        }
        .navigationTitle(mode.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
    }
}

struct ProjectPlanningView: View {
    @State var mode: ProjectPlanningMode
    let project: Project
    @State private var items: [PlanningDraftItem] = []
    @State private var collapsed = Set<UUID>()
    @State private var editing: PlanningDraftItem?
    private var rows: [PlanningDraftRow] { PlanningDraftRow.flatten(items, collapsed: collapsed) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("プレビュー・変更は保存されません")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    metric("工程", value: "\(items.count)項目")
                    Spacer()
                    metric("完了", value: "\(items.filter { $0.progress == 1 }.count)項目")
                    Spacer()
                    metric("表示", value: mode.rawValue)
                }
                Picker("表示", selection: $mode) {
                    ForEach(ProjectPlanningMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Text("工程").font(.headline)
                if items.isEmpty {
                    ContentUnavailableView("工程がありません", systemImage: "list.bullet.indent",
                                           description: Text("工程データが登録されると、ここに表示されます。"))
                } else if mode == .wbs {
                    wbs
                } else {
                    Label("左右にスクロールして期間を確認", systemImage: "arrow.left.and.right")
                        .font(.caption).foregroundStyle(.secondary)
                    gantt
                }
            }.padding(16)
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .themedScreen()
        .sheet(item: $editing) { item in
            PlanningDraftEditor(item: item, parents: items.filter { $0.id != item.id && !isDescendant($0, of: item.id) }) { value in
                var next = items
                if let index = next.firstIndex(where: { $0.id == value.id }) { next[index] = value }
                else { next.append(value) }
                items = next
            }
        }
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
        }
    }

    private var wbs: some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 8) {
                    Button {
                        if collapsed.contains(row.id) { collapsed.remove(row.id) }
                        else { collapsed.insert(row.id) }
                    } label: {
                        Image(systemName: row.hasChildren ? (collapsed.contains(row.id) ? "chevron.right" : "chevron.down") : "minus")
                            .frame(width: 24, height: 44)
                    }
                    .disabled(!row.hasChildren)
                    .accessibilityLabel(collapsed.contains(row.id) ? "工程を展開" : "工程を折りたたむ")
                    Button { editing = row.item } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(row.code + "  " + row.item.title).font(.subheadline.weight(row.hasChildren ? .semibold : .regular))
                            Text(period(row.item)).font(.caption).foregroundStyle(.secondary)
                            ProgressView(value: row.item.progress)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(Int(row.item.progress * 100))%") .font(.caption.monospacedDigit())
                    }.buttonStyle(.plain)
                }
                .padding(.leading, CGFloat(row.depth) * 14)
                .padding(.vertical, 10)
                Divider()
            }
        }
    }

    private var gantt: some View {
        let calendar = Calendar.current
        let first = calendar.startOfDay(for: items.map(\.start).min() ?? .now)
        let last = calendar.startOfDay(for: items.map(\.end).max() ?? first)
        let count = min(180, max(7, (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 2))
        let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        return ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    Text("WBS / 工程").frame(width: 160, alignment: .leading)
                    ForEach(days, id: \.self) { day in
                        Text(day.formatted(.dateTime.month().day())).frame(width: 44)
                    }
                }.font(.caption2).frame(height: 36)
                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        Button { editing = row.item } label: {
                            Text(row.code + " " + row.item.title)
                                .font(.caption).lineLimit(2)
                                .padding(.leading, CGFloat(row.depth) * 8)
                                .frame(width: 160, height: 48, alignment: .leading)
                        }.buttonStyle(.plain)
                        HStack(spacing: 0) {
                            ForEach(days, id: \.self) { day in
                                Rectangle()
                                    .fill(calendar.isDateInWeekend(day) ? Color.secondary.opacity(0.10) : Color.secondary.opacity(0.03))
                                    .frame(width: 44, height: 48)
                                    .overlay(alignment: .trailing) { Divider() }
                            }
                        }
                        .overlay(alignment: .leading) {
                            let offset = max(0, calendar.dateComponents([.day], from: first, to: calendar.startOfDay(for: row.item.start)).day ?? 0)
                            let length = max(1, (calendar.dateComponents([.day], from: calendar.startOfDay(for: row.item.start), to: calendar.startOfDay(for: row.item.end)).day ?? 0) + 1)
                            if offset < count {
                                Capsule().fill(.tint.opacity(0.25))
                                    .overlay(alignment: .leading) {
                                        Capsule().fill(.tint).frame(width: (CGFloat(min(length, count - offset)) * 44 - 4) * row.item.progress)
                                    }
                                    .frame(width: CGFloat(min(length, count - offset)) * 44 - 4, height: 20)
                                    .offset(x: CGFloat(offset) * 44 + 2)
                                    .accessibilityLabel(row.item.title + "、" + period(row.item))
                            }
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func period(_ item: PlanningDraftItem) -> String {
        item.start.formatted(.dateTime.month().day()) + " – " + item.end.formatted(.dateTime.month().day())
    }
    private func isDescendant(_ item: PlanningDraftItem, of id: UUID) -> Bool {
        var parent = item.parentID
        var visited = Set<UUID>()
        while let value = parent, visited.insert(value).inserted {
            if value == id { return true }
            parent = items.first { $0.id == value }?.parentID
        }
        return false
    }
}

private struct PlanningDraftEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: PlanningDraftItem
    let parents: [PlanningDraftItem]
    let save: (PlanningDraftItem) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField("工程名", text: $item.title)
                Picker("親工程", selection: $item.parentID) {
                    Text("なし").tag(UUID?.none)
                    ForEach(parents) { Text($0.title).tag(Optional($0.id)) }
                }
                DatePicker("開始", selection: $item.start, displayedComponents: .date)
                DatePicker("終了", selection: $item.end, in: item.start..., displayedComponents: .date)
                Slider(value: $item.progress, in: 0...1, step: 0.1) { Text("進捗") }
                Text("進捗 \(Int(item.progress * 100))%")
                Text("プレビュー用です。画面を閉じると変更は失われます。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("工程を試す")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: item.start) { _, date in if item.end < date { item.end = date } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("反映") { item.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines); save(item); dismiss() }
                        .disabled(item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.end < item.start)
                }
            }
        }
    }
}
