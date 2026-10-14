import XCTest
@testable import DynamicIsland

final class CameraPrecisionTests: XCTestCase {
    private func hand(_ t: Double, ratio: Double = 1, tip: CGPoint = .init(x: 0.5, y: 0.5),
                      palm: CGPoint = .init(x: 0.5, y: 0.4), pose: HandNavigationPose = .pointer) -> HandNavigationObservation {
        .init(fingertip: tip, palm: palm, handScale: 0.2, pinchRatio: ratio, pose: pose, confidence: 0.9, timestamp: t)
    }

    func testPrecisionSurvivesBriefOtherAndUnconfirmedNavigationFlicker() {
        var machine = HandNavigationStateMachine()
        for (i, pose) in [HandNavigationPose.pointer, .other, .pointer, .twoFinger, .pointer, .openPalm, .pointer, .pointer, .pointer].enumerated() {
            _ = machine.update(hand(Double(i) * 0.05, pose: pose))
            XCTAssertTrue(machine.hasPrecisionInteraction, "Flicker frame \(i)")
        }
        for i in 9...13 { _ = machine.update(hand(Double(i) * 0.05, pose: .other)) }
        XCTAssertFalse(machine.hasPrecisionInteraction, "Tolerance must expire")
    }

    func testStationaryPinchDriftAndGhostDragSuppression() {
        var machine = HandNavigationStateMachine(), filter = HandPointerFilter(), baseline = HandPointerFilter()
        var stabilizer = HandPinchPointerStabilizer()
        let frame = CGRect(x: 0, y: 0, width: 640, height: 360), calibration = HandNavigationCalibration()
        let ratios = [1.0, 0.62, 0.45, 0.24, 0.18, 0.12, 0.1, 0.1, 0.1]
        let ys = [0.5, 0.5, 0.498, 0.48, 0.46, 0.44, 0.43, 0.43, 0.43]
        var drift = 0.0, oldDrift = 0.0, presses = 0, drags = 0
        for i in ratios.indices {
            let h = hand(Double(i) * 0.05, ratio: ratios[i], tip: .init(x: 0.5, y: ys[i]))
            let actions = machine.update(h)
            presses += actions.filter { $0 == .press }.count
            drags += actions.filter { $0 == .drag && stabilizer.isDragging }.count
            let input = calibration.map(h.fingertip, sensitivity: 0.5)
            let corrected = stabilizer.update(h, input: input, palm: calibration.map(h.palm, sensitivity: 0.5),
                filtered: filter.point, phase: machine.phase, pinchSensitivity: 0.5)
            let point = HandNavigationCoordinates.islandPoint(filter.update(corrected, at: h.timestamp, smoothing: 0.65), frame: frame)
            let old = HandNavigationCoordinates.islandPoint(baseline.update(input, at: h.timestamp, smoothing: 0.65), frame: frame)
            drift = max(drift, abs(point.y - 180)); oldDrift = max(oldDrift, abs(old.y - 180))
        }
        XCTAssertLessThan(drift, 6)
        XCTAssertGreaterThan(oldDrift, 25)
        XCTAssertEqual(presses, 1); XCTAssertEqual(drags, 0)
        print(String(format: "CAMERA_V4_PINCH frame=640x360 calibration=.15...85 oldDrift=%.3fpt newDrift=%.3fpt presses=%d ghostDrags=%d", oldDrift, drift, presses, drags))
    }

    func testIntentionalDragIsRelativeToAnchorAndReleaseHasNoJump() {
        var s = HandPinchPointerStabilizer()
        _ = s.update(hand(0), input: .init(x: 0.5, y: 0.5), palm: .init(x: 0.5, y: 0.4), filtered: nil, phase: .tracking, pinchSensitivity: 0.5)
        let anchor = s.update(hand(0.05, ratio: 0.1), input: .init(x: 0.5, y: 0.4), palm: .init(x: 0.5, y: 0.4), filtered: .init(x: 0.5, y: 0.5), phase: .pinchCandidate, pinchSensitivity: 0.5)
        _ = s.update(hand(0.15, ratio: 0.1), input: .init(x: 0.5, y: 0.4), palm: .init(x: 0.5, y: 0.4), filtered: anchor, phase: .pressed, pinchSensitivity: 0.5)
        let tiny = s.update(hand(0.2, ratio: 0.1, palm: .init(x: 0.505, y: 0.4)), input: .init(x: 0.55, y: 0.35), palm: .init(x: 0.505, y: 0.4), filtered: anchor, phase: .dragging, pinchSensitivity: 0.5)
        XCTAssertEqual(tiny, anchor); XCTAssertFalse(s.isDragging)
        let moved = s.update(hand(0.25, ratio: 0.1, palm: .init(x: 0.55, y: 0.4)), input: .init(x: 0.7, y: 0.35), palm: .init(x: 0.55, y: 0.4), filtered: anchor, phase: .dragging, pinchSensitivity: 0.5)
        XCTAssertEqual(moved.x, anchor.x + 0.05, accuracy: 0.00001); XCTAssertEqual(moved.y, anchor.y)
        XCTAssertTrue(s.isDragging)
        let released = s.update(hand(0.3), input: .init(x: 0.7, y: 0.6), palm: .init(x: 0.55, y: 0.4), filtered: moved, phase: .tracking, pinchSensitivity: 0.5)
        XCTAssertEqual(released, moved); XCTAssertNil(s.anchor); XCTAssertFalse(s.isDragging)
        s.reset(); XCTAssertNil(s.anchor)
    }

    func testNormalFingerMovementDoesNotFreezeAndApproachTimesOut() {
        var s = HandPinchPointerStabilizer()
        for i in 0..<12 {
            let input = CGPoint(x: 0.4 + Double(i) * 0.01, y: 0.5)
            XCTAssertEqual(s.update(hand(Double(i) * 0.05, ratio: i % 2 == 0 ? 0.9 : 0.8), input: input,
                palm: input, filtered: input, phase: .tracking, pinchSensitivity: 0.5), input)
            XCTAssertNil(s.anchor)
        }
        for (i, ratio) in [0.8, 0.6, 0.4].enumerated() {
            _ = s.update(hand(1 + Double(i) * 0.05, ratio: ratio), input: .zero, palm: .zero, filtered: .zero, phase: .tracking, pinchSensitivity: 0.5)
        }
        XCTAssertNotNil(s.anchor)
        _ = s.update(hand(1.3, ratio: 0.4), input: .zero, palm: .zero, filtered: .zero, phase: .tracking, pinchSensitivity: 0.5)
        XCTAssertNil(s.anchor)
    }

    func testStaleAndNonfiniteFilterInputsCannotTeleportPointer() {
        var f = HandPointerFilter()
        let point = CGPoint(x: 0.5, y: 0.5)
        _ = f.update(point, at: 10, smoothing: 0.65)
        XCTAssertEqual(f.update(.zero, at: 9.99, smoothing: 0.65), point)
        XCTAssertEqual(f.update(.init(x: CGFloat.nan, y: 0), at: 11, smoothing: 0.65), point)
    }

    func testStationaryJitterAtDifferentInferenceRates() {
        for fps in [15, 20, 30, 60] {
            var f = HandPointerFilter(); var maximum = 0.0
            _ = f.update(.init(x: 0.5, y: 0.5), at: 0, smoothing: 0.65)
            for i in 1...fps {
                let point = f.update(.init(x: CGFloat(0.5 + sin(Double(i)) * 0.0008), y: 0.5), at: Double(i) / Double(fps), smoothing: 0.65)
                maximum = max(maximum, Double(abs(point.x - 0.5)) * 640)
            }
            XCTAssertLessThan(maximum, 1)
            print("CAMERA_V4_JITTER fps=\(fps) max=\(maximum)pt fixture=640pt-wide")
        }
    }

    func testNoCollapsedSequenceCanExpandIncludingLossAndLegacyMapping() {
        var machine = HandNavigationStateMachine()
        for i in 0..<100 {
            let h = i % 9 == 0 ? nil : hand(Double(i) * 0.05, ratio: i % 8 < 2 ? 1 : 0.1,
                pose: i % 5 == 0 ? .openPalm : .pointer)
            let actions = machine.update(h, expanded: false, interactionAvailable: i % 3 == 0, expandOnPinch: true, collapsedGestureAvailable: true)
            XCTAssertFalse(actions.contains(.expandIsland)); XCTAssertFalse(actions.contains(.press))
            XCTAssertFalse(machine.hasPrecisionInteraction)
        }
    }

    func testPalmReturnsToPrecisionWithinTwoHundredMilliseconds() {
        var machine = HandNavigationStateMachine()
        for i in 0...2 { _ = machine.update(hand(Double(i) * 0.05, pose: .openPalm)) }
        XCTAssertFalse(machine.hasPrecisionInteraction)
        var restoredAt: Double?
        for i in 3...8 {
            let time = Double(i) * 0.05
            _ = machine.update(hand(time))
            if machine.hasPrecisionInteraction, restoredAt == nil { restoredAt = time }
        }
        XCTAssertNotNil(restoredAt)
        XCTAssertLessThanOrEqual((restoredAt ?? 10) - 0.15, 0.2 + 0.000001)
        print("CAMERA_V4_PALM_RECOVERY ms=\(((restoredAt ?? 10) - 0.15) * 1000)")
    }

    func testSlowMotionIsMonotonicAndFastMotionResponsiveAcrossFrameRates() {
        for fps in [15, 20, 30, 60] {
            var filter = HandPointerFilter(); var last = CGPoint(x: 0.2, y: 0.5)
            _ = filter.update(last, at: 0, smoothing: 0.65)
            for i in 1...fps {
                let input = CGPoint(x: 0.2 + Double(i) / Double(fps) * 0.1, y: 0.5)
                let next = filter.update(input, at: Double(i) / Double(fps), smoothing: 0.65)
                XCTAssertGreaterThanOrEqual(next.x, last.x); XCTAssertLessThanOrEqual(next.x, input.x)
                XCTAssertLessThan(input.x - next.x, 0.05)
                last = next
            }
            let fast = filter.update(.init(x: 0.9, y: 0.5), at: 1 + 1 / Double(fps), smoothing: 0.65)
            XCTAssertGreaterThan(fast.x, 0.8)
        }
    }
}
