import XCTest
@testable import DynamicIsland

@MainActor
final class AgentWorkspacePresentationTests: XCTestCase {
    func testModeSelectionAndEmphasisDoNotReplaceTerminalOrSelectedAgent() {
        let presentation = AgentWorkspacePresentation()
        XCTAssertEqual(presentation.mode, .feed)
        XCTAssertEqual(presentation.interactionMode, .chat)
        presentation.interact(.terminal)
        XCTAssertEqual(presentation.mode, .terminal)
        XCTAssertEqual(presentation.terminalFocusRequest, 1)
        presentation.toggleEmphasis()
        presentation.select(.feed)
        XCTAssertTrue(presentation.isEmphasized)
        XCTAssertEqual(presentation.interactionMode, .terminal, "Operational page is separate from interaction intent")
        presentation.interact(.chat)
        XCTAssertEqual(presentation.mode, .feed)
        XCTAssertEqual(presentation.terminalFocusRequest, 1)
    }

    func testWidthPressureKeepsBothPanesInsideOneShell() {
        for width: CGFloat in [0, 240, 360, 520, 720, 946, 1400] {
            for emphasized in [false, true] {
                let columns = AgentWorkspaceColumns.make(width: width, emphasized: emphasized)
                XCTAssertGreaterThanOrEqual(columns.chat, 0)
                XCTAssertGreaterThanOrEqual(columns.workspace, 0)
                XCTAssertEqual(columns.chat + columns.workspace + columns.gap, width, accuracy: 0.001)
                if width >= 360 { XCTAssertGreaterThanOrEqual(columns.chat, 190) }
                if width < 540 { XCTAssertEqual(columns, AgentWorkspaceColumns.make(width: width, emphasized: false)) }
            }
        }
        XCTAssertEqual(AgentWorkspaceColumns.make(width: .infinity, emphasized: true).chat, 0)
    }

    func testEmphasisAllocatesRoomWithoutHidingChat() {
        let balanced = AgentWorkspaceColumns.make(width: 820, emphasized: false)
        let expanded = AgentWorkspaceColumns.make(width: 820, emphasized: true)
        XCTAssertGreaterThan(expanded.workspace, balanced.workspace)
        XCTAssertGreaterThanOrEqual(expanded.chat, 240)
    }

    func testUsageHasThreePairedGroupsWithTruthfulUnavailableValues() {
        let groups = AgentWorkspaceUsageProjection.make(accountUsage: [:], selectedSessions: [:])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.map { $0.map(\.provider) }, Array(repeating: [.codex, .claude], count: 3))
        XCTAssertEqual(groups.map { $0.map(\.kind) }, [[.fiveHour, .fiveHour], [.week, .week], [.context, .context]])
        XCTAssertEqual(groups.map { $0.map(\.direction) }, [[.remaining, .remaining], [.remaining, .remaining], [.used, .used]])
        XCTAssertTrue(groups.flatMap { $0 }.allSatisfy { !$0.isAvailable && $0.fraction == nil && $0.accessibilityDescription.contains("unavailable") })
    }

    func testBeamNeverOverridesBlockingOrTerminalTruth() {
        for state in [AgentState.idle, .thinking, .planning, .working, .runningTool, .runningCommand, .waitingForApproval, .waitingForUser, .planReady, .completed, .failed, .interrupted] {
            var session = AgentDashboardPreviewFactory.sessions()[0]
            session.state = state
            XCTAssertEqual(AgentWorkspaceMotion.animatesBeam(session: session, interaction: .working(canInterrupt: true)), AgentVisualMotion.animates(state), state.rawValue)
            XCTAssertFalse(AgentWorkspaceMotion.animatesBeam(session: session, interaction: .stopping))
            XCTAssertFalse(AgentWorkspaceMotion.animatesBeam(session: session, interaction: .failed("transport")))
        }
        XCTAssertFalse(AgentWorkspaceMotion.animatesBeam(session: nil, interaction: .working(canInterrupt: true)))
    }

    func testReduceMotionHasNoSpatialAnimationDependency() {
        XCTAssertNil(AgentWorkspaceMotion.selection(reduceMotion: true))
        XCTAssertNil(AgentWorkspaceMotion.resize(reduceMotion: true))
        XCTAssertNotNil(AgentWorkspaceMotion.selection(reduceMotion: false))
    }

    func testTwoScrollViewportsRemainIndependentAndClearOnTeardown() {
        let layout = IslandLayoutStore()
        layout.setExpandedContentScrollRegion(CGRect(x: 10, y: 20, width: 250, height: 180))
        layout.setAgentWorkspaceScrollRegion(CGRect(x: 280, y: 20, width: 240, height: 180))
        XCTAssertTrue(layout.containsExpandedScrollPoint(CGPoint(x: 20, y: 30)))
        XCTAssertTrue(layout.containsExpandedScrollPoint(CGPoint(x: 300, y: 30)))
        XCTAssertFalse(layout.containsExpandedScrollPoint(CGPoint(x: 270, y: 30)))
        layout.setAgentWorkspaceScrollRegion(.zero)
        XCTAssertFalse(layout.containsExpandedScrollPoint(CGPoint(x: 300, y: 30)))
        XCTAssertTrue(layout.containsExpandedScrollPoint(CGPoint(x: 20, y: 30)))
    }
}
