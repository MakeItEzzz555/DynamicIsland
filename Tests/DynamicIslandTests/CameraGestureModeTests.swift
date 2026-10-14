import XCTest
@testable import DynamicIsland

final class CameraGestureModeTests: XCTestCase {
    private func hand(_ time: Double, x: Double = 0.5, y: Double = 0.5,
                      pose: HandNavigationPose = .pointer, pinch: Double = 1,
                      ring: Bool? = true, little: Bool? = true) -> HandNavigationObservation {
        .init(fingertip: CGPoint(x: x, y: y), palm: CGPoint(x: x, y: y), handScale: 0.2,
              pinchRatio: pinch, pose: pose, confidence: 0.9, timestamp: time,
              fingers: .init(index: true, middle: pose != .pointer, ring: ring, little: little))
    }

    func testMissingAndFlickeringOptionalFingersStillConfirmPalm() {
        var classifier = NavigationPoseClassifier()
        let sequence = [hand(0, pose: .other, ring: true, little: nil),
                        hand(0.05, pose: .other, ring: nil, little: nil),
                        hand(0.1, pose: .other, ring: nil, little: true),
                        hand(0.15, pose: .other, ring: false, little: nil)]
        for h in sequence { classifier.update(h, releaseThreshold: 0.39) }
        XCTAssertTrue(classifier.palmCandidate)
        XCTAssertEqual(classifier.pose, .openPalm)
    }

    func testTwoFoldedFingersNeverBecomePalmAndIndexAloneNeverNavigates() {
        for pose in [HandNavigationPose.pointer, .twoFinger] {
            var classifier = NavigationPoseClassifier()
            for i in 0...5 { classifier.update(hand(Double(i) * 0.05, pose: pose, ring: false, little: false), releaseThreshold: 0.39) }
            XCTAssertFalse(classifier.palmCandidate)
            XCTAssertEqual(classifier.pose, pose)
        }
    }

    func testOpenOtherOpenFlickerKeepsNavigationOwnership() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0, x: 0.7, pose: .openPalm))
        _ = machine.update(hand(0.05, x: 0.67, pose: .openPalm))
        _ = machine.update(hand(0.1, x: 0.64, pose: .other, ring: false, little: false))
        XCTAssertEqual(machine.mode, .navigation)
        XCTAssertEqual(machine.update(hand(0.15, x: 0.55, pose: .openPalm)), [.page(forward: true)])
        XCTAssertFalse(machine.hasPrecisionInteraction)
    }

    func testThreePalmStrokesRearmWhilePalmRemainsOpenAndReturnMotionIsIgnored() {
        var machine = HandNavigationStateMachine()
        var actions: [HandNavigationAction] = []
        var time = 0.0
        func inject(_ x: Double, available: Bool = true) {
            actions += machine.update(hand(time, x: x, pose: .openPalm), interactionAvailable: available)
            XCTAssertFalse(machine.hasPrecisionInteraction)
            time += 0.05
        }
        for stroke in 0..<3 {
            for x in [0.8, 0.65, 0.48, 0.3, 0.2] { inject(x) }
            XCTAssertEqual(actions.count, stroke + 1, "Continuous sweep fires once")
            for x in [0.35, 0.5, 0.65, 0.8] { inject(x) }
            XCTAssertEqual(actions.count, stroke + 1, "Moving recenter cannot fire Previous")
            XCTAssertFalse(machine.swipeArmed)
            for _ in 0..<4 { inject(0.8) }
            XCTAssertTrue(machine.swipeArmed)
        }
        XCTAssertEqual(actions, Array(repeating: .page(forward: true), count: 3))
    }

    func testPalmDwellRearmsOppositeStrokeWithoutPointing() {
        var machine = HandNavigationStateMachine()
        var actions: [HandNavigationAction] = []
        let xs = [0.8, 0.65, 0.48, 0.3, 0.4, 0.5, 0.5, 0.5, 0.5, 0.5, 0.6, 0.7, 0.8]
        for (i, x) in xs.enumerated() {
            actions += machine.update(hand(Double(i) * 0.05, x: x, pose: .openPalm,
                ring: i == 7 ? nil : true, little: i == 8 ? nil : true))
        }
        XCTAssertEqual(actions, [.page(forward: true), .page(forward: false)])
        XCTAssertFalse(machine.hasPrecisionInteraction)
    }

    func testContinuousSweepCannotRepeatOrRearm() {
        var machine = HandNavigationStateMachine()
        var actions: [HandNavigationAction] = []
        for i in 0...14 {
            actions += machine.update(hand(Double(i) * 0.05, x: 0.8 - Double(i) * 0.05, pose: .openPalm))
        }
        XCTAssertEqual(actions, [.page(forward: true)])
        XCTAssertFalse(machine.swipeArmed)
    }

    func testPalmStrokeAndStillDwellSurvivePageMorphWithoutPointing() {
        var machine = HandNavigationStateMachine()
        var actions: [HandNavigationAction] = []
        let xs = [0.8, 0.65, 0.48, 0.3, 0.45, 0.55, 0.55, 0.55, 0.55, 0.55, 0.45, 0.35]
        for (i, x) in xs.enumerated() {
            actions += machine.update(hand(Double(i) * 0.05, x: x, pose: .openPalm),
                interactionAvailable: !(3...8).contains(i))
            XCTAssertEqual(machine.mode, .navigation)
        }
        XCTAssertEqual(actions, [.page(forward: true), .page(forward: true)])
    }

    func testCollapsedPinchCannotExpandEvenAfterShellBecomesSafe() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0, pose: .openPalm), expanded: false, interactionAvailable: false,
            collapsedGestureAvailable: false)
        _ = machine.update(hand(0.05, pinch: 0.1), expanded: false, interactionAvailable: false,
            collapsedGestureAvailable: false)
        XCTAssertEqual(machine.update(hand(0.15, pinch: 0.1), expanded: false, interactionAvailable: false,
            collapsedGestureAvailable: false), [])
        XCTAssertEqual(machine.update(hand(0.2, pinch: 0.1), expanded: false, interactionAvailable: false), [])
        XCTAssertEqual(machine.update(hand(0.25, pinch: 0.1), expanded: false, interactionAvailable: false), [])
        XCTAssertFalse(machine.hasPrecisionInteraction)
    }

    func testReleasedPendingPinchCannotExpandLater() {
        var machine = HandNavigationStateMachine()
        for (i, pinch) in [1.0, 0.1, 0.1, 0.1, 1.0].enumerated() {
            XCTAssertEqual(machine.update(hand(Double(i) * 0.05, pinch: pinch), expanded: false,
                interactionAvailable: false, collapsedGestureAvailable: false), [])
        }
        XCTAssertEqual(machine.update(hand(0.25), expanded: false, interactionAvailable: false), [])
        _ = machine.update(hand(0.3, pinch: 0.1), expanded: false, interactionAvailable: false)
        XCTAssertEqual(machine.update(hand(0.4, pinch: 0.1), expanded: false, interactionAvailable: false), [])
    }

    func testDownCollapseOpenHandThenPinchNeedsNoPointerRearm() {
        var machine = HandNavigationStateMachine()
        var actions: [HandNavigationAction] = []
        for i in 0...5 {
            actions += machine.update(hand(Double(i) * 0.05, y: 0.7 - Double(i) * 0.04, pose: .openPalm), downAction: .collapse)
        }
        XCTAssertEqual(actions, [.collapseIsland])
        _ = machine.update(hand(0.3, y: 0.5, pose: .openPalm), expanded: false, interactionAvailable: false,
            collapsedGestureAvailable: false)
        _ = machine.update(hand(0.35, y: 0.5, pinch: 0.1), expanded: false, interactionAvailable: false,
            collapsedGestureAvailable: false)
        XCTAssertEqual(machine.update(hand(0.45, y: 0.5, pinch: 0.1), expanded: false, interactionAvailable: false,
            collapsedGestureAvailable: false), [])
        XCTAssertEqual(machine.update(hand(0.5, y: 0.5, pinch: 0.1), expanded: false, interactionAvailable: false), [])
    }

    func testJitterDiagonalVerticalAndSlowDriftNeverPage() {
        for shape in 0...3 {
            var machine = HandNavigationStateMachine()
            var actions: [HandNavigationAction] = []
            for i in 0...15 {
                let delta = Double(i) * 0.015
                let x = shape == 0 ? 0.5 + (i % 2 == 0 ? 0.005 : -0.005) : shape == 1 ? 0.5 + delta : shape == 2 ? 0.5 : 0.5 + Double(i) * 0.006
                let y = shape == 1 || shape == 2 ? 0.5 + delta : 0.5
                actions += machine.update(hand(Double(i) * 0.05, x: x, y: y, pose: .openPalm))
            }
            XCTAssertEqual(actions, [], "Shape \(shape)")
        }
    }

    func testCollapsedPinchNeverExpandsOrClicksAcrossRepeatedPinches() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0, x: -2), expanded: false)
        XCTAssertFalse(machine.hasPrecisionInteraction)
        _ = machine.update(hand(0.05, x: -2, pinch: 0.1), expanded: false)
        XCTAssertEqual(machine.update(hand(0.15, x: -2, pinch: 0.1), expanded: false), [])
        for i in 4...8 { XCTAssertEqual(machine.update(hand(Double(i) * 0.05, x: -2, pinch: 0.1), expanded: false), []) }
        _ = machine.update(hand(0.5, x: -2), expanded: false)
        _ = machine.update(hand(0.55, x: -2, pinch: 0.1), expanded: false)
        XCTAssertEqual(machine.update(hand(0.65, x: -2, pinch: 0.1), expanded: false), [])
    }

    func testCollapsedNoneOrProtectedControlConsumesPinchWithoutExpansion() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0), expanded: false, expandOnPinch: false)
        _ = machine.update(hand(0.05, pinch: 0.1), expanded: false, expandOnPinch: false)
        XCTAssertEqual(machine.update(hand(0.15, pinch: 0.1), expanded: false, expandOnPinch: false), [])
        XCTAssertEqual(machine.update(hand(0.2, pinch: 0.1), expanded: false, expandOnPinch: true), [], "Removing a protected control cannot turn a held pinch into expansion")
    }

    func testExpansionHeldPinchCannotClickThenPointerReturnsAfterRelease() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0), expanded: false)
        _ = machine.update(hand(0.05, pinch: 0.1), expanded: false)
        _ = machine.update(hand(0.15, pinch: 0.1), expanded: false)
        for i in 4...7 { XCTAssertEqual(machine.update(hand(Double(i) * 0.05, pinch: 0.1)), []) }
        for i in 8...12 { _ = machine.update(hand(Double(i) * 0.05)) }
        XCTAssertTrue(machine.hasPrecisionInteraction)
    }

    func testDownwardSwipeCollapsesOnceAndUpIsUnbound() {
        for direction in [-1.0, 1.0] {
            var machine = HandNavigationStateMachine()
            var actions: [HandNavigationAction] = []
            for i in 0...7 {
                actions += machine.update(hand(Double(i) * 0.05, y: 0.5 + direction * Double(i) * 0.03, pose: .openPalm), downAction: .collapse)
                XCTAssertFalse(machine.hasPrecisionInteraction)
            }
            XCTAssertEqual(actions, direction < 0 ? [.collapseIsland] : [])
        }
    }

    func testNavigationCancelsActiveDragOnceAndCannotImmediatelyCollapse() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0)); _ = machine.update(hand(0.05, pinch: 0.1))
        XCTAssertEqual(machine.update(hand(0.15, pinch: 0.1)), [.press])
        XCTAssertEqual(machine.update(hand(0.2, x: 0.6, pinch: 0.1)), [.drag])
        XCTAssertEqual(machine.update(hand(0.25, x: 0.6, pose: .openPalm), downAction: .collapse), [.cancel])
        for i in 6...11 { XCTAssertEqual(machine.update(hand(Double(i) * 0.05, x: 0.6, y: 0.5 - Double(i - 5) * 0.03, pose: .openPalm), downAction: .collapse), []) }
    }

    func testShellMorphRetainsNavigationThenPointerRearmsAutomatically() {
        var machine = HandNavigationStateMachine()
        _ = machine.update(hand(0))
        XCTAssertTrue(machine.hasPrecisionInteraction)
        _ = machine.update(hand(0.05, x: 0.7, pose: .openPalm))
        _ = machine.update(hand(0.1, x: 0.65, pose: .openPalm))
        XCTAssertEqual(machine.update(hand(0.15, x: 0.55, pose: .openPalm)), [.page(forward: true)])
        for i in 4...10 { XCTAssertEqual(machine.update(hand(Double(i) * 0.05, x: 0.55), interactionAvailable: false), []) }
        XCTAssertTrue(machine.hasPrecisionInteraction)
        XCTAssertEqual(machine.update(hand(0.6, x: 0.55)), [])
        XCTAssertTrue(machine.hasPrecisionInteraction)
    }

    func testTwoFingerModeHidesPointerAndDoesNotPage() {
        var machine = HandNavigationStateMachine()
        var actions: [HandNavigationAction] = []
        for i in 0...6 {
            actions += machine.update(hand(Double(i) * 0.05, y: 0.5 + Double(i) * 0.01, pose: .twoFinger, ring: false, little: false), scroll: true)
            XCTAssertFalse(machine.hasPrecisionInteraction)
        }
        XCTAssertFalse(actions.isEmpty)
        XCTAssertTrue(actions.allSatisfy { if case .scroll = $0 { return true }; return false })
        for i in 7...12 { _ = machine.update(hand(Double(i) * 0.05)) }
        XCTAssertTrue(machine.hasPrecisionInteraction)
    }

    func testBindingsPersistAndLegacyDisabledSwipeMigratesWithoutResettingCalibration() throws {
        let old = Data(#"{"showPointer":false,"horizontalPageSwipe":false,"smoothing":0.8,"twoFingerScroll":true,"calibration":{"left":0.1,"right":0.9,"bottom":0.2,"top":0.8}}"#.utf8)
        var prefs = try JSONDecoder().decode(CameraNavigationPreferences.self, from: old)
        XCTAssertFalse(prefs.showPointer); XCTAssertEqual(prefs.swipeLeftAction, .none); XCTAssertEqual(prefs.swipeRightAction, .none)
        XCTAssertEqual(prefs.collapsedPinchAction, .none); XCTAssertEqual(prefs.swipeDownAction, .collapse)
        XCTAssertEqual(prefs.smoothing, 0.8); XCTAssertEqual(prefs.calibration.top, 0.8)
        prefs.swipeRightAction = .nextTab; prefs.collapsedPinchAction = .none
        XCTAssertEqual(try JSONDecoder().decode(CameraNavigationPreferences.self, from: JSONEncoder().encode(prefs)), prefs)
    }
}
