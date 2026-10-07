import AppKit
import CoreGraphics
import XCTest
@testable import DynamicIsland

@MainActor
final class TimerRulerInteractionTests: XCTestCase {
    func testSecondPrecisionCapturesOriginAndDoesNotCompoundTranslations() {
        var drag = TimerRulerDragSelection(seconds: 125, resolution: .seconds)
        XCTAssertEqual(drag.update(translation: -9).selectedSeconds, 126)
        XCTAssertEqual(drag.update(translation: -18).selectedSeconds, 127)
        XCTAssertEqual(drag.update(translation: -18).crossedTicks, [], "Repeating an event must not repeat feedback")
        XCTAssertEqual(drag.update(translation: 9).selectedSeconds, 124)
        XCTAssertEqual(drag.originSeconds, 125)
        XCTAssertEqual(drag.resolution, .seconds)
    }

    func testSlowDragProducesOneEventAtEachReachedTick() {
        var drag = TimerRulerDragSelection(seconds: 120, resolution: .seconds)
        XCTAssertEqual(drag.update(translation: -2).crossedTicks, [])
        XCTAssertEqual(drag.update(translation: -5).crossedTicks, [], "Rounded label selection is not a crossed physical tick")
        XCTAssertEqual(drag.update(translation: -9).crossedTicks, [121])
        XCTAssertEqual(drag.update(translation: -11).crossedTicks, [])
        XCTAssertEqual(drag.update(translation: -18).crossedTicks, [122])
    }

    func testFastDragEnumeratesAllCrossedTicksAndReversalIsExact() {
        var drag = TimerRulerDragSelection(seconds: 120, resolution: .seconds)
        XCTAssertEqual(drag.update(translation: -45).crossedTicks, [121, 122, 123, 124, 125])
        XCTAssertEqual(drag.update(translation: -45).crossedTicks, [])
        XCTAssertEqual(drag.update(translation: 18).crossedTicks, [124, 123, 122, 121, 120, 119, 118])
        XCTAssertEqual(drag.update(translation: 17).crossedTicks, [], "Leaving a reached boundary must not replay it")
        XCTAssertEqual(drag.update(translation: 9).crossedTicks, [119])
    }

    func testFractionalMotionCrossingsHaveSymmetricBoundaryRules() {
        XCTAssertEqual(TimerRulerInteractionGeometry.crossedTicks(from: 125, to: 124.9, resolution: .seconds), [])
        XCTAssertEqual(TimerRulerInteractionGeometry.crossedTicks(from: 124.9, to: 124, resolution: .seconds), [124])
        XCTAssertEqual(TimerRulerInteractionGeometry.crossedTicks(from: 124, to: 124.1, resolution: .seconds), [])
        XCTAssertEqual(TimerRulerInteractionGeometry.crossedTicks(from: 124.1, to: 125, resolution: .seconds), [125])
    }

    func testSelectionBoundsAndInvalidInputStaySafe() {
        var minimum = TimerRulerDragSelection(seconds: 1, resolution: .seconds)
        XCTAssertEqual(minimum.update(translation: 1000).selectedSeconds, 1)
        XCTAssertEqual(minimum.update(translation: 1000).crossedTicks, [])
        var maximum = TimerRulerDragSelection(seconds: 10800, resolution: .seconds)
        XCTAssertEqual(maximum.update(translation: -1000).selectedSeconds, 10800)
        XCTAssertEqual(maximum.update(translation: -1000).crossedTicks, [])
        XCTAssertEqual(maximum.update(translation: .nan).selectedSeconds, 10800)
        XCTAssertEqual(TimerDurationSelection.seconds(.nan), 1500)
        XCTAssertEqual(TimerDurationSelection.seconds(-100), 1)
        XCTAssertEqual(TimerDurationSelection.seconds(.greatestFiniteMagnitude), 10800)
    }

    func testExactSecondsPreferencesOverrideAndMigrateLegacyMinutes() {
        XCTAssertEqual(TimerDurationSelection.restored(seconds: 0, legacyMinutes: 25), 1500)
        XCTAssertEqual(TimerDurationSelection.restored(seconds: 0, legacyMinutes: 5), 300)
        XCTAssertEqual(TimerDurationSelection.restored(seconds: 125, legacyMinutes: 25), 125)
        XCTAssertEqual(TimerDurationSelection.restored(seconds: -1, legacyMinutes: 5), 300)
        XCTAssertEqual(TimerDurationSelection.restored(seconds: Int.max, legacyMinutes: 5), 10800)
        let idle = TimerTimingSnapshot()
        XCTAssertEqual(TimerCountdownPresentation.rulerSeconds(snapshot: idle, now: .zero, selectedSeconds: 125), 125)
        XCTAssertEqual(TimerCountdownPresentation.accessibilityValue(snapshot: idle, now: .zero, selectedSeconds: 125), "2 minutes 5 seconds selected")
        XCTAssertEqual(TimerCountdownPresentation.displayText(remaining: 125), "2:05")
    }

    func testZoomDoesNotQuantizeSelectionAndTickGeometryIsBounded() {
        let selected = 125.0
        XCTAssertEqual(TimerRulerInteractionGeometry.x(forTick: 125, valueSeconds: selected, center: 140, resolution: .seconds), 140)
        XCTAssertEqual(TimerRulerInteractionGeometry.x(forTick: 2, valueSeconds: selected, center: 140, resolution: .minutes), 139.25, accuracy: 0.001)
        let secondTicks = TimerRulerInteractionGeometry.visibleTicks(valueSeconds: selected, width: 280, resolution: .seconds)
        XCTAssertLessThanOrEqual(secondTicks.count, 35)
        XCTAssertEqual(TimerRulerInteractionGeometry.tick(60, resolution: .seconds).height, 32)
        XCTAssertEqual(TimerRulerInteractionGeometry.tick(15, resolution: .seconds).height, 28)
        XCTAssertEqual(TimerRulerInteractionGeometry.tick(5, resolution: .seconds).height, 22)
        XCTAssertEqual(TimerRulerInteractionGeometry.tick(1, resolution: .seconds).height, 14)
        XCTAssertTrue(TimerRulerInteractionGeometry.tick(15, resolution: .seconds).labelled)
        XCTAssertFalse(TimerRulerInteractionGeometry.tick(5, resolution: .seconds).labelled)
        for width in [Double.nan, .infinity, -.infinity, .greatestFiniteMagnitude] {
            let ticks = TimerRulerInteractionGeometry.visibleTicks(valueSeconds: .nan, width: CGFloat(width), resolution: .seconds)
            XCTAssertLessThanOrEqual(ticks.count, 10801)
        }
    }

    func testNativeWheelMonitorAttachesDetachesAndOwnsNoClickLayer() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 300, height: 62),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let view = TimerRulerWheelInput.WheelView(frame: CGRect(x: 0, y: 0, width: 300, height: 62))
        XCTAssertFalse(view.hasWheelMonitor)
        window.contentView = view
        XCTAssertTrue(view.hasWheelMonitor)
        XCTAssertNil(view.hitTest(CGPoint(x: 100, y: 20)), "The wheel bridge must never cover Canvas click-drag or buttons")
        window.contentView = nil
        XCTAssertFalse(view.hasWheelMonitor, "Window detachment must release the local event monitor")
        window.contentView = view
        XCTAssertTrue(view.hasWheelMonitor)
        final class CallbackLifetime {}
        weak var callbackLifetime: CallbackLifetime?
        do {
            let token = CallbackLifetime()
            callbackLifetime = token
            view.changed = { _ in _ = token }
            view.finished = { _ in _ = token }
        }
        XCTAssertNotNil(callbackLifetime)
        TimerRulerWheelInput.dismantleNSView(view, coordinator: ())
        XCTAssertFalse(view.hasWheelMonitor)
        XCTAssertNil(callbackLifetime, "Dismantled native sources must release captured view/controller callbacks")
    }

    func testPausedClockAlignmentSurvivesZoomAndRemount() {
        let clock = ManualCountdownClock()
        let timer = TimerController(clock: clock, refreshInterval: nil)
        timer.start(seconds: 125)
        clock.advance(by: .milliseconds(12500))
        timer.pause()
        let snapshot = timer.timingSnapshot
        let before = TimerCountdownPresentation.rulerSeconds(snapshot: snapshot, now: timer.clockNow, selectedSeconds: 7)
        XCTAssertEqual(before, 112.5)
        clock.advance(by: .seconds(60))
        let after = TimerCountdownPresentation.rulerSeconds(snapshot: snapshot, now: timer.clockNow, selectedSeconds: 1500)
        XCTAssertEqual(after, before)
        XCTAssertNil(TimerCountdownPresentation.frameInterval(snapshot: snapshot, displayScale: 2, resolution: .seconds))
        timer.resume()
        XCTAssertEqual(TimerCountdownPresentation.rulerSeconds(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedSeconds: 1), before)
        clock.advance(by: .seconds(1))
        XCTAssertEqual(TimerCountdownPresentation.rulerSeconds(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedSeconds: 1), 111.5)
        XCTAssertEqual(timer.totalSeconds, 125)
    }
}

@MainActor
final class TimerRulerOverscrollAndZoomTests: XCTestCase {
    func testOverscrollPastMinimumDoesNotBankADeadZone() {
        var drag = TimerRulerDragSelection(seconds: 3, resolution: .seconds)
        XCTAssertEqual(drag.update(translation: 18).selectedSeconds, 1)
        XCTAssertEqual(drag.update(translation: 900).selectedSeconds, 1, "Keeps clamping while overscrolling")
        let back = drag.update(translation: 891)
        XCTAssertEqual(back.selectedSeconds, 2, "Reversing must respond immediately after overscroll")
        XCTAssertEqual(back.crossedTicks, [2])
        XCTAssertEqual(drag.originSeconds, 3, "Cancel still restores the original selection")
    }

    func testOverscrollPastMaximumReversesImmediately() {
        var drag = TimerRulerDragSelection(seconds: 10_790, resolution: .seconds)
        XCTAssertEqual(drag.update(translation: -5_000).selectedSeconds, 10_800)
        XCTAssertEqual(drag.update(translation: -4_991).selectedSeconds, 10_799)
    }

    func testOverviewZoomReachesLongDurationsQuickly() {
        XCTAssertEqual(TimerRulerResolution.seconds.next, .minutes)
        XCTAssertEqual(TimerRulerResolution.minutes.next, .overview)
        XCTAssertEqual(TimerRulerResolution.overview.next, .seconds)
        var drag = TimerRulerDragSelection(seconds: 300, resolution: .overview)
        XCTAssertEqual(drag.update(translation: -90).selectedSeconds, 300 + 10 * 300, "Ten 5-minute ticks per 90pt")
        XCTAssertEqual(TimerRulerResolution.overview.label(forTick: 6), "30")
        XCTAssertTrue(TimerRulerInteractionGeometry.tick(6, resolution: .overview).labelled)
        XCTAssertFalse(TimerRulerInteractionGeometry.tick(3, resolution: .overview).labelled)
        let ticks = TimerRulerInteractionGeometry.visibleTicks(valueSeconds: 5_400, width: 280, resolution: .overview)
        XCTAssertLessThanOrEqual(ticks.upperBound, 36)
        XCTAssertLessThanOrEqual(ticks.count, 35)
    }

    func testWheelAccelerationKeepsSlowScrollsExactAndBoundsFastFlicks() {
        XCTAssertEqual(TimerRulerInteractionGeometry.acceleratedWheelDelta(3), 3)
        XCTAssertEqual(TimerRulerInteractionGeometry.acceleratedWheelDelta(-6), -6)
        XCTAssertEqual(TimerRulerInteractionGeometry.acceleratedWheelDelta(12), 24)
        XCTAssertEqual(TimerRulerInteractionGeometry.acceleratedWheelDelta(-60), -240, "Capped at 4x")
        XCTAssertEqual(TimerRulerInteractionGeometry.acceleratedWheelDelta(.nan), 0)
    }
}

/// P0-C: idle selection can never reach 0 through any input path or zoom
/// level; countdown completion may present 0 safely.
@MainActor
final class TimerRulerLowerBoundTests: XCTestCase {
    func testHugeDragAndWheelFlicksFromOneSecondStayAtOneInEveryResolution() {
        for resolution in TimerRulerResolution.allCases {
            var drag = TimerRulerDragSelection(seconds: 1, resolution: resolution)
            XCTAssertEqual(drag.update(translation: 1_000_000).selectedSeconds, 1, "\(resolution)")
            // Accelerated wheel momentum: dozens of large deltas toward zero,
            // continuing the same session's cumulative translation.
            var translation = 1_000_000.0
            for _ in 0..<200 {
                translation += TimerRulerInteractionGeometry.acceleratedWheelDelta(120)
                let change = drag.update(translation: translation)
                XCTAssertEqual(change.selectedSeconds, 1)
                XCTAssertGreaterThanOrEqual(change.value, 1)
                XCTAssertTrue(change.value.isFinite)
            }
            // Immediate reversal: no banked dead zone.
            let reversed = drag.update(translation: translation - Double(resolution.pointsPerTick))
            XCTAssertGreaterThan(reversed.selectedSeconds, 1, "\(resolution) reverses immediately")
        }
    }

    func testFastFlickFromThreeSecondsStopsAtOne() {
        var drag = TimerRulerDragSelection(seconds: 3, resolution: .seconds)
        XCTAssertEqual(drag.update(translation: TimerRulerInteractionGeometry.acceleratedWheelDelta(400)).selectedSeconds, 1)
    }

    func testRapidAlternatingFlicksNearMinimumStayInBounds() {
        var drag = TimerRulerDragSelection(seconds: 2, resolution: .seconds)
        var translation = 0.0
        for step in 0..<400 {
            translation += (step.isMultiple(of: 2) ? 1 : -1) * TimerRulerInteractionGeometry.acceleratedWheelDelta(Double(step % 37) + 1)
            let change = drag.update(translation: translation)
            XCTAssertGreaterThanOrEqual(change.selectedSeconds, 1)
            XCTAssertLessThanOrEqual(change.selectedSeconds, TimerDurationSelection.maximumSeconds)
        }
    }

    func testTapKeyboardAccessibilityAndPersistenceCannotSelectZero() {
        // Tap left of the zero landmark, keyboard/accessibility decrement at 1 s.
        for value in [-500.0, -1, 0, 0.4, -.infinity, .nan] {
            XCTAssertGreaterThanOrEqual(TimerDurationSelection.seconds(value), 1)
        }
        XCTAssertEqual(TimerDurationSelection.seconds(Double(1 - TimerRulerResolution.overview.stepSeconds)), 1)
        XCTAssertGreaterThanOrEqual(TimerDurationSelection.restored(seconds: 0, legacyMinutes: 0), 1)
        XCTAssertGreaterThanOrEqual(TimerDurationSelection.restored(seconds: -7, legacyMinutes: -3), 1)
    }

    func testPresentedValueSeparatesIdleMinimumFromCountdownCompletion() {
        let idle = TimerRulerInteractionGeometry.presentedValue(countingDown: false, countdownSeconds: 0, dragValue: 0, selectedSeconds: 0)
        XCTAssertEqual(idle, 1, "idle selection never presents 0")
        XCTAssertEqual(TimerRulerInteractionGeometry.presentedValue(countingDown: false, countdownSeconds: 0, dragValue: .nan, selectedSeconds: 5), 5)
        XCTAssertEqual(TimerRulerInteractionGeometry.presentedValue(countingDown: true, countdownSeconds: 0.35, dragValue: nil, selectedSeconds: 1), 0.35,
                       "subsecond countdown is presented")
        XCTAssertEqual(TimerRulerInteractionGeometry.presentedValue(countingDown: true, countdownSeconds: 0, dragValue: nil, selectedSeconds: 1), 0,
                       "completion presents 0")
        XCTAssertEqual(TimerRulerInteractionGeometry.presentedValue(countingDown: true, countdownSeconds: -0.2, dragValue: nil, selectedSeconds: 1), 0)
        XCTAssertEqual(TimerRulerInteractionGeometry.presentedValue(countingDown: true, countdownSeconds: .infinity, dragValue: nil, selectedSeconds: 1), 0)
    }

    func testZeroLandmarkTickGeometryIsValidAtCompletionAndMinimum() {
        for resolution in TimerRulerResolution.allCases {
            for value in [0.0, 0.25, 1] {
                let ticks = TimerRulerInteractionGeometry.visibleTicks(valueSeconds: value, width: 260, resolution: resolution)
                XCTAssertGreaterThanOrEqual(ticks.lowerBound, 0, "no negative ticks")
                XCTAssertTrue(ticks.contains(0), "zero landmark stays visible")
                for tick in ticks {
                    let x = TimerRulerInteractionGeometry.x(forTick: tick, valueSeconds: value, center: 130, resolution: resolution)
                    XCTAssertTrue(x.isFinite)
                }
            }
        }
    }

    func testOneSecondCountdownProgressesThroughSubsecondToCompletion() {
        let clock = ManualCountdownClock()
        let timer = TimerController(clock: clock, refreshInterval: nil)
        timer.start(seconds: 1)
        clock.advance(by: .milliseconds(400))
        let mid = TimerCountdownPresentation.rulerSeconds(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedSeconds: 1)
        XCTAssertEqual(mid, 0.6, accuracy: 0.001)
        clock.advance(by: .milliseconds(700))
        let done = TimerCountdownPresentation.remainingSeconds(timer.timingSnapshot, now: timer.clockNow)
        XCTAssertGreaterThanOrEqual(done, 0)
        XCTAssertEqual(TimerCountdownPresentation.displayText(remaining: max(0, done)), "0:00")
    }
}

final class TimerRulerInputOwnershipTests: XCTestCase {
    func testForeignOrStaleSessionsAreSettledBeforeANewGesture() {
        var ownership = TimerRulerInputOwnership()
        XCTAssertFalse(ownership.begin(.wheel, newGesture: true, hasSession: false))
        XCTAssertEqual(ownership.source, .wheel)
        // A wheel gesture whose `ended` never arrived: the next wheel gesture settles it.
        XCTAssertTrue(ownership.begin(.wheel, newGesture: true, hasSession: true))
        // A pointer drag never continues a wheel session (different translation origin).
        XCTAssertTrue(ownership.begin(.pointer, newGesture: true, hasSession: true))
        XCTAssertEqual(ownership.source, .pointer)
        ownership.end()
        XCTAssertNil(ownership.source)
        XCTAssertFalse(ownership.begin(.pointer, newGesture: true, hasSession: false))
    }

    func testSettledLowerBoundSessionNeverLeaksItsRebasedAnchor() {
        // Wheel overscroll toward zero rebases the anchor far past the minimum.
        var wheel = TimerRulerDragSelection(seconds: 1, resolution: .seconds)
        _ = wheel.update(translation: 50_000)
        let committed = TimerDurationSelection.seconds(1)
        // Settling commits 1 s; the pointer session starts from the committed value.
        var pointer = TimerRulerDragSelection(seconds: committed, resolution: .seconds)
        XCTAssertEqual(pointer.update(translation: 9).selectedSeconds, 1)
        XCTAssertEqual(pointer.update(translation: -9).selectedSeconds, 3, "18 pt reversal from the clamp = 2 ticks")
        // Without settling, a fresh 0-based translation against the rebased
        // anchor would jump toward the maximum - the regression this prevents.
        XCTAssertGreaterThan(wheel.update(translation: -9).selectedSeconds, 1_000)
    }
}
