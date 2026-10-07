import XCTest
@testable import DynamicIsland

final class IslandShellRadiiTests: XCTestCase {
    func testNotchAwareContentPaddingResolution() {
        XCTAssertEqual(IslandShellLayout.collapsedHorizontalPadding(isNotchIntegrated: true), 8)
        XCTAssertEqual(IslandShellLayout.collapsedHorizontalPadding(isNotchIntegrated: false), 8)
        // Shell hugging (2026-10-06): a 12 pt visible inset. The integrated
        // shell adds its concave top "ear" (the expanded top radius).
        let ear = IslandShellRadii.interpolated(progress: 1, isNotchIntegrated: true).top
        XCTAssertEqual(IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: false), 12)
        XCTAssertEqual(IslandShellLayout.expandedHorizontalPadding(isNotchIntegrated: true), ear + 12)
        // The content corner (inset, bottom padding) stays inside the shell's
        // rounded bottom corner.
        let bottom = IslandShellRadii.interpolated(progress: 1, isNotchIntegrated: true).bottom
        let corner = CGPoint(x: 12, y: IslandShellLayout.expandedBottomPadding)
        XCTAssertLessThanOrEqual(hypot(bottom - corner.x, bottom - corner.y), bottom, "content clears the rounded corner")
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

    func testNotchIntegrationStaysTrueWhenEitherIndependentSignalStillSeesHardwareNotch() {
        XCTAssertFalse(
            IslandShellNotchIntegration.resolve(
                geometryHasHardwareNotch: false,
                displayMetricsHaveHardwareNotch: false
            )
        )
        XCTAssertTrue(
            IslandShellNotchIntegration.resolve(
                geometryHasHardwareNotch: true,
                displayMetricsHaveHardwareNotch: false
            )
        )
        XCTAssertTrue(
            IslandShellNotchIntegration.resolve(
                geometryHasHardwareNotch: false,
                displayMetricsHaveHardwareNotch: true
            )
        )
        XCTAssertTrue(
            IslandShellNotchIntegration.resolve(
                geometryHasHardwareNotch: true,
                displayMetricsHaveHardwareNotch: true
            )
        )
    }

    func testShellPathGeometryKeepsFiniteRoundedRadiiAcrossCollapsedAndMorphFrames() throws {
        let cases: [(CGRect, CGFloat, CGFloat)] = [
            (CGRect(x: 0, y: 0, width: 216, height: 34), 6, 14),
            (CGRect(x: 0, y: 0, width: 260, height: 42), 9, 17),
            (CGRect(x: 0, y: 0, width: 393, height: 66), 12.5, 19),
            (CGRect(x: 0, y: 0, width: 676, height: 260), 19, 24),
        ]

        for (rect, top, bottom) in cases {
            let radii = try XCTUnwrap(
                IslandShellPathGeometry.resolvedRadii(
                    in: rect,
                    topCornerRadius: top,
                    bottomCornerRadius: bottom
                )
            )
            XCTAssertGreaterThan(radii.top, 0)
            XCTAssertGreaterThan(radii.bottom, 0)
            XCTAssertTrue(radii.top.isFinite)
            XCTAssertTrue(radii.bottom.isFinite)
            XCTAssertLessThanOrEqual(radii.top, rect.height)
            XCTAssertLessThanOrEqual(radii.bottom, rect.height)
        }
    }

    func testGlowContourUsesSameGeometryButNeverClosesAcrossPhysicalNotch() {
        let rect = CGRect(x: 0, y: 0, width: 216, height: 34)
        let shell = IslandShellPathGeometry.path(
            in: rect,
            topCornerRadius: 6,
            bottomCornerRadius: 14,
            closesAcrossNotch: true
        )
        let glow = IslandShellPathGeometry.path(
            in: rect,
            topCornerRadius: 6,
            bottomCornerRadius: 14,
            closesAcrossNotch: false
        )

        var shellCloseCount = 0
        var glowCloseCount = 0
        shell.forEach { element in
            if case .closeSubpath = element { shellCloseCount += 1 }
        }
        glow.forEach { element in
            if case .closeSubpath = element { glowCloseCount += 1 }
        }

        XCTAssertEqual(shellCloseCount, 1)
        XCTAssertEqual(glowCloseCount, 0)
        XCTAssertEqual(shell.boundingRect, glow.boundingRect)
    }

}
