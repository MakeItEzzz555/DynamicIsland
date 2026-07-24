import XCTest
@testable import DynamicIsland

@MainActor
final class ExpandedScrollEventRoutingPolicyTests: XCTestCase {
    func testSuppressedExpandedScrollPassesThroughToContent() {
        XCTAssertEqual(
            route(isSuppressed: true, isExpanded: true),
            .passThroughToContent
        )
    }

    func testUnsuppressedExpandedScrollRoutesToIslandGesture() {
        XCTAssertEqual(
            route(isSuppressed: false, isExpanded: true),
            .islandGesture
        )
    }

    func testExpandedSuppressionDoesNotChangeCollapsedRouting() {
        XCTAssertEqual(
            route(isSuppressed: true, isExpanded: false),
            .islandGesture
        )
    }

    func testDisablingSuppressionRestoresExpandedGestureRouting() {
        XCTAssertEqual(
            route(isSuppressed: true, isExpanded: true),
            .passThroughToContent
        )
        XCTAssertEqual(
            route(isSuppressed: false, isExpanded: true),
            .islandGesture
        )
    }

    func testSuppressedRouteIsNeverAnIslandConsumedGesture() {
        XCTAssertNotEqual(
            route(isSuppressed: true, isExpanded: true),
            .islandGesture
        )
    }

    func testDisabledOrNonTrackpadGesturesPassThrough() {
        XCTAssertEqual(
            route(
                isSuppressed: false,
                isExpanded: true,
                gesturesEnabled: false,
                usesTrackpad: true
            ),
            .passThroughToContent
        )
        XCTAssertEqual(
            route(
                isSuppressed: false,
                isExpanded: true,
                gesturesEnabled: true,
                usesTrackpad: false
            ),
            .passThroughToContent
        )
    }

    func testLayoutStoreSuppressionDefaultsFalseAndTogglesIdempotently() {
        let store = IslandLayoutStore()

        XCTAssertFalse(store.isExpandedScrollGestureSuppressed)

        store.setExpandedScrollGestureSuppressed(true)
        XCTAssertTrue(store.isExpandedScrollGestureSuppressed)

        store.setExpandedScrollGestureSuppressed(true)
        XCTAssertTrue(store.isExpandedScrollGestureSuppressed)

        store.setExpandedScrollGestureSuppressed(false)
        XCTAssertFalse(store.isExpandedScrollGestureSuppressed)
    }

    private func route(
        isSuppressed: Bool,
        isExpanded: Bool,
        gesturesEnabled: Bool = true,
        usesTrackpad: Bool = true
    ) -> ExpandedScrollEventRoute {
        ExpandedScrollEventRoutingPolicy.route(
            isSuppressed: isSuppressed,
            isExpanded: isExpanded,
            gesturesEnabled: gesturesEnabled,
            usesTrackpad: usesTrackpad
        )
    }
}
