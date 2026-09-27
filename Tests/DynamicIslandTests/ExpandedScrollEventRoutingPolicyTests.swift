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

    func testContentScrollHitPassesThroughWhileExpanded() {
        XCTAssertEqual(
            route(
                isSuppressed: false,
                isExpanded: true,
                contentScrollHit: true
            ),
            .passThroughToContent
        )
    }

    func testLatchedContentScrollSequenceStaysWithContentOutsideRegion() {
        XCTAssertEqual(
            route(
                isSuppressed: false,
                isExpanded: true,
                contentScrollHit: false,
                contentScrollSequenceActive: true
            ),
            .passThroughToContent
        )
    }

    func testContentRegionDoesNotOverrideCollapsedIslandGestures() {
        XCTAssertEqual(
            route(
                isSuppressed: false,
                isExpanded: false,
                contentScrollHit: true,
                contentScrollSequenceActive: true
            ),
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

    func testLayoutStoreRegistersAndClearsExpandedContentScrollRegion() {
        let store = IslandLayoutStore()
        XCTAssertEqual(store.expandedContentScrollRegion, .zero)

        store.setExpandedContentScrollRegion(CGRect(x: 11.2, y: 19.8, width: 310.4, height: 121.1))
        XCTAssertEqual(store.expandedContentScrollRegion, CGRect(x: 11, y: 20, width: 311, height: 121))

        store.setExpandedContentScrollRegion(.zero)
        XCTAssertEqual(store.expandedContentScrollRegion, .zero)
    }

    private func route(
        isSuppressed: Bool,
        isExpanded: Bool,
        gesturesEnabled: Bool = true,
        usesTrackpad: Bool = true,
        contentScrollHit: Bool = false,
        contentScrollSequenceActive: Bool = false
    ) -> ExpandedScrollEventRoute {
        ExpandedScrollEventRoutingPolicy.route(
            isSuppressed: isSuppressed,
            isExpanded: isExpanded,
            gesturesEnabled: gesturesEnabled,
            usesTrackpad: usesTrackpad,
            contentScrollHit: contentScrollHit,
            contentScrollSequenceActive: contentScrollSequenceActive
        )
    }
}
