import XCTest
@testable import DynamicIsland

final class ClipboardHistoryPresentationStateTests: XCTestCase {
    func testOpenMountsHiddenBeforeReveal() {
        var state = ClipboardHistoryPresentationState()
        state.open()

        XCTAssertTrue(state.isRequested)
        XCTAssertTrue(state.isMounted)
        XCTAssertFalse(state.isVisible)
        XCTAssertFalse(state.isRemoving)
    }

    func testRevealMakesMountedContentVisible() {
        var state = ClipboardHistoryPresentationState()
        let generation = state.open()

        XCTAssertTrue(state.reveal(generation: generation))
        XCTAssertTrue(state.isMounted)
        XCTAssertTrue(state.isVisible)
    }

    func testAnimatedCloseKeepsContentMountedUntilCompletion() {
        var state = ClipboardHistoryPresentationState()
        let openGeneration = state.open()
        state.reveal(generation: openGeneration)

        let closeGeneration = state.beginAnimatedClose()

        XCTAssertNotNil(closeGeneration)
        XCTAssertFalse(state.isRequested)
        XCTAssertTrue(state.isMounted)
        XCTAssertFalse(state.isVisible)
        XCTAssertTrue(state.isRemoving)
    }

    func testRepeatedAnimatedCloseDuringRemovalIsIdempotent() {
        var state = ClipboardHistoryPresentationState()
        state.open()
        let closeGeneration = state.beginAnimatedClose()!

        XCTAssertNil(state.beginAnimatedClose())
        XCTAssertEqual(state.generation, closeGeneration)
        XCTAssertTrue(state.isMounted)
        XCTAssertTrue(state.isRemoving)
    }

    func testCloseCompletionUnmountsContent() {
        var state = ClipboardHistoryPresentationState()
        state.open()
        let closeGeneration = state.beginAnimatedClose()!

        XCTAssertTrue(state.completeAnimatedClose(generation: closeGeneration))
        XCTAssertFalse(state.isMounted)
        XCTAssertFalse(state.isRemoving)
    }

    func testStaleRevealCannotReopenAfterClose() {
        var state = ClipboardHistoryPresentationState()
        let openGeneration = state.open()
        state.beginAnimatedClose()

        XCTAssertFalse(state.reveal(generation: openGeneration))
        XCTAssertFalse(state.isVisible)
    }

    func testStaleUnmountCannotRemoveReopenedClipboard() {
        var state = ClipboardHistoryPresentationState()
        state.open()
        let closeGeneration = state.beginAnimatedClose()!
        let reopenedGeneration = state.open()
        state.reveal(generation: reopenedGeneration)

        XCTAssertFalse(state.completeAnimatedClose(generation: closeGeneration))
        XCTAssertTrue(state.isRequested)
        XCTAssertTrue(state.isMounted)
        XCTAssertTrue(state.isVisible)
    }

    func testImmediateCloseClearsAllPresentationState() {
        var state = ClipboardHistoryPresentationState()
        let generation = state.open()
        state.reveal(generation: generation)
        state.closeImmediately()

        XCTAssertFalse(state.isRequested)
        XCTAssertFalse(state.isMounted)
        XCTAssertFalse(state.isVisible)
        XCTAssertFalse(state.isRemoving)
    }

    func testRapidOpenCloseOpenEndsRequestedMountedAndVisible() {
        var state = ClipboardHistoryPresentationState()
        state.open()
        let staleCloseGeneration = state.beginAnimatedClose()!
        let finalGeneration = state.open()

        XCTAssertFalse(state.completeAnimatedClose(generation: staleCloseGeneration))
        XCTAssertTrue(state.reveal(generation: finalGeneration))
        XCTAssertTrue(state.isRequested)
        XCTAssertTrue(state.isMounted)
        XCTAssertTrue(state.isVisible)
        XCTAssertFalse(state.isRemoving)
    }
}
