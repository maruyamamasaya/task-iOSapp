import SwiftUI

@MainActor public final class LocalBridgePanelModel: ObservableObject {
    @Published public private(set) var snapshot: BridgeSnapshot?
    @Published public private(set) var message: String?
    @Published public private(set) var busy = false
    private let store: LocalBridgeStore
    private var transport: (any BridgeTransport)?
    private let onChange: (@MainActor () async -> Void)?
    private let deviceSeed: (@MainActor () async throws -> BridgeFeed)?
    public var canInitializeFromDevice: Bool { deviceSeed != nil && snapshot?.tasks.isEmpty == true }
    public init(store: LocalBridgeStore, transport: (any BridgeTransport)? = nil,
                onChange: (@MainActor () async -> Void)? = nil, deviceSeed: (@MainActor () async throws -> BridgeFeed)? = nil) {
        self.store = store; self.transport = transport; self.deviceSeed = deviceSeed; self.onChange = onChange
    }
    public func load() async { snapshot = await store.snapshot; await onChange?() }
    public func cancelConnection() { transport?.cancelRequests(); transport = nil }
    public func initializeFromDevice() async {
        guard !busy, let deviceSeed else { return }; busy = true; defer { busy = false }
        do {
            try await store.initializeFromDevice(try await deviceSeed())
            message = "端末内の一覧から開始しました。Mac や dot の反映確認はまだです。"
        } catch { message = error.localizedDescription }
        await load()
    }
    public func queue(_ task: LocalTask) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { try await store.queueCompletion(slug: task.value.id, completed: !(snapshot?.displayedCompletion(for: task.value.id) ?? task.value.completed)); message = "端末内保存済み・送信待ち。接続中は自動送信します。" }
        catch { message = error.localizedDescription }
        await load()
    }
    public func synchronize() async {
        guard !busy else { return }
        guard let transport else { message = "未接続：Mac とのペアリングは未設定です。"; return }
        busy = true; defer { busy = false }
        do { try await store.synchronize(using: transport); message = nil }
        catch { message = "未同期：Mac 接続または反映を確認できません。変更は保持しています。" }
        await load()
    }
    public func resolveConflict(_ task: LocalTask, retryOwnChoice: Bool) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            try await store.resolveConflict(slug: task.value.id, retryOwnChoice: retryOwnChoice)
            message = retryOwnChoice ? "選んだ変更を未送信として保存しました。再送後に確認します。" : "未反映の操作を取り下げ、取得済みの確定状態を使います。"
        } catch { message = error.localizedDescription }
        await load()
    }
}

// Standalone panel for later reviewed target/DI integration; not inserted into TaskApp.
public struct LocalBridgePanel: View {
    @StateObject private var model: LocalBridgePanelModel
    @State private var resolving: LocalTask?
    public init(model: LocalBridgePanelModel) { _model = StateObject(wrappedValue: model) }
    public var body: some View {
        List {
            Section {
                Text("Mac のローカル記録と、dot が内容を確認した状態は別です。既存タスクは置き換えません。")
                if let notice = model.snapshot?.sourceNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
                if model.canInitializeFromDevice {
                    Button("端末内の dot 一覧から開始") { Task { await model.initializeFromDevice() } }.disabled(model.busy)
                    Text("端末内の JSON 一覧を別の作業領域へ読み込みます。既存タスクは変更しません。")
                        .font(.caption)
                }
                Button("Mac と確認・送受信") { Task { await model.synchronize() } }.disabled(model.busy)
                if let message = model.message { Text(message).font(.caption) }
            }
            ForEach(model.snapshot?.tasks ?? []) { task in
                VStack(alignment: .leading) {
                    Text(task.value.title)
                    let confirmed = model.snapshot?.appliedHistory?.last(where: { $0.taskId == task.value.id && $0.revision == task.value.revision && $0.completed == task.value.completed })
                    Text((confirmed == nil ? "端末表示：" : "Mac ローカル反映済み：") + (task.value.completed ? "完了" : "未完了")).font(.caption)
                    if let pending = model.snapshot?.outbox.first(where: { $0.operation.taskId == task.value.id }) {
                        Text(pending.state == "conflict" ? "競合：変更を保持しています" : pending.state == "received" ? "Mac 受信済み・ローカル反映待ち" : "端末内保存済み・送信待ち").font(.caption)
                        Text(pending.displayedCompletion ? "希望する変更：完了" : "希望する変更：未完了").font(.caption)
                        if pending.state == "conflict" {
                            Button("競合を確認する") { resolving = task }.disabled(model.busy)
                        }
                    } else {
                        Button((model.snapshot?.displayedCompletion(for: task.value.id) ?? task.value.completed) ? "未完了への変更を保存" : "完了への変更を保存") { Task { await model.queue(task) } }.disabled(model.busy)
                    }
                }
            }
        }.navigationTitle("dot ローカル連携").task {
            while !Task.isCancelled {
                await model.load()
                do { try await Task.sleep(for: .seconds(2)) } catch { break }
            }
        }
        .confirmationDialog("取得済みの状態と、未反映の変更を確認してください", isPresented: Binding(
            get: { resolving != nil }, set: { if !$0 { resolving = nil } })) {
            if let task = resolving {
                Button("自分の変更を再送待ちにする") { Task { await model.resolveConflict(task, retryOwnChoice: true) }; resolving = nil }
                Button("未反映の操作を取り下げる", role: .destructive) { Task { await model.resolveConflict(task, retryOwnChoice: false) }; resolving = nil }
            }
            Button("戻る", role: .cancel) { resolving = nil }
        } message: {
            if let task = resolving {
                Text("取得済みの確定状態は「\(task.value.completed ? "完了" : "未完了")」です。再送には新しい操作 ID と現在の版を使います。取り下げてもタスク自体は削除しません。")
            }
        }
    }
}
