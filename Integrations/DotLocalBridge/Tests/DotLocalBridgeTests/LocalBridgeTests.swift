import XCTest
@testable import DotLocalBridge

final class LocalBridgeTests: XCTestCase {
    func file() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "dot-local-test-" + UUID().uuidString).appending(path: "state.json")
    }
    func task(_ slug: String = "sample-task", revision: Int = 1) -> WireTask {
        WireTask(id: slug, title: "合成タスク", date: nil, dateLabel: "未定", status: "確認待ち", details: "", category: "テスト", completed: false, revision: revision)
    }
    func receipt(_ operation: CompletionOperation, status: String = "applied", bridge: String = "fixture") -> OperationReceipt {
        OperationReceipt(bridgeID: bridge, operationId: operation.operationId, status: status,
                         acknowledgment: status == "applied" ? ApplyAcknowledgment(taskId: operation.taskId, revision: operation.expectedRevision + 1, completed: operation.completed, target: "dot_local_file", operationDigest: String(repeating: "a", count: 64)) : nil)
    }
    func testScheduleAIAndPendingSurviveRestart() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        var row = task(); row.date = "2026-10-24"; row.startTime = "10:00"; row.endTime = "10:30"
        row.timeZone = "Asia/Tokyo"; row.deadlineDate = "2026-11-07"; row.deadlineTime = "17:00"
        row.details = "人向け"; row.aiContext = "AI根拠"
        XCTAssertEqual(row.scheduleDate(), ISO8601DateFormatter().date(from: "2026-10-24T01:00:00Z"))
        XCTAssertFalse(row.humanDetails.contains("AI根拠"))
        XCTAssertTrue(row.humanDetails.contains("固定期限: 2026-11-07 17:00"))
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let op = try await store.queueCompletion(slug: row.id, completed: true)
        let before = await store.snapshot
        let restarted = try LocalBridgeStore(file: url, bridgeID: "fixture")
        let after = await restarted.snapshot
        XCTAssertEqual(before, after)
        try await restarted.accept(receipt(op))
        let applied = await restarted.snapshot
        XCTAssertEqual(applied.tasks[0].value.aiContext, "AI根拠")
        XCTAssertEqual(applied.tasks[0].value.endTime, "10:30")
        XCTAssertEqual(applied.tasks[0].value.deadlineDate, "2026-11-07")
        var legacy = task(); legacy.date = "2026-11-08"
        XCTAssertTrue(legacy.hasValidSchedule)
    }
    func testInvalidMinuteSchedules() {
        var row = task(); row.date = "2026-10-24"; row.timeZone = "Asia/Tokyo"
        for invalid in ["24:00", "10:00:00", "9:00"] {
            row.startTime = invalid; XCTAssertFalse(row.hasValidSchedule)
        }
        row.startTime = "10:00"; row.endTime = "09:00"; XCTAssertFalse(row.hasValidSchedule)
        row.endTime = nil; row.timeZone = "Imaginary/Zone"; XCTAssertFalse(row.hasValidSchedule)
        row.date = "2026-03-08"; row.startTime = "02:30"; row.timeZone = "America/Los_Angeles"
        XCTAssertFalse(row.hasValidSchedule)
    }
    func testMetadataPersistsAcrossRestartAndCompletion() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        var row = task()
        row.project = WireReference(id: UUID(), name: "仕事")
        row.tags = [WireReference(id: UUID(), name: "請求")]
        row.reminderAt = "2026-10-23T09:00:00+09:00"
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let before = await store.snapshot
        let reopened = try LocalBridgeStore(file: url, bridgeID: "fixture")
        let saved = await reopened.snapshot
        XCTAssertEqual(saved, before)
        XCTAssertEqual(row.reminderDate, ISO8601DateFormatter().date(from: "2026-10-23T00:00:00Z"))
        let op = try await reopened.queueCompletion(slug: row.id, completed: true)
        try await reopened.accept(receipt(op))
        let completed = await reopened.snapshot
        XCTAssertEqual(completed.tasks[0].value.project, row.project)
        XCTAssertEqual(completed.tasks[0].value.tags, row.tags)
        XCTAssertEqual(completed.tasks[0].value.reminderAt, row.reminderAt)
        row.revision = 3; row.project = nil; row.tags = []; row.reminderAt = nil
        try await reopened.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let cleared = await reopened.snapshot
        XCTAssertEqual(cleared.tasks[0].id, before.tasks[0].id)
        XCTAssertNil(cleared.tasks[0].value.reminderDate)
    }
    func testInvalidMetadataCannotReplaceSavedTasks() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        let before = await store.snapshot
        var bad = task(revision: 2)
        for reminder in ["2026-10-23T09:00:00", "invalid"] {
            bad.reminderAt = reminder
            do { try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [bad])); XCTFail() } catch {}
        }
        bad.reminderAt = nil
        let tag = WireReference(id: UUID(), name: "tag")
        bad.tags = [tag, tag]
        do { try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [bad])); XCTFail() } catch {}
        let after = await store.snapshot
        XCTAssertEqual(after, before)
    }
    func testStableUUIDNonDestructiveMergeAndRestart() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task(), task("another")]))
        let original = await store.snapshot
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task(revision: 2)]))
        let restarted = try LocalBridgeStore(file: url, bridgeID: "fixture")
        let value = await restarted.snapshot
        XCTAssertEqual(value.tasks.count, 2)
        XCTAssertEqual(value.tasks.first?.id, original.tasks.first?.id)
        XCTAssertEqual(value.tasks.first?.value.revision, 2)
    }
    func testReceiptIsNotDotApplyOutboxSurvivesRestart() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        let op = try await store.queueCompletion(slug: "sample-task", completed: true)
        try await store.accept(receipt(op, status: "received"))
        let reopened = try LocalBridgeStore(file: url, bridgeID: "fixture")
        var value = await reopened.snapshot
        XCTAssertEqual(value.outbox.first?.operation, op)
        XCTAssertEqual(value.outbox.first?.state, "received")
        XCTAssertEqual(value.tasks.first?.value.completed, false)
        try await reopened.accept(receipt(op))
        value = await reopened.snapshot
        XCTAssertTrue(value.outbox.isEmpty)
        XCTAssertEqual(value.tasks.first?.value.completed, true)
        XCTAssertEqual(value.tasks.first?.value.status, "確認待ち")
        try await reopened.accept(receipt(op)) // Replay doesn't increment revision again.
        let replayed = await reopened.snapshot
        XCTAssertEqual(replayed.tasks.first?.value.revision, 2)
    }
    func testConflictAndBadAcknowledgmentsNeverDiscardOutbox() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        let op = try await store.queueCompletion(slug: "sample-task", completed: true)
        _ = try await store.queueCompletion(slug: "sample-task", completed: true) // Same desired state is idempotent.
        do { try await store.accept(receipt(op, bridge: "another")); XCTFail() } catch {}
        let wrong = OperationReceipt(bridgeID: "fixture", operationId: op.operationId, status: "applied", acknowledgment: ApplyAcknowledgment(taskId: "unknown", revision: 2, completed: true, target: "dot_local_file", operationDigest: String(repeating: "a", count: 64)))
        do { try await store.accept(wrong); XCTFail() } catch {}
        try await store.accept(receipt(op, status: "conflict"))
        let value = await store.snapshot
        XCTAssertEqual(value.outbox.first?.state, "conflict")
        XCTAssertEqual(value.tasks.first?.value.completed, false)
    }
    func testSaveFailurePreservesSnapshotAndWrongNamespaceRejected() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        XCTAssertThrowsError(try LocalBridgeStore(file: url, bridgeID: "another"))
        let old = await store.snapshot
        // Replacing own test destination with a directory guarantees a save error.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        do { _ = try await store.queueCompletion(slug: "sample-task", completed: true); XCTFail() } catch {}
        let current = await store.snapshot
        XCTAssertEqual(current, old)
    }
    func testDelayedAcknowledgmentDoesNotRollBackNewerFeed() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        let op = try await store.queueCompletion(slug: "sample-task", completed: true)
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task(revision: 4)]))
        try await store.accept(receipt(op))
        let value = await store.snapshot
        XCTAssertEqual(value.tasks.first?.value.revision, 4)
        XCTAssertEqual(value.tasks.first?.value.completed, false)
        XCTAssertTrue(value.outbox.isEmpty)
    }
    func testUnpairedAndPublicEndpointsRejected() {
        for url in ["http://192.168.1.2:8443", "https://public.example.invalid", "https://user:pass@mac.local", "https://mac.local?token=x"] {
            XCTAssertThrowsError(try HTTPSBridgeTransport(base: URL(string: url)!, certificateSHA256: String(repeating: "a", count: 64), bearer: "synthetic-only"))
        }
        XCTAssertThrowsError(try HTTPSBridgeTransport(base: URL(string: "https://mac.local")!, certificateSHA256: "", bearer: ""))
    }
    func testInvalidAndRegressingFeedPreservesPreviousSnapshot() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task(revision: 3)]))
        let old = await store.snapshot
        var invalid = task(revision: 4); invalid.date = "2026-02-30"
        for rows in [[invalid], [task(revision: 1)], [task(), task()]] {
            do { try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: rows)); XCTFail() } catch {}
        }
        let current = await store.snapshot
        XCTAssertEqual(old, current)
    }
    func testExplicitDeviceSeedNeverOverwritesStartedWork() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try await store.initializeFromDevice(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        let op = try await store.queueCompletion(slug: "sample-task", completed: true)
        do { try await store.initializeFromDevice(BridgeFeed(bridgeID: "fixture", tasks: [task(revision: 8)])); XCTFail() } catch {}
        let value = await store.snapshot
        XCTAssertEqual(value.outbox.first?.operation, op)
        XCTAssertEqual(value.tasks.first?.value.revision, 1)
    }
    func testAppliedHistoryIsDurableAndReceivedIsNotConfirmation() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        let op = try await store.queueCompletion(slug: "sample-task", completed: true)
        try await store.accept(receipt(op, status: "received"))
        var value = await store.snapshot
        XCTAssertTrue(value.appliedHistory?.isEmpty ?? true)
        try await store.accept(receipt(op))
        let restarted = try LocalBridgeStore(file: url, bridgeID: "fixture")
        value = await restarted.snapshot
        XCTAssertEqual(value.appliedHistory?.last?.operationId, op.operationId)
        XCTAssertEqual(value.appliedHistory?.last?.completed, true)
        XCTAssertTrue(value.outbox.isEmpty)
    }
    func testConflictResolutionIsExplicitAndRetryUsesNewIdCurrentRevision() async throws {
        let url = file(); defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: url, bridgeID: "fixture")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task()]))
        let op = try await store.queueCompletion(slug: "sample-task", completed: true)
        try await store.accept(receipt(op, status: "conflict"))
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [task(revision: 3)]))
        try await store.resolveConflict(slug: "sample-task", retryOwnChoice: true)
        var value = await store.snapshot
        let new = try XCTUnwrap(value.outbox.first?.operation)
        XCTAssertNotEqual(new.operationId, op.operationId)
        XCTAssertEqual(new.expectedRevision, 3)
        XCTAssertTrue(new.completed)
        try await store.accept(receipt(new, status: "conflict"))
        try await store.resolveConflict(slug: "sample-task", retryOwnChoice: false)
        value = await store.snapshot
        XCTAssertTrue(value.outbox.isEmpty)
        XCTAssertEqual(value.tasks.count, 1)
        XCTAssertFalse(value.tasks[0].value.completed)
    }
}
