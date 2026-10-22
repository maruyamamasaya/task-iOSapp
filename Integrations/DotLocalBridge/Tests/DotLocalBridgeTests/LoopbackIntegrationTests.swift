import XCTest
@testable import DotLocalBridge

// HTTP is permitted only in this synthetic 127.0.0.1 test adapter.
// Production transport requires HTTPS + paired certificate pin.
private struct LoopbackTransport: BridgeTransport {
    let base: URL
    func request<T: Decodable>(_ path: String, operation: CompletionOperation? = nil, type: T.Type) async throws -> T {
        guard base.host == "127.0.0.1" else { throw BridgeNetworkError.invalidConfiguration }
        var request = URLRequest(url: base.appending(path: path))
        request.setValue("Bearer synthetic-loopback-only", forHTTPHeaderField: "Authorization")
        if let operation {
            request.httpMethod = "POST"; request.httpBody = try JSONEncoder().encode(operation)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, [200,202].contains(response.statusCode) else { throw BridgeNetworkError.unexpectedResponse }
        return try JSONDecoder().decode(type, from: data)
    }
    func fetch() async throws -> BridgeFeed { try await request("v1/tasks", type: BridgeFeed.self) }
    func submit(_ operation: CompletionOperation) async throws -> OperationReceipt { try await request("v1/operations", operation: operation, type: OperationReceipt.self) }
    func receipt(for id: UUID) async throws -> OperationReceipt { try await request("v1/operations/"+id.uuidString.lowercased(), type: OperationReceipt.self) }
}

final class LoopbackIntegrationTests: XCTestCase {
    func readLine(_ handle: FileHandle) throws -> String {
        var data = Data()
        while let byte = try handle.read(upToCount: 1), !byte.isEmpty {
            if byte.first == 10 { break }; data.append(byte)
        }
        guard let line = String(data: data, encoding: .utf8), !line.isEmpty else { throw BridgeNetworkError.unavailable }
        return line
    }
    func testSwiftOutboxAcrossRealLoopbackAndExplicitDotApply() async throws {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        process.arguments = ["python3", root.appending(path: "test_loopback_harness.py").path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        try process.run()
        defer {
            try? input.fileHandleForWriting.write(contentsOf: Data("QUIT\n".utf8))
            try? input.fileHandleForWriting.close()
            process.waitUntilExit()
        }
        let port = try readLine(output.fileHandleForReading)
        guard Int(port) != nil else { throw BridgeNetworkError.unavailable }
        let transport = LoopbackTransport(base: URL(string: "http://127.0.0.1:"+port)!)
        let file = FileManager.default.temporaryDirectory.appending(path: "dot-swift-e2e-"+UUID().uuidString).appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: file, bridgeID: "swift-loopback-fixture")
        try await store.synchronize(using: transport)
        let first = await store.snapshot
        let operation = try await store.queueCompletion(slug: "sample-task", completed: true)
        try await store.synchronize(using: transport)
        var value = await store.snapshot
        XCTAssertEqual(value.outbox.count, 1)
        XCTAssertEqual(value.outbox.first?.state, "received")
        XCTAssertEqual(value.tasks.first?.value.completed, false)
        let restarted = try LocalBridgeStore(file: file, bridgeID: "swift-loopback-fixture")
        try await restarted.synchronize(using: transport) // Same operation retried after restart.
        try input.fileHandleForWriting.write(contentsOf: Data(("APPLY "+operation.operationId.uuidString+"\n").utf8))
        let applied = try readLine(output.fileHandleForReading)
        XCTAssertTrue(applied.contains("applied"))
        try await restarted.synchronize(using: transport)
        value = await restarted.snapshot
        XCTAssertTrue(value.outbox.isEmpty)
        XCTAssertEqual(value.tasks.first?.value.completed, true)
        XCTAssertEqual(value.tasks.first?.value.revision, 2)
        XCTAssertEqual(value.tasks.first?.id, first.tasks.first?.id)
    }
}

private actor DelayedFirstAcknowledgment: BridgeTransport {
    let underlying: LoopbackTransport
    private var held: CheckedContinuation<Void, Never>?
    private var delayedOnce = false
    private(set) var waiting = false
    init(underlying: LoopbackTransport) { self.underlying = underlying }
    func fetch() async throws -> BridgeFeed { try await underlying.fetch() }
    func receipt(for id: UUID) async throws -> OperationReceipt { try await underlying.receipt(for: id) }
    func submit(_ operation: CompletionOperation) async throws -> OperationReceipt {
        let receipt = try await underlying.submit(operation)
        if !delayedOnce {
            delayedOnce = true; waiting = true
            await withCheckedContinuation { held = $0 }
        }
        return receipt
    }
    func release() { held?.resume(); held = nil }
}

extension LoopbackIntegrationTests {
    func testUndoWhileRealCanonicalPOSTAcknowledgmentIsDelayed() async throws {
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        process.arguments = ["python3", root.appending(path: "test_auto_apply_harness.py").path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        try process.run()
        defer {
            try? input.fileHandleForWriting.write(contentsOf: Data("QUIT\n".utf8))
            try? input.fileHandleForWriting.close(); process.waitUntilExit()
        }
        let port = try readLine(output.fileHandleForReading)
        let transport = DelayedFirstAcknowledgment(underlying: LoopbackTransport(base: URL(string: "http://127.0.0.1:"+port)!))
        let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "state.json")
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let store = try LocalBridgeStore(file: file, bridgeID: "undo-loopback-fixture")
        try await store.synchronize(using: transport)
        let completion = try await store.queueCompletion(slug: "sample-task", completed: true)
        let first = Task { try await store.synchronize(using: transport) }
        for _ in 0..<200 {
            if await transport.waiting { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        _ = try await store.queueCompletion(slug: "sample-task", completed: false)
        var value = await store.snapshot
        XCTAssertEqual(value.outbox.first?.operation, completion)
        XCTAssertEqual(value.displayedCompletion(for: "sample-task"), false)
        await transport.release(); try await first.value
        value = await store.snapshot
        let undo = try XCTUnwrap(value.outbox.first?.operation)
        XCTAssertNotEqual(undo.id, completion.id)
        XCTAssertEqual(undo.expectedRevision, 2)
        try await store.synchronize(using: transport)
        value = await store.snapshot
        XCTAssertTrue(value.outbox.isEmpty)
        XCTAssertFalse(value.tasks[0].value.completed)
        XCTAssertEqual(value.tasks[0].value.revision, 3)
        try input.fileHandleForWriting.write(contentsOf: Data("READ\n".utf8))
        let report = try JSONSerialization.jsonObject(with: Data(readLine(output.fileHandleForReading).utf8)) as! [String:Any]
        let row = report["task"] as! [String:Any]
        XCTAssertEqual(row["completed"] as? Bool, false)
        XCTAssertEqual(row["revision"] as? Int, 3)
        XCTAssertEqual(report["operationCount"] as? Int, 2)
    }
}
