import XCTest
@testable import CalendarTaskApp

final class ProjectPlanningTests: XCTestCase {
    func testHierarchyCodesAndCollapseKeepSiblingNumbers() {
        let day = Date(timeIntervalSince1970: 0)
        let parent = PlanningDraftItem(title: "工程", start: day, end: day)
        let child = PlanningDraftItem(parentID: parent.id, title: "子工程", start: day, end: day)
        let grandchild = PlanningDraftItem(parentID: child.id, title: "作業", start: day, end: day)
        let sibling = PlanningDraftItem(title: "公開", start: day, end: day)
        let items = [parent, child, grandchild, sibling]
        let rows = PlanningDraftRow.flatten(items)
        XCTAssertEqual(rows.map(\.code), ["1", "1.1", "1.1.1", "2"])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2, 0])
        XCTAssertEqual(rows.map(\.hasChildren), [true, true, false, false])
        let collapsed = PlanningDraftRow.flatten(items, collapsed: [parent.id])
        XCTAssertEqual(collapsed.map(\.item.id), [parent.id, sibling.id])
        XCTAssertEqual(collapsed.map(\.code), ["1", "2"])
    }

    func testEmptyAndDisconnectedDraftsDoNotInventParents() {
        XCTAssertTrue(PlanningDraftRow.flatten([]).isEmpty)
        let day = Date(timeIntervalSince1970: 0)
        let orphan = PlanningDraftItem(parentID: UUID(), title: "未接続", start: day, end: day)
        XCTAssertTrue(PlanningDraftRow.flatten([orphan]).isEmpty)
    }
}
