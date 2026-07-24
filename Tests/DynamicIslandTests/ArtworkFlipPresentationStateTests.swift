import AppKit
import XCTest
@testable import DynamicIsland

final class ArtworkFlipPresentationStateTests: XCTestCase {
    func testNextRequestKeepsOldArtworkUntilMidpoint() {
        let old = snapshot("old", fingerprint: "old")
        let new = snapshot("new", fingerprint: "new")
        let requestID = UUID()
        var state = ArtworkFlipPresentationState(initial: old)

        let start = state.receive(
            new,
            direction: .next,
            requestID: requestID,
            shouldAnimate: true
        )

        XCTAssertEqual(start, .firstHalfStarted(generation: 1, direction: .next))
        XCTAssertEqual(state.phase, .firstHalf)
        XCTAssertEqual(state.displayed, old)
        XCTAssertEqual(state.pending, new)

        XCTAssertEqual(state.commitMidpoint(generation: 1), .midpointCommitted(requestID: requestID))
        XCTAssertEqual(state.phase, .secondHalf)
        XCTAssertEqual(state.displayed, new)

        XCTAssertEqual(state.complete(generation: 1), .transitionCompleted)
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.displayed, new)
    }

    func testPreviousRequestMirrorsDirection() {
        var state = ArtworkFlipPresentationState(initial: snapshot("old", fingerprint: "old"))

        let effect = state.receive(
            snapshot("new", fingerprint: "new"),
            direction: .previous,
            requestID: UUID(),
            shouldAnimate: true
        )

        XCTAssertEqual(effect, .firstHalfStarted(generation: 1, direction: .previous))
        XCTAssertEqual(state.direction, .previous)
    }

    func testReceivingRawArtworkDoesNotDisplayItDuringFirstHalf() {
        let old = snapshot("old", fingerprint: "old")
        let incoming = snapshot("incoming", fingerprint: "incoming")
        var state = ArtworkFlipPresentationState(initial: old)

        _ = state.receive(
            incoming,
            direction: .next,
            requestID: UUID(),
            shouldAnimate: true
        )

        XCTAssertEqual(state.displayed, old)
        XCTAssertEqual(state.pending, incoming)
    }

    func testUpdateDuringFirstHalfQueuesLatestWithoutChangingDisplayedArtwork() {
        let old = snapshot("old", fingerprint: "old")
        let first = snapshot("first", fingerprint: "first")
        let queued = snapshot("queued", fingerprint: "queued")
        var state = ArtworkFlipPresentationState(initial: old)
        _ = state.receive(first, direction: .next, requestID: UUID(), shouldAnimate: true)

        let effect = state.receive(queued, direction: .next, requestID: UUID(), shouldAnimate: true)

        XCTAssertEqual(effect, .queued)
        XCTAssertEqual(state.displayed, old)
        XCTAssertEqual(state.pending, first)
        XCTAssertEqual(state.queuedSnapshot, queued)
    }

    func testUpdateDuringSecondHalfQueuesWithoutReplacingMidpointArtwork() {
        let old = snapshot("old", fingerprint: "old")
        let midpoint = snapshot("midpoint", fingerprint: "midpoint")
        let queued = snapshot("queued", fingerprint: "queued")
        var state = ArtworkFlipPresentationState(initial: old)
        _ = state.receive(midpoint, direction: .next, requestID: UUID(), shouldAnimate: true)
        _ = state.commitMidpoint(generation: 1)

        let effect = state.receive(queued, direction: nil, requestID: nil, shouldAnimate: false)

        XCTAssertEqual(effect, .queued)
        XCTAssertEqual(state.displayed, midpoint)
        XCTAssertEqual(state.queuedSnapshot, queued)
    }

    func testStaleGenerationCannotModifyNewerTransition() {
        let old = snapshot("old", fingerprint: "old")
        let first = snapshot("first", fingerprint: "first")
        let second = snapshot("second", fingerprint: "second")
        var state = ArtworkFlipPresentationState(initial: old)
        _ = state.receive(first, direction: .next, requestID: UUID(), shouldAnimate: true)
        _ = state.receive(second, direction: .next, requestID: UUID(), shouldAnimate: true)
        _ = state.commitMidpoint(generation: 1)

        XCTAssertEqual(
            state.complete(generation: 1),
            .firstHalfStarted(generation: 2, direction: .next)
        )
        XCTAssertEqual(state.displayed, first)
        XCTAssertEqual(state.pending, second)

        XCTAssertEqual(state.commitMidpoint(generation: 1), .staleTransitionDiscarded)
        XCTAssertEqual(state.displayed, first)
        XCTAssertEqual(state.pending, second)
    }

    func testSameFingerprintDoesNotAnimate() {
        let old = snapshot("old", fingerprint: "same")
        let equivalent = snapshot("new identity", fingerprint: "same")
        let requestID = UUID()
        var state = ArtworkFlipPresentationState(initial: old)

        let effect = state.receive(
            equivalent,
            direction: .next,
            requestID: requestID,
            shouldAnimate: true
        )

        XCTAssertEqual(effect, .displayedDirectly(requestID: requestID))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.displayed, equivalent)
    }

    func testInitialArtworkDisplaysImmediatelyWithoutFlip() {
        let initial = snapshot("initial", fingerprint: "initial")
        var state = ArtworkFlipPresentationState()

        let effect = state.receive(
            initial,
            direction: nil,
            requestID: nil,
            shouldAnimate: false
        )

        XCTAssertEqual(effect, .displayedDirectly(requestID: nil))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.displayed, initial)
    }

    func testNilToImageSwapsOnlyAtMidpoint() {
        let placeholder = snapshot("placeholder", fingerprint: "placeholder", hasImage: false)
        let image = snapshot("image", fingerprint: "image")
        var state = ArtworkFlipPresentationState(initial: placeholder)
        _ = state.receive(image, direction: .next, requestID: UUID(), shouldAnimate: true)

        XCTAssertNil(state.displayed?.image)
        XCTAssertNotNil(state.pending?.image)

        _ = state.commitMidpoint(generation: 1)

        XCTAssertNotNil(state.displayed?.image)
    }

    func testImageToPlaceholderDoesNotLeakPlaceholderBeforeMidpoint() {
        let image = snapshot("image", fingerprint: "image")
        let placeholder = snapshot("placeholder", fingerprint: "placeholder", hasImage: false)
        var state = ArtworkFlipPresentationState(initial: image)
        _ = state.receive(placeholder, direction: .next, requestID: UUID(), shouldAnimate: true)

        XCTAssertNotNil(state.displayed?.image)
        XCTAssertNil(state.pending?.image)

        _ = state.commitMidpoint(generation: 1)

        XCTAssertNil(state.displayed?.image)
    }

    func testNoRequestWhileIdleUpdatesDirectly() {
        let incoming = snapshot("incoming", fingerprint: "incoming")
        var state = ArtworkFlipPresentationState(initial: snapshot("old", fingerprint: "old"))

        let effect = state.receive(
            incoming,
            direction: nil,
            requestID: nil,
            shouldAnimate: false
        )

        XCTAssertEqual(effect, .displayedDirectly(requestID: nil))
        XCTAssertEqual(state.displayed, incoming)
        XCTAssertEqual(state.phase, .idle)
    }

    func testExpiredRequestWhileIdleUpdatesDirectlyAndCanBeConsumed() {
        let incoming = snapshot("incoming", fingerprint: "incoming")
        let requestID = UUID()
        var state = ArtworkFlipPresentationState(initial: snapshot("old", fingerprint: "old"))

        let effect = state.receive(
            incoming,
            direction: nil,
            requestID: requestID,
            shouldAnimate: false
        )

        XCTAssertEqual(effect, .displayedDirectly(requestID: requestID))
        XCTAssertEqual(state.displayed, incoming)
        XCTAssertEqual(state.phase, .idle)
    }

    func testReduceMotionPerformsImmediateDirectHandoff() {
        let incoming = snapshot("incoming", fingerprint: "incoming")
        let requestID = UUID()
        var state = ArtworkFlipPresentationState(initial: snapshot("old", fingerprint: "old"))

        let effect = state.receive(
            incoming,
            direction: .next,
            requestID: requestID,
            shouldAnimate: false
        )

        XCTAssertEqual(effect, .displayedDirectly(requestID: requestID))
        XCTAssertEqual(state.displayed, incoming)
        XCTAssertEqual(state.phase, .idle)
    }

    func testNoRequestUpdateDuringActiveFlipIsQueued() {
        let old = snapshot("old", fingerprint: "old")
        let first = snapshot("first", fingerprint: "first")
        let queued = snapshot("queued", fingerprint: "queued")
        var state = ArtworkFlipPresentationState(initial: old)
        _ = state.receive(first, direction: .next, requestID: UUID(), shouldAnimate: true)

        let effect = state.receive(
            queued,
            direction: nil,
            requestID: nil,
            shouldAnimate: false
        )

        XCTAssertEqual(effect, .queued)
        XCTAssertEqual(state.displayed, old)
        XCTAssertEqual(state.queuedSnapshot, queued)
    }

    func testBothPlaceholdersDoNotRunMeaninglessFlip() {
        let old = snapshot("old placeholder", fingerprint: "placeholder", hasImage: false)
        let new = snapshot("new placeholder", fingerprint: "another-placeholder", hasImage: false)
        let requestID = UUID()
        var state = ArtworkFlipPresentationState(initial: old)

        let effect = state.receive(
            new,
            direction: .next,
            requestID: requestID,
            shouldAnimate: true
        )

        XCTAssertEqual(effect, .displayedDirectly(requestID: requestID))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(state.displayed, new)
    }

    private func snapshot(
        _ identity: String,
        fingerprint: String,
        hasImage: Bool = true
    ) -> ArtworkPresentationSnapshot {
        ArtworkPresentationSnapshot(
            image: hasImage ? NSImage(size: CGSize(width: 10, height: 10)) : nil,
            identity: identity,
            fingerprint: fingerprint
        )
    }
}
