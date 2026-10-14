import XCTest
@testable import DynamicIsland

final class DetachedNavigationReachabilityTests: XCTestCase {
    private let shell = CGRect(x: 100, y: 200, width: 600, height: 300)
    private let actions = CGRect(x: 200, y: 158, width: 400, height: 30)
    private let navigation = CGRect(x: 275, y: 113, width: 250, height: 42)

    func testNormalGapIsThreePointsAndRowsNeverOverlap() {
        let frame = DetachedIslandNavigationMetrics.frame(shell: shell, pageCount: 5)
        XCTAssertEqual(shell.minY - frame.maxY, 3)
        XCTAssertFalse(shell.intersects(frame))
        let gapPoint = CGPoint(x: frame.midX, y: frame.maxY + 1.5)
        XCTAssertFalse(ExpandedHoverContainment.interactiveRegions(frames: [shell, frame]).contains { $0.contains(gapPoint) })
        XCTAssertEqual(ExpandedHoverContainment.decide(pointer: gapPoint, shellFrame: shell,
            accessoryFrames: [frame], holds: []), .keepExpanded)
    }

    func testSlowFastReverseAndJitterTrajectoriesStayReachable() {
        for step: CGFloat in [1, 2, 7, 25] {
            for y in stride(from: CGFloat(210), through: CGFloat(120), by: -step) {
                for x in [CGFloat(399), 400, 401] {
                    XCTAssertEqual(ExpandedHoverContainment.decide(pointer: CGPoint(x: x, y: y),
                        shellFrame: shell, accessoryFrames: [navigation, actions], holds: []), .keepExpanded)
                }
            }
        }
        for y in stride(from: CGFloat(120), through: CGFloat(210), by: 1) {
            XCTAssertEqual(ExpandedHoverContainment.decide(pointer: CGPoint(x: 400, y: y),
                shellFrame: shell, accessoryFrames: [navigation, actions], holds: []), .keepExpanded)
        }
    }

    func testCorridorsAreHoverOnlyAndDoNotClaimDesktopBesideRows() {
        let clickRegions = ExpandedHoverContainment.interactiveRegions(frames: [shell, navigation, actions])
        for point in [CGPoint(x: 400, y: 195), CGPoint(x: 400, y: 156)] {
            XCTAssertFalse(clickRegions.contains { $0.contains(point) })
            XCTAssertEqual(ExpandedHoverContainment.decide(pointer: point, shellFrame: shell,
                accessoryFrames: [navigation, actions], holds: []), .keepExpanded)
        }
        XCTAssertEqual(ExpandedHoverContainment.decide(pointer: CGPoint(x: 210, y: 145),
            shellFrame: shell, accessoryFrames: [navigation, actions], holds: []), .collapse)
        XCTAssertEqual(ExpandedHoverContainment.decide(pointer: CGPoint(x: 400, y: 100),
            shellFrame: shell, accessoryFrames: [navigation, actions], holds: []), .collapse)
    }

    func testAccessoryDisappearanceRemovesOnlyItsOwnRegionAndProtectionStillHolds() {
        XCTAssertEqual(ExpandedHoverContainment.decide(pointer: CGPoint(x: 210, y: 165),
            shellFrame: shell, accessoryFrames: [navigation], holds: []), .collapse)
        for hold in [ExpandedHoverContainment.Holds.fileDrag, .textInput, .menuTracking, .transientInteraction] {
            XCTAssertEqual(ExpandedHoverContainment.decide(pointer: .zero, shellFrame: shell,
                accessoryFrames: [], holds: hold), .held(hold))
        }
    }
}
