import XCTest
@testable import DynamicIsland

final class IslandWidgetLayoutTests: XCTestCase {
    func testStoredLayoutPreservesOrderAndRejectsUnknownOrDuplicateWidgets() {
        let layout = IslandWidgetLayout(stored: "timer,calendar,timer,unknown,media")
        XCTAssertEqual(layout.widgets, [.timer, .calendar, .media])
        XCTAssertEqual(IslandWidgetLayout(stored: layout.stored), layout)
    }
    func testReorderRetainsIdentityAndDoesNotDuplicateWidget() {
        var layout = IslandWidgetLayout.initial
        layout.move(.clipboard, before: .media)
        XCTAssertEqual(layout.widgets, [.clipboard, .media, .files])
        layout.move(.clipboard, before: .clipboard)
        layout.move(.timer, before: .media)
        XCTAssertEqual(layout.widgets, [.clipboard, .media, .files])
    }
    func testAddRemoveCancelDraftAndKeyboardReorder() {
        let saved = IslandWidgetLayout.initial
        var draft = saved
        draft.toggle(.timer)
        draft.shift(.timer, by: -1)
        XCTAssertEqual(draft.widgets, [.media, .files, .timer, .clipboard])
        draft.toggle(.media)
        XCTAssertEqual(saved, .initial, "editing a draft does not change persisted layout")
        XCTAssertEqual(draft.widgets, [.files, .timer, .clipboard])
    }
    func testRulerDragAndSafeBounds() {
        XCTAssertEqual(TimerRulerScale.dragged(from: 25, translation: 35), 20)
        XCTAssertEqual(TimerRulerScale.dragged(from: 25, translation: -35), 30)
        XCTAssertEqual(TimerRulerScale.minutes(-100), 1)
        XCTAssertEqual(TimerRulerScale.minutes(.greatestFiniteMagnitude), 180)
        XCTAssertEqual(TimerRulerScale.minutes(.nan), 25)
    }
}
