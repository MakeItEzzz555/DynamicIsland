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
        XCTAssertEqual(store.state, .collapsed)
    }

    func testOutsideClickCollapsesExpandedState() {
        let store = IslandStateStore()

        store.toggleExpanded()
        XCTAssertEqual(store.state, .expanded)

        store.collapseFromOutsideClick()

        XCTAssertEqual(store.state, .collapsed)
    }

    func testExpandSetsExpandedWithoutAddingPresentationStates() {
        let store = IslandStateStore()

        store.expand()

        XCTAssertEqual(store.state, .expanded)
    }
}
