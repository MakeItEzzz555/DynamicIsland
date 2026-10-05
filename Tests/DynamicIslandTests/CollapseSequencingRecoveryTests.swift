import XCTest
@testable import DynamicIsland

/// P0: collapse must never wait forever for a child-exit acknowledgement.
/// Children exit -> acknowledgement -> shell collapses -> idle.
@MainActor
final class CollapseSequencingRecoveryTests: XCTestCase {
    /// Simulates the overlay (IslandCollapseRequest + layout store) and the
    /// root (ExpandedChildExitTracker) exchanging generations.
    @MainActor private struct Harness {
        var request = IslandCollapseRequest()
        let store = IslandLayoutStore()
        var tracker = ExpandedChildExitTracker()
        var childrenHidden = false
        var collapsed = false
        var pendingAnimation: Int?

        mutating func requestCollapse() {
            // Re-driving while exiting issues a fresh generation (recovery).
            let generation = request.begin()
            store.expandedChildExitGeneration = generation
            store.isExpandedContentExiting = true
        }
        mutating func cancelForExpansion() {
            if request.cancel() { store.isExpandedContentExiting = false; tracker.reset(); childrenHidden = false }
        }
        /// What the root does when it observes the generation/flag.
        mutating func rootObserves() {
            switch tracker.drive(generation: store.expandedChildExitGeneration,
                                 isExiting: store.isExpandedContentExiting, childrenHidden: childrenHidden) {
            case .beginExit: pendingAnimation = tracker.beginAnimation()
            case .acknowledge(let generation): acknowledge(generation)
            case .none: break
            }
        }
        mutating func finishAnimation(token: Int? = nil) {
            guard let token = token ?? pendingAnimation else { return }
            childrenHidden = true
            if let generation = tracker.animationFinished(token: token, currentGeneration: store.expandedChildExitGeneration,
                                                          isExiting: store.isExpandedContentExiting) {
                acknowledge(generation)
            }
        }
        mutating func acknowledge(_ generation: Int) {
            store.acknowledgeExpandedChildExit(generation: generation)
            if store.isExpandedContentExiting, request.commit(store.expandedChildExitAcknowledgement) {
                collapsed = true
                store.isExpandedContentExiting = false
            }
        }
    }

    func testOrdinaryCollapseAcknowledgesAndCommitsOnce() {
        var h = Harness()
        h.requestCollapse(); h.rootObserves()
        XCTAssertFalse(h.collapsed, "shell waits while children exit")
        h.finishAnimation()
        XCTAssertTrue(h.collapsed)
    }

    func testCoalescedCancelAndRecollapseCannotStrandTheShell() {
        // collapse -> exit starts -> expansion cancels -> collapse again, and
        // SwiftUI coalesced the Bool edge so the root saw no new exit start.
        var h = Harness()
        h.requestCollapse(); h.rootObserves()
        let first = h.pendingAnimation
        h.cancelForExpansion()
        h.requestCollapse() // root not re-driven by the Bool (true -> true)
        h.finishAnimation(token: first) // the stale animation from before the cancel
        h.rootObserves() // generation change drives the root
        if !h.collapsed { h.finishAnimation() }
        XCTAssertTrue(h.collapsed, "a newer generation must still reach acknowledgement")
    }

    func testStaleAnimationCompletionNeverAcknowledgesANewerExit() {
        var h = Harness()
        h.requestCollapse(); h.rootObserves()
        let stale = h.pendingAnimation!
        h.cancelForExpansion()
        h.requestCollapse(); h.rootObserves()
        let current = h.pendingAnimation!
        XCTAssertNotEqual(stale, current)
        h.finishAnimation(token: stale)
        h.childrenHidden = false // the stale callback must not count as the new exit
        XCTAssertFalse(h.collapsed, "children of the newer exit are still fading")
        h.finishAnimation(token: current)
        XCTAssertTrue(h.collapsed)
    }

    func testCollapseRequestedWhileChildrenAlreadyHiddenAcknowledgesImmediately() {
        var h = Harness()
        h.childrenHidden = true // e.g. collapse during expansion before reveal, or Reduce Motion
        h.requestCollapse(); h.rootObserves()
        XCTAssertTrue(h.collapsed)
    }

    func testLostAcknowledgementRecoversOnTheNextCollapseRequest() {
        var h = Harness()
        h.requestCollapse(); h.rootObserves()
        // The exit animation's completion is lost (child unmounted mid-transition).
        h.childrenHidden = true
        h.tracker.reset()
        XCTAssertFalse(h.collapsed)
        h.requestCollapse(); h.rootObserves() // Escape / pointer exit again
        XCTAssertTrue(h.collapsed, "a repeated request must re-drive, never be ignored")
    }

    func testRapidCollapseCancelCyclesAlwaysEndCollapsedOrExpanded() {
        for seed in 0..<200 {
            var generator = SystemRandomNumberGenerator()
            _ = seed
            var h = Harness()
            for _ in 0..<12 {
                switch Int.random(in: 0..<4, using: &generator) {
                case 0: h.requestCollapse(); if Bool.random() { h.rootObserves() }
                case 1: h.cancelForExpansion()
                case 2: h.finishAnimation()
                default: h.rootObserves()
                }
                if h.collapsed { break }
            }
            // Settle: whatever happened, a final request + observation + completion terminates.
            if !h.collapsed {
                if !h.store.isExpandedContentExiting { h.requestCollapse() }
                h.rootObserves(); h.finishAnimation(); h.rootObserves()
            }
            XCTAssertTrue(h.collapsed, "seed \(seed) left the shell waiting")
        }
    }

    func testReduceMotionNoAnimationPathAcknowledgesInTheSameTurn() {
        var tracker = ExpandedChildExitTracker()
        XCTAssertEqual(tracker.drive(generation: 3, isExiting: true, childrenHidden: false), .beginExit)
        let token = tracker.beginAnimation()
        // nil animation: completion runs immediately
        XCTAssertEqual(tracker.animationFinished(token: token, currentGeneration: 3, isExiting: true), 3)
        XCTAssertEqual(tracker.drive(generation: 3, isExiting: false, childrenHidden: true), .none)
    }

    func testCommittedCollapseEndsTheExitPhaseRegardlessOfLaterMorphs() {
        // Root cause of the "must pkill" hang: the exit flag was cleared only by a
        // delayed morph-generation-gated block; a collapsed live-activity morph
        // superseded it, leaving the collapsed pill unhittable forever.
        XCTAssertTrue(IslandCollapseRequest.exitPhaseEnds(at: .collapsed))
        XCTAssertTrue(IslandCollapseRequest.exitPhaseEnds(at: .expanded))
    }
}

/// Resume -> collapse regression (2026-10-05). After a session Resume the
/// expanded content's `withAnimation` completion was observed to never fire
/// (95 of 96 packaged exits), so the root acknowledges from an isolated exit
/// clock animated in its own transaction, plus container unmount. These model
/// the root's three completion sources against overlay generations.
@MainActor
final class ResumedSessionCollapseTests: XCTestCase {
    @MainActor private struct Root {
        let store = IslandLayoutStore()
        var request = IslandCollapseRequest()
        var tracker = ExpandedChildExitTracker()
        var contentVisible = true
        var acknowledged: [Int] = []
        var token: Int?

        mutating func collapse() {
            store.expandedChildExitGeneration = request.begin()
            store.isExpandedContentExiting = true
            drive()
        }
        mutating func expand() {
            if request.cancel() { store.isExpandedContentExiting = false; tracker.reset(); contentVisible = true }
        }
        mutating func drive() {
            switch tracker.drive(generation: store.expandedChildExitGeneration,
                                 isExiting: store.isExpandedContentExiting, childrenHidden: !contentVisible) {
            case .beginExit: token = tracker.beginAnimation(); contentVisible = false
            case .acknowledge(let generation): acknowledged.append(generation)
            case .none: break
            }
        }
        /// Any of: exit clock completion, content completion, container unmount.
        mutating func completion(_ token: Int?) {
            guard let token, tracker.exitInFlight else { return }
            if let generation = tracker.animationFinished(token: token, currentGeneration: store.expandedChildExitGeneration,
                                                          isExiting: store.isExpandedContentExiting) {
                acknowledged.append(generation)
            }
        }
        mutating func commitIfAcknowledged() -> Bool {
            guard let last = acknowledged.last, request.isPending, last == request.generation else { return false }
            store.isExpandedContentExiting = false
            tracker.reset()
            return true
        }
    }

    func testResumeThenCollapseAcknowledgesFromTheClockWhenContentCompletionIsLost() {
        var root = Root()
        root.collapse()
        root.completion(root.token) // exit clock; the content completion never arrives
        XCTAssertTrue(root.commitIfAcknowledged())
    }

    func testVisualClockAlwaysCreatesANewAnimationEdgeAcrossRapidCycles() {
        var clock = 0.0
        for cycle in 0..<200 {
            let next = ExpandedChildExitVisualClock.next(after: clock)
            XCTAssertNotEqual(next, clock, "cycle \(cycle) must own a real animatable edge")
            clock = next
        }
    }

    func testDuplicateCompletionSourcesAcknowledgeExactlyOnce() {
        var root = Root()
        root.collapse()
        let token = root.token
        root.completion(token)      // clock
        root.completion(token)      // late content completion
        root.completion(token)      // container unmount
        XCTAssertEqual(root.acknowledged.count, 1)
        XCTAssertTrue(root.commitIfAcknowledged())
    }

    func testResumeCollapseExpandAndRepeatNeverLeavesAStuckGeneration() {
        var root = Root()
        for cycle in 0..<200 {
            root.collapse()
            let token = root.token
            if cycle % 3 == 0 { root.expand(); root.completion(token); XCTAssertFalse(root.commitIfAcknowledged()); continue }
            root.completion(token)
            XCTAssertTrue(root.commitIfAcknowledged(), "cycle \(cycle)")
            root.contentVisible = true
        }
    }

    func testProviderOrFeedPublicationDuringCollapseOnlyRedrivesTheCurrentGeneration() {
        var root = Root()
        root.collapse()
        let token = root.token
        // Live session/Feed updates re-enter the root while the exit runs and a
        // repeated collapse request issues a newer generation.
        root.drive(); root.drive()
        root.store.expandedChildExitGeneration = root.request.begin()
        root.drive()
        root.completion(token)
        XCTAssertEqual(root.acknowledged, [root.request.generation], "stale generations never block the current one")
        XCTAssertTrue(root.commitIfAcknowledged())
    }

    func testStaleExitTokensFromAnInterruptedExitAreIgnored() {
        var root = Root()
        root.collapse()
        let stale = root.token
        root.expand()
        root.collapse()
        root.completion(stale)
        XCTAssertTrue(root.acknowledged.isEmpty)
        root.completion(root.token)
        XCTAssertTrue(root.commitIfAcknowledged())
    }

    func testChildUnmountBeforeCompletionStillAcknowledges() {
        var root = Root()
        root.collapse()
        // The expanded container disappears (e.g. its subtree is replaced
        // after Resume) before any animation callback.
        root.completion(root.tracker.animationToken)
        XCTAssertTrue(root.commitIfAcknowledged())
    }

    func testRapidCollapseExpandAlternationEndsInteractive() {
        var root = Root()
        for _ in 0..<50 { root.collapse(); root.expand() }
        XCTAssertFalse(root.store.isExpandedContentExiting)
        root.collapse()
        root.completion(root.token)
        XCTAssertTrue(root.commitIfAcknowledged())
        XCTAssertFalse(root.store.isExpandedContentExiting, "collapsed island is interactive")
    }
}
