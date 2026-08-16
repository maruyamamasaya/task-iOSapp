import SwiftUI

struct ProjectManagementView: View {
    @EnvironmentObject private var store: ProjectStore
    @State private var editingProject: Project?
    @State private var createsProject = false

    var body: some View {
        List {
            Section("使用中") {
                ForEach(store.activeProjects) { project in
                    projectRow(project)
                }
                if store.activeProjects.isEmpty {
                    Text("プロジェクトはまだありません").foregroundStyle(.secondary)
                }
            }
            let archived = store.projects.filter(\.isArchived)
            if !archived.isEmpty {
                Section("アーカイブ") { ForEach(archived) { project in projectRow(project) } }
            }
        }
        .navigationTitle("プロジェクト")
        .toolbar { Button { createsProject = true } label: { Image(systemName: "plus") } }
        .sheet(isPresented: $createsProject) { ProjectEditorView(project: nil) }
        .sheet(item: $editingProject) { ProjectEditorView(project: $0) }
        .task { await store.load() }
    }

    private func projectRow(_ project: Project) -> some View {
        Button { editingProject = project } label: {
            HStack(spacing: 12) {
                Image(systemName: project.iconName).foregroundStyle(project.colorIdentifier.color).frame(width: 24)
                Text(project.name).foregroundStyle(.primary)
                Spacer()
                if project.isArchived { Text("アーカイブ済み").font(.caption).foregroundStyle(.secondary) }
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
        }.buttonStyle(.plain)
    }
}

private struct ProjectEditorView: View {
    @EnvironmentObject private var store: ProjectStore
    @Environment(\.dismiss) private var dismiss
    let project: Project?
    @State private var name: String
    @State private var color: ProjectColor
    @State private var iconName: String
    @State private var confirmsDeletion = false

    init(project: Project?) {
        self.project = project
        _name = State(initialValue: project?.name ?? "")
        _color = State(initialValue: project?.colorIdentifier ?? .blue)
        _iconName = State(initialValue: project?.iconName ?? "briefcase")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") { TextField("仕事、個人、勉強…", text: $name) }
                Section("色") {
                    Picker("色", selection: $color) {
                        ForEach(ProjectColor.allCases, id: \.self) { value in
                            Label(value.rawValue.capitalized, systemImage: "circle.fill").foregroundStyle(value.color).tag(value)
                        }
                    }
                }
                Section("アイコン") {
                    Picker("アイコン", selection: $iconName) {
                        ForEach(ProjectIcon.presets, id: \.self) { Label($0, systemImage: $0).tag($0) }
                    }
                }
                if let project {
                    Section {
                        Button(project.isArchived ? "アーカイブから戻す" : "アーカイブ") {
                            Task { await store.setArchived(!project.isArchived, id: project.id); dismiss() }
                        }
                        Button("削除", role: .destructive) { confirmsDeletion = true }
                    } footer: { Text("削除時、紐づくタスクと予定は残り、プロジェクトなしになります。") }
                }
            }
            .navigationTitle(project == nil ? "プロジェクトを作成" : "プロジェクトを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
            .confirmationDialog("プロジェクトを削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("削除", role: .destructive) { if let project { Task { await store.delete(id: project.id); dismiss() } } }
            }
        }
    }

    private func save() {
        let now = Date.now
        let value = Project(id: project?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            colorIdentifier: color, iconName: iconName, isArchived: project?.isArchived ?? false,
                            createdAt: project?.createdAt ?? now, updatedAt: now)
        Task { await store.save(value); dismiss() }
    }
}
