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
