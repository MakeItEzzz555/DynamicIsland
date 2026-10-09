import AppKit
import XCTest
@testable import DynamicIsland

final class IslandPageScrollGestureTests: XCTestCase {
    private func actions(_ deltas: [CGFloat], momentum: Bool = false) -> [IslandPageScrollGesture.Outcome] {
        var gesture = IslandPageScrollGesture()
        var output: [IslandPageScrollGesture.Outcome] = []
        for (index, delta) in deltas.enumerated() {
            output.append(gesture.update(deltaX: delta, deltaY: 0,
                phase: index == 0 ? .began : .changed, canBegin: true))
        }
        output.append(gesture.update(deltaX: 0, deltaY: 0, phase: .ended, canBegin: true))
        if momentum {
            for _ in 0..<20 {
                output.append(gesture.update(deltaX: -100, deltaY: 0, phase: .momentum, canBegin: true))
            }
            output.append(gesture.update(deltaX: 0, deltaY: 0, phase: .momentumEnded, canBegin: true))
        }
        return output.filter { $0 == .next || $0 == .previous }
    }

    func testShortNormalVeryLongAndTwentyChangesFireOnceInBothDirections() {
        for direction: CGFloat in [-1, 1] {
            let expected: IslandPageScrollGesture.Outcome = direction < 0 ? .next : .previous
            for samples in [[CGFloat(18)], [6, 6, 6, 6], [18, 1_000, 10_000], Array(repeating: CGFloat(20), count: 21)] {
                XCTAssertEqual(actions(samples.map { $0 * direction }), [expected])
            }
        }
    }

    func testMomentumCannotNavigateAfterPhysicalEnd() {
        XCTAssertEqual(actions([-20, -100, -100], momentum: true), [.next])
        XCTAssertEqual(actions([20, 100, 100], momentum: true), [.previous])
        XCTAssertEqual(actions([-5], momentum: true), [], "momentum cannot complete a subthreshold physical swipe")
    }

    func testReversalAndShellMorphCompletionCannotRearmConsumedSequence() {
        var gesture = IslandPageScrollGesture()
        XCTAssertEqual(gesture.update(deltaX: -18, deltaY: 0, phase: .began, canBegin: true), .next)
        for delta: CGFloat in [1_000, -2_000, 3_000, -4_000] {
            XCTAssertEqual(gesture.update(deltaX: delta, deltaY: 0, phase: .changed,
                canBegin: false, inputStillAllowed: false), .consumed)
            XCTAssertEqual(gesture.state, .consumed(.next))
        }
        XCTAssertEqual(gesture.update(deltaX: -100, deltaY: 0, phase: .changed, canBegin: true), .consumed)
    }

    func testTwoDistinctSwipesNavigateImmediatelyWithoutCooldown() {
        for nextDelta: CGFloat in [-18, 18] {
            var gesture = IslandPageScrollGesture()
            XCTAssertEqual(gesture.update(deltaX: -18, deltaY: 0, phase: .began, canBegin: true), .next)
            XCTAssertEqual(gesture.update(deltaX: 0, deltaY: 0, phase: .ended, canBegin: true), .consumed)
            XCTAssertEqual(gesture.update(deltaX: nextDelta, deltaY: 0, phase: .began, canBegin: true),
                nextDelta < 0 ? .next : .previous)
        }
    }

    func testVerticalAndDiagonalSequencesStayWithContent() {
        for delta in [CGSize(width: 2, height: 20), CGSize(width: 20, height: 20), CGSize(width: 20, height: 14)] {
            var gesture = IslandPageScrollGesture()
            XCTAssertEqual(gesture.update(deltaX: delta.width, deltaY: delta.height, phase: .began, canBegin: true), .ignored)
            XCTAssertEqual(gesture.update(deltaX: -100, deltaY: 0, phase: .changed, canBegin: true), .ignored)
            XCTAssertEqual(gesture.state, .content)
        }
    }

    func testBelowThresholdNeverNavigatesAndOrdinaryWheelNeverStartsTracking() {
        XCTAssertEqual(actions([-3, -3, -3]), [])
        var gesture = IslandPageScrollGesture()
        for _ in 0..<20 {
            XCTAssertEqual(gesture.update(deltaX: -100, deltaY: 0, phase: .ordinary, canBegin: true), .ignored)
        }
        XCTAssertEqual(gesture.state, .idle)
        XCTAssertEqual(gesture.update(deltaX: -100, deltaY: 0, phase: .changed, canBegin: true), .ignored,
            "an unobserved beginning cannot steal an existing content sequence")
    }

    func testNativeControlsContentAndEditorKeepTheirEntireSequence() {
        var gesture = IslandPageScrollGesture()
        XCTAssertEqual(gesture.update(deltaX: -30, deltaY: 0, phase: .began, canBegin: false), .ignored)
        XCTAssertEqual(gesture.update(deltaX: -300, deltaY: 0, phase: .changed, canBegin: true), .ignored,
            "moving out of an excluded control does not transfer its sequence")
        XCTAssertEqual(gesture.update(deltaX: -6, deltaY: 0, phase: .began, canBegin: true), .consumed)
        XCTAssertEqual(gesture.update(deltaX: -30, deltaY: 0, phase: .changed,
            canBegin: true, inputStillAllowed: false), .ignored, "entering the editor cancels an uncommitted page")
        XCTAssertEqual(gesture.update(deltaX: -30, deltaY: 0, phase: .changed, canBegin: true), .ignored)
    }

    func testDisabledDirectionPassesToExistingFeatureGesture() {
        var gesture = IslandPageScrollGesture()
        XCTAssertEqual(gesture.update(deltaX: -20, deltaY: 0, phase: .began,
            canBegin: true, leftAllowed: false, rightAllowed: true), .ignored)
        XCTAssertEqual(gesture.update(deltaX: -100, deltaY: 0, phase: .changed, canBegin: true), .ignored)
        XCTAssertEqual(gesture.update(deltaX: 20, deltaY: 0, phase: .began,
            canBegin: true, leftAllowed: false, rightAllowed: true), .previous)
    }

    func testCancellationAndMomentumEndReleaseOwnership() {
        for end: IslandPageScrollGesture.Phase in [.cancelled, .momentumEnded] {
            var gesture = IslandPageScrollGesture()
            XCTAssertEqual(gesture.update(deltaX: -18, deltaY: 0, phase: .began, canBegin: true), .next)
            XCTAssertEqual(gesture.update(deltaX: 0, deltaY: 0, phase: end, canBegin: true), .consumed)
            XCTAssertEqual(gesture.state, .idle)
            XCTAssertEqual(gesture.update(deltaX: 18, deltaY: 0, phase: .began, canBegin: true), .previous)
        }
    }

    func testInvalidDeltasNeverCommitNavigation() {
        for value: CGFloat in [.nan, .infinity, -.infinity] {
            var gesture = IslandPageScrollGesture()
            XCTAssertEqual(gesture.update(deltaX: value, deltaY: 0, phase: .began, canBegin: true), .ignored)
            XCTAssertEqual(gesture.update(deltaX: -100, deltaY: 0, phase: .changed, canBegin: true), .ignored)
        }
    }

    func testNativeEventPhasesDistinguishPhysicalInputMomentumAndOrdinaryScroll() {
        typealias Gesture = IslandPageScrollGesture
        XCTAssertEqual(Gesture.phase(precise: true, physical: .began, momentum: []), .began)
        XCTAssertEqual(Gesture.phase(precise: true, physical: .changed, momentum: []), .changed)
        XCTAssertEqual(Gesture.phase(precise: true, physical: .ended, momentum: []), .ended)
        XCTAssertEqual(Gesture.phase(precise: true, physical: .cancelled, momentum: []), .cancelled)
        for phase: NSEvent.Phase in [.began, .changed] {
            XCTAssertEqual(Gesture.phase(precise: true, physical: [], momentum: phase), .momentum)
        }
        XCTAssertEqual(Gesture.phase(precise: true, physical: [], momentum: .ended), .momentumEnded)
        XCTAssertEqual(Gesture.phase(precise: true, physical: [], momentum: .cancelled), .momentumEnded)
        XCTAssertEqual(Gesture.phase(precise: true, physical: [], momentum: []), .ordinary)
        XCTAssertEqual(Gesture.phase(precise: false, physical: .began, momentum: []), .ordinary)
    }

    func testPhysicalPageDirectionIsIndependentOfNaturalScrolling() {
        for inverted in [false, true] {
            for physical: CGFloat in [-20, 20] {
                let delivered = inverted ? physical : -physical
                let delta = IslandPageScrollGesture.fingerDelta(delivered, invertedFromDevice: inverted)
                XCTAssertEqual(delta, physical)
                var gesture = IslandPageScrollGesture()
                XCTAssertEqual(gesture.update(deltaX: delta, deltaY: 0, phase: .began, canBegin: true),
                    physical < 0 ? .next : .previous)
            }
        }
    }
}
