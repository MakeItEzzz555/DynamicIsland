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
