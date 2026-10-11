import XCTest
@testable import DynamicIsland

final class HandNavigationTests: XCTestCase {
    func testInferenceDeadlineAchievesTwentyFPSFromThirtyFPSCameraWithoutBacklog() {
        var cadence = HandInferenceCadence()
        var accepted = 0
        for frame in 0..<30 { if cadence.accepts(Double(frame) / 30) { accepted += 1 } }
        XCTAssertGreaterThanOrEqual(accepted, 19)
        XCTAssertLessThanOrEqual(accepted, 21)
        XCTAssertTrue(cadence.accepts(10), "A slow/cold inference cannot create a frame backlog")
        XCTAssertFalse(cadence.accepts(9), "Stale camera time must not schedule work")
    }
    func testPinchUsesHandScaleAndCameraAspectInsteadOfPixels() {
        var ratios: [Double] = []
        for factor in [0.4, 0.8, 1.0] {
            func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * factor, y: y * factor) }
            let metric = HandNavigationGeometry.measure(thumb: p(0.2, 0.6), index: p(0.25, 0.6), wrist: p(0.2, 0.2),
                middleMCP: p(0.2, 0.4), indexMCP: p(0.1, 0.4), littleMCP: p(0.3, 0.4), aspectRatio: 4 / 3)
            ratios.append(metric.pinch)
        }
        XCTAssertEqual(ratios[0], ratios[1], accuracy: 0.00001)
        XCTAssertEqual(ratios[1], ratios[2], accuracy: 0.00001)
    }
    func testChangingHandsCancelsHeldPinch() {
        var machine = HandNavigationStateMachine()
        var h = hand(0); h.side = .left; _ = machine.update(h)
        h.timestamp = 0.04; h.pinchRatio = 0.1; _ = machine.update(h)
        h.timestamp = 0.11; XCTAssertEqual(machine.update(h), [.press])
        h.side = .right; h.timestamp = 0.16
        XCTAssertEqual(machine.update(h), [.cancel])
        h.timestamp = 0.22; XCTAssertEqual(machine.update(h), [])
    }
    private func hand(_ time: Double, pinch: Double = 1, point: CGPoint = CGPoint(x: 0.5, y: 0.5),
                      pose: HandNavigationPose = .pointer, confidence: Double = 0.9) -> HandNavigationObservation {
        .init(fingertip: point, palm: point, handScale: 0.2, pinchRatio: pinch, pose: pose, confidence: confidence, timestamp: time)
    }
    func testMirroringAndVisionOrigin() {
        XCTAssertEqual(HandNavigationCoordinates.oriented(CGPoint(x: 0.2, y: 0.8)), CGPoint(x: 0.8, y: 0.8))
        XCTAssertEqual(HandNavigationCoordinates.oriented(CGPoint(x: 0.2, y: 0.8), mirrored: false), CGPoint(x: 0.2, y: 0.8))
    }
    func testOrientationRotations() {
        let p = CGPoint(x: 0.25, y: 0.75)
        XCTAssertEqual(HandNavigationCoordinates.oriented(p, quarterTurns: 1, mirrored: false), CGPoint(x: 0.25, y: 0.25))
        XCTAssertEqual(HandNavigationCoordinates.oriented(p, quarterTurns: 4, mirrored: false), p)
    }
    func testCalibrationAndFinalBounds() {
        let c = HandNavigationCalibration()
        XCTAssertEqual(c.map(CGPoint(x: c.left, y: c.bottom), sensitivity: 0.5), .zero)
        let frame = CGRect(x: 20, y: 40, width: 200, height: 60)
        XCTAssertEqual(HandNavigationCoordinates.islandPoint(CGPoint(x: -1, y: 2), frame: frame), CGPoint(x: 20.5, y: 99.5))
    }
    func testInvalidCalibrationFallsBack() {
        let bad = HandNavigationCalibration(left: 0.5, right: 0.5, bottom: .nan, top: 1)
        XCTAssertFalse(bad.isValid)
        XCTAssertEqual(bad.map(CGPoint(x: 0.5, y: 0.5), sensitivity: 0.5), CGPoint(x: 0.5, y: 0.5))
    }
    func testMappingAcrossResizeKeepsNormalizedPosition() {
        let point = CGPoint(x: 0.25, y: 0.75)
        for frame in [CGRect(x: 10, y: 20, width: 200, height: 40), CGRect(x: 30, y: 0, width: 640, height: 300)] {
            let mapped = HandNavigationCoordinates.islandPoint(point, frame: frame)
            XCTAssertEqual((mapped.x - frame.minX) / frame.width, point.x)
            XCTAssertEqual((mapped.y - frame.minY) / frame.height, point.y)
        }
    }
    func testCalibrationExtremesRemainInsideNativeHitBounds() {
        let frame = CGRect(x: 20, y: 30, width: 240, height: 34)
        for point in [CGPoint.zero, CGPoint(x: 1, y: 1), CGPoint(x: -5, y: 5)] {
            XCTAssertTrue(frame.contains(HandNavigationCoordinates.islandPoint(point, frame: frame)))
        }
    }
    func testSmoothingRestDeadZoneAndFastMotion() {
        var filter = HandPointerFilter()
        _ = filter.update(CGPoint(x: 0.5, y: 0.5), at: 0, smoothing: 0.8)
        XCTAssertEqual(filter.update(CGPoint(x: 0.5001, y: 0.5), at: 0.05, smoothing: 0.8).x, 0.5)
        XCTAssertGreaterThan(filter.update(CGPoint(x: 0.9, y: 0.5), at: 0.1, smoothing: 0.8).x, 0.8)
    }
    func testSmoothingResetDoesNotAccumulateLag() {
        var filter = HandPointerFilter()
        _ = filter.update(.zero, at: 0, smoothing: 1)
        filter.reset()
        XCTAssertEqual(filter.update(CGPoint(x: 1, y: 1), at: 1, smoothing: 1), CGPoint(x: 1, y: 1))
    }
    func testLowConfidenceAndNonfiniteRejected() {
        XCTAssertFalse(hand(0, confidence: 0.4).isValid)
        XCTAssertFalse(hand(0, point: CGPoint(x: CGFloat.nan, y: 0)).isValid)
        var machine = HandNavigationStateMachine()
        XCTAssertEqual(machine.update(hand(0, confidence: 0.4)), [])
    }
    func testOnePinchOnePressAndRelease() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0))
        XCTAssertEqual(machine.update(hand(0.05, pinch: 0.1)), [])
        XCTAssertEqual(machine.update(hand(0.12, pinch: 0.1)), [.press])
        for i in 3...12 { XCTAssertEqual(machine.update(hand(Double(i) * 0.05, pinch: 0.1)), []) }
        XCTAssertEqual(machine.update(hand(0.65)), [.release])
        XCTAssertEqual(machine.update(hand(0.7)), [])
    }
    func testPinchHysteresisRejectsThresholdNoise() {
        var machine = pressed()
        XCTAssertEqual(machine.update(hand(0.15, pinch: 0.3)), [])
        XCTAssertEqual(machine.phase, .pressed)
        XCTAssertEqual(machine.update(hand(0.2, pinch: 0.5)), [.release])
    }
    func testBriefPinchDoesNotPress() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0))
        _ = machine.update(hand(0.05, pinch: 0.1))
        XCTAssertEqual(machine.update(hand(0.08)), [])
        XCTAssertEqual(machine.phase, .tracking)
    }
    func testDragLifecycle() {
        var machine = pressed()
        XCTAssertEqual(machine.update(hand(0.15, pinch: 0.1, point: CGPoint(x: 0.6, y: 0.5))), [.drag])
        XCTAssertEqual(machine.phase, .dragging)
        XCTAssertEqual(machine.update(hand(0.2, point: CGPoint(x: 0.6, y: 0.5))), [.release])
    }
    func testHandLossCancelsOnceAndRequiresOpenBeforeNextPinch() {
        var machine = pressed()
        XCTAssertEqual(machine.update(nil), [.cancel])
        XCTAssertEqual(machine.update(nil), [])
        XCTAssertEqual(machine.update(hand(0.2, pinch: 0.1)), [])
        XCTAssertEqual(machine.update(hand(0.3, pinch: 0.1)), [])
    }
    func testPalmCancelsInsteadOfCommitting() {
        var machine = pressed()
        XCTAssertEqual(machine.update(hand(0.15, pose: .openPalm)), [.cancel])
        XCTAssertEqual(machine.update(hand(0.2, pose: .openPalm)), [])
    }
    func testHandJumpCancelsAndRejectsStaleTime() {
        var machine = pressed()
        XCTAssertEqual(machine.update(hand(0.15, pinch: 0.1, point: CGPoint(x: 0.95, y: 0.5))), [.cancel])
        XCTAssertEqual(machine.update(hand(0.1, pinch: 0.1)), [])
    }
    func testPointerMotionNeverPages() {
        var machine = HandNavigationStateMachine()
        for i in 0...5 { XCTAssertEqual(machine.update(hand(Double(i) * 0.05, point: CGPoint(x: 0.2 + Double(i) * 0.12, y: 0.5))), []) }
    }
    func testOneSwipeOnePageAndRearm() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0, point: CGPoint(x: 0.2, y: 0.5), pose: .openPalm))
        XCTAssertEqual(machine.update(hand(0.1, point: CGPoint(x: 0.5, y: 0.5), pose: .openPalm)), [.page(forward: false)])
        XCTAssertEqual(machine.update(hand(0.2, point: CGPoint(x: 0.8, y: 0.5), pose: .openPalm)), [])
        _ = machine.update(hand(0.25, point: CGPoint(x: 0.8, y: 0.5)))
        _ = machine.update(hand(0.5, point: CGPoint(x: 0.8, y: 0.5)))
        _ = machine.update(hand(0.55, point: CGPoint(x: 0.8, y: 0.5), pose: .openPalm))
        XCTAssertEqual(machine.update(hand(0.65, point: CGPoint(x: 0.5, y: 0.5), pose: .openPalm)), [.page(forward: true)])
    }
    func testPoseFlickerAndBriefTrackingLossCannotRearmSwipe() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0, point: CGPoint(x: 0.2, y: 0.5), pose: .openPalm))
        XCTAssertEqual(machine.update(hand(0.1, point: CGPoint(x: 0.5, y: 0.5), pose: .openPalm)), [.page(forward: false)])
        _ = machine.update(hand(0.15, point: CGPoint(x: 0.6, y: 0.5)))
        _ = machine.update(nil)
        _ = machine.update(hand(0.2, point: CGPoint(x: 0.6, y: 0.5), pose: .openPalm))
        XCTAssertEqual(machine.update(hand(0.3, point: CGPoint(x: 0.9, y: 0.5), pose: .openPalm)), [])
    }
    func testVerticalPalmNeverPages() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0, point: CGPoint(x: 0.5, y: 0.2), pose: .openPalm))
        XCTAssertEqual(machine.update(hand(0.1, point: CGPoint(x: 0.5, y: 0.5), pose: .openPalm)), [])
    }
    func testScrollRequiresDistinctPoseAndExplicitOption() {
        for enabled in [false, true] {
            var machine = HandNavigationStateMachine()
            _ = machine.update(hand(0, pose: .twoFinger), scroll: enabled)
            _ = machine.update(hand(0.1, pose: .twoFinger), scroll: enabled)
            let actions = machine.update(hand(0.15, point: CGPoint(x: 0.5, y: 0.55), pose: .twoFinger), scroll: enabled)
            XCTAssertEqual(actions, enabled ? [.scroll(30.00000000000003)] : [])
        }
    }
    private func pressed() -> HandNavigationStateMachine {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0)); _ = machine.update(hand(0.04, pinch: 0.1))
        _ = machine.update(hand(0.11, pinch: 0.1)); return machine
    }
}
