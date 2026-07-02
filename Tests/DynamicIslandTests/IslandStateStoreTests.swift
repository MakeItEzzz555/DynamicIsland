import XCTest
@testable import DynamicIsland

@MainActor
final class IslandStateStoreTests: XCTestCase {
    func testToggleExpandedCyclesThroughExpectedStates() {
        let store = IslandStateStore()
        XCTAssertEqual(store.state, .collapsed)

        store.toggleExpanded()
        XCTAssertEqual(store.state, .expanded)

        store.toggleExpanded()
        XCTAssertEqual(store.state, .pinned)

        store.toggleExpanded()
        XCTAssertEqual(store.state, .collapsed)
    }

    func testDragStateReturnsToExpanded() {
        let store = IslandStateStore()

        store.dragEntered()
        XCTAssertEqual(store.state, .dragReceiving)

        store.dragEnded()
        XCTAssertEqual(store.state, .expanded)
    }

    func testPinnedIgnoresOutsideClick() {
        let store = IslandStateStore()

        store.pin()
        store.collapseFromOutsideClick()

        XCTAssertEqual(store.state, .pinned)
    }
}
