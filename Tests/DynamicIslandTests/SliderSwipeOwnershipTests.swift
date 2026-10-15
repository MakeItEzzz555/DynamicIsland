import XCTest
@testable import DynamicIsland

@MainActor
final class SliderSwipeOwnershipTests: XCTestCase {
    func testDragStartingInsidePillNeverNavigatesWhileOutsideSwipeStill() {
        let layout = IslandLayoutStore()
        let pill = CGRect(x: 100, y: 200, width: 200, height: 30)
        layout.setNativeControlRegion(pill, owner: UUID())
        var level = 0.5
        for direction in [CGFloat(1), -1, 1, -1] {
            // Pointer travels well past either end of the pill (0%/100% boundary).
            let start = CGPoint(x: direction > 0 ? 110 : 290, y: 215)
            let translation = CGSize(width: direction * 400, height: 2)
            XCTAssertNil(IslandPointerGestureModifier.swipe(translation: translation, start: start,
                                                            layoutStore: layout, sensitivity: 1))
            level = AppVolumePill.level(atX: start.x - pill.minX + translation.width, width: pill.width)
            XCTAssertEqual(level, direction > 0 ? 1 : 0)
        }
        let outside = IslandPointerGestureModifier.swipe(translation: CGSize(width: -400, height: 2),
            start: CGPoint(x: 110, y: 100), layoutStore: layout, sensitivity: 1)
        XCTAssertEqual(outside, .swipeLeft)
    }
}
