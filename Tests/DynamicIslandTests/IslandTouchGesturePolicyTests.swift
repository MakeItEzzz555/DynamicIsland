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
            XCTAssertNil(policy.update(contacts: contacts(), began: true, canBegin: true))
            XCTAssertEqual(policy.update(contacts: contacts(delta), began: false, canBegin: true), expected)
        }
    }

    func testNormalizedThresholdAndDirectionLockNoise() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.01, 0.01), began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.02, 0.005), began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.079, 0.02), began: false, canBegin: true))
        XCTAssertEqual(policy.update(contacts: contacts(-0.081, 0.02), began: false, canBegin: true), .next)
    }

    func testVerticalAndDiagonalStartCannotBecomeHorizontalPaging() {
        for first in [CGPoint(x: 0.005, y: 0.02), CGPoint(x: 0.025, y: 0.02)] {
            var policy = IslandTouchGesturePolicy()
            policy.update(contacts: contacts(), began: true, canBegin: true)
            XCTAssertNil(policy.update(contacts: contacts(first.x, first.y), began: false, canBegin: true))
            XCTAssertNil(policy.update(contacts: contacts(0.2), began: false, canBegin: true))
        }
    }

    func testHorizontalDominanceMustExceedOneAndHalf() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(0.03, 0.02), began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(0.2), began: false, canBegin: true))
    }

    func testExactlyOneActionUntilEveryFingerLifts() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1), began: false, canBegin: true), .next)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(ids: [1]), began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(0.1, ids: [1, 4, 5]), began: true, canBegin: true))
        XCTAssertTrue(policy.reservesIslandScroll)
        policy.update(contacts: [], began: false, canBegin: true)
        XCTAssertFalse(policy.reservesIslandScroll)
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(0.1), began: false, canBegin: true), .previous)
    }

    func testIncrementalFingerArrivalCanAssembleThreeContacts() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(ids: [1]), began: true, canBegin: true)
        policy.update(contacts: contacts(ids: [1, 2]), began: true, canBegin: true)
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1), began: false, canBegin: true), .next)
    }

    func testExistingOneOrTwoFingerMovementCannotBecomePaging() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(ids: [1, 2]), began: true, canBegin: true)
        policy.update(contacts: contacts(-0.02, ids: [1, 2]), began: false, canBegin: true)
        policy.update(contacts: contacts(-0.02), began: true, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
        XCTAssertFalse(policy.reservesIslandScroll)
    }

    func testTwoFingersDoNotReserveOrPage() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(ids: [1, 2]), began: true, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.2, ids: [1, 2]), began: false, canBegin: true))
        XCTAssertFalse(policy.reservesIslandScroll)
        var wheel = IslandTouchScrollOwnership()
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .began, touchesReserved: policy.reservesIslandScroll))
    }

    func testFourthFingerOrReplacedIdentityRejectsUntilAllLift() {
        for ids in [[1, 2, 3, 4], [1, 2, 4], [1, 2]] {
            var policy = IslandTouchGesturePolicy()
            policy.update(contacts: contacts(), began: true, canBegin: true)
            XCTAssertNil(policy.update(contacts: contacts(-0.04, ids: ids), began: true, canBegin: true))
            XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
        }
    }

    func testSameTouchIdentityOrderIsStable() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.1, ids: [3, 1, 2]), began: false, canBegin: true), .next)
    }

    func testMixedDevicesInvalidPositionsAndDuplicateIDsReject() {
        let invalid = [contacts(ids: [1, 1, 2]), contacts(1),
            [contacts()[0], contacts()[1], contacts(device: 2)[2]]]
        for samples in invalid {
            var policy = IslandTouchGesturePolicy()
            policy.update(contacts: samples, began: true, canBegin: true)
            XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
        }
    }

    func testPinchOrOpposingFingerDoesNotPage() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        var samples = contacts(-0.2)
        samples[2] = contacts(0.1)[2]
        XCTAssertNil(policy.update(contacts: samples, began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
    }

    func testLockedDirectionCannotReverseIntoOppositePage() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        policy.update(contacts: contacts(-0.02), began: false, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(0.2), began: false, canBegin: true))
    }

    func testIneligibleStartCannotBecomeEligibleMidSequence() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: false)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
        XCTAssertFalse(policy.reservesIslandScroll)
    }

    func testInputDisabledDuringSequenceRejectsAndCancellationRearms() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true, inputStillAllowed: false))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
        policy.cancel()
        XCTAssertFalse(policy.isSequenceActive)
        XCTAssertFalse(policy.reservesIslandScroll)
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
        policy.update(contacts: contacts(), began: true, canBegin: true)
        XCTAssertEqual(policy.update(contacts: contacts(-0.2), began: false, canBegin: true), .next)
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
        policy.update(contacts: contacts(), began: true, canBegin: true)
        let rotation = [IslandIndirectTouch(identity: 1, device: 1, normalizedPosition: CGPoint(x: 0.35, y: 0.7)),
                        IslandIndirectTouch(identity: 2, device: 1, normalizedPosition: CGPoint(x: 0.35, y: 0.3)),
                        IslandIndirectTouch(identity: 3, device: 1, normalizedPosition: CGPoint(x: 0.35, y: 0.5))]
        XCTAssertNil(policy.update(contacts: rotation, began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
    }

    func testLateVerticalExcursionRejectsTheSequenceUntilAllLift() {
        var policy = IslandTouchGesturePolicy()
        policy.update(contacts: contacts(), began: true, canBegin: true)
        policy.update(contacts: contacts(-0.02), began: false, canBegin: true)
        XCTAssertNil(policy.update(contacts: contacts(-0.03, 0.05), began: false, canBegin: true))
        XCTAssertNil(policy.update(contacts: contacts(-0.2), began: false, canBegin: true))
    }

    func testOrdinaryWheelAndCancelRestorePassThrough() {
        var wheel = IslandTouchScrollOwnership()
        wheel.reserve()
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .ordinaryWheel, touchesReserved: false))
        wheel.reserve()
        XCTAssertTrue(wheel.suppressIslandRouting(phase: .cancelled, touchesReserved: false))
        XCTAssertFalse(wheel.suppressIslandRouting(phase: .changed, touchesReserved: false))
    }
}
