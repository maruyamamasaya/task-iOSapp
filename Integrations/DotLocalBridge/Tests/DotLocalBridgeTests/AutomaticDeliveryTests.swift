import XCTest
@testable import DotLocalBridge

private actor DeliveryTransport: BridgeTransport {
    let feed: BridgeFeed
    var offline = false
    var submissions: [CompletionOperation] = []
    var concurrent = 0
    var maximumConcurrent = 0
    init(_ feed: BridgeFeed) { self.feed = feed }
    func setOffline(_ value: Bool) { offline = value }
    func fetch() async throws -> BridgeFeed {
        concurrent += 1; maximumConcurrent = max(maximumConcurrent, concurrent)
        defer { concurrent -= 1 }
        try await Task.sleep(for: .milliseconds(10))
        if offline { throw BridgeNetworkError.unavailable }
        return feed
    }
    func submit(_ operation: CompletionOperation) async throws -> OperationReceipt {
        submissions.append(operation)
        return OperationReceipt(bridgeID: feed.bridgeID, operationId: operation.id, status: "received", acknowledgment: nil)
    }
    func receipt(for id: UUID) async throws -> OperationReceipt {
        OperationReceipt(bridgeID: feed.bridgeID, operationId: id, status: "received", acknowledgment: nil)
    }
}

final class AutomaticDeliveryTests: XCTestCase {
    func testAutomaticSaveThenSendOfflineRestartAndSingleFlight() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let task = WireTask(id: "synthetic", title: "Synthetic", date: nil, dateLabel: "", status: "", details: "", category: "", completed: false, revision: 1)
        let feed = BridgeFeed(bridgeID: "fixture", tasks: [task])
        let transport = DeliveryTransport(feed)
        await transport.setOffline(true)
        let store = try LocalBridgeStore(file: file, bridgeID: "fixture")
        try await store.merge(feed)
        await store.setAutomaticTransport(transport)
        let operation = try await store.queueCompletion(slug: "synthetic", completed: true)
        // Disk already contains the exact operation, even before any network result.
        let disk = try JSONDecoder().decode(BridgeSnapshot.self, from: Data(contentsOf: file))
        XCTAssertEqual(disk.outbox.first?.operation, operation)
        let sameOperation = try await store.queueCompletion(slug: "synthetic", completed: true)
        XCTAssertEqual(sameOperation, operation)
        let choice = await store.snapshot
        XCTAssertEqual(choice.displayedCompletion(for: "synthetic"), true)
        try await Task.sleep(for: .milliseconds(100))
        await store.setAutomaticTransport(nil)
        let offlineValue = await store.snapshot
        XCTAssertEqual(offlineValue.outbox.first?.state, "pending")
        let restarted = try LocalBridgeStore(file: file, bridgeID: "fixture")
        await transport.setOffline(false)
        // Activation after restart is sufficient: no manual synchronize call.
        await restarted.setAutomaticTransport(transport)
        for _ in 0..<100 {
            if await restarted.snapshot.outbox.first?.state == "received" { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let received = await restarted.snapshot
        XCTAssertEqual(received.outbox.first?.state, "received")
        XCTAssertEqual(received.outbox.first?.operation, operation)
        XCTAssertFalse(received.tasks[0].value.completed)
        async let a: Void = restarted.synchronize(using: transport)
        async let b: Void = restarted.synchronize(using: transport)
        _ = try await (a, b)
        try await Task.sleep(for: .milliseconds(100))
        let operations = await transport.submissions
        XCTAssertFalse(operations.isEmpty)
        XCTAssertTrue(operations.allSatisfy { $0 == operation })
        let maximum = await transport.maximumConcurrent
        XCTAssertEqual(maximum, 1)
        await restarted.setAutomaticTransport(nil)
    }
}
