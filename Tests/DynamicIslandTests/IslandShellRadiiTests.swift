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

    func testCollapsedPresentationProfileControlsOnlyCollapsedBottomRadius() {
        XCTAssertEqual(
            IslandShellRadii.interpolated(
                progress: 0,
                isNotchIntegrated: true,
                collapsedBottom: CollapsedPresentationProfile.agentRoutine(
                    leftContentWidth: 60,
                    rightContentWidth: 80
                ).bottomCornerRadius
            ),
            IslandShellRadii(top: 6, bottom: 16)
        )
        XCTAssertEqual(
            IslandShellRadii.interpolated(
                progress: 0,
                isNotchIntegrated: true,
                collapsedBottom: CollapsedPresentationProfile.agentAttention(
                    leftContentWidth: 90,
                    rightContentWidth: 110
                ).bottomCornerRadius
            ),
            IslandShellRadii(top: 6, bottom: 24)
        )
        XCTAssertEqual(
            IslandShellRadii.interpolated(progress: 1, isNotchIntegrated: true, collapsedBottom: 19),
            IslandShellRadii(top: 19, bottom: 24)
        )
    }

    @MainActor
    func testReduceMotionUsesBoundedShellTimingWithoutChangingGeometryProfile() {
        let settings = AppSettings()
        let profile = CollapsedPresentationProfile.agentAttention(
            leftContentWidth: 90,
            rightContentWidth: 110
        )

        XCTAssertEqual(IslandContentTransitionTiming.shellDuration(settings: settings, reduceMotion: true), 0.24)
        XCTAssertEqual(profile.kind, .agentAttention)
        XCTAssertEqual(profile.heightDelta, 60)
    }
}
