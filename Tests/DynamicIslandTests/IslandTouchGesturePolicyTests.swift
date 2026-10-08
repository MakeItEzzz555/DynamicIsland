import XCTest
@testable import DynamicIsland

final class IslandTouchGesturePolicyTests: XCTestCase {
    private func contacts(_ x: CGFloat = 0, _ y: CGFloat = 0, ids: [Int] = [1, 2, 3], device: Int = 1) -> [IslandIndirectTouch] {
        ids.map { IslandIndirectTouch(identity: $0, device: device,
            normalizedPosition: CGPoint(x: 0.45 + x, y: 0.5 + y)) }
    }

    func testLeftAndRightUsePhysicalNormalizedDirection() {
        for (delta, expected) in [(CGFloat(-0.09), IslandTouchPageAction.next), (CGFloat(0.09), .previous)] {
            var policy = IslandTouchGesturePolicy()
            XCTAssertNil(policy.update(contacts: contacts(), phase: .began, canBegin: true))
            XCTAssertEqual(policy.update(contacts: contacts(delta), phase: .moved, canBegin: true), expected)
        }
    }

    func testNormalizedThresholdAndDirectionLockNoise() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.01, 0.01), phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.02, 0.005), phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.079, 0.02), phase: .moved, canBegin: true))
        XCTAssertEqual(policy.update(contacts: contacts(-0.081, 0.02), phase: .moved, canBegin: true), .next)
    }

    func testVerticalAndDiagonalStartCannotBecomeHorizontalPaging() {
        for first in [CGPoint(x: 0.005, y: 0.02), CGPoint(x: 0.025, y: 0.02)] {
            var policy = IslandTouchGesturePolicy()
            policy.update(contacts: contacts(), phase: .began, canBegin: true)
            XCTAssertNil(policy.update(contacts: contacts(first.x, first.y), phase: .moved, canBegin: true))
            XCTAssertNil(policy.update(contacts: contacts(0.2), phase: .moved, canBegin: true))
        }
    }

    func testHorizontalDominanceMustExceedOneAndHalf() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(0.03, 0.02), phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(0.2), phase: .moved, canBegin: true))
    }

    func testExactlyOneActionUntilEveryFingerLifts() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1), phase: .moved, canBegin: true), .next)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(ids: [1]), phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(0.1, ids: [1, 4, 5]), phase: .began, canBegin: true))
        XCTAssertTrue(policy.reservesIslandScroll)
        policy.update(contacts: [], phase: .ended, canBegin: true)
        XCTAssertFalse(policy.reservesIslandScroll)
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(0.1), phase: .moved, canBegin: true), .previous)
    }

    func testIncrementalFingerArrivalCanAssembleThreeContacts() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(ids: [1]), phase: .began, canBegin: true)
        policy.update(contacts: contacts(ids: [1, 2]), phase: .began, canBegin: true)
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1), phase: .moved, canBegin: true), .next)
    }

    func testExistingOneOrTwoFingerMovementCannotBecomePaging() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(ids: [1, 2]), phase: .began, canBegin: true)
        policy.update(contacts: contacts(-0.02, ids: [1, 2]), phase: .moved, canBegin: true)
        policy.update(contacts: contacts(-0.02), phase: .began, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
        XCTAssertFalse(policy.reservesIslandScroll)
    }

    func testTwoFingersDoNotReserveOrPage() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(ids: [1, 2]), phase: .began, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.2, ids: [1, 2]), phase: .moved, canBegin: true))
        XCTAssertFalse(policy.reservesIslandScroll)
        var wheel = IslandTouchScrollOwnership()
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .began, touchesReserved: policy.reservesIslandScroll))
    }

    func testFourthFingerOrReplacedIdentityRejectsUntilAllLift() {
        for ids in [[1, 2, 3, 4], [1, 2, 4], [1, 2]] {
            var policy = IslandTouchGesturePolicy()
            policy.update(contacts: contacts(), phase: .began, canBegin: true)
            XCTAssertNil(policy.update(contacts: contacts(-0.04, ids: ids), phase: .began, canBegin: true))
            XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
        }
    }

    func testSameTouchIdentityOrderIsStable() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1, ids: [3, 1, 2]), phase: .moved, canBegin: true), .next)
    }

    func testMixedDevicesInvalidPositionsAndDuplicateIDsReject() {
        let invalid = [contacts(ids: [1, 1, 2]), contacts(1),
            [contacts()[0], contacts()[1], contacts(device: 2)[2]]]
        for samples in invalid {
            var policy = IslandTouchGesturePolicy()
            policy.update(contacts: samples, phase: .began, canBegin: true)
            XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
        }
    }

    func testPinchOrOpposingFingerDoesNotPage() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        var samples = contacts(-0.2)
        samples[2] = contacts(0.1)[2]
        XCTAssertNil(policy.update(contacts: samples, phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
    }

    func testLockedDirectionCannotReverseIntoOppositePage() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        policy.update(contacts: contacts(-0.02), phase: .moved, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(0.2), phase: .moved, canBegin: true))
    }

    func testIneligibleStartCannotBecomeEligibleMidSequence() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: false)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
        XCTAssertFalse(policy.reservesIslandScroll)
    }

    func testInputDisabledDuringSequenceRejectsAndCancellationRearms() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true, inputStillAllowed: false))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
        policy.cancel()
        XCTAssertFalse(policy.isSequenceActive)
        XCTAssertFalse(policy.reservesIslandScroll)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true), .next)
    }

    func testWheelTailOwnedAfterLiftAndNextPhysicalBeginningReleases() {
        var wheel = IslandTouchScrollOwnership()
        wheel.reserve()
        XCTAssertTrue(wheel.suppressIslandRouting(phase: .ended, touchesReserved: false))
        XCTAssertTrue(wheel.suppressIslandRouting(phase: .momentum, touchesReserved: false))
        XCTAssertTrue(wheel.suppressIslandRouting(phase: .momentumEnded, touchesReserved: false))
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .began, touchesReserved: false))
        wheel.reserve()
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .began, touchesReserved: false))
        XCTAssertFalse(wheel.ownsSequence)
    }

    func testOpposedVerticalFingerMotionCannotHideBehindHorizontalCentroid() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        let rotation = [IslandIndirectTouch(identity: 1, device: 1, normalizedPosition: CGPoint(x: 0.35, y: 0.7)),
                        IslandIndirectTouch(identity: 2, device: 1, normalizedPosition: CGPoint(x: 0.35, y: 0.3)),
                        IslandIndirectTouch(identity: 3, device: 1, normalizedPosition: CGPoint(x: 0.35, y: 0.5))]
        XCTAssertNil(policy.update(contacts: rotation, phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
    }

    func testLateVerticalExcursionRejectsTheSequenceUntilAllLift() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        policy.update(contacts: contacts(-0.02), phase: .moved, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.03, 0.05), phase: .moved, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: true))
    }

    func testOrdinaryWheelAndCancelRestorePassThrough() {
        var wheel = IslandTouchScrollOwnership()
        wheel.reserve()
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .ordinaryWheel, touchesReserved: false))
        wheel.reserve()
        XCTAssertTrue(wheel.suppressIslandRouting(phase: .cancelled, touchesReserved: false))
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .changed, touchesReserved: false))
    }

    func testEmptyMovedSnapshotCannotRearmConsumedGestureDuringPageMorph() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1), phase: .moved, canBegin: true), .next)
        XCTAssertNil(policy.update(contacts: [], phase: .moved, canBegin: false, inputStillAllowed: false))
        XCTAssertTrue(policy.isSequenceActive)
        XCTAssertTrue(policy.hasFired)
        XCTAssertTrue(policy.reservesIslandScroll)
        // A new target view can deliver began for contacts still on the pad.
        XCTAssertNil(policy.update(contacts: contacts(-0.1), phase: .began, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.4), phase: .moved, canBegin: true))
        XCTAssertTrue(policy.hasFired)
    }

    func testShortLongExtremeSwipesAndReversalFireOnceUntilPhysicalRelease() {
        for sign in [CGFloat(-1), 1] {
            for distance in [CGFloat(0.081), 0.25, 0.44] {
                var policy = IslandTouchGesturePolicy()
                policy.update(contacts: contacts(), phase: .began, canBegin: true)
                let action: IslandTouchPageAction = sign < 0 ? .next : .previous
                XCTAssertEqual(policy.update(contacts: contacts(sign * distance), phase: .moved, canBegin: true), action)
                for step in 1...100 {
                    XCTAssertNil(policy.update(contacts: contacts(sign * 0.44 * CGFloat(step) / 100),
                        phase: .moved, canBegin: true))
                }
                XCTAssertNil(policy.update(contacts: contacts(-sign * 0.3), phase: .moved, canBegin: true))
                XCTAssertNil(policy.update(contacts: contacts(ids: [1]), phase: .ended, canBegin: true))
                XCTAssertTrue(policy.hasFired, "a partial lift is not the physical ending")
                policy.update(contacts: [], phase: .ended, canBegin: true)
                XCTAssertFalse(policy.isSequenceActive)
                XCTAssertFalse(policy.hasFired)
            }
        }
    }

    func testTwoDistinctRapidSwipesRearmWithoutCooldown() {
        for second in [CGFloat(-0.1), 0.1] {
            var policy = IslandTouchGesturePolicy()
            policy.update(contacts: contacts(), phase: .began, canBegin: true)
            XCTAssertEqual(policy.update(contacts: contacts(-0.1), phase: .moved, canBegin: true), .next)
            policy.update(contacts: [], phase: .ended, canBegin: true)
            policy.update(contacts: contacts(), phase: .began, canBegin: true)
            XCTAssertEqual(policy.update(contacts: contacts(second), phase: .moved, canBegin: true), second < 0 ? .next : .previous)
        }
    }

    func testMomentumAndMorphCompletionCannotTurnConsumedGestureIntoAnotherPage() {
        var policy = IslandTouchGesturePolicy()
        var wheel = IslandTouchScrollOwnership()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1), phase: .moved, canBegin: true), .next)
        wheel.reserve()
        XCTAssertNil(policy.update(contacts: contacts(-0.2), phase: .moved, canBegin: false, inputStillAllowed: false))
        XCTAssertNil(policy.update(contacts: contacts(-0.3), phase: .moved, canBegin: true))
        for phase in [IslandTouchScrollOwnership.Phase.changed, .ended, .momentum, .momentumEnded] {
            XCTAssertTrue(wheel.suppressIslandRouting(phase: phase, touchesReserved: policy.reservesIslandScroll))
            XCTAssertTrue(policy.hasFired)
        }
        policy.update(contacts: [], phase: .ended, canBegin: true)
        XCTAssertTrue(wheel.suppressIslandRouting(phase: .momentum, touchesReserved: false))
        XCTAssertTrue(wheel.suppressIslandRouting(phase: .momentumEnded, touchesReserved: false))
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .began, touchesReserved: false))
    }

    func testExplicitCancellationRearmsButEmptyTrackingSnapshotDoesNot() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        policy.update(contacts: [], phase: .moved, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1), phase: .moved, canBegin: true), .next)
        policy.update(contacts: [], phase: .cancelled, canBegin: true)
        XCTAssertFalse(policy.hasFired)
        policy.update(contacts: contacts(), phase: .began, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(0.1), phase: .moved, canBegin: true), .previous)
    }
}
