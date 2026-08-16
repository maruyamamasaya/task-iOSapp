import SwiftUI

enum AddItemType: String, CaseIterable {
    case task = "タスク"
    case event = "予定"
    case note = "メモ"
    var symbol: String { switch self { case .task: "checkmark.circle"; case .event: "calendar"; case .note: "pencil.line" } }
}

enum EditorRoute: Identifiable {
    case new(AddItemType, Date)
    case task(TaskItem)
    case event(CalendarEvent)
    case note(DailyNote?, Date)
    case quickAddDraft(QuickAddResult)

    var id: String {
        switch self {
        case let .new(type, date): "new-\(type.rawValue)-\(date.timeIntervalSinceReferenceDate)"
        case let .task(item): "task-\(item.id)"
        case let .event(item): "event-\(item.id)"
        case let .note(note, date): "note-\(note?.id.uuidString ?? String(date.timeIntervalSinceReferenceDate))"
        case let .quickAddDraft(result): "quick-\(result.type.rawValue)-\(result.date.timeIntervalSinceReferenceDate)-\(result.title)"
        }
    }
}

struct AddItemMenu: View {
    let date: Date
    @Binding var route: EditorRoute?
    var body: some View {
        Menu {
            ForEach(AddItemType.allCases, id: \.self) { type in
                Button { route = .new(type, date) } label: { Label(type.rawValue, systemImage: type.symbol) }
            }
        } label: { Image(systemName: "plus") }
        .accessibilityLabel("手帳に追加")
    }
}

struct EditorHostView: View {
    let route: EditorRoute
    let noteForDate: (Date) -> DailyNote?
    let saveTask: (TaskItem) async -> Bool
    let deleteTask: (UUID) async -> Void
    let saveEvent: (CalendarEvent) async -> Bool
    let deleteEvent: (UUID) async -> Void
    let saveNote: (DailyNote) async -> Void
    let deleteNote: (UUID) async -> Void

    var body: some View {
        switch route {
        case let .new(.task, date): TaskFormView(item: nil, defaultDate: date, onSave: saveTask, onDelete: deleteTask)
        case let .new(.event, date): EventFormView(item: nil, defaultDate: date, onSave: saveEvent, onDelete: deleteEvent)
        case let .new(.note, date): NoteFormView(note: noteForDate(date), defaultDate: date, onSave: { await saveNote($0); return true }, onDelete: deleteNote)
        case let .task(item): TaskFormView(item: item, defaultDate: item.dueDate ?? item.startDate ?? .now, onSave: saveTask, onDelete: deleteTask)
        case let .event(item): EventFormView(item: item, defaultDate: item.startDate, onSave: saveEvent, onDelete: deleteEvent)
        case let .note(note, date): NoteFormView(note: note, defaultDate: date, onSave: { await saveNote($0); return true }, onDelete: deleteNote)
        case let .quickAddDraft(result):
            switch result.type {
            case .task: TaskFormView(item: result.task(), defaultDate: result.date, isCreating: true, onSave: saveTask, onDelete: deleteTask)
            case .event: EventFormView(item: result.event(), defaultDate: result.date, isCreating: true, onSave: saveEvent, onDelete: deleteEvent)
            case .note: NoteFormView(note: result.note(existing: noteForDate(result.date)), defaultDate: result.date, isCreating: noteForDate(result.date) == nil, onSave: { await saveNote($0); return true }, onDelete: deleteNote)
            }
        }
    }
}

private struct EditorScaffold<Content: View>: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let canSave: Bool
    let existingID: UUID?
    let save: () async -> Bool
    let delete: ((UUID) async -> Void)?
    let hasUnsavedChanges: Bool
    @ViewBuilder let content: Content
    @State private var confirmsDeletion = false
    @State private var showsSaveError = false
    @State private var confirmsCancellation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    content
                    if let existingID, let delete {
                        Divider().padding(.top, 12)
                        Button(role: .destructive) { confirmsDeletion = true } label: { Label("削除", systemImage: "trash") }
                            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                            .confirmationDialog("この項目を削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
                                Button("削除", role: .destructive) { Task { await delete(existingID); dismiss() } }
                            }
                    }
                }.padding(.horizontal, 24).padding(.vertical, 22)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { if hasUnsavedChanges { confirmsCancellation = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { Task { if await save() { dismiss() } else { showsSaveError = true } } }.disabled(!canSave) }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("完了") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
            }
            .alert("保存できませんでした", isPresented: $showsSaveError) { Button("OK", role: .cancel) {} } message: { Text("入力内容は保持されています。もう一度お試しください。") }
            .confirmationDialog("変更を破棄しますか？", isPresented: $confirmsCancellation, titleVisibility: .visible) {
                Button("変更を破棄", role: .destructive) { dismiss() }
                Button("編集を続ける", role: .cancel) {}
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
        }
    }
}

struct TaskFormView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var settings: SettingsStore
    let original: TaskItem?
    let isCreating: Bool
    let onSave: (TaskItem) async -> Bool
    let onDelete: (UUID) async -> Void
    @State private var title: String; @State private var date: Date; @State private var isAllDay: Bool
    @State private var note: String; @State private var priority: TaskPriority
    @State private var reminderDate: Date?
    @State private var recurrenceOption: RecurrenceOption
    @State private var projectID: UUID?
    @FocusState private var titleFocused: Bool
    @State private var appliedDefaults = false

    init(item: TaskItem?, defaultDate: Date, isCreating: Bool? = nil, onSave: @escaping (TaskItem) async -> Bool, onDelete: @escaping (UUID) async -> Void) {
        original = item; self.isCreating = isCreating ?? (item == nil); self.onSave = onSave; self.onDelete = onDelete
        _title = State(initialValue: item?.title ?? ""); _date = State(initialValue: item?.dueDate ?? defaultDate)
        _isAllDay = State(initialValue: item?.isAllDay ?? true); _note = State(initialValue: item?.note ?? "")
        _priority = State(initialValue: item?.priority ?? .normal)
        _reminderDate = State(initialValue: item?.reminderDate)
        _recurrenceOption = State(initialValue: RecurrenceOption(rule: item?.recurrenceRule))
        _projectID = State(initialValue: item?.projectID)
    }
    var body: some View {
        EditorScaffold(title: isCreating ? "タスクを書く" : "タスクを編集", canSave: !title.trimmed.isEmpty,
                       existingID: isCreating ? nil : original?.id, save: save, delete: onDelete, hasUnsavedChanges: hasChanges) {
            editorTitle("やること", text: $title, focused: $titleFocused)
            ruledSection("日付") {
                DatePicker("日付", selection: $date, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute]).labelsHidden()
                Toggle("終日", isOn: $isAllDay)
            }
            ruledSection("詳細") {
                Picker("優先度", selection: $priority) { ForEach(TaskPriority.allCases, id: \.self) { Text($0.displayName).tag($0) } }
                TextField("メモ（任意）", text: $note, axis: .vertical).lineLimit(2...5)
            }
            ruledSection("プロジェクト") {
                Picker("プロジェクト", selection: $projectID) {
                    Text("なし").tag(Optional<UUID>.none)
                    ForEach(projectStore.activeProjects) { project in
                        Label(project.name, systemImage: project.iconName).tag(Optional(project.id))
                    }
                }
            }
            ruledSection("リマインダー") { ReminderEditor(reminderDate: $reminderDate, referenceDate: date) }
            ruledSection("繰り返し") { Picker("繰り返し", selection: $recurrenceOption) { ForEach(RecurrenceOption.allCases) { Text($0.rawValue).tag($0) } } }
        }.onAppear {
            if original == nil && !appliedDefaults {
                let defaults = settings.taskCreationDefaults(referenceDate: date)
                priority = defaults.priority; isAllDay = defaults.isAllDay; reminderDate = defaults.reminderDate; appliedDefaults = true
            }
            if isCreating { titleFocused = true }
        }
    }
    private func save() async -> Bool {
        let now = Date.now
        let value = TaskItem(id: original?.id ?? UUID(), title: title.trimmed, note: note, startDate: date, dueDate: date,
                             isAllDay: isAllDay, isCompleted: original?.isCompleted ?? false, completedAt: original?.completedAt,
                             priority: priority, reminderDate: reminderDate, recurrenceRule: recurrenceOption.rule, projectID: projectID,
                             category: original?.category, tags: original?.tags ?? [],
                             createdAt: original?.createdAt ?? now, updatedAt: now)
        return await onSave(value)
    }
    private var hasChanges: Bool {
        guard let original else { return !title.trimmed.isEmpty || !note.isEmpty || projectID != nil || reminderDate != nil }
        return title != original.title || note != original.note || date != (original.dueDate ?? original.startDate) ||
            isAllDay != original.isAllDay || priority != original.priority || reminderDate != original.reminderDate ||
            recurrenceOption.rule != original.recurrenceRule || projectID != original.projectID
    }
}

struct EventFormView: View {
    @EnvironmentObject private var projectStore: ProjectStore
    @EnvironmentObject private var settings: SettingsStore
    let original: CalendarEvent?; let isCreating: Bool; let onSave: (CalendarEvent) async -> Bool; let onDelete: (UUID) async -> Void
    @State private var title: String; @State private var start: Date; @State private var end: Date
    @State private var isAllDay: Bool; @State private var note: String
    @State private var reminderDate: Date?
    @State private var recurrenceOption: RecurrenceOption
    @State private var projectID: UUID?
    @FocusState private var titleFocused: Bool
    @State private var appliedDefaults = false
    init(item: CalendarEvent?, defaultDate: Date, isCreating: Bool? = nil, onSave: @escaping (CalendarEvent) async -> Bool, onDelete: @escaping (UUID) async -> Void) {
        original = item; self.isCreating = isCreating ?? (item == nil); self.onSave = onSave; self.onDelete = onDelete
        let base = item?.startDate ?? defaultDate
        _title = State(initialValue: item?.title ?? ""); _start = State(initialValue: base)
        _end = State(initialValue: item?.endDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: base) ?? base)
        _isAllDay = State(initialValue: item?.isAllDay ?? true); _note = State(initialValue: item?.note ?? "")
        _reminderDate = State(initialValue: item?.reminderDate)
        _recurrenceOption = State(initialValue: RecurrenceOption(rule: item?.recurrenceRule))
        _projectID = State(initialValue: item?.projectID)
    }
    var body: some View {
        EditorScaffold(title: isCreating ? "予定を書く" : "予定を編集", canSave: !title.trimmed.isEmpty,
                       existingID: isCreating ? nil : original?.id, save: save, delete: onDelete, hasUnsavedChanges: hasChanges) {
            editorTitle("予定", text: $title, focused: $titleFocused)
            ruledSection("日時") {
                Toggle("終日", isOn: $isAllDay)
                DatePicker("開始", selection: $start, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                DatePicker("終了", selection: $end, in: start..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
            }
            ruledSection("メモ") { TextField("メモ（任意）", text: $note, axis: .vertical).lineLimit(2...6) }
            ruledSection("プロジェクト") {
                Picker("プロジェクト", selection: $projectID) {
                    Text("なし").tag(Optional<UUID>.none)
                    ForEach(projectStore.activeProjects) { project in
                        Label(project.name, systemImage: project.iconName).tag(Optional(project.id))
                    }
                }
            }
            ruledSection("リマインダー") { ReminderEditor(reminderDate: $reminderDate, referenceDate: start) }
            ruledSection("繰り返し") { Picker("繰り返し", selection: $recurrenceOption) { ForEach(RecurrenceOption.allCases) { Text($0.rawValue).tag($0) } } }
        }.onAppear {
            if original == nil && !appliedDefaults {
                let defaults = settings.eventCreationDefaults(referenceDate: start)
                start = defaults.startDate; end = defaults.endDate; isAllDay = false; reminderDate = defaults.reminderDate; appliedDefaults = true
            }
            if isCreating { titleFocused = true }
        }
            .onChange(of: start) { _, value in if end < value { end = value } }
    }
    private func save() async -> Bool {
        let now = Date.now
        let value = CalendarEvent(id: original?.id ?? UUID(), title: title.trimmed, note: note, startDate: start,
                                  endDate: max(start, end), isAllDay: isAllDay, reminderDate: reminderDate,
                                  recurrenceRule: recurrenceOption.rule, projectID: projectID, category: original?.category,
                                  externalEventID: original?.externalEventID, createdAt: original?.createdAt ?? now, updatedAt: now)
        return await onSave(value)
    }
    private var hasChanges: Bool {
        guard let original else { return !title.trimmed.isEmpty || !note.isEmpty || projectID != nil || reminderDate != nil }
        return title != original.title || note != original.note || start != original.startDate || end != original.endDate ||
            isAllDay != original.isAllDay || reminderDate != original.reminderDate || recurrenceOption.rule != original.recurrenceRule || projectID != original.projectID
    }
}

struct NoteFormView: View {
    let original: DailyNote?; let defaultDate: Date; let isCreating: Bool; let onSave: (DailyNote) async -> Bool; let onDelete: (UUID) async -> Void
    @State private var text: String
    init(note: DailyNote?, defaultDate: Date, isCreating: Bool? = nil, onSave: @escaping (DailyNote) async -> Bool, onDelete: @escaping (UUID) async -> Void) {
        original = note; self.defaultDate = defaultDate; self.isCreating = isCreating ?? (note == nil); self.onSave = onSave; self.onDelete = onDelete; _text = State(initialValue: note?.text ?? "")
    }
    var body: some View {
        EditorScaffold(title: defaultDate.formatted(.dateTime.month().day().weekday(.short)), canSave: true,
                       existingID: isCreating ? nil : original?.id, save: save, delete: onDelete, hasUnsavedChanges: text != (original?.text ?? "")) {
            Text("今日のメモ").font(.title2.weight(.semibold))
            Divider()
            TextEditor(text: $text).frame(minHeight: 260).scrollContentBackground(.hidden)
        }
    }
    private func save() async -> Bool {
        let now = Date.now
        return await onSave(DailyNote(id: original?.id ?? UUID(), date: defaultDate, text: text,
                                      createdAt: original?.createdAt ?? now, updatedAt: now))
    }
}

private func editorTitle(_ placeholder: String, text: Binding<String>, focused: FocusState<Bool>.Binding) -> some View {
    TextField(placeholder, text: text, axis: .vertical)
        .focused(focused).submitLabel(.done).onSubmit { focused.wrappedValue = false }
        .font(.title2.weight(.semibold)).lineLimit(1...3).textInputAutocapitalization(.sentences)
}
private func ruledSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 14) { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary); Divider(); content() }
}

private struct ReminderEditor: View {
    @Binding var reminderDate: Date?
    let referenceDate: Date
    var body: some View {
        Toggle("通知", isOn: Binding(get: { reminderDate != nil }, set: { enabled in reminderDate = enabled ? defaultReminder : nil }))
        if let reminder = reminderDate {
            DatePicker("通知日時", selection: Binding(get: { reminder }, set: { reminderDate = $0 }), displayedComponents: [.date, .hourAndMinute])
            Menu("プリセット") {
                Button("予定時刻") { reminderDate = referenceDate }
                Button("10分前") { reminderDate = Calendar.current.date(byAdding: .minute, value: -10, to: referenceDate) }
                Button("30分前") { reminderDate = Calendar.current.date(byAdding: .minute, value: -30, to: referenceDate) }
                Button("1時間前") { reminderDate = Calendar.current.date(byAdding: .hour, value: -1, to: referenceDate) }
                Button("1日前") { reminderDate = Calendar.current.date(byAdding: .day, value: -1, to: referenceDate) }
            }.font(.subheadline)
        } else { Text("通知なし").font(.caption).foregroundStyle(.secondary) }
    }
    private var defaultReminder: Date { referenceDate > .now ? referenceDate : Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now }
}
private extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
