import XCTest
@testable import DynamicIsland

final class ExpandedIslandRightStackVisibilityTests: XCTestCase {
    func testBothExpandedSectionsVisible() {
        let visibility = ExpandedIslandRightStackVisibility.resolve(
            liveActivitiesEnabled: true,
            showExpandedLiveActivitiesSection: true,
            shortcutsEnabled: true
        )

        XCTAssertTrue(visibility.showsLiveActivities)
        XCTAssertTrue(visibility.showsShortcuts)
        XCTAssertTrue(visibility.showsRightStack)
    }

    func testHiddenExpandedLiveActivitiesKeepsShortcutsVisible() {
        let visibility = ExpandedIslandRightStackVisibility.resolve(
            liveActivitiesEnabled: true,
            showExpandedLiveActivitiesSection: false,
            shortcutsEnabled: true
        )

        XCTAssertFalse(visibility.showsLiveActivities)
        XCTAssertTrue(visibility.showsShortcuts)
        XCTAssertTrue(visibility.showsRightStack)
    }

    func testDisabledMasterSwitchHidesExpandedLiveActivitiesOnly() {
        let visibility = ExpandedIslandRightStackVisibility.resolve(
            liveActivitiesEnabled: false,
            showExpandedLiveActivitiesSection: true,
            shortcutsEnabled: true
        )

        XCTAssertFalse(visibility.showsLiveActivities)
        XCTAssertTrue(visibility.showsShortcuts)
        XCTAssertTrue(visibility.showsRightStack)
    }

    func testLiveActivitiesRemainAsOnlyRightStackSection() {
        let visibility = ExpandedIslandRightStackVisibility.resolve(
            liveActivitiesEnabled: true,
            showExpandedLiveActivitiesSection: true,
            shortcutsEnabled: false
        )

        XCTAssertTrue(visibility.showsLiveActivities)
        XCTAssertFalse(visibility.showsShortcuts)
        XCTAssertTrue(visibility.showsRightStack)
    }

    func testRightStackHiddenWhenBothSectionsUnavailable() {
        let visibility = ExpandedIslandRightStackVisibility.resolve(
            liveActivitiesEnabled: true,
            showExpandedLiveActivitiesSection: false,
            shortcutsEnabled: false
        )

        XCTAssertFalse(visibility.showsLiveActivities)
        XCTAssertFalse(visibility.showsShortcuts)
        XCTAssertFalse(visibility.showsRightStack)
    }
}
