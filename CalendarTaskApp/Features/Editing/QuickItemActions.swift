import SwiftUI

struct TaskRowActions {
    let edit: (TaskItem) -> Void
    let toggle: (TaskItem) -> Void
    let moveToday: (TaskItem) -> Void
    let moveTomorrow: (TaskItem) -> Void
    let reschedule: (TaskItem, Date) -> Void
    let duplicate: (TaskItem) -> Void
    let delete: (TaskItem) -> Void
}

struct EventRowActions {
    let edit: (CalendarEvent) -> Void
    let reschedule: (CalendarEvent, Date) -> Void
    let duplicate: (CalendarEvent) -> Void
    let delete: (CalendarEvent) -> Void
}

struct TaskQuickActionsModifier: ViewModifier {
    let task: TaskItem
    var projects: [Project] = []
    var usesCustomSwipe = false
    let edit: () -> Void
    let toggle: () -> Void
    let moveToday: () -> Void
    let moveTomorrow: () -> Void
    let reschedule: (Date) -> Void
    let duplicate: () -> Void
    let assignProject: (UUID?) -> Void
    let delete: () -> Void
    @State private var showsDatePicker = false
    @State private var confirmsDeletion = false
    @State private var showsQuickActions = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button(action: toggle) { Label(task.isCompleted ? "未完了" : "完了", systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark") }
                    .tint(.green)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if task.recurrenceRule == nil {
                    Button(action: moveTomorrow) { Label("明日へ", systemImage: "sunrise") }.tint(.blue)
                    Button { showsDatePicker = true } label: { Label("日付変更", systemImage: "calendar") }.tint(.indigo)
                }
                Button(action: edit) { Label("その他", systemImage: "ellipsis") }.tint(.gray)
            }
            .contextMenu {
                Button(action: edit) { Label(task.recurrenceRule == nil ? "編集" : "系列全体を編集", systemImage: "pencil") }
                if task.recurrenceRule == nil {
                    Button(action: moveToday) { Label("今日へ移動", systemImage: "sun.max") }
                    Button(action: moveTomorrow) { Label("明日へ送る", systemImage: "sunrise") }
                    Button { showsDatePicker = true } label: { Label("日付変更", systemImage: "calendar") }
                }
                Button(action: duplicate) { Label("複製", systemImage: "plus.square.on.square") }
                if !projects.isEmpty {
                    Menu("プロジェクト") {
                        Button("なし") { assignProject(nil) }
                        ForEach(projects) { project in Button { assignProject(project.id) } label: { Label(project.name, systemImage: project.iconName) } }
                    }
                }
                Button(action: toggle) { Label(task.isCompleted ? "未完了に戻す" : "完了", systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle") }
                Divider()
                Button("削除", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
            }
            .sheet(isPresented: $showsDatePicker) {
                CompactDatePicker(title: "タスクの日付", initialDate: task.dueDate ?? task.startDate ?? .now, apply: reschedule)
            }
            .confirmationDialog("このタスクを削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                Button("削除", role: .destructive, action: delete)
            }
            .confirmationDialog("クイック操作", isPresented: $showsQuickActions, titleVisibility: .visible) {
                if task.recurrenceRule == nil {
                    Button("明日へ送る", action: moveTomorrow)
                    Button("日付変更") { showsDatePicker = true }
                }
                Button(task.recurrenceRule == nil ? "その他・編集" : "系列全体を編集", action: edit)
                Button("キャンセル", role: .cancel) {}
            }
            .simultaneousGesture(DragGesture(minimumDistance: 28).onEnded { value in
                guard usesCustomSwipe, abs(value.translation.width) > abs(value.translation.height) * 1.4 else { return }
                if value.translation.width > 55 { toggle() }
                else if value.translation.width < -55 { showsQuickActions = true }
            })
    }
}

struct EventQuickActionsModifier: ViewModifier {
    let event: CalendarEvent
    let edit: () -> Void
    let reschedule: (Date) -> Void
    let duplicate: () -> Void
    let delete: () -> Void
    @State private var showsDatePicker = false
    @State private var confirmsDeletion = false

    func body(content: Content) -> some View {
        content.contextMenu {
            Button(action: edit) { Label(event.recurrenceRule == nil ? "編集" : "系列全体を編集", systemImage: "pencil") }
            if event.recurrenceRule == nil { Button { showsDatePicker = true } label: { Label("日付変更", systemImage: "calendar") } }
            Button(action: duplicate) { Label("複製", systemImage: "plus.square.on.square") }
            Divider()
            Button("削除", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
        }
        .sheet(isPresented: $showsDatePicker) {
            CompactDatePicker(title: "予定の日付", initialDate: event.startDate, apply: reschedule)
        }
        .confirmationDialog("この予定を削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("削除", role: .destructive, action: delete)
        }
    }
}

private struct CompactDatePicker: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let apply: (Date) -> Void
    @State private var date: Date
    init(title: String, initialDate: Date, apply: @escaping (Date) -> Void) {
        self.title = title; self.apply = apply; _date = State(initialValue: initialDate)
    }
    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $date, displayedComponents: .date).datePickerStyle(.graphical).padding()
                .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("変更") { apply(date); dismiss() } }
                }
        }.presentationDetents([.medium])
    }
}
