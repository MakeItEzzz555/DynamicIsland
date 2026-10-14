import AppKit
import QuartzCore
import XCTest
@testable import DynamicIsland

@MainActor
final class NormalCollapseDisplayBeatTests: XCTestCase {
    func testBeatCompletesOnDisplayCallbacksAndCancelsExactlyOnce() async throws {
        let window = try fixture()
        defer { window.close() }
        let done = expectation(description: "two real display callbacks")
        var completions = 0
        let started = CACurrentMediaTime()
        let beat = NormalCollapseDisplayBeat(view: window.contentView!, isCurrent: { true }) {
            completions += 1; done.fulfill()
        }
        defer { beat.cancel() }
        await fulfillment(of: [done], timeout: 2)
        beat.cancel(); beat.cancel()
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(beat.deliveredFrameCount, 2)
        XCTAssertGreaterThan(CACurrentMediaTime() - started, 0)
    }

    func testCancelledOrStaleBeatNeverCompletes() async throws {
        let window = try fixture()
        defer { window.close() }
        var completions = 0
        let cancelled = NormalCollapseDisplayBeat(view: window.contentView!, isCurrent: { true }) { completions += 1 }
        cancelled.cancel()
        let stale = NormalCollapseDisplayBeat(view: window.contentView!, isCurrent: { false }) { completions += 1 }
        defer { stale.cancel() }
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(completions, 0)
    }

    func testNewCollapseRejectsOldLogicalCompletionBeforeSchedulingBeat() {
        let layout = IslandLayoutStore()
        let old = layout.beginNormalCollapsedReturn()
        let new = layout.beginNormalCollapsedReturn()
        XCTAssertFalse(layout.isCurrentNormalCollapsedReturn(generation: old))
        XCTAssertTrue(layout.isCurrentNormalCollapsedReturn(generation: new))
        layout.cancelNormalCollapsedReturn()
        XCTAssertFalse(layout.isCurrentNormalCollapsedReturn(generation: new))
    }

    private func fixture() throws -> NSWindow {
        try XCTSkipIf(CGDisplayIsActive(CGMainDisplayID()) == 0 || CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            "Display-linked timing requires an awake display.")
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let window = NSWindow(contentRect: CGRect(x: screen.frame.midX - 50, y: screen.frame.midY - 50,
            width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.orderFrontRegardless()
        return window
    }
}
