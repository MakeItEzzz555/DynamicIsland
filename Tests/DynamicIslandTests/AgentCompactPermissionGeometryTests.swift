import AppKit
import XCTest
@testable import DynamicIsland

final class AgentCompactPermissionGeometryTests: XCTestCase {
    func testHoverGrowsBothAxesWithoutMovingNotchAnchorAndReverses() {
        let service = NotchGeometryService()
        let snapshots = [
            ScreenSnapshot(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 944),
                safeAreaInsets: NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 0),
                auxiliaryTopLeftArea: CGRect(x: 0, y: 944, width: 635, height: 38),
                auxiliaryTopRightArea: CGRect(x: 877, y: 944, width: 635, height: 38)),
            ScreenSnapshot(frame: CGRect(x: 0, y: 0, width: 800, height: 600),
                visibleFrame: CGRect(x: 0, y: 0, width: 800, height: 575),
                safeAreaInsets: NSEdgeInsets(), auxiliaryTopLeftArea: nil, auxiliaryTopRightArea: nil)
        ]
        for snapshot in snapshots {
            func frame(_ hovered: Bool, reduced: Bool = false) -> CGRect {
                service.geometry(for: snapshot, collapsedSize: CGSize(width: 224, height: 34),
                    expandedSize: CGSize(width: 720, height: 446), collapsedActivityProfile: nil,
                    collapsedPresentationProfile: .agentPermission(hovered: hovered, reduceMotion: reduced)).collapsedFrame
            }
            let base = frame(false), hover = frame(true)
            XCTAssertGreaterThan(base.width, 330)
            XCTAssertGreaterThanOrEqual(base.height, 102)
            XCTAssertEqual(hover.width - base.width, 20, accuracy: 1)
            XCTAssertEqual(hover.height - base.height, 8, accuracy: 1)
            XCTAssertEqual(base.maxY, hover.maxY)
            XCTAssertEqual(base.midX, hover.midX)
            XCTAssertEqual(frame(false), base)
            XCTAssertEqual(frame(true, reduced: true), frame(false, reduced: true))
            XCTAssertTrue(snapshot.frame.contains(hover))
        }
        XCTAssertEqual(AgentCompactPermissionMotion.duration, 0.15)
        XCTAssertLessThan(AgentCompactPermissionMotion.shadowOpacity, 0.25)
        XCTAssertLessThan(AgentCompactPermissionMotion.shadowRadius, 10)
        XCTAssertGreaterThan(AgentCompactPermissionMotion.shadowY, 0)
    }

    func testStandaloneRowsAreAbsentAndControlsBelongToComposer() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let activity = try String(contentsOf: root.appendingPathComponent("Sources/DynamicIsland/Views/AgentActivityViews.swift"), encoding: .utf8)
        let chat = try String(contentsOf: root.appendingPathComponent("Sources/DynamicIsland/Views/AgentWorkspaceViews.swift"), encoding: .utf8)
        let console = try String(contentsOf: root.appendingPathComponent("Sources/DynamicIsland/Views/AgentConsoleViews.swift"), encoding: .utf8)
        XCTAssertFalse(activity.contains("stagedAgentContent(index: 2)"))
        XCTAssertFalse(chat.contains("reasoningControl"))
        XCTAssertTrue(activity.contains("composerControls: AnyView(AgentCLIControlBar("))
        XCTAssertTrue(console.contains("AgentComposerContainer {\n                    if let composerControls"))
        XCTAssertTrue(activity.contains("reasoningControl(for: session, compact: compact)"))
        let island = try String(contentsOf: root.appendingPathComponent("Sources/DynamicIsland/Views/IslandRootView.swift"), encoding: .utf8)
        XCTAssertTrue(island.contains("guard settings.expandOnClick, compactPermission == nil"))
        XCTAssertTrue(island.contains(".shadow(color: .black.opacity"))
    }
}
