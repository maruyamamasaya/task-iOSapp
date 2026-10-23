import Foundation

public struct WireReference: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public init(id: UUID, name: String) { self.id = id; self.name = name }
    fileprivate var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 100 }
}

public struct WireTask: Codable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var date: String?
    public var dateLabel: String
    public var status: String
    public var details: String
    public var category: String
    public var taskKind: String?
    public var subcategory: String?
    public var parentId: String?
    public var completed: Bool
    public var revision: Int
    public var project: WireReference?
    public var tags: [WireReference]?
    public var aiContext: String?
    public var startTime: String?
    public var endTime: String?
    public var timeZone: String?
    public var deadlineDate: String?
    public var deadlineTime: String?
    public var reminderAt: String?
    public var reminderDate: Date? {
        guard let reminderAt else { return nil }
        let datePart = String(reminderAt.prefix(10))
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let day = formatter.date(from: datePart), formatter.string(from: day) == datePart else { return nil }
        return ISO8601DateFormatter().date(from: reminderAt)
    }
    public init(id: String, title: String, date: String?, dateLabel: String, status: String, details: String,
                category: String, subcategory: String? = nil, parentId: String? = nil, completed: Bool, revision: Int,
                project: WireReference? = nil, tags: [WireReference]? = nil, reminderAt: String? = nil,
                aiContext: String? = nil, startTime: String? = nil, endTime: String? = nil,
                timeZone: String? = nil, deadlineDate: String? = nil, deadlineTime: String? = nil, taskKind: String? = nil) {
        self.taskKind = taskKind
        self.id = id; self.title = title; self.date = date; self.dateLabel = dateLabel; self.status = status
        self.details = details; self.category = category; self.subcategory = subcategory; self.parentId = parentId
        self.completed = completed; self.revision = revision
        self.project = project; self.tags = tags; self.reminderAt = reminderAt
        self.aiContext = aiContext; self.startTime = startTime; self.endTime = endTime
        self.timeZone = timeZone; self.deadlineDate = deadlineDate; self.deadlineTime = deadlineTime
    }
}
// Calendar-day schedules and fixed deadlines stay separate from notification instants.
extension WireTask {
    public func scheduleDate(calendar: Calendar = .current) -> Date? {
        Self.wallDate(date, clock: startTime, zone: startTime == nil ? calendar.timeZone : TimeZone(identifier: timeZone ?? ""))
    }
    private static func wallDate(_ day: String?, clock: String?, zone: TimeZone?) -> Date? {
        guard let day, let zone else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = zone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.isLenient = false
        formatter.dateFormat = clock == nil ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm"
        let text = day + (clock.map { " " + $0 } ?? "")
        guard let value = formatter.date(from: text), formatter.string(from: value) == text else { return nil }
        return value
    }
    public var hasValidSchedule: Bool {
        for value in [startTime, endTime, deadlineTime].compactMap({ $0 }) {
            guard value.range(of: #"^(?:[01]\d|2[0-3]):[0-5]\d$"#, options: .regularExpression) != nil else { return false }
        }
        if let timeZone, TimeZone(identifier: timeZone) == nil { return false }
        if startTime != nil && (date == nil || timeZone == nil || scheduleDate() == nil) { return false }
        if let endTime {
            guard let startTime, endTime > startTime,
                  Self.wallDate(date, clock: endTime, zone: TimeZone(identifier: timeZone ?? "")) != nil else { return false }
        }
        if let deadlineDate, Self.wallDate(deadlineDate, clock: nil, zone: TimeZone(secondsFromGMT: 0)) == nil { return false }
        if deadlineTime != nil && (deadlineDate == nil || timeZone == nil || Self.wallDate(deadlineDate, clock: deadlineTime, zone: TimeZone(identifier: timeZone ?? "")) == nil) { return false }
        return true
    }
    public var humanDetails: String {
        var lines = [details]
        if let startTime {
            lines.append("予定: " + startTime + (endTime.map { "〜" + $0 } ?? "") + (timeZone.map { " (" + $0 + ")" } ?? ""))
        }
        if let deadlineDate {
            lines.append("固定期限: " + deadlineDate + (deadlineTime.map { " " + $0 } ?? "") + (deadlineTime == nil ? "" : timeZone.map { " (" + $0 + ")" } ?? ""))
        }
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
public struct BridgeFeed: Codable, Sendable {
    public let bridgeID: String
    public let tasks: [WireTask]
    public let sourceNotice: String?
    public init(bridgeID: String, tasks: [WireTask], sourceNotice: String? = nil) {
        self.bridgeID = bridgeID; self.tasks = tasks; self.sourceNotice = sourceNotice
    }
}
public struct LocalTask: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var value: WireTask
}
public struct CompletionOperation: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { operationId }
    public let operationId: UUID
    public let taskId: String
    public let expectedRevision: Int
    public let completed: Bool
}
public struct PendingOperation: Codable, Equatable, Sendable {
    public let operation: CompletionOperation
    public var state: String // pending, sending (possibly delivered), received, conflict.
    public var nextCompleted: Bool? = nil
    public var neverSubmitted: Bool? = nil // nil in legacy files means delivery is uncertain.
    public var displayedCompletion: Bool { nextCompleted ?? operation.completed }
}
public struct ApplyAcknowledgment: Codable, Sendable {
    public let taskId: String
    public let revision: Int
    public let completed: Bool
    public let target: String
    public let operationDigest: String
}
public struct OperationReceipt: Codable, Sendable {
    public let bridgeID: String
    public let operationId: UUID
    public let status: String
    public let acknowledgment: ApplyAcknowledgment?
}
public struct BridgeSnapshot: Codable, Equatable, Sendable {
    public let version: Int
    public let bridgeID: String
    public var tasks: [LocalTask]
    public var outbox: [PendingOperation]
    public var appliedHistory: [LocalApplyRecord]? = nil
    public var allowsInitialMacRegistration: Bool? = nil
    public var sourceNotice: String? = nil
    public func displayedCompletion(for slug: String) -> Bool? {
        outbox.first(where: { $0.operation.taskId == slug })?.displayedCompletion
            ?? tasks.first(where: { $0.value.id == slug })?.value.completed
    }
}
public struct LocalApplyRecord: Codable, Equatable, Sendable {
    public let operationId: UUID
    public let taskId: String
    public let revision: Int
    public let completed: Bool
    public let confirmedAt: Date
}
public enum LocalBridgeError: Error, LocalizedError {
    case invalidFeed, wrongBridge, unknownTask, pendingOperation, invalidReceipt, saveFailed, noSeedData, alreadyInitialized
    public var errorDescription: String? {
        switch self {
        case .invalidFeed: "タスク情報の形式を確認できません。"
        case .wrongBridge: "ペアリング先の Mac が一致しません。"
        case .unknownTask: "対象タスクを確認できません。"
        case .pendingOperation: "前の変更の反映を確認してから操作してください。"
        case .invalidReceipt: "dot への反映を確認できません。未同期の変更を保持します。"
        case .saveFailed: "端末への保存に失敗しました。"
        case .noSeedData: "先に端末内の dot 一覧へ JSON を読み込んでください。"
        case .alreadyInitialized: "開始済みの一覧は上書きしません。"
        }
    }
}
public protocol BridgeTransport: Sendable {
    func fetch() async throws -> BridgeFeed
    func submit(_ operation: CompletionOperation) async throws -> OperationReceipt
    func receipt(for operationId: UUID) async throws -> OperationReceipt
    func registerInitialFeed(_ feed: BridgeFeed) async throws -> BridgeFeed
    func cancelRequests()
}
public extension BridgeTransport {
    func registerInitialFeed(_ feed: BridgeFeed) async throws -> BridgeFeed { throw BridgeNetworkError.unavailable }
    func cancelRequests() {}
}

// Separate file persistence: never opens SwiftData or the whole-store backup restore.
public actor LocalBridgeStore {
    private let file: URL
    private let bridgeID: String
    private var automaticTransport: (any BridgeTransport)?
    private var synchronizing = false
    private var synchronizeAgain = false
    private var observers: [UUID: AsyncStream<BridgeSnapshot>.Continuation] = [:]
    public func changes() -> AsyncStream<BridgeSnapshot> {
        let id = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            observers[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { @Sendable _ in Task { await self.removeObserver(id) } }
        }
    }
    private func removeObserver(_ id: UUID) { observers.removeValue(forKey: id) }

    // Foreground owner supplies the already-paired transport. No credentials are persisted here.
    public func setAutomaticTransport(_ transport: (any BridgeTransport)?) {
        automaticTransport = transport
        if transport != nil { requestAutomaticSend() }
    }
    private func requestAutomaticSend() {
        guard let transport = automaticTransport else { return }
        Task { try? await self.synchronize(using: transport) }
    }
    public private(set) var snapshot: BridgeSnapshot
    public init(file: URL, bridgeID: String) throws {
        self.file = file; self.bridgeID = bridgeID
        if FileManager.default.fileExists(atPath: file.path) {
            let value = try JSONDecoder().decode(BridgeSnapshot.self, from: Data(contentsOf: file))
            guard value.version == 1, value.bridgeID == bridgeID else { throw LocalBridgeError.wrongBridge }
            guard Set(value.tasks.map(\.id)).count == value.tasks.count,
                  Set(value.tasks.map { $0.value.id }).count == value.tasks.count,
                  Set(value.outbox.map { $0.operation.operationId }).count == value.outbox.count else { throw LocalBridgeError.invalidFeed }
            guard value.tasks.allSatisfy({ Self.valid($0.value) }) else { throw LocalBridgeError.invalidFeed }
            snapshot = value
        } else { snapshot = BridgeSnapshot(version: 1, bridgeID: bridgeID, tasks: [], outbox: []) }
    }
    private func commit(_ candidate: BridgeSnapshot) throws {
        do {
            let data = try JSONEncoder().encode(candidate)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: [.atomic, .completeFileProtection])
        } catch { throw LocalBridgeError.saveFailed }
        snapshot = candidate // Only after durable save succeeds.
        for observer in observers.values { observer.yield(candidate) }
    }
    private static func valid(_ task: WireTask) -> Bool {
        guard task.id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
              !task.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, task.revision > 0 else { return false }
        if let date = task.date {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
            guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else { return false }
        }
        guard task.hasValidSchedule, task.project?.isValid != false else { return false }
        let tags = task.tags ?? []
        guard tags.count <= 50, tags.allSatisfy(\.isValid), Set(tags.map(\.id)).count == tags.count else { return false }
        if let reminder = task.reminderAt {
            guard reminder.range(of: #"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$"#, options: .regularExpression) != nil,
                  task.reminderDate != nil else { return false }
        }
        return true
    }
    public func merge(_ feed: BridgeFeed, allowInitialRegistration: Bool = false) throws {
        guard feed.bridgeID == bridgeID else { throw LocalBridgeError.wrongBridge }
        guard Set(feed.tasks.map(\.id)).count == feed.tasks.count,
              feed.tasks.allSatisfy(Self.valid) else { throw LocalBridgeError.invalidFeed }
        var next = snapshot
        if let notice = feed.sourceNotice { next.sourceNotice = notice }
        if allowInitialRegistration { next.allowsInitialMacRegistration = true }
        for incoming in feed.tasks {
            if let index = next.tasks.firstIndex(where: { $0.value.id == incoming.id }) {
                guard incoming.revision >= next.tasks[index].value.revision else { throw LocalBridgeError.invalidFeed }
                // A pending choice stays in the outbox, not conflated with remote completion.
                next.tasks[index].value = incoming
            } else { next.tasks.append(LocalTask(id: UUID(), value: incoming)) }
        }
        for references in [next.tasks.compactMap { $0.value.project }, next.tasks.flatMap { $0.value.tags ?? [] }] {
            var names: [UUID: String] = [:]
            for reference in references {
                guard names[reference.id] == nil || names[reference.id] == reference.name else { throw LocalBridgeError.invalidFeed }
                names[reference.id] = reference.name
            }
        }
        // Missing rows do not delete existing data, IDs, or queued changes.
        try commit(next)
    }
    public func initializeFromDevice(_ feed: BridgeFeed) throws {
        guard snapshot.tasks.isEmpty, snapshot.outbox.isEmpty else { throw LocalBridgeError.alreadyInitialized }
        guard !feed.tasks.isEmpty else { throw LocalBridgeError.noSeedData }
        try merge(feed, allowInitialRegistration: true)
    }
    @discardableResult public func queueCompletion(slug: String, completed: Bool) throws -> CompletionOperation {
        guard let task = snapshot.tasks.first(where: { $0.value.id == slug }) else { throw LocalBridgeError.unknownTask }
        if let index = snapshot.outbox.firstIndex(where: { $0.operation.taskId == slug }) {
            let pending = snapshot.outbox[index]
            guard pending.state != "conflict" else { throw LocalBridgeError.pendingOperation }
            if pending.displayedCompletion == completed { return pending.operation }
            var next = snapshot
            if pending.state == "pending", pending.neverSubmitted == true, completed == task.value.completed {
                // No network submission began: the unsent choice can be withdrawn safely.
                next.outbox.remove(at: index)
            } else {
                // Never mutate a submitted ID/payload. Persist the latest desired state behind it.
                next.outbox[index].nextCompleted = completed == pending.operation.completed ? nil : completed
            }
            try commit(next)
            requestAutomaticSend()
            return pending.operation
        }
        let operation = CompletionOperation(operationId: UUID(), taskId: slug, expectedRevision: task.value.revision, completed: completed)
        var next = snapshot
        next.outbox.append(PendingOperation(operation: operation, state: "pending", neverSubmitted: true))
        try commit(next)
        requestAutomaticSend()
        return operation
    }
    public func accept(_ receipt: OperationReceipt) throws {
        guard receipt.bridgeID == bridgeID else { throw LocalBridgeError.wrongBridge }
        guard let index = snapshot.outbox.firstIndex(where: { $0.operation.operationId == receipt.operationId }) else { return }
        var next = snapshot
        let operation = next.outbox[index].operation
        switch receipt.status {
        case "received":
            guard receipt.acknowledgment == nil else { throw LocalBridgeError.invalidReceipt }
            guard next.outbox[index].state != "conflict" else { return }
            next.outbox[index].state = "received"
        case "conflict":
            guard receipt.acknowledgment == nil else { throw LocalBridgeError.invalidReceipt }
            next.outbox[index].state = "conflict"
        case "applied":
            guard let ack = receipt.acknowledgment, ack.taskId == operation.taskId,
                  ack.completed == operation.completed, ack.revision == operation.expectedRevision + 1,
                  ack.target == "dot_local_file", ack.operationDigest.count == 64,
                  let taskIndex = next.tasks.firstIndex(where: { $0.value.id == operation.taskId }) else { throw LocalBridgeError.invalidReceipt }
            // A newer fetched task must not be rolled back by a delayed receipt.
            if next.tasks[taskIndex].value.revision <= ack.revision {
                next.tasks[taskIndex].value.completed = ack.completed
                next.tasks[taskIndex].value.revision = ack.revision
            }
            let desired = next.outbox[index].nextCompleted
            next.outbox.remove(at: index)
            if let desired, desired != ack.completed {
                let followup = CompletionOperation(operationId: UUID(), taskId: operation.taskId,
                    expectedRevision: ack.revision, completed: desired)
                // A newer external version requires review, never automatic rebasing.
                let state = next.tasks[taskIndex].value.revision > ack.revision ? "conflict" : "pending"
                next.outbox.append(PendingOperation(operation: followup, state: state, neverSubmitted: true))
            }
            var history = next.appliedHistory ?? []
            history.append(LocalApplyRecord(operationId: operation.operationId, taskId: operation.taskId,
                                            revision: ack.revision, completed: ack.completed, confirmedAt: .now))
            next.appliedHistory = Array(history.suffix(1000))
        default: throw LocalBridgeError.invalidReceipt
        }
        try commit(next)
        if snapshot.outbox.contains(where: { $0.state == "pending" }) { requestAutomaticSend() }
    }
    public func resolveConflict(slug: String, retryOwnChoice: Bool) throws {
        guard let index = snapshot.outbox.firstIndex(where: { $0.operation.taskId == slug && $0.state == "conflict" }),
              let task = snapshot.tasks.first(where: { $0.value.id == slug }) else { throw LocalBridgeError.unknownTask }
        var next = snapshot
        if retryOwnChoice {
            // New immutable ID and current revision; server still decides whether it can apply.
            next.outbox[index] = PendingOperation(operation: CompletionOperation(operationId: UUID(), taskId: slug,
                expectedRevision: task.value.revision, completed: next.outbox[index].displayedCompletion), state: "pending", neverSubmitted: true)
        } else { next.outbox.remove(at: index) }
        try commit(next)
        requestAutomaticSend()
    }
    public func synchronize(using transport: any BridgeTransport) async throws {
        // Actor isolation alone does not serialize across network awaits.
        guard !synchronizing else { synchronizeAgain = true; return }
        synchronizing = true
        defer {
            synchronizing = false
            if synchronizeAgain {
                synchronizeAgain = false
                requestAutomaticSend()
            }
        }
        var feed = try await transport.fetch()
        guard feed.bridgeID == bridgeID else { throw LocalBridgeError.wrongBridge }
        if feed.tasks.isEmpty && !snapshot.tasks.isEmpty {
            guard snapshot.allowsInitialMacRegistration == true,
                  snapshot.tasks.allSatisfy({ $0.value.revision == 1 }) else { throw LocalBridgeError.invalidFeed }
            feed = try await transport.registerInitialFeed(BridgeFeed(bridgeID: bridgeID, tasks: snapshot.tasks.map(\.value)))
        }
        try merge(feed)
        if !feed.tasks.isEmpty, snapshot.allowsInitialMacRegistration == true {
            var next = snapshot; next.allowsInitialMacRegistration = false; try commit(next)
        }
        for pending in snapshot.outbox {
            guard pending.state != "conflict" else { continue }
            // Recheck after awaits: an unsent operation may have been withdrawn.
            guard let index = snapshot.outbox.firstIndex(where: { $0.operation.id == pending.operation.id }),
                  snapshot.outbox[index].state != "conflict" else { continue }
            if snapshot.outbox[index].state == "pending" {
                var next = snapshot
                next.outbox[index].state = "sending"
                next.outbox[index].neverSubmitted = false
                try commit(next) // Persist uncertainty BEFORE starting any POST.
            }
            // POST retries reuse the same immutable operationId and payload.
            let receipt: OperationReceipt
            do { receipt = try await transport.submit(pending.operation) }
            catch BridgeNetworkError.conflict {
                try accept(OperationReceipt(bridgeID: bridgeID, operationId: pending.operation.operationId, status: "conflict", acknowledgment: nil))
                continue
            }
            try accept(receipt)
            if receipt.status == "received" {
                try accept(try await transport.receipt(for: pending.operation.operationId))
            }
        }
    }
}
