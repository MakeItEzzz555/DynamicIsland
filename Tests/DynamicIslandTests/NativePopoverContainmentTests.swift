import CoreGraphics
import XCTest
@testable import DynamicIsland

/// A date-picker popover is a separate AppKit window: the pointer leaves the
/// island shell to use it. That must never collapse the island, and closing it
/// must return normal containment with no stuck state.
@MainActor
final class NativePopoverContainmentTests: XCTestCase {
    private let shell = CGRect(x: 100, y: 800, width: 600, height: 300)
    private let insidePopover = CGPoint(x: 400, y: 700)

    func testVisiblePopoverWindowHoldsTheIslandOpen() {
        XCTAssertEqual(ExpandedHoverContainment.decide(pointer: insidePopover, shellFrame: shell, holds: []), .collapse)
        XCTAssertEqual(
            ExpandedHoverContainment.decide(pointer: insidePopover, shellFrame: shell, holds: [.nativePopover]),
            .held([.nativePopover])
        )
    }

    func testTransientNativeWindowClassifier() {
        XCTAssertTrue(ExpandedHoverContainment.isTransientNativeWindow(className: "_NSPopoverWindow", isVisible: true, isIslandPanel: false))
        XCTAssertTrue(ExpandedHoverContainment.isTransientNativeWindow(className: "NSDatePickerCalendarOverlayWindow", isVisible: true, isIslandPanel: false))
        XCTAssertFalse(ExpandedHoverContainment.isTransientNativeWindow(className: "_NSPopoverWindow", isVisible: false, isIslandPanel: false),
                       "a closed popover releases the hold")
        XCTAssertFalse(ExpandedHoverContainment.isTransientNativeWindow(className: "IslandOverlayPanel", isVisible: true, isIslandPanel: true))
        XCTAssertFalse(ExpandedHoverContainment.isTransientNativeWindow(className: "NSWindow", isVisible: true, isIslandPanel: false),
                       "Settings and other app windows are not transient island surfaces")
    }

    func testTransientInteractionOwnersAreIndependentAndNeverStick() {
        let store = IslandLayoutStore()
        store.setTransientInteraction(true, owner: .calendarDatePicker)
        store.setTransientInteraction(true, owner: .agentsLauncher)
        store.setTransientInteraction(false, owner: .agentsLauncher)
        XCTAssertTrue(store.isTransientInteractionActive, "closing the launcher must not release the calendar's hold")
        store.setTransientInteraction(false, owner: .calendarDatePicker)
        XCTAssertFalse(store.isTransientInteractionActive)
        store.setTransientInteraction(false, owner: .calendarDatePicker)
        store.setTransientInteraction(true, owner: .calendarDatePicker)
        store.setTransientInteraction(true, owner: .calendarDatePicker)
        store.setTransientInteraction(false, owner: .calendarDatePicker)
        XCTAssertFalse(store.isTransientInteractionActive, "repeated open/close is idempotent")
    }

    func testMenuTrackingHoldIsUnaffected() {
        XCTAssertEqual(
            ExpandedHoverContainment.decide(pointer: insidePopover, shellFrame: shell, holds: [.menuTracking]),
            .held([.menuTracking])
        )
        var menus = NativeMenuTrackingLifecycle()
        menus.begin(); menus.end()
        XCTAssertFalse(menus.isTracking)
    }
}
