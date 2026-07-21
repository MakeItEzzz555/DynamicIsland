import XCTest
@testable import DynamicIsland

final class IslandShellRadiiTests: XCTestCase {
    func testNotchAwareContentPaddingResolution() {
        XCTAssertEqual(IslandShellLayout.collapsedHorizontalPadding(isNotchIntegrated: true), 8)
        XCTAssertEqual(IslandShellLayout.collapsedHorizontalPadding(isNotchIntegrated: false), 8)
        XCTAssertEqual(IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true), 41)
        XCTAssertEqual(IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: false), 22)
        XCTAssertEqual(IslandShellLayout.collapsedBottomPadding, 6)
    }

    func testPhysicalNotchRadiusEndpointsAndMidpoint() {
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: 0, isNotchIntegrated: true),
            IslandShellRadii(top: 6, bottom: 14)
        )
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: 0.5, isNotchIntegrated: true),
            IslandShellRadii(top: 12.5, bottom: 19)
        )
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: 1, isNotchIntegrated: true),
            IslandShellRadii(top: 19, bottom: 24)
        )
    }

    func testNonNotchShellKeepsPlainTopEdge() {
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: 0.5, isNotchIntegrated: false),
            IslandShellRadii(top: 0, bottom: 19)
        )
    }

    func testProgressClampsAndInvalidProgressFallsBackSafely() {
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: -1, isNotchIntegrated: true),
            IslandShellRadii(top: 6, bottom: 14)
        )
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: 2, isNotchIntegrated: true),
            IslandShellRadii(top: 19, bottom: 24)
        )
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: .nan, isNotchIntegrated: true),
            IslandShellRadii(top: 6, bottom: 14)
        )
    }
}
