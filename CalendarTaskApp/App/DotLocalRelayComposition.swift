import SwiftUI
import DotLocalBridge

@MainActor struct DotLocalRelayFactory {
    let makeModel: () throws -> LocalBridgePanelModel
    let stagedPairing: () throws -> RelayPairing?
    let confirmPairing: () throws -> Void
    let connectionLabel: () throws -> String?
    let disconnect: () throws -> Void

    static func local(dotTaskStore: DotTaskStore?, cache: DotRelayTaskCache, onChange: @escaping @MainActor () async -> Void) -> DotLocalRelayFactory {
        // Approved dedicated, protected, backup-excluded transfer directory. No credential generated here.
        try? RelayPairingInbox.prepareDirectory()
        return DotLocalRelayFactory(makeModel: {
            let pairing = try KeychainRelayPairing().load()
            let store = try cache.store()
            let bridgeID = pairing?.bridgeID ?? "unpaired-local-relay"
            return LocalBridgePanelModel(store: store, transport: try pairing?.transport(), onChange: onChange, deviceSeed: {
                guard let dotTaskStore else { throw LocalBridgeError.noSeedData }
                dotTaskStore.load()
                guard let snapshot = dotTaskStore.snapshot, !snapshot.tasks.isEmpty else { throw LocalBridgeError.noSeedData }
                let rows = snapshot.tasks.map { task in
                    WireTask(id: task.slug, title: task.title, date: task.date, dateLabel: task.dateLabel,
                             status: task.status, details: task.details, category: task.category,
                             subcategory: task.subcategory, parentId: task.parentId,
                             completed: task.status == "完了", revision: 1,
                             aiContext: task.aiContext, startTime: task.startTime, endTime: task.endTime,
                             timeZone: task.timeZone, deadlineDate: task.deadlineDate, deadlineTime: task.deadlineTime)
                }
                return BridgeFeed(bridgeID: bridgeID, tasks: rows)
            })
        }, stagedPairing: { try RelayPairingInbox.read() },
        confirmPairing: { try RelayPairingInbox.confirmIntoKeychain(); Task { await cache.setActive(true) } },
        connectionLabel: { try KeychainRelayPairing().load()?.endpoint.absoluteString },
        disconnect: { cache.stopAutomaticDelivery(); try KeychainRelayPairing().remove() })
    }
}

struct DotLocalRelayEntryView: View {
    let factory: DotLocalRelayFactory
    @State private var model: LocalBridgePanelModel?
    @State private var staged: RelayPairing?
    @State private var connected: String?
    @State private var message: String?
    @State private var confirmDisconnect = false
    private func reload() {
        do {
            staged = try factory.stagedPairing()
            connected = try factory.connectionLabel()
            model = try factory.makeModel()
            message = nil
        } catch { message = "Mac 接続情報を確認できません。保存済みのタスクは保持しています。" }
    }
    var body: some View {
        VStack(spacing: 0) {
            if let staged {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mac 接続情報の確認").font(.headline)
                    Text(staged.endpoint.absoluteString)
                    Text("宛先：\(staged.deviceLabel)").font(.caption)
                    Text("証明書指紋：\(staged.certificateSHA256)").font(.caption2).textSelection(.enabled)
                    Text("信頼済みの Mac 接続からアプリ専用領域へ届いた情報です。秘密はこの端末の Keychain に保存し、iCloud には同期しません。")
                        .font(.caption)
                    Button("この Mac への接続設定を保存") {
                        do { try factory.confirmPairing(); reload() }
                        catch { message = "接続設定の保存・受渡しファイルの削除を確認できません。" }
                    }
                }.padding()
                Divider()
            }
            if let connected { Text("接続先：\(connected)").font(.caption).padding(.horizontal) }
            if let message { Text(message).font(.caption).foregroundStyle(.red).padding() }
            if let model { LocalBridgePanel(model: model) }
            else if message == nil { ProgressView("接続状態を確認中") }
        }
        .task { if model == nil { reload() } }
        .toolbar {
            if connected != nil {
                Button("接続解除") { confirmDisconnect = true }
            }
        }
        .confirmationDialog("この端末の接続設定だけを解除します", isPresented: $confirmDisconnect) {
            Button("接続を解除", role: .destructive) {
                do { model?.cancelConnection(); try factory.disconnect(); reload() }
                catch { message = "接続解除を確認できません。" }
            }
        } message: { Text("タスクと未反映の変更は削除しません。Mac 側の資格情報の失効は別途行います。") }
    }
}


// A single actor per pairing is shared by ordinary screens and the relay panel.
// This adapter projects into memory; it never inserts relay rows into SwiftData.
@MainActor final class DotRelayTaskCache {
    private var namespace: String?
    private var cached: LocalBridgeStore?
    var onChange: (@MainActor () async -> Void)?
    private var observation: Task<Void, Never>?
    private var active = false
    private var automaticTransport: (any BridgeTransport)?
    init(store: LocalBridgeStore? = nil) {
        if let store { namespace = "injected"; cached = store; observe(store) }
    }
    deinit { observation?.cancel() }
    private func observe(_ value: LocalBridgeStore) {
        observation?.cancel()
        observation = Task { [weak self] in
            let changes = await value.changes()
            for await _ in changes {
                guard !Task.isCancelled, let self else { break }
                await self.onChange?()
            }
        }
    }
    func stopAutomaticDelivery() {
        automaticTransport?.cancelRequests()
        automaticTransport = nil
        if let cached { Task { await cached.setAutomaticTransport(nil) } }
    }
    func setActive(_ value: Bool) async {
        active = value
        guard let store = try? store() else { return }
        automaticTransport?.cancelRequests()
        automaticTransport = value ? (try? KeychainRelayPairing().load()?.transport()) : nil
        await store.setAutomaticTransport(automaticTransport)
    }
    func retry() async {
        guard active, let store = try? store(), let automaticTransport else { return }
        try? await store.synchronize(using: automaticTransport)
    }
    func store() throws -> LocalBridgeStore {
        if namespace == "injected", let cached { return cached }
        let pairing = try KeychainRelayPairing().load()
        let key = pairing?.bridgeID ?? "unpaired-local-relay"
        if namespace == key, let cached { return cached }
        let relative = pairing == nil ? "DotLocalRelay/unpaired/state-v1.json" : "DotLocalRelay/paired/\(key)/state-v1.json"
        stopAutomaticDelivery()
        let value = try LocalBridgeStore(file: URL.applicationSupportDirectory.appending(path: relative), bridgeID: key)
        namespace = key; cached = value
        observe(value)
        return value
    }
}

@MainActor final class DotRelayTaskRepository: TaskRepository {
    let native: any TaskRepository
    let cache: DotRelayTaskCache
    init(native: any TaskRepository, cache: DotRelayTaskCache) { self.native = native; self.cache = cache }
    func plannerTasks() async throws -> [DotPlannerTask] {
        let snapshot = await (try cache.store()).snapshot
        return snapshot.tasks.map { row in
            let pending = snapshot.outbox.first { $0.operation.taskId == row.value.id }
            let completion = pending?.displayedCompletion ?? row.value.completed
            let applied = snapshot.appliedHistory?.contains { $0.taskId == row.value.id && $0.revision == row.value.revision && $0.completed == row.value.completed } == true
            let state = pending == nil ? (applied ? "Macローカル反映済み（Web・dot確認は別）" : "端末内保存済み（Web完了未照合）") : pending!.state == "conflict" ? "競合・変更保持" : pending!.state == "received" ? "Mac受信済み・反映待ち" : "未送信・端末保存済み"
            let date = row.value.scheduleDate()
            let task = TaskItem(id: row.id, title: row.value.title,
                note: "dot: \(row.value.id)\n\(state)\n" + row.value.humanDetails,
                startDate: row.value.startTime == nil ? nil : date, dueDate: date, isAllDay: row.value.startTime == nil, isCompleted: completion,
                completedAt: nil, priority: .normal, reminderDate: row.value.reminderDate, recurrenceRule: nil,
                projectID: row.value.project?.id, category: nil, tags: (row.value.tags ?? []).map { AppTag(id: $0.id, name: $0.name) }, createdAt: .distantPast, updatedAt: .distantPast)
            return DotPlannerTask(slug: row.value.id, task: task)
        }
    }
    private func projected() async throws -> [TaskItem] { try await plannerTasks().map(\.task) }
    func fetchTasks() async throws -> [TaskItem] {
        let nativeRows = try await native.fetchTasks()
        let relayRows = try await projected()
        guard Set(nativeRows.map(\.id)).isDisjoint(with: relayRows.map(\.id)) else { throw RelayListError.identifierCollision }
        return nativeRows + relayRows
    }
    func addTask(_ task: TaskItem) async throws {
        guard !(try await projected()).contains(where: { $0.id == task.id }) else { throw RelayListError.completionOnly }
        try await checkNativeReferences(task)
        try await native.addTask(task)
    }
    func updateTask(_ task: TaskItem) async throws {
        guard let original = try await projected().first(where: { $0.id == task.id }) else { try await checkNativeReferences(task); try await native.updateTask(task); return }
        guard Self.isCompletionUpdate(task, from: original) else { throw RelayListError.completionOnly }
        guard original.isCompleted != task.isCompleted else { return }
        let store = try cache.store()
        let snapshot = await store.snapshot
        guard let row = snapshot.tasks.first(where: { $0.id == task.id }) else { throw LocalBridgeError.unknownTask }
        try await store.queueCompletion(slug: row.value.id, completed: task.isCompleted)
    }
    private func checkNativeReferences(_ task: TaskItem) async throws {
        let snapshot = await (try cache.store()).snapshot
        let projectIDs = Set(snapshot.tasks.compactMap { $0.value.project?.id })
        let tagIDs = Set(snapshot.tasks.flatMap { ($0.value.tags ?? []).map(\.id) })
        guard task.projectID.map({ !projectIDs.contains($0) }) ?? true,
              Set(task.tags.map(\.id)).isDisjoint(with: tagIDs) else { throw RelayCatalogError.nativeAssignment }
    }
    static func isCompletionUpdate(_ requested: TaskItem, from original: TaskItem) -> Bool {
        var allowed = original
        allowed.isCompleted = requested.isCompleted
        allowed.completedAt = requested.completedAt; allowed.updatedAt = requested.updatedAt
        // Delivery can advance between a tap and repository lookup. Ignore only our
        // generated status line, never task content, identity, or other edits.
        let states: Set<String> = ["端末内保存済み（Web完了未照合）", "Mac取得済み（Web完了未照合）",
            "Macローカル反映済み（Web・dot確認は別）", "競合・変更保持", "Mac受信済み・反映待ち", "未送信・端末保存済み"]
        func content(_ note: String) -> [String]? {
            let lines = note.components(separatedBy: "\n")
            guard lines.count >= 2, lines[0].hasPrefix("dot: "), states.contains(lines[1]) else { return nil }
            return [lines[0]] + lines.dropFirst(2)
        }
        if let a = content(original.note), let b = content(requested.note), a == b { allowed.note = requested.note }
        return allowed == requested
    }
    func deleteTask(id: UUID) async throws {
        guard !(try await projected()).contains(where: { $0.id == id }) else { throw RelayListError.completionOnly }
        try await native.deleteTask(id: id)
    }
}
private enum RelayListError: LocalizedError {
    case completionOnly, identifierCollision
    var errorDescription: String? {
        switch self {
        case .completionOnly: "dot項目は完了変更のみ対応しています。詳細・競合はMac中継画面で確認してください。"
        case .identifierCollision: "dotと既存タスクのIDが衝突したため統合を停止しました。元データは保持しています。"
        }
    }
}


// Trusted app-container maintenance request. No URL/network endpoint accepts writes.
// Fixed, user-authorized one-time operation; all task mutations use the ordinary Store.
@MainActor enum ApprovedOverdueMove {
    static let operationID = "move-overdue-20261021-1"
    static func run(native: any TaskRepository, tasks: TaskStore, cache: DotRelayTaskCache, directory: URL = URL.applicationSupportDirectory.appending(path: "DotLocalRelay/maintenance"), now: Date = .now) async {
        let request = directory.appending(path: operationID + ".request.json")
        let report = directory.appending(path: operationID + ".report.json")
        guard FileManager.default.fileExists(atPath: request.path), !FileManager.default.fileExists(atPath: report.path) else { return }
        do {
            let value = try JSONSerialization.jsonObject(with: Data(contentsOf: request)) as? [String:String]
            guard value?["operationID"] == operationID, value?["targetDate"] == "2026-10-21", value?["timezone"] == "Asia/Tokyo", ["inspect","apply","refresh"].contains(value?["mode"] ?? "") else { return }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
            let today = calendar.date(from: DateComponents(year:2026, month:10, day:21))!
            guard calendar.isDate(now, inSameDayAs: today) else { return }
            if value?["mode"] == "refresh" {
                guard let pairing = try KeychainRelayPairing().load() else { return }
                let relayStore = try cache.store()
                guard await relayStore.snapshot.outbox.isEmpty else { return }
                try await relayStore.synchronize(using: pairing.transport())
                await tasks.load()
                let refreshed = await relayStore.snapshot
                let result:[String:Any] = ["operationID":operationID,"action":"relay-feed-refresh","taskCount":refreshed.tasks.count,"todayCount":refreshed.tasks.filter {$0.value.date == "2026-10-21" && !$0.value.completed}.count,"outboxCount":refreshed.outbox.count]
                try JSONSerialization.data(withJSONObject:result).write(to:report,options:[.atomic,.completeFileProtection])
                try FileManager.default.removeItem(at:request)
                return
            }
            let original = try await native.fetchTasks()
            let relay = await (try cache.store()).snapshot
            let eligible = original.filter { !$0.isCompleted && $0.recurrenceRule == nil && ($0.dueDate.map { $0 < today } ?? false) }
            let recurring = original.filter { !$0.isCompleted && $0.recurrenceRule != nil && ($0.dueDate.map { $0 < today } ?? false) }
            if value?["mode"] == "inspect" {
                let plan:[String:Any] = ["nativeTotal":original.count,"eligible":try eligible.map { try JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) },"recurringExcluded":recurring.count,"nativeOtherExcluded":original.count-eligible.count-recurring.count,"relayTotal":relay.tasks.count,"relayOutboxCount":relay.outbox.count]
                try JSONSerialization.data(withJSONObject:plan,options:[.sortedKeys]).write(to:directory.appending(path:operationID + ".inspection.json"),options:[.atomic,.completeFileProtection])
                try FileManager.default.removeItem(at:request)
                return
            }
            let backup = directory.appending(path: operationID + ".original-tasks.json")
            // Exclusive journal creation protects the original dates against retries.
            guard !FileManager.default.fileExists(atPath: backup.path) else { return }
            try JSONEncoder().encode(original).write(to: backup, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
            var moved:[String] = [], failed:[String] = []
            for item in eligible {
                // Refetch protects concurrent edits made after planning/backup.
                guard let current = try await native.fetchTasks().first(where: {$0.id == item.id}), current == item else { failed.append(item.id.uuidString); continue }
                var changed = item
                changed.dueDate = calendar.replacingDate(of: item.dueDate!, with: today)
                if let reminder = item.reminderDate { changed.reminderDate = reminder.addingTimeInterval(changed.dueDate!.timeIntervalSince(item.dueDate!)) }
                changed.updatedAt = .now
                if await tasks.update(changed), let readback = try await native.fetchTasks().first(where: {$0.id == item.id}), readback == changed { moved.append(item.id.uuidString) }
                else { failed.append(item.id.uuidString) }
            }
            let relayOverdue = relay.tasks.filter { ($0.value.date.map { $0 < "2026-10-21" } ?? false) && !$0.value.completed }
            let result:[String:Any] = ["operationID":operationID, "targetDate":"2026-10-21", "timezone":"Asia/Tokyo",
                "nativeTotal":original.count,"nativeEligible":eligible.count,"nativeMoved":moved,"nativeFailed":failed,
                "nativeExcluded":original.count-eligible.count,"nativeRecurringRequiresOccurrenceSupport":recurring.map { $0.id.uuidString },
                "relayTotal":relay.tasks.count,"relayOverdueCompletionUnverified":relayOverdue.map { $0.value.id },
                "relayOutboxCount":relay.outbox.count,"relayDatesChanged":0,"webChanged":false,
                "nativeTodayAfter":try await native.fetchTasks().filter { !$0.isCompleted && ($0.dueDate.map {calendar.isDate($0,inSameDayAs:today)} ?? false) }.map { $0.id.uuidString }]
            try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]).write(to:report,options:[.atomic,.completeFileProtection])
            try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:report.path)
            try FileManager.default.removeItem(at:request)
            await tasks.load()
        } catch { /* Keep request and immutable journal for inspection; never replay a partial operation. */ }
    }
}

// Mac-owned catalogs are projected in memory alongside native definitions.
@MainActor final class DotRelayProjectRepository: ProjectRepository {
    let native: any ProjectRepository
    let cache: DotRelayTaskCache
    init(native: any ProjectRepository, cache: DotRelayTaskCache) { self.native = native; self.cache = cache }
    private func remote() async throws -> [Project] {
        let snapshot = await (try cache.store()).snapshot
        var seen = Set<UUID>()
        return snapshot.tasks.compactMap { $0.value.project }.filter { seen.insert($0.id).inserted }.map {
            Project(id: $0.id, name: $0.name, colorIdentifier: .blue, iconName: "briefcase", isArchived: false, createdAt: .distantPast, updatedAt: .distantPast)
        }
    }
    func fetchProjects() async throws -> [Project] {
        let local = try await native.fetchProjects(), remote = try await remote()
        guard Set(local.map(\.id)).isDisjoint(with: remote.map(\.id)) else { throw RelayCatalogError.collision }
        return local + remote
    }
    private func check(_ id: UUID) async throws {
        guard !(try await remote()).contains(where: { $0.id == id }) else { throw RelayCatalogError.macOwned }
    }
    func addProject(_ project: Project) async throws { try await check(project.id); try await native.addProject(project) }
    func updateProject(_ project: Project) async throws { try await check(project.id); try await native.updateProject(project) }
    func archiveProject(id: UUID, archived: Bool) async throws { try await check(id); try await native.archiveProject(id: id, archived: archived) }
    func deleteProject(id: UUID) async throws { try await check(id); try await native.deleteProject(id: id) }
}

@MainActor final class DotRelayTagRepository: TagRepository {
    let native: any TagRepository
    let cache: DotRelayTaskCache
    init(native: any TagRepository, cache: DotRelayTaskCache) { self.native = native; self.cache = cache }
    private func remote() async throws -> [AppTag] {
        let snapshot = await (try cache.store()).snapshot
        var seen = Set<UUID>()
        return snapshot.tasks.flatMap { $0.value.tags ?? [] }.filter { seen.insert($0.id).inserted }.map { AppTag(id: $0.id, name: $0.name) }
    }
    func fetchTags() async throws -> [AppTag] {
        let local = try await native.fetchTags(), remote = try await remote()
        guard Set(local.map(\.id)).isDisjoint(with: remote.map(\.id)) else { throw RelayCatalogError.collision }
        return local + remote
    }
    private func check(_ id: UUID) async throws {
        guard !(try await remote()).contains(where: { $0.id == id }) else { throw RelayCatalogError.macOwned }
    }
    func saveTag(_ tag: AppTag) async throws { try await check(tag.id); try await native.saveTag(tag) }
    func deleteTag(id: UUID) async throws { try await check(id); try await native.deleteTag(id: id) }
}
private enum RelayCatalogError: LocalizedError {
    case macOwned, collision, nativeAssignment
    var errorDescription: String? {
        switch self {
        case .macOwned: "Dotのプロジェクト・タグはMacの正本から変更してください。"
        case .nativeAssignment: "Dotの分類はDotタスク専用です。端末内のタスクには端末内の分類を選んでください。"
        case .collision: "Dotと端末内の分類IDが重複しています。元データを保持しています。"
        }
    }
}

// Serialize side effects even when newer snapshots arrive while awaiting iOS.
@MainActor final class DotRelayNotificationSync {
    private let service: any NotificationService
    private var pending: [TaskItem]?
    private var running = false
    private var previous: [UUID: TaskItem] = [:]
    private var previousPermission: NotificationPermissionStatus?
    init(service: any NotificationService) { self.service = service }
    func synchronize(_ tasks: [TaskItem]) async {
        pending = tasks
        guard !running else { return }
        running = true
        defer { running = false }
        while let current = pending {
            pending = nil
            let next = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            let permission = await service.authorizationStatus()
            for id in previous.keys where next[id] == nil { await service.removeTaskNotification(id: id) }
            for task in current {
                let old = previous[task.id]
                if old?.title != task.title || old?.reminderDate != task.reminderDate || old?.isCompleted != task.isCompleted || previousPermission != permission {
                    await service.sync(task: task)
                }
            }
            previous = next
            previousPermission = await service.authorizationStatus()
        }
    }
}
