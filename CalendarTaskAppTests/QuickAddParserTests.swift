import XCTest
@testable import CalendarTaskApp

final class QuickAddParserTests: XCTestCase {
    func testQuickNoteAppendsWithoutReplacingExistingText() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let existing = DailyNote(id: UUID(), date: date, text: "朝のメモ", createdAt: date, updatedAt: date)
        let result = QuickAddResult(type: .note, title: "夜の振り返り", date: date, hasExplicitTime: false)
        let note = result.note(existing: existing, now: date.addingTimeInterval(60))
        XCTAssertEqual(note.text, "朝のメモ\n夜の振り返り")
        XCTAssertEqual(note.id, existing.id)
        XCTAssertEqual(note.createdAt, existing.createdAt)
    }

    func testQuickNoteWithoutExistingTextHasNoLeadingNewline() {
        let result = QuickAddResult(type: .note, title: "メモ", date: .now, hasExplicitTime: false)
        XCTAssertEqual(result.note(existing: nil).text, "メモ")
    }

    func testSelectedTypeAndExplicitPrefix() {
        let parser = QuickAddParser(calendar: calendar)
        XCTAssertEqual(parser.parse("買い物", defaultDate: .now, defaultType: .note).type, .note)
        XCTAssertEqual(parser.parse("予定: 打ち合わせ", defaultDate: .now, defaultType: .note).type, .event)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 9 * 3600) ?? .current
        return value
    }

    func testTomorrowAndTimeAreExtracted() throws {
        let base = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 12)))
        let result = QuickAddParser(calendar: calendar).parse("明日 18:00 病院", defaultDate: base)
        XCTAssertEqual(result.type, .task)
        XCTAssertEqual(result.title, "病院")
        XCTAssertEqual(calendar.component(.day, from: result.date), 17)
        XCTAssertEqual(calendar.component(.hour, from: result.date), 18)
        XCTAssertTrue(result.hasExplicitTime)
    }

    func testEventPrefixAndNumericDateAreExtracted() throws {
        let base = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16)))
        let result = QuickAddParser(calendar: calendar).parse("予定: 8/20 打ち合わせ", defaultDate: base)
        XCTAssertEqual(result.type, .event)
        XCTAssertEqual(result.title, "打ち合わせ")
        XCTAssertEqual(calendar.component(.month, from: result.date), 8)
        XCTAssertEqual(calendar.component(.day, from: result.date), 20)
    }

    func testUnknownTextFallsBackToTaskTitle() throws {
        let base = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 16)))
        let result = QuickAddParser(calendar: calendar).parse("なんとなく買い物する", defaultDate: base)
        XCTAssertEqual(result.type, .task)
        XCTAssertEqual(result.title, "なんとなく買い物する")
        XCTAssertFalse(result.hasExplicitTime)
    }
}

private actor QuickNoteRepository: DailyNoteRepository {
    var notes: [DailyNote]
    let failsToSave: Bool
    init(notes: [DailyNote], failsToSave: Bool = false) {
        self.notes = notes; self.failsToSave = failsToSave
    }
    func fetchNote(for date: Date) async throws -> DailyNote? {
        notes.first { Calendar.current.isDate($0.date, inSameDayAs: date) }
    }
    func saveNote(_ note: DailyNote) async throws {
        if failsToSave { throw CocoaError(.fileWriteUnknown) }
        notes.removeAll { $0.id == note.id }; notes.append(note)
    }
    func deleteNote(id: UUID) async throws { notes.removeAll { $0.id == id } }
}

private actor QuickCompletionRepository: TaskCompletionRepository {
    func fetchCompletions() async throws -> [TaskCompletion] { [] }
    func addCompletion(_ completion: TaskCompletion) async throws {}
    func deleteCompletion(id: UUID) async throws {}
    func deleteCompletions(taskID: UUID) async throws {}
}

@MainActor final class QuickAddSaveTests: XCTestCase {
    func testHomeQuickNoteForAnotherDayKeepsSelectedDayAndAppends() async throws {
        let today = Calendar.current.startOfDay(for: .now)
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        let first = DailyNote(id: UUID(), date: today, text: "今日", createdAt: today, updatedAt: today)
        let second = DailyNote(id: UUID(), date: tomorrow, text: "明日", createdAt: today, updatedAt: today)
        let repository = QuickNoteRepository(notes: [first, second])
        let model = makeHome(repository: repository, today: today)
        await model.load()
        let saved = await model.saveQuickAdd(QuickAddResult(type: .note, title: "追記", date: tomorrow, hasExplicitTime: false))
        XCTAssertTrue(saved)
        XCTAssertEqual(model.memoText, "今日")
        XCTAssertEqual(model.note(for: today)?.id, first.id)
        let note = try await repository.fetchNote(for: tomorrow)
        XCTAssertEqual(note?.text, "明日\n追記")
        XCTAssertEqual(note?.id, second.id)
    }

    func testHomeReportsFailedQuickNoteSave() async {
        let today = Date.now
        let repository = QuickNoteRepository(notes: [], failsToSave: true)
        let model = makeHome(repository: repository, today: today)
        let saved = await model.saveQuickAdd(QuickAddResult(type: .note, title: "保存失敗", date: today, hasExplicitTime: false))
        XCTAssertFalse(saved)
        XCTAssertTrue(model.memoText.isEmpty)
    }

    private func makeHome(repository: QuickNoteRepository, today: Date) -> HomeViewModel {
        HomeViewModel(taskStore: TaskStore(repository: InMemoryTaskRepository(tasks: [])),
                      calendarStore: CalendarStore(repository: InMemoryCalendarRepository(events: [])),
                      dailyNoteStore: DailyNoteStore(repository: repository),
                      taskCompletionStore: TaskCompletionStore(repository: QuickCompletionRepository()),
                      dateProvider: FixedDateProvider(now: today),
                      hapticService: SystemHapticService(isEnabled: { false }))
    }
}
