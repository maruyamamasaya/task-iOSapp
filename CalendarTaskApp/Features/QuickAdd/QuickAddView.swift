import SwiftUI

struct QuickAddView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: SettingsStore
    @FocusState private var focused: Bool
    @State private var text = ""
    @State private var selectedType: QuickAddItemType?
    @State private var isSaving = false
    @State private var saveFailed = false
    @State private var result: QuickAddResult?
    let defaultDate: Date
    let parser: QuickAddParser
    let add: (QuickAddResult) async -> Bool
    let edit: (QuickAddResult) -> Void

    init(defaultDate: Date, parser: QuickAddParser = QuickAddParser(),
         add: @escaping (QuickAddResult) async -> Bool, edit: @escaping (QuickAddResult) -> Void) {
        self.defaultDate = defaultDate; self.parser = parser; self.add = add; self.edit = edit
    }

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("追加する種類", selection: Binding(
                    get: { selectedType ?? (settings.quickAddDefaultType == .task ? .task : .event) },
                    set: { selectedType = $0; updatePreview() }
                )) {
                    Text("タスク").tag(QuickAddItemType.task)
                    Text("予定").tag(QuickAddItemType.event)
                    Text("メモ").tag(QuickAddItemType.note)
                }.pickerStyle(.segmented)
                HStack(spacing: 10) {
                    Image(systemName: "plus").foregroundStyle(.secondary)
                    TextField("タイトルやメモを入力...", text: $text)
                        .focused($focused).submitLabel(result == nil ? .next : .done).onSubmit {
                            if let result { Task { await saveAndContinue(result) } } else { parse() }
                        }
                    if !text.isEmpty { Button(action: parse) { Image(systemName: "arrow.right.circle.fill") }.accessibilityLabel("解析") }
                }
                .font(.title3).padding(.vertical, 10).themedSurface(padding: 12)
                Divider()
                if saveFailed { Text("保存できませんでした。入力を残しています。もう一度お試しください。").font(.caption).foregroundStyle(.red) }
                if let result { preview(result) }
                else {
                    Text("「明日 18:00 病院」や「予定: 8/20 打ち合わせ」のように入力できます。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24).padding(.vertical, 12)
            }
            .themedScreen()
            .navigationTitle("すばやく書く").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } } }
        }
        .onAppear { focused = true }
        .onChange(of: text) { _, _ in updatePreview() }
        .disabled(isSaving)
        .interactiveDismissDisabled(isSaving)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func preview(_ result: QuickAddResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(result.type.rawValue, systemImage: symbol(for: result.type)).font(.headline)
            previewLine("タイトル", result.title)
            previewLine("日付", result.date.formatted(date: .long, time: .omitted))
            if result.hasExplicitTime { previewLine("時刻", result.date.formatted(date: .omitted, time: .shortened)) }
            Divider().padding(.top, 2)
            HStack {
                Button("編集") { edit(result); dismiss() }.buttonStyle(.bordered)
                Spacer()
                Button("追加") { Task { await saveAndContinue(result) } }.buttonStyle(ThemedProminentStyle())
            }
        }
    }
    private func previewLine(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 54, alignment: .leading); Text(value) }
    }
    private func symbol(for type: QuickAddItemType) -> String {
        switch type { case .task: "checkmark.circle"; case .event: "calendar"; case .note: "pencil.line" }
    }
    private func parse() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let defaultType = selectedType ?? (settings.quickAddDefaultType == .task ? .task : .event)
        let parsed = parser.parse(text, defaultDate: defaultDate, defaultType: defaultType)
        if settings.quickAddSaveImmediately && !settings.quickAddAlwaysPreview {
            Task { await saveAndContinue(parsed) }
        } else {
            result = parsed; focused = false
        }
    }
    private func updatePreview() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { result = nil; return }
        result = parser.parse(text, defaultDate: defaultDate,
                              defaultType: selectedType ?? (settings.quickAddDefaultType == .task ? .task : .event))
    }
    @MainActor private func saveAndContinue(_ value: QuickAddResult) async {
        guard !isSaving else { return }
        isSaving = true
        let saved = await add(value)
        saveFailed = !saved
        if saved { text = ""; result = nil; focused = true }
        isSaving = false
    }
}
