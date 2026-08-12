import XCTest
@testable import CalendarTaskApp

final class CalendarExtensionTests: XCTestCase {
    func testMonthDatesIncludesEveryDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 12)))
        XCTAssertEqual(calendar.monthDates(containing: date).compactMap { $0 }.count, 28)
    }
}
