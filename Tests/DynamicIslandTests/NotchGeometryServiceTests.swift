import AppKit
import XCTest
@testable import DynamicIsland

final class NotchGeometryServiceTests: XCTestCase {
    func testInfersHardwareNotchFromAuxiliaryAreas() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
            auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 620, height: 210)
        )

        XCTAssertTrue(geometry.hasHardwareNotch)
        XCTAssertEqual(geometry.notchRect, CGRect(x: 635, y: 944, width: 242, height: 38))
        XCTAssertEqual(geometry.collapsedFrame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.width, 254, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.height, 40, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 760, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.height, 260, accuracy: 0.5)
        XCTAssertLessThan(geometry.expandedFrame.width / snapshot.frame.width, 0.52)
        XCTAssertEqual(geometry.canvas.frame.maxY, snapshot.frame.maxY, accuracy: 0.5)
        XCTAssertTrue(geometry.canvas.frame.contains(geometry.collapsedFrame))
        XCTAssertTrue(geometry.canvas.frame.contains(geometry.expandedFrame))
        XCTAssertEqual(geometry.canvas.collapsedSurfaceFrame, CGRect(x: 253, y: 220, width: 254, height: 40))
        XCTAssertEqual(geometry.canvas.expandedSurfaceFrame, CGRect(x: 0, y: 0, width: 760, height: 260))
    }

    func testProductionCollapsedSizeIsIgnoredOnNotchedScreen() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
            auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 520, height: 58),
            expandedSize: CGSize(width: 900, height: 300)
        )

        XCTAssertEqual(geometry.collapsedFrame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.width, 254, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.height, 40, accuracy: 0.5)
        XCTAssertTrue((226...254).contains(geometry.collapsedFrame.width))
        XCTAssertEqual(
            geometry.canvas.collapsedSurfaceFrame,
            geometry.collapsedFrame.offsetBy(dx: -geometry.canvas.frame.minX, dy: -geometry.canvas.frame.minY)
        )
        XCTAssertEqual(
            geometry.canvas.expandedSurfaceFrame,
            geometry.expandedFrame.offsetBy(dx: -geometry.canvas.frame.minX, dy: -geometry.canvas.frame.minY)
        )
    }

    func testExpandedFrameStaysScreenCenteredWhenNotchIsOffCenter() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 600, height: 38),
            auxiliaryTopRightArea: CGRect(x: 850, y: 944, width: 662, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 620, height: 210)
        )

        XCTAssertEqual(geometry.collapsedFrame.midX, 725, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.midX, 756, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, 982, accuracy: 0.5)
        XCTAssertLessThanOrEqual(geometry.expandedFrame.width, 760)
    }

    func testExpandedFrameKeepsSideMarginsOnNarrowScreens() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 900, height: 700),
            visibleFrame: CGRect(x: 0, y: 0, width: 900, height: 662),
            safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 662, width: 340, height: 38),
            auxiliaryTopRightArea: CGRect(x: 560, y: 662, width: 340, height: 38)
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 1180, height: 210)
        )

        XCTAssertEqual(geometry.expandedFrame.minX, 140, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxX, 760, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.midX, 450, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 620, accuracy: 0.5)
    }

    func testUsesFloatingIslandWhenNoNotchExists() {
        let service = NotchGeometryService()
        let snapshot = ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            safeAreaInsets: NSEdgeInsetsZero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        let geometry = service.geometry(
            for: snapshot,
            collapsedSize: CGSize(width: 224, height: 42),
            expandedSize: CGSize(width: 620, height: 210)
        )

        XCTAssertFalse(geometry.hasHardwareNotch)
        XCTAssertNil(geometry.notchRect)
        XCTAssertEqual(geometry.collapsedFrame.midX, 960, accuracy: 0.5)
        XCTAssertEqual(geometry.collapsedFrame.maxY, 1072, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.maxY, 1070, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.width, 760, accuracy: 0.5)
        XCTAssertEqual(geometry.expandedFrame.height, 260, accuracy: 0.5)
        XCTAssertEqual(geometry.canvas.frame, CGRect(x: 580, y: 810, width: 760, height: 270))
        XCTAssertEqual(geometry.canvas.collapsedSurfaceFrame, CGRect(x: 268, y: 220, width: 224, height: 42))
        XCTAssertEqual(geometry.canvas.expandedSurfaceFrame, CGRect(x: 0, y: 0, width: 760, height: 260))
    }
}
