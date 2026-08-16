import XCTest
@testable import CalendarTaskApp

final class CalendarExtensionTests: XCTestCase {
    func testMonthDatesIncludesEveryDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 2, day: 12)))
        XCTAssertEqual(calendar.monthDates(containing: date).compactMap { $0 }.count, 28)
    }

    func testMondayWeekAcrossMonthAndYearBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let newYear = try XCTUnwrap(calendar.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 12)))
        let dates = calendar.mondayWeekDates(containing: newYear)
        XCTAssertEqual(dates.count, 7)
        XCTAssertEqual(calendar.component(.weekday, from: dates[0]), 2)
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: dates[0]), DateComponents(year: 2026, month: 12, day: 28))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: dates[6]), DateComponents(year: 2027, month: 1, day: 3))
    }

    func testMondayWeekIncludesLeapDayWithoutChangingTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let leapDay = try XCTUnwrap(calendar.date(from: DateComponents(year: 2024, month: 2, day: 29, hour: 23)))
        let dates = calendar.mondayWeekDates(containing: leapDay)
        XCTAssertTrue(dates.contains { calendar.component(.month, from: $0) == 2 && calendar.component(.day, from: $0) == 29 })
        XCTAssertTrue(dates.allSatisfy { calendar.component(.hour, from: $0) == 0 })
    }

    func testSundayWeekSettingChangesGridBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!; calendar.firstWeekday = 1
        let wednesday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 19)))
        let dates = calendar.weekDates(containing: wednesday)
        XCTAssertEqual(calendar.component(.weekday, from: dates[0]), 1)
        XCTAssertEqual(calendar.component(.day, from: dates[0]), 16)
        XCTAssertEqual(calendar.component(.day, from: dates[6]), 22)
    }
}
