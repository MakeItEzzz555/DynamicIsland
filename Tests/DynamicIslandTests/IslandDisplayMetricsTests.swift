import AppKit
import XCTest
@testable import DynamicIsland

final class IslandDisplayMetricsTests: XCTestCase {
    private func snapshot(
        width: CGFloat,
        height: CGFloat,
        scale: CGFloat = 2,
        notched: Bool = false,
        builtIn: Bool = true
    ) -> IslandDisplaySnapshot {
        let frame = CGRect(x: 0, y: 0, width: width, height: height)
        let top: CGFloat = notched ? 32 : 0
        let left = notched
            ? CGRect(x: 0, y: height - top, width: (width - 180) / 2, height: top)
            : nil
        let right = notched
            ? CGRect(x: (width + 180) / 2, y: height - top, width: (width - 180) / 2, height: top)
            : nil
        return IslandDisplaySnapshot(
            frame: frame,
            visibleFrame: CGRect(x: 0, y: 0, width: width, height: height - 26),
            safeAreaInsets: NSEdgeInsets(top: top, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: left,
            auxiliaryTopRightArea: right,
            backingScaleFactor: scale,
            displayID: nil,
            isBuiltIn: builtIn,
            pixelSize: CGSize(width: width * scale, height: height * scale)
        )
    }

    func testRepresentativeMacDisplayMatrixStaysWithinTokenBounds() {
        let sizes: [CGSize] = [
            .init(width: 1280, height: 720),
            .init(width: 1366, height: 768),
            .init(width: 1440, height: 900),
            .init(width: 1512, height: 982),
            .init(width: 1728, height: 1117),
            .init(width: 1680, height: 1050),
            .init(width: 1920, height: 1080),
            .init(width: 1920, height: 1200),
            .init(width: 2560, height: 1440),
            .init(width: 2560, height: 1600),
            .init(width: 3440, height: 1440),
            .init(width: 3840, height: 2160),
            .init(width: 5120, height: 2880),
            .init(width: 6016, height: 3384)
        ]

        for size in sizes {
            for scale in [CGFloat(1), 2] {
                let m = IslandDisplayMetricsResolver.resolve(
                    snapshot(width: size.width, height: size.height, scale: scale)
                )
                XCTAssertTrue(m.uiScale.isFinite)
                XCTAssertGreaterThanOrEqual(m.uiScale, 0.90)
                XCTAssertLessThanOrEqual(m.uiScale, 1.12)
                XCTAssertGreaterThanOrEqual(m.typographyScale, 0.94)
                XCTAssertLessThanOrEqual(m.typographyScale, 1.10)
                XCTAssertGreaterThanOrEqual(m.transcriptFontSize, 9)
                XCTAssertLessThanOrEqual(m.transcriptFontSize, 10.8)
                XCTAssertGreaterThanOrEqual(m.workspaceTileMinimumHeight, 44)
                XCTAssertLessThanOrEqual(m.workspaceTileMinimumHeight, 58)
            }
        }
    }

    func testBackingScaleDoesNotDoubleScaleUILayout() {
        let one = IslandDisplayMetricsResolver.resolve(snapshot(width: 1512, height: 982, scale: 1))
        let two = IslandDisplayMetricsResolver.resolve(snapshot(width: 1512, height: 982, scale: 2))

        XCTAssertEqual(one.uiScale, two.uiScale, accuracy: 0.0001)
        XCTAssertEqual(one.typographyScale, two.typographyScale, accuracy: 0.0001)
        XCTAssertEqual(one.expandedShellScale, two.expandedShellScale, accuracy: 0.0001)
        XCTAssertEqual(one.pixelSize.width * 2, two.pixelSize.width, accuracy: 0.0001)
    }

    func testNotchDetectionDependsOnRuntimeSafeAreaGeometryNotModelName() {
        let notched = IslandDisplayMetricsResolver.resolve(
            snapshot(width: 1512, height: 982, notched: true)
        )
        let floating = IslandDisplayMetricsResolver.resolve(
            snapshot(width: 1512, height: 982, notched: false)
        )

        XCTAssertTrue(notched.hasHardwareNotch)
        XCTAssertFalse(floating.hasHardwareNotch)
    }

    func testGeneratedLogicalRangeNeverProducesInvalidTokens() {
        for width in stride(from: CGFloat(960), through: 6400, by: 211) {
            for height in stride(from: CGFloat(640), through: 3600, by: 173) {
                let m = IslandDisplayMetricsResolver.resolve(snapshot(width: width, height: height))
                let values = [
                    m.uiScale, m.typographyScale, m.iconScale, m.spacingScale,
                    m.compactControlScale, m.expandedCardScale,
                    m.collapsedSideContentScale, m.cornerRadiusScale,
                    m.expandedShellScale, m.hudSliderHeight,
                    m.transcriptFontSize, m.workspaceTileMinimumHeight
                ]
                XCTAssertTrue(values.allSatisfy { $0.isFinite && $0 > 0 })
            }
        }
    }

    func testExpandedLayoutMetricsRemainFiniteAtSmallAndLargeSizes() {
        let displays = [
            IslandDisplayMetricsResolver.resolve(snapshot(width: 1280, height: 720)),
            IslandDisplayMetricsResolver.resolve(snapshot(width: 1728, height: 1117, notched: true)),
            IslandDisplayMetricsResolver.resolve(snapshot(width: 6016, height: 3384, scale: 2))
        ]

        for display in displays {
            let shell = CGSize(
                width: 760 * display.expandedShellScale,
                height: 260 * display.expandedShellScale
            )
            let metrics = ExpandedIslandLayoutMetrics(
                containerSize: shell,
                horizontalPadding: 41 * display.spacingScale,
                displayMetrics: display
            )
            let finite = [
                metrics.innerWidth, metrics.innerHeight, metrics.pageHeight,
                metrics.rightStackWidth, metrics.mediaColumnWidth,
                metrics.timerRingSize, metrics.statsCardHeight
            ]
            XCTAssertTrue(finite.allSatisfy { $0.isFinite && $0 >= 0 })
            XCTAssertLessThanOrEqual(metrics.rightStackWidth, metrics.innerWidth)
        }
    }
}
