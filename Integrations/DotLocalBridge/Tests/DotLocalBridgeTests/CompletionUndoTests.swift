import XCTest
@testable import DotLocalBridge

private actor HeldDelivery: BridgeTransport {
    let feed: BridgeFeed
    private var continuation: CheckedContinuation<OperationReceipt, Never>?
    private(set) var submitted: CompletionOperation?
    init(feed: BridgeFeed) { self.feed = feed }
    func fetch() async throws -> BridgeFeed { feed }
    func submit(_ operation: CompletionOperation) async throws -> OperationReceipt {
        submitted = operation
        return await withCheckedContinuation { continuation = $0 }
    }
    func receipt(for id: UUID) async throws -> OperationReceipt { fatalError("applied POST needs no poll") }
    func finish() {
        guard let operation = submitted else { return }
        continuation?.resume(returning: OperationReceipt(bridgeID: feed.bridgeID, operationId: operation.id, status: "applied", acknowledgment: ApplyAcknowledgment(taskId: operation.taskId, revision: operation.expectedRevision + 1, completed: operation.completed, target: "dot_local_file", operationDigest: String(repeating: "a", count: 64))))
        continuation = nil
    }
}

final class CompletionUndoTests: XCTestCase {
    private func fixture() throws -> (LocalBridgeStore, URL, WireTask) {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "state.json")
        let row = WireTask(id: "synthetic", title: "Synthetic", date: nil, dateLabel: "", status: "", details: "", category: "", completed: false, revision: 1)
        return (try LocalBridgeStore(file: file, bridgeID: "fixture"), file, row)
    }
    private func ack(_ operation: CompletionOperation) -> OperationReceipt {
        OperationReceipt(bridgeID: "fixture", operationId: operation.id, status: "applied", acknowledgment: ApplyAcknowledgment(taskId: operation.taskId, revision: operation.expectedRevision + 1, completed: operation.completed, target: "dot_local_file", operationDigest: String(repeating: "a", count: 64)))
    }
    func testUnsentUndoWithdrawsOnlyTheNeverSubmittedOperation() async throws {
        let (store,file,row) = try fixture(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let original = try await store.queueCompletion(slug: row.id, completed: true)
        _ = try await store.queueCompletion(slug: row.id, completed: false)
        let restarted = try LocalBridgeStore(file: file, bridgeID: "fixture")
        let value = await restarted.snapshot
        XCTAssertTrue(value.outbox.isEmpty)
        XCTAssertFalse(value.tasks[0].value.completed)
        try await restarted.accept(ack(original))
        let replay = await restarted.snapshot
        XCTAssertFalse(replay.tasks[0].value.completed)
    }
    func testReceivedUndoSurvivesRestartThenUsesNewIDAndIgnoresOldAcknowledgments() async throws {
        let (store,file,row) = try fixture(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let original = try await store.queueCompletion(slug: row.id, completed: true)
        try await store.accept(OperationReceipt(bridgeID: "fixture", operationId: original.id, status: "received", acknowledgment: nil))
        _ = try await store.queueCompletion(slug: row.id, completed: false)
        _ = try await store.queueCompletion(slug: row.id, completed: true)
        _ = try await store.queueCompletion(slug: row.id, completed: false) // Rapid choices retain only the latest intent.
        let restarted = try LocalBridgeStore(file: file, bridgeID: "fixture")
        var value = await restarted.snapshot
        XCTAssertEqual(value.outbox[0].operation, original)
        XCTAssertFalse(value.outbox[0].displayedCompletion)
        try await restarted.accept(ack(original))
        value = await restarted.snapshot
        let undo = try XCTUnwrap(value.outbox.first?.operation)
        XCTAssertNotEqual(undo.id, original.id)
        XCTAssertEqual(undo.expectedRevision, 2)
        XCTAssertFalse(undo.completed)
        try await restarted.accept(ack(original))
        try await restarted.accept(OperationReceipt(bridgeID: "fixture", operationId: original.id, status: "received", acknowledgment: nil))
        value = await restarted.snapshot
        XCTAssertEqual(value.outbox[0].operation, undo)
        XCTAssertFalse(value.outbox[0].displayedCompletion)
        try await restarted.accept(ack(undo))
        value = await restarted.snapshot
        XCTAssertTrue(value.outbox.isEmpty)
        XCTAssertFalse(value.tasks[0].value.completed)
        XCTAssertEqual(value.tasks[0].value.revision, 3)
        var stale = row; stale.revision = 2; stale.completed = true
        do { try await restarted.merge(BridgeFeed(bridgeID: "fixture", tasks: [stale])); XCTFail() } catch {}
        let after = await restarted.snapshot
        XCTAssertEqual(after, value)
    }
    func testUndoWhilePOSTIsInFlightNeverChangesSubmittedPayload() async throws {
        let (store,file,row) = try fixture(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let feed = BridgeFeed(bridgeID: "fixture", tasks: [row]); try await store.merge(feed)
        let original = try await store.queueCompletion(slug: row.id, completed: true)
        let transport = HeldDelivery(feed: feed)
        let delivery = Task { try await store.synchronize(using: transport) }
        for _ in 0..<100 {
            if await transport.submitted != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        var value = await store.snapshot
        XCTAssertEqual(value.outbox.first?.state, "sending")
        _ = try await store.queueCompletion(slug: row.id, completed: false)
        let submitted = await transport.submitted
        XCTAssertEqual(submitted, original)
        await transport.finish(); try await delivery.value
        value = await store.snapshot
        XCTAssertFalse(try XCTUnwrap(value.outbox.first).displayedCompletion)
        XCTAssertEqual(value.outbox.first?.operation.expectedRevision, 2)
    }
    func testLegacyPendingIsUncertainAndCannotBeDiscardedByUndo() async throws {
        let (store,file,row) = try fixture(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let original = try await store.queueCompletion(slug: row.id, completed: true)
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String:Any]
        var outbox = object["outbox"] as! [[String:Any]]
        outbox[0].removeValue(forKey: "neverSubmitted"); outbox[0].removeValue(forKey: "nextCompleted")
        object["outbox"] = outbox
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        let restarted = try LocalBridgeStore(file: file, bridgeID: "fixture")
        _ = try await restarted.queueCompletion(slug: row.id, completed: false)
        var value = await restarted.snapshot
        XCTAssertEqual(value.outbox[0].operation, original)
        XCTAssertEqual(value.outbox[0].nextCompleted, false)
        try await restarted.accept(ack(original))
        value = await restarted.snapshot
        XCTAssertEqual(value.outbox.count, 1)
        XCTAssertNotEqual(value.outbox[0].operation.id, original.id)
        XCTAssertFalse(value.outbox[0].operation.completed)
    }
    func testFailedUndoSaveKeepsPreviousDurableChoiceAndPublishesNothingNew() async throws {
        let (store,file,row) = try fixture(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        _ = try await store.queueCompletion(slug: row.id, completed: true)
        let before = await store.snapshot
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        do { _ = try await store.queueCompletion(slug: row.id, completed: false); XCTFail() } catch {}
        let after = await store.snapshot
        XCTAssertEqual(after, before)
    }
    func testChangesStreamYieldsOnlyAfterPersistedStateIsAvailable() async throws {
        let (store,file,row) = try fixture(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let stream = await store.changes(); var iterator = stream.makeAsyncIterator()
        _ = await iterator.next()
        _ = try await store.queueCompletion(slug: row.id, completed: true)
        let next = await iterator.next()
        let emitted = try XCTUnwrap(next)
        let disk = try JSONDecoder().decode(BridgeSnapshot.self, from: Data(contentsOf: file))
        XCTAssertEqual(emitted, disk)
        XCTAssertTrue(emitted.displayedCompletion(for: row.id) == true)
    }
    func testNewerExternalRevisionDoesNotSilentlyRebaseUndo() async throws {
        let (store,file,row) = try fixture(); defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let original = try await store.queueCompletion(slug: row.id, completed: true)
        try await store.accept(OperationReceipt(bridgeID: "fixture", operationId: original.id, status: "received", acknowledgment: nil))
        _ = try await store.queueCompletion(slug: row.id, completed: false)
        var external = row; external.revision = 5; external.completed = true
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [external]))
        try await store.accept(ack(original))
        let value = await store.snapshot
        XCTAssertEqual(value.tasks[0].value, external)
        XCTAssertEqual(value.outbox.first?.state, "conflict")
        XCTAssertFalse(try XCTUnwrap(value.outbox.first).displayedCompletion)
    }
}
