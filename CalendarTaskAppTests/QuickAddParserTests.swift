import XCTest
@testable import CalendarTaskApp

final class QuickAddParserTests: XCTestCase {
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
