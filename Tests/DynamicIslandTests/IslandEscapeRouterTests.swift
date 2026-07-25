import Combine
import XCTest
@testable import DynamicIsland

final class IslandEscapeRouterTests: XCTestCase {
    @MainActor
    func testNoPresentationReturnsFalse() {
        let router = IslandEscapeRouter()

        XCTAssertFalse(router.requestDismissTopmost())
        XCTAssertEqual(router.dismissalRequestGeneration, 0)
    }

    @MainActor
    func testClipboardRegistrationHandlesDismissalRequest() {
        let router = IslandEscapeRouter()
        router.setTopmostPresentation(.clipboardHistory)

        XCTAssertTrue(router.requestDismissTopmost())
    }

    @MainActor
    func testHandledRequestIncrementsDismissalGeneration() {
        let router = IslandEscapeRouter()
        router.setTopmostPresentation(.clipboardHistory)

        XCTAssertTrue(router.requestDismissTopmost())
        XCTAssertEqual(router.dismissalRequestGeneration, 1)
    }

    @MainActor
    func testRepeatedHandledRequestsIncrementDeterministically() {
        let router = IslandEscapeRouter()
        router.setTopmostPresentation(.clipboardHistory)

        XCTAssertTrue(router.requestDismissTopmost())
        XCTAssertEqual(router.dismissalRequestGeneration, 1)
        XCTAssertTrue(router.requestDismissTopmost())
        XCTAssertEqual(router.dismissalRequestGeneration, 2)
    }

    @MainActor
    func testClearingClipboardRegistrationRestoresFalse() {
        let router = IslandEscapeRouter()
        router.setTopmostPresentation(.clipboardHistory)
        router.setTopmostPresentation(nil)

        XCTAssertFalse(router.requestDismissTopmost())
    }

    @MainActor
    func testRegistrationIsIdempotent() {
        let router = IslandEscapeRouter()
        var emissions: [IslandOverlayPresentation?] = []
        let cancellable = router.$topmostPresentation
            .dropFirst()
            .sink { emissions.append($0) }

        router.setTopmostPresentation(.clipboardHistory)
        router.setTopmostPresentation(.clipboardHistory)

        XCTAssertEqual(router.topmostPresentation, .clipboardHistory)
        XCTAssertEqual(emissions, [.clipboardHistory])
        withExtendedLifetime(cancellable) {}
    }

    func testExpandedWithClipboardRoutesToDismissPresentation() {
        XCTAssertEqual(
            IslandEscapeRoutingPolicy.route(
                islandState: .expanded,
                topmostPresentation: .clipboardHistory
            ),
            .dismissPresentation
        )
    }

    func testExpandedWithoutPresentationRoutesToCollapseIsland() {
        XCTAssertEqual(
            IslandEscapeRoutingPolicy.route(
                islandState: .expanded,
                topmostPresentation: nil
            ),
            .collapseIsland
        )
    }

    func testCollapsedStateRoutesToPassThrough() {
        XCTAssertEqual(
            IslandEscapeRoutingPolicy.route(
                islandState: .collapsed,
                topmostPresentation: .clipboardHistory
            ),
            .passThrough
        )
    }

    func testClipboardRemainsTopmostThroughoutMountedRemovalState() {
        var state = ClipboardHistoryPresentationState()
        let openGeneration = state.open()
        XCTAssertEqual(state.topmostOverlayPresentation, .clipboardHistory)

        XCTAssertTrue(state.reveal(generation: openGeneration))
        XCTAssertEqual(state.topmostOverlayPresentation, .clipboardHistory)

        let closeGeneration = state.beginAnimatedClose()
        XCTAssertNotNil(closeGeneration)
        XCTAssertTrue(state.isMounted)
        XCTAssertTrue(state.isRemoving)
        XCTAssertEqual(state.topmostOverlayPresentation, .clipboardHistory)

        XCTAssertTrue(state.completeAnimatedClose(generation: closeGeneration!))
        XCTAssertNil(state.topmostOverlayPresentation)
    }
}
