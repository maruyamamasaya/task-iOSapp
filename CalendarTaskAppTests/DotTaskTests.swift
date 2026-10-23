import XCTest
import DotLocalBridge
@testable import CalendarTaskApp

@MainActor final class DotTaskTests: XCTestCase {
    final class Cache: DotTaskCache {
        var value: DotTaskSnapshot?
        var failSave = false
        func load() throws -> DotTaskSnapshot? { value }
        func save(_ snapshot: DotTaskSnapshot) throws {
            if failSave { throw DotTaskError.invalidFeed }
            value = snapshot
        }
    }
    final class Source: DotTaskSource {
        var source = "test"
        var account = "one"
        var feed = DotTaskFeed(updatedAt: "v1", tasks: [])
        var fails = false
        func fetch() async throws -> DotTaskFeed {
            if fails { throw DotTaskError.invalidFeed }
            return feed
        }
    }
    func row(_ slug: String, title: String = "same") -> DotTaskRecord {
        DotTaskRecord(id: UUID(), slug: slug, title: title, date: nil, dateLabel: "未定",
                      status: "pending", details: "", category: "test")
    }
    func testKindImportRefreshAndRestartKeepsIdentity() async throws {
        let cache = Cache(), source = Source()
        let store = DotTaskStore(source:source, cache:cache)
        var first = row("synthetic-kind"); first.taskKind = "idea"
        source.feed = DotTaskFeed(updatedAt:"v1",tasks:[first]); await store.refresh()
        let identity = try XCTUnwrap(store.snapshot?.tasks.first?.id)
        first.taskKind = "task"
        source.feed = DotTaskFeed(updatedAt:"v2",tasks:[first]); await store.refresh()
        let reopened = DotTaskStore(source:source,cache:cache); reopened.load()
        XCTAssertEqual(reopened.snapshot?.tasks.first?.id,identity)
        XCTAssertEqual(reopened.snapshot?.tasks.first?.taskKind,"task")
        let data = Data(FixtureDotTaskSource.json.replacingOccurrences(of: "\"category\":\"開発\"", with: "\"category\":\"開発\",\"taskKind\":\"event\"").utf8)
        XCTAssertEqual(try DotTaskFeedDecoder.decode(data).tasks.first?.taskKind,"event")
    }
    func testWireDatesAndOptionalFields() async throws {
        let feed = try DotTaskFeedDecoder.decode(Data(FixtureDotTaskSource.json.utf8))
        XCTAssertEqual(feed.tasks[0].date, "2026-10-21")
        XCTAssertNil(feed.tasks[1].date)
        XCTAssertEqual(feed.tasks[1].parentId, "sample-review")
        XCTAssertEqual(feed.tasks[1].status, "pending")
        let bad = FixtureDotTaskSource.json.replacingOccurrences(of: "2026-10-21\",\"dateLabel", with: "2026-02-30\",\"dateLabel")
        XCTAssertThrowsError(try DotTaskFeedDecoder.decode(Data(bad.utf8)))
        let duplicate = FixtureDotTaskSource.json.replacingOccurrences(of: "sample-later", with: "sample-review")
        XCTAssertThrowsError(try DotTaskFeedDecoder.decode(Data(duplicate.utf8)))
    }
    func testIdentitySurvivesRestartAndMissingRowsDoNotDelete() async {
        let cache = Cache(), source = Source()
        source.feed = DotTaskFeed(updatedAt: "v1", tasks: [row("a"), row("b")])
        let first = DotTaskStore(source: source, cache: cache)
        await first.refresh()
        let id = first.snapshot?.tasks[0].id
        XCTAssertEqual(first.snapshot?.tasks.count, 2) // same title never merges
        source.feed = DotTaskFeed(updatedAt: "v2", tasks: [row("a", title: "changed")])
        let restarted = DotTaskStore(source: source, cache: cache)
        restarted.load()
        XCTAssertEqual(restarted.snapshot, first.snapshot)
        await restarted.refresh()
        XCTAssertEqual(restarted.snapshot?.tasks[0].id, id)
        XCTAssertEqual(restarted.snapshot?.tasks[0].title, "changed")
        XCTAssertEqual(restarted.snapshot?.tasks.count, 2)
    }
    func testFetchAndSaveFailureKeepLastSuccessfulSnapshot() async {
        let cache = Cache(), source = Source()
        source.feed = DotTaskFeed(updatedAt: "v1", tasks: [row("a")])
        let store = DotTaskStore(source: source, cache: cache)
        await store.refresh()
        let old = store.snapshot
        source.fails = true
        await store.refresh()
        XCTAssertEqual(store.snapshot, old)
        XCTAssertNotNil(store.errorMessage)
        source.fails = false
        cache.failSave = true
        await store.refresh()
        XCTAssertEqual(store.snapshot, old)
        XCTAssertEqual(cache.value, old)
        XCTAssertFalse(store.isRefreshing)
    }
    func testRejectsOtherAccountSourceVersionAndDuplicateFeed() async {
        let cache = Cache(), source = Source()
        source.feed = DotTaskFeed(updatedAt: "v1", tasks: [row("a")])
        let store = DotTaskStore(source: source, cache: cache)
        await store.refresh()
        source.account = "two"
        let other = DotTaskStore(source: source, cache: cache)
        other.load()
        XCTAssertNil(other.snapshot)
        await other.refresh()
        XCTAssertNil(other.snapshot)
        source.account = "one"
        source.source = "another"
        await other.refresh()
        XCTAssertNil(other.snapshot)
        source.source = "test"
        source.feed = DotTaskFeed(updatedAt: "v2", tasks: [row("a"), row("a")])
        let old = cache.value
        await store.refresh()
        XCTAssertEqual(cache.value, old)
        cache.value = DotTaskSnapshot(version: 2, source: "test", account: "one", updatedAt: "v1", fetchedAt: .now, tasks: [])
        let future = DotTaskStore(source: source, cache: cache)
        future.load()
        XCTAssertNil(future.snapshot)
        XCTAssertNotNil(future.errorMessage)
    }
    func testFileCacheRoundTripAndCorruption() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("sample.json")
        let cache = DotTaskFileCache(url: url)
        XCTAssertNil(try cache.load())
        let snapshot = DotTaskSnapshot(version: 1, source: "fixture", account: "sample", updatedAt: "v1", fetchedAt: Date(timeIntervalSince1970: 1234), tasks: [row("a")])
        try cache.save(snapshot)
        XCTAssertEqual(try DotTaskFileCache(url: url).load(), snapshot)
        try Data("broken".utf8).write(to: url)
        XCTAssertThrowsError(try cache.load())
    }

    func testLocalJSONImportSurvivesRestartAndKeepsIdentity() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("tasks.json")
        let cacheURL = directory.appendingPathComponent("local-cache.json")
        try Data(FixtureDotTaskSource.json.utf8).write(to: input)
        let cache = DotTaskFileCache(url: cacheURL)
        let store = DotTaskStore(source: LocalDotTaskSource(cache: cache), cache: cache, importer: DotTaskJSONFileImporter())
        XCTAssertTrue(store.canImport)
        store.importFile(from: input)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.snapshot?.tasks.count, 2)
        XCTAssertEqual(store.snapshot?.source, "dot-local-json-v1")
        XCTAssertEqual(store.snapshot?.account, "on-device")
        let firstID = store.snapshot?.tasks.first?.id
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(FixtureDotTaskSource.json.utf8)) as? [String: Any])
        var rows = try XCTUnwrap(document["tasks"] as? [[String: Any]])
        rows[0]["title"] = "更新後のタイトル"
        document["tasks"] = [rows[0]]
        try JSONSerialization.data(withJSONObject: document).write(to: input)
        store.importFile(from: input)
        XCTAssertEqual(store.snapshot?.tasks.first?.id, firstID)
        XCTAssertEqual(store.snapshot?.tasks.first?.title, "更新後のタイトル")
        XCTAssertEqual(store.snapshot?.tasks.count, 2, "Missing rows are not deletion instructions")
        let reopenedCache = DotTaskFileCache(url: cacheURL)
        let restarted = DotTaskStore(source: LocalDotTaskSource(cache: reopenedCache), cache: reopenedCache,
                                     importer: DotTaskJSONFileImporter())
        restarted.load()
        XCTAssertEqual(restarted.snapshot, store.snapshot)
        // The originally selected file is no longer needed for offline use.
        try FileManager.default.removeItem(at: input)
        await restarted.refresh()
        XCTAssertNil(restarted.errorMessage)
        XCTAssertEqual(restarted.snapshot?.tasks.first?.id, firstID)
    }

    func testInvalidOrOversizedImportPreservesLastGoodCache() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appendingPathComponent("tasks.json")
        let cache = Cache()
        let store = DotTaskStore(source: LocalDotTaskSource(cache: cache), cache: cache, importer: DotTaskJSONFileImporter())
        try Data(FixtureDotTaskSource.json.utf8).write(to: input)
        store.importFile(from: input)
        let original = store.snapshot
        for data in [Data("invalid".utf8),
                     Data(FixtureDotTaskSource.json.replacingOccurrences(of: "sample-later", with: "sample-review").utf8),
                     Data(repeating: 32, count: DotTaskJSONFileImporter.maximumBytes + 1)] {
            try data.write(to: input)
            store.importFile(from: input)
            XCTAssertEqual(store.snapshot, original)
            XCTAssertEqual(cache.value, original)
            XCTAssertNotNil(store.errorMessage)
            XCTAssertFalse(store.isRefreshing)
        }
        XCTAssertThrowsError(try DotTaskJSONFileImporter().read(from: URL(string: "https://example.invalid/tasks.json")!))
        try Data(FixtureDotTaskSource.json.utf8).write(to: input)
        cache.failSave = true
        store.importFile(from: input)
        XCTAssertEqual(store.snapshot, original)
        XCTAssertEqual(cache.value, original)
        XCTAssertNotNil(store.errorMessage)
    }

    func testLocalSourceStartsEmptyAndDoesNotLoadFixture() async {
        let cache = Cache()
        let store = DotTaskStore(source: LocalDotTaskSource(cache: cache), cache: cache, importer: DotTaskJSONFileImporter())
        store.load()
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.errorMessage)
        await store.refresh()
        XCTAssertNil(store.snapshot)
        XCTAssertNotNil(store.errorMessage)
    }
}


@MainActor final class DotPlannerTaskRepositoryTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return value
    }
    private func record(_ slug: String, date: String? = "2026-10-21", status: String = "todo") -> DotTaskRecord {
        DotTaskRecord(id: UUID(), slug: slug, title: slug, date: date, dateLabel: "",
                      status: status, details: "詳細", category: "test")
    }
    func testProjectsLocalDaysCompletionAndStableIdentityWithoutNativeTasks() async throws {
        let rows = [record("today"), record("later", date: "2026-10-22"),
                    record("undated", date: nil), record("done", status: "完了"),
                    record("unknown", status: "new-status"), record("invalid", date: "2026-02-30")]
        let repository = DotPlannerTaskRepository(imported: { rows }, relay: { [] },
            updateRelay: { _ in XCTFail("JSON must not write to relay") }, calendar: calendar)
        let tasks = try await repository.fetchTasks()
        XCTAssertEqual(tasks.map(\.id), rows.map(\.id))
        XCTAssertEqual(tasks[0].dueDate, calendar.date(from: DateComponents(year: 2026, month: 10, day: 21)))
        XCTAssertEqual(tasks[1].dueDate, calendar.date(from: DateComponents(year: 2026, month: 10, day: 22)))
        XCTAssertNil(tasks[2].dueDate)
        XCTAssertTrue(tasks[3].isCompleted)
        XCTAssertFalse(tasks[4].isCompleted)
        XCTAssertNil(tasks[5].dueDate)
        XCTAssertTrue(tasks.allSatisfy { $0.isAllDay && $0.reminderDate == nil && $0.recurrenceRule == nil })
        do { try await repository.updateTask(tasks[0]); XCTFail("JSON is read-only") } catch {}
        do { try await repository.addTask(tasks[0]); XCTFail("Manual creation is disabled") } catch {}
        do { try await repository.deleteTask(id: tasks[0].id); XCTFail("Deletion is disabled") } catch {}
    }
    func testRelayOverridesSameSlugAndCompletionIsForwarded() async throws {
        let imported = record("same")
        let localOnly = record("local-only")
        let projection = DotPlannerTaskRepository(imported: { [imported] }, relay: { [] }, updateRelay: { _ in })
        let projected = try await projection.fetchTasks()
        var relayTask = try XCTUnwrap(projected.first)
        relayTask = TaskItem(id: UUID(), title: "relay", note: "", startDate: nil, dueDate: relayTask.dueDate,
            isAllDay: true, isCompleted: true, completedAt: nil, priority: .normal, reminderDate: nil,
            recurrenceRule: nil, projectID: nil, category: nil, tags: [], createdAt: .distantPast, updatedAt: .distantPast)
        let original = relayTask
        var updated: TaskItem?
        let repository = DotPlannerTaskRepository(imported: { [imported, localOnly] },
            relay: { [DotPlannerTask(slug: "same", task: original)] }, updateRelay: { updated = $0 })
        let tasks = try await repository.fetchTasks()
        XCTAssertEqual(tasks.map(\.id), [localOnly.id, original.id])
        relayTask.isCompleted = false
        try await repository.updateTask(relayTask)
        XCTAssertEqual(updated, relayTask)
    }
    func testEmptyOrFailedDotSourceNeverFallsBackToNativeTasks() async throws {
        let empty = DotPlannerTaskRepository(imported: { [] }, relay: { [] }, updateRelay: { _ in })
        let tasks = try await empty.fetchTasks()
        XCTAssertTrue(tasks.isEmpty)
        let failed = DotPlannerTaskRepository(imported: { [] }, relay: { throw DotTaskError.invalidFeed }, updateRelay: { _ in })
        do { _ = try await failed.fetchTasks(); XCTFail("Source errors must propagate") } catch {}
    }
}

@MainActor final class APScheduleProjectionTests: XCTestCase {
    func testRelayMinuteScheduleAndWidgetHideAIContext() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try LocalBridgeStore(file: folder.appending(path: "relay.json"), bridgeID: "fixture")
        let row = WireTask(id: "ap-fixture", title: "申込", date: "2026-10-24", dateLabel: "仮枠", status: "未着手",
                           details: "空き枠を確認", category: "test", completed: false, revision: 1,
                           aiContext: "AI_ONLY_SOURCE", startTime: "10:00", endTime: "10:30", timeZone: "Asia/Tokyo",
                           deadlineDate: "2026-11-07", deadlineTime: "17:00")
        try await store.merge(BridgeFeed(bridgeID: "fixture", tasks: [row]))
        let repository = DotRelayTaskRepository(native: InMemoryTaskRepository(tasks: []), cache: DotRelayTaskCache(store: store))
        let tasks = try await repository.fetchTasks()
        let task = try XCTUnwrap(tasks.first)
        XCTAssertFalse(task.isAllDay)
        XCTAssertEqual(task.dueDate, ISO8601DateFormatter().date(from: "2026-10-24T01:00:00Z"))
        XCTAssertTrue(task.note.contains("10:00〜10:30"))
        XCTAssertTrue(task.note.contains("固定期限: 2026-11-07 17:00"))
        XCTAssertFalse(task.note.contains("AI_ONLY_SOURCE"))
        let widget = DotWidgetTaskCache(url: folder.appending(path: "widget.json"))
        try widget.save(tasks)
        XCTAssertEqual(try widget.load().first?.date, task.dueDate)
        XCTAssertNil(try widget.load().first?.calendarDate)
        XCTAssertFalse(try String(contentsOf: widget.url).contains("AI_ONLY_SOURCE"))
        var complete = task; complete.isCompleted = true
        try await repository.updateTask(complete)
        let pending = await store.snapshot
        XCTAssertEqual(pending.outbox.count, 1)
        let reopened = try LocalBridgeStore(file: folder.appending(path: "relay.json"), bridgeID: "fixture")
        let saved = await reopened.snapshot
        XCTAssertEqual(saved, pending)
        XCTAssertEqual(saved.tasks[0].value.aiContext, "AI_ONLY_SOURCE")
    }
    func testJSONUpdateKeepsIdentityAndScheduleWithoutShowingAI() async throws {
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(FixtureDotTaskSource.json.utf8)) as? [String: Any])
        var rows = try XCTUnwrap(document["tasks"] as? [[String: Any]])
        rows[0]["startTime"] = "10:00"; rows[0]["endTime"] = "10:30"
        rows[0]["timeZone"] = "Asia/Tokyo"; rows[0]["aiContext"] = "AI_ONLY_SOURCE"
        document["tasks"] = [rows[0]]
        let feed = try DotTaskFeedDecoder.decode(JSONSerialization.data(withJSONObject: document))
        let cache = DotTaskTests.Cache(), source = DotTaskTests.Source()
        source.feed = feed
        let store = DotTaskStore(source: source, cache: cache)
        await store.refresh(); let first = store.snapshot!.tasks[0]
        source.feed = feed; await store.refresh()
        XCTAssertEqual(store.snapshot?.tasks[0].id, first.id)
        XCTAssertEqual(store.snapshot?.tasks[0].aiContext, "AI_ONLY_SOURCE")
        let repository = DotPlannerTaskRepository(imported: { store.snapshot!.tasks }, relay: { [] }, updateRelay: { _ in })
        let tasks = try await repository.fetchTasks()
        XCTAssertFalse(tasks[0].isAllDay)
        XCTAssertFalse(tasks[0].note.contains("AI_ONLY_SOURCE"))
    }
}

@MainActor final class DailyBriefStoreTests: XCTestCase {
    final class Repository: DailyBriefRepository {
        var saved: DailyBrief?
        var response: DailyBrief?
        var failure = false
        var continuation: CheckedContinuation<DailyBrief?, Error>?
        var suspends = false
        func cached(for context: DailyBriefContext) throws -> DailyBrief? { saved }
        func exchange(_ context: DailyBriefContext) async throws -> DailyBrief? {
            if failure { throw CocoaError(.fileReadUnknown) }
            if suspends { return try await withCheckedThrowingContinuation { continuation = $0 } }
            return response
        }
    }
    func context(_ day: String = "2026-10-22", completed: Bool = false) -> DailyBriefContext {
        .init(date: day, timeZone: "Asia/Tokyo", tasks: [
            .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, title: "合成タスク", details: "次の一歩", scheduledAt: nil, completed: completed)
        ], events: [])
    }
    func brief(_ context: DailyBriefContext) -> DailyBrief {
        .init(date: context.date, timeZone: context.timeZone, contextID: context.id, kind: "outlook", text: "合成の見通し", generatedAt: .distantPast)
    }
    func testFingerprintChangesWithCompletionAndIgnoresArrayOrder() {
        let first = context()
        XCTAssertNotEqual(first.id, context(completed: true).id)
        XCTAssertNotEqual(first.id, context("2026-10-23").id)
        let second = DailyBriefContext.Task(id: UUID(), title: "別タスク", details: "", scheduledAt: nil, completed: false)
        let a = DailyBriefContext(date: first.date, timeZone: first.timeZone, tasks: first.tasks + [second], events: [])
        let b = DailyBriefContext(date: first.date, timeZone: first.timeZone, tasks: [second] + first.tasks, events: [])
        XCTAssertEqual(a.id, b.id)
    }
    func testOfflineCacheAndOutdatedCompletion() async {
        let repo = Repository(); repo.saved = brief(context()); repo.failure = true
        let store = DailyBriefStore(repository: repo)
        await store.refresh(context(completed: true))
        XCTAssertEqual(store.brief, repo.saved)
        XCTAssertTrue(store.isOutdated)
        XCTAssertNotNil(store.errorMessage)
    }
    func testPreviousDayIsClearedAndWrongDateIsRejected() async {
        let repo = Repository(); repo.response = brief(context())
        let store = DailyBriefStore(repository: repo)
        await store.refresh(context())
        await store.refresh(context("2026-10-23"))
        XCTAssertNil(store.brief)
        XCTAssertNotNil(store.errorMessage)
    }
    func testLateResponseCannotReplaceNewDate() async {
        let repo = Repository(); repo.suspends = true
        let store = DailyBriefStore(repository: repo)
        let old = Task { await store.refresh(context()) }
        while repo.continuation == nil { await Task.yield() }
        let continuation = repo.continuation
        repo.suspends = false; repo.response = brief(context("2026-10-23"))
        await store.refresh(context("2026-10-23"))
        continuation?.resume(returning: brief(context()))
        await old.value
        XCTAssertEqual(store.brief?.date, "2026-10-23")
    }
}

@MainActor final class DailyBriefAudioTests: XCTestCase {
    func pair(_ id: String = "synthetic-mac") throws -> RelayPairing {
        let data = try JSONSerialization.data(withJSONObject: ["version":1,"endpoint":"https://192.168.1.2:8778",
            "bridgeID":id,"certificateSHA256":String(repeating:"0",count:64),"bearer":String(repeating:"s",count:32),"deviceLabel":"synthetic"])
        return try JSONDecoder().decode(RelayPairing.self, from:data)
    }
    func testAudioVerifiedBeforeReadyAndRetryReusesFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let pairing = try pair(), bytes = Data(repeating:0,count:100)
        let hash = DotDailyBriefRepository.digest(bytes), id = String(repeating:"a",count:64)
        let context = DailyBriefContext(date:"2026-10-22",timeZone:"Asia/Tokyo",tasks:[],events:[])
        var value = DailyBrief(date:context.date,timeZone:context.timeZone,contextID:context.id,kind:"outlook",text:"合成見通し",generatedAt:.distantPast)
        value.briefID = id; value.audio = .init(sha256:hash,byteCount:100,contentType:"audio/wav",duration:1)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let response = try JSONSerialization.data(withJSONObject:["brief":JSONSerialization.jsonObject(with:encoder.encode(value))])
        var fetches = 0, ready = 0
        let repository = DotDailyBriefRepository(directory:folder,pairing:{pairing},exchange:{_,_ in response},audio:{_,_ in fetches += 1; return bytes},ready:{_,_ in
            XCTAssertTrue(FileManager.default.fileExists(atPath:folder.appending(path:"synthetic-mac/audio/"+id+".json").path)); ready += 1
        })
        _ = try await repository.exchange(context); _ = try await repository.exchange(context)
        XCTAssertEqual(fetches,1); XCTAssertEqual(ready,2)
        XCTAssertEqual(try repository.cached(for:context),value)
        // A corrupt local asset must be reacquired, not reported as already downloaded.
        try Data([1]).write(to:folder.appending(path:"synthetic-mac/audio/"+hash+".wav"))
        _ = try await repository.exchange(context); XCTAssertEqual(fetches,2)
    }
    func testCorruptTransferNeverPublishesReady() async throws {
        let folder=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:folder) }
        let pairing=try pair(), context=DailyBriefContext(date:"2026-10-22",timeZone:"Asia/Tokyo",tasks:[],events:[])
        let response = try JSONSerialization.data(withJSONObject:["brief":["date":context.date,"timeZone":context.timeZone,"contextID":context.id,"kind":"outlook","text":"合成","generatedAt":"2026-10-22T00:00:00Z","briefID":String(repeating:"a",count:64),"audio":["sha256":String(repeating:"b",count:64),"byteCount":100,"contentType":"audio/wav","duration":1]]])
        var ready=0
        let repository=DotDailyBriefRepository(directory:folder,pairing:{pairing},exchange:{_,_ in response},audio:{_,_ in Data(repeating:0,count:100)},ready:{_,_ in ready += 1})
        do { _ = try await repository.exchange(context); XCTFail("corrupt audio accepted") } catch {}
        XCTAssertEqual(ready,0); XCTAssertNil(try repository.cached(for:context))
    }
    func testNotificationReservationIsDurableAndUnique() throws {
        let folder=FileManager.default.temporaryDirectory.appending(path:UUID().uuidString)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:folder) }
        let marker=folder.appending(path:"synthetic.notified")
        try DotDailyBriefRepository.reserveNotification(marker)
        XCTAssertThrowsError(try DotDailyBriefRepository.reserveNotification(marker))
    }
}
