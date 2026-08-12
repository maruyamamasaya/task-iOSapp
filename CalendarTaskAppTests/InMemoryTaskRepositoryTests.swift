import XCTest
@testable import CalendarTaskApp

final class InMemoryTaskRepositoryTests: XCTestCase {
    func testFetchReturnsInjectedTasks() async throws {
        let now = Date()
        let expected = SampleData.tasks(now: now)
        let repository = InMemoryTaskRepository(tasks: expected)
        let result = try await repository.fetchTasks()
        XCTAssertEqual(result, expected)
    }
}
