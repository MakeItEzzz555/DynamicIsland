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
    }
}
