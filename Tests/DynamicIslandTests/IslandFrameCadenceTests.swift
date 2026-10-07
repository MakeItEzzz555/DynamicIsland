import XCTest
@testable import DynamicIsland

/// ProMotion cadence: decorations follow the display instead of a fixed
/// 24/30 Hz cap; always-on ambient effects stay at 60 Hz; Low Power caps all.
@MainActor
final class IslandFrameCadenceTests: XCTestCase {
    func testExpandedDecorationsFollowTheDisplayRefreshRate() {
        XCTAssertEqual(IslandFrameCadence.interval(.expandedDecoration, displayRate: 120, lowPower: false), 1.0 / 120, accuracy: 1e-9)
        XCTAssertEqual(IslandFrameCadence.interval(.expandedDecoration, displayRate: 60, lowPower: false), 1.0 / 60, accuracy: 1e-9)
    }

    func testAmbientCollapsedEffectsStayAtSixtyHertz() {
        XCTAssertEqual(IslandFrameCadence.interval(.ambient, displayRate: 120, lowPower: false), 1.0 / 60, accuracy: 1e-9)
        XCTAssertEqual(IslandFrameCadence.interval(.ambient, displayRate: 48, lowPower: false), 1.0 / 48, accuracy: 1e-9)
    }

    func testLowPowerCapsEveryDecorationAndInvalidRatesStayFinite() {
        for surface in [IslandFrameCadence.Surface.expandedDecoration, .ambient] {
            XCTAssertEqual(IslandFrameCadence.interval(surface, displayRate: 120, lowPower: true), 1.0 / 30, accuracy: 1e-9)
        }
        XCTAssertEqual(IslandFrameCadence.interval(.expandedDecoration, displayRate: 0, lowPower: false), 1.0 / 30, accuracy: 1e-9)
    }

    func testNoDecorationIsHeldBelowSixtyHertzOnAProMotionDisplay() {
        for surface in [IslandFrameCadence.Surface.expandedDecoration, .ambient] {
            XCTAssertLessThanOrEqual(IslandFrameCadence.interval(surface, displayRate: 120, lowPower: false), 1.0 / 60 + 1e-9)
        }
    }
}

/// Editor motion tokens (Droppy press/release vs. reorder reflow).
@MainActor
final class WorkspaceEditorMotionTokenTests: XCTestCase {
    func testReduceMotionRemovesEverySpatialAnimation() {
        XCTAssertNil(WorkspaceEditorMotion.hover(entering: true, reduceMotion: true))
        XCTAssertNil(WorkspaceEditorMotion.hover(entering: false, reduceMotion: true))
        XCTAssertNil(WorkspaceEditorMotion.reorder(reduceMotion: true))
        XCTAssertNil(WorkspaceEditorMotion.resize(reduceMotion: true))
    }

    func testPressIsQuickerThanReleaseAndBothQuickerThanReflow() {
        XCTAssertNotNil(WorkspaceEditorMotion.hover(entering: true, reduceMotion: false))
        XCTAssertLessThan(WorkspaceEditorMotion.pressResponse, WorkspaceEditorMotion.releaseResponse)
        XCTAssertLessThan(WorkspaceEditorMotion.releaseResponse, WorkspaceEditorMotion.reorderDuration,
                          "target feedback answers before neighbours finish moving")
        XCTAssertGreaterThan(WorkspaceEditorMotion.pressDamping, WorkspaceEditorMotion.releaseDamping)
    }
}

/// Droppy shell architecture: SwiftUI owns the visible morph; the panel frame
/// never animates in AppKit; open/close springs are asymmetric.
@MainActor
final class DroppyShellMotionParityTests: XCTestCase {
    func testThePanelFrameNeverAnimatesInAppKit() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/DynamicIsland/Overlay/OverlayWindowController.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(source.contains("animator().setFrame"), "two animation engines would fight (Droppy: animate: false)")
        XCTAssertTrue(source.contains("morphInsideStablePanel"))
    }

    func testCloseIsMoreDampedAndQuickerThanOpen() {
        XCTAssertGreaterThan(WorkspaceMotion.shellCloseDamping, WorkspaceMotion.shellOpenDamping)
        XCTAssertLessThan(WorkspaceMotion.shellCloseResponseRatio, 1)
        XCTAssertEqual(WorkspaceMotion.shellOpenDamping, 0.90, accuracy: 1e-9, "Droppy expandOpen")
        XCTAssertEqual(WorkspaceMotion.shellCloseDamping, 0.97, accuracy: 1e-9, "Droppy expandClose")
    }

    func testDisplayTuningMatchesDroppy() {
        XCTAssertEqual(WorkspaceMotion.motionScale(refreshRate: 120), 1.0)
        XCTAssertEqual(WorkspaceMotion.motionScale(refreshRate: 90), 1.1)
        XCTAssertEqual(WorkspaceMotion.motionScale(refreshRate: 60), 1.18)
    }
}
