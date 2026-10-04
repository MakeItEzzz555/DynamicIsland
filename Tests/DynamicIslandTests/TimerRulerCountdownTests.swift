import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Deterministic clock only: the ruler's countdown position is derived from
/// the controller's low-frequency timing snapshot, never from view state.
@MainActor
final class TimerRulerCountdownTests: XCTestCase {
    private func makeTimer() -> (TimerController, ManualCountdownClock) {
        let clock = ManualCountdownClock()
        return (TimerController(clock: clock, refreshInterval: nil), clock)
    }

    private func remaining(_ timer: TimerController) -> Double {
        timer.timingSnapshot.remaining(at: timer.clockNow).seconds
    }

    func testSnapshotFollowsLifecycleAndDerivesRemainingFromTheClock() {
        let (timer, clock) = makeTimer()
        XCTAssertEqual(timer.timingSnapshot.phase, .idle)
        XCTAssertEqual(remaining(timer), 0)

        timer.start(seconds: 600)
        XCTAssertTrue(timer.timingSnapshot.isRunning)
        XCTAssertEqual(timer.timingSnapshot.total, .seconds(600))
        XCTAssertEqual(remaining(timer), 600)

        clock.advance(by: .seconds(150))
        XCTAssertEqual(remaining(timer), 450, accuracy: 0.001, "No refresh needed: position comes from deadline")
        clock.advance(by: .milliseconds(250))
        XCTAssertEqual(remaining(timer), 449.75, accuracy: 0.001, "Sub-second precision for smooth motion")
    }

    func testPauseFreezesAndResumeContinuesWithoutJump() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 60)
        clock.advance(by: .milliseconds(20_500))
        timer.pause()
        XCTAssertEqual(timer.timingSnapshot.phase, .paused(remaining: .milliseconds(39_500)))
        let frozen = remaining(timer)
        clock.advance(by: .seconds(30))
        XCTAssertEqual(remaining(timer), frozen, "Paused ruler never moves")
        XCTAssertEqual(timer.remainingSeconds, 40, "Numeric label agrees with ceil(remaining)")
        XCTAssertEqual(TimerCountdownPresentation.displayText(remaining: frozen), timer.displayText)

        timer.resume()
        XCTAssertEqual(remaining(timer), frozen, accuracy: 0.001, "Resume starts exactly where pause froze")
        clock.advance(by: .seconds(9))
        XCTAssertEqual(remaining(timer), 30.5, accuracy: 0.001)
    }

    func testResetStopAndCompletionMatchControllerSemantics() {
        var completed = 0
        let clock = ManualCountdownClock()
        let timer = TimerController(clock: clock, refreshInterval: nil) { completed += 1 }
        timer.start(seconds: 30)
        clock.advance(by: .seconds(10))
        timer.reset()
        XCTAssertEqual(timer.timingSnapshot.phase, .ready(remaining: .seconds(30)))
        XCTAssertEqual(remaining(timer), 30)
        timer.start(seconds: 30)
        timer.stop()
        XCTAssertEqual(timer.timingSnapshot.phase, .idle)
        timer.start(seconds: 5)
        clock.advance(by: .seconds(6))
        XCTAssertEqual(remaining(timer), 0, "Never below zero")
        timer.refresh()
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(timer.timingSnapshot.phase, .idle)
    }

    func testSnapshotIsNotRepublishedByRefreshesOrClockReads() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 120)
        var publications = 0
        let cancellable = timer.$timingSnapshot.dropFirst().sink { _ in publications += 1 }
        defer { cancellable.cancel() }
        for _ in 0..<100 {
            clock.advance(by: .milliseconds(100))
            timer.refresh()
            _ = remaining(timer)
        }
        XCTAssertEqual(publications, 0, "Per-frame presentation must not publish controller state")
        timer.pause()
        XCTAssertEqual(publications, 1)
    }

    func testRemountDerivesTheSamePositionRunningAndPaused() {
        let (timer, clock) = makeTimer()
        timer.start(seconds: 60)
        clock.advance(by: .seconds(15))
        // A "remounted" view only has the controller: same snapshot, same clock.
        let first = TimerCountdownPresentation.rulerValue(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedMinutes: 25)
        let remounted = TimerCountdownPresentation.rulerValue(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedMinutes: 7)
        XCTAssertEqual(first, 0.75, accuracy: 0.0001)
        XCTAssertEqual(remounted, first, "Selection stored by a view cannot reset an active countdown")
        timer.pause()
        clock.advance(by: .seconds(100))
        XCTAssertEqual(TimerCountdownPresentation.rulerValue(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedMinutes: 3), 0.75, accuracy: 0.0001)
    }

    func testIdleRulerShowsSelectionAndActiveRulerMovesTowardZero() {
        let (timer, clock) = makeTimer()
        XCTAssertEqual(TimerCountdownPresentation.rulerValue(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedMinutes: 25), 25)
        timer.start(minutes: 25)
        var previous = TimerCountdownPresentation.rulerValue(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedMinutes: 25)
        XCTAssertEqual(previous, 25, "Starts at the full duration")
        for _ in 0..<10 {
            clock.advance(by: .seconds(30))
            let value = TimerCountdownPresentation.rulerValue(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedMinutes: 25)
            XCTAssertLessThan(value, previous, "Indicator trends toward zero, never elapsed direction")
            previous = value
        }
        XCTAssertEqual(previous, 20, accuracy: 0.0001, "Halfway-style check: 5 minutes elapsed")
        clock.advance(by: .seconds(1_199))
        XCTAssertEqual(TimerCountdownPresentation.rulerValue(snapshot: timer.timingSnapshot, now: timer.clockNow, selectedMinutes: 25), 1.0 / 60, accuracy: 0.0001, "Near zero")
    }

    func testRulerGeometryMovesTicksUnderAFixedPointer() {
        let center: CGFloat = 100
        let at25 = TimerRulerScale.x(forMinute: 25, value: 25, center: center)
        XCTAssertEqual(at25, center, "Value under pointer sits at the centre")
        let later = TimerRulerScale.x(forMinute: 25, value: 24.5, center: center)
        XCTAssertGreaterThan(later, at25, "Ruler slides so smaller values reach the pointer")
        XCTAssertEqual(later - at25, TimerRulerScale.pointsPerMinute / 2, accuracy: 0.0001)
        XCTAssertEqual(TimerRulerScale.tick(forMinute: 25).height, TimerRulerScale.majorTickHeight)
        XCTAssertEqual(TimerRulerScale.tick(forMinute: 23).height, TimerRulerScale.minuteTickHeight)
        XCTAssertGreaterThan(TimerRulerScale.majorTickHeight, TimerRulerScale.minuteTickHeight)
        XCTAssertGreaterThanOrEqual(TimerRulerScale.majorTickHeight, 20, "Taller, more substantial ticks")
        XCTAssertTrue(TimerRulerScale.tick(forMinute: 25).labelled)
        XCTAssertFalse(TimerRulerScale.tick(forMinute: 24).labelled)
    }

    func testFrameCadenceIsBoundedByPixelMotionAndStopsWhenNotRunning() {
        let (timer, _) = makeTimer()
        XCTAssertNil(TimerCountdownPresentation.frameInterval(snapshot: timer.timingSnapshot, displayScale: 2))
        timer.start(seconds: 300)
        let interval = try? XCTUnwrap(TimerCountdownPresentation.frameInterval(snapshot: timer.timingSnapshot, displayScale: 2))
        // 7 pt/min at 2x = 14 px/min; half-pixel steps need ~2.1 frames/minute... bounded to >= 30 Hz cap and <= 1 s.
        XCTAssertNotNil(interval)
        XCTAssertGreaterThanOrEqual(interval ?? 0, 1.0 / 30, "Never a 120 Hz controller-free loop for sub-pixel motion")
        XCTAssertLessThanOrEqual(interval ?? 9, 1.0, "Label and ruler update at least every second")
        timer.pause()
        XCTAssertNil(TimerCountdownPresentation.frameInterval(snapshot: timer.timingSnapshot, displayScale: 2), "Paused: no presentation loop")
    }

    func testDisplayTextUsesTheControllerRounding() {
        XCTAssertEqual(TimerCountdownPresentation.displayText(remaining: 0), "0:00")
        XCTAssertEqual(TimerCountdownPresentation.displayText(remaining: 0.2), "0:01")
        XCTAssertEqual(TimerCountdownPresentation.displayText(remaining: 59.01), "1:00")
        XCTAssertEqual(TimerCountdownPresentation.displayText(remaining: 1_500), "25:00")
    }
}

@MainActor
final class TimerRulerSnapshotTests: XCTestCase {
    /// Review fixtures, opt-in: DYNAMIC_ISLAND_TIMER_SNAPSHOT_DIR=/path swift test --filter TimerRulerSnapshotTests
    func testRenderTimerRulerReviewFixtures() async throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_TIMER_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_TIMER_SNAPSHOT_DIR for timer ruler fixtures")
        }
        let clock = ManualCountdownClock()
        let timer = TimerController(clock: clock, refreshInterval: nil)
        let settings = AppSettings(defaults: UserDefaults(suiteName: "TimerRulerSnapshot.\(UUID().uuidString)")!)
        let directory = URL(fileURLWithPath: path)
        try await render(FocusTimerView(timer: timer, settings: settings, showsPanel: false), to: directory.appendingPathComponent("timer-idle.png"))
        timer.start(minutes: 25)
        clock.advance(by: .seconds(7 * 60 + 18))
        timer.refresh()
        try await render(FocusTimerView(timer: timer, settings: settings, showsPanel: false), to: directory.appendingPathComponent("timer-running.png"))
        timer.pause()
        try await render(FocusTimerView(timer: timer, settings: settings), to: directory.appendingPathComponent("timer-paused-panel.png"))
    }

    private func render<Content: View>(_ content: Content, to url: URL) async throws {
        _ = NSApplication.shared
        let size = CGSize(width: 330, height: 150)
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .padding(12).background(Color.black).environment(\.colorScheme, .dark))
        host.frame = CGRect(origin: .zero, size: CGSize(width: size.width + 24, height: size.height + 24))
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for _ in 0..<12 { await Task.yield(); try await Task.sleep(for: .milliseconds(3)); host.layoutSubtreeIfNeeded() }
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
