import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

final class ExpandedHoverContainmentTests: XCTestCase {
    /// Agents workspace profile: 946 x 446, top edge at the screen top.
    private let agentsShell = CGRect(x: 283, y: 982 - 446, width: 946, height: 446)

    func testSendButtonPositionFarBelowScreenTopKeepsExpanded() {
        // Bottom-right corner area where the composer's Send button renders,
        // ~430pt below the top of the screen (the old 350pt hard test failed here).
        let send = CGPoint(x: agentsShell.maxX - 24, y: agentsShell.minY + 16)
        XCTAssertEqual(
            ExpandedHoverContainment.decide(pointer: send, shellFrame: agentsShell, holds: []),
            .keepExpanded
        )
    }

    func testInternalGapsAndEdgesKeepExpanded() {
        let points = [
            CGPoint(x: agentsShell.midX, y: agentsShell.midY),
            CGPoint(x: agentsShell.minX + 1, y: agentsShell.maxY - 1),
            CGPoint(x: agentsShell.minX - 3, y: agentsShell.midY),
            CGPoint(x: agentsShell.midX, y: agentsShell.minY - 3)
        ]
        for point in points {
            XCTAssertEqual(
                ExpandedHoverContainment.decide(pointer: point, shellFrame: agentsShell, holds: []),
                .keepExpanded,
                "\(point)"
            )
        }
    }

    func testLeavingTheShellCollapses() {
        let below = CGPoint(x: agentsShell.midX, y: agentsShell.minY - 10)
        let beside = CGPoint(x: agentsShell.maxX + 10, y: agentsShell.midY)
        XCTAssertEqual(ExpandedHoverContainment.decide(pointer: below, shellFrame: agentsShell, holds: []), .collapse)
        XCTAssertEqual(ExpandedHoverContainment.decide(pointer: beside, shellFrame: agentsShell, holds: []), .collapse)
    }

    func testHoldsKeepExpandedEvenOutside() {
        let outside = CGPoint(x: 0, y: 0)
        for hold in [
            ExpandedHoverContainment.Holds.menuTracking,
            .transientInteraction,
            .textInput
        ] {
            XCTAssertEqual(
                ExpandedHoverContainment.decide(pointer: outside, shellFrame: agentsShell, holds: hold),
                .held(hold)
            )
        }
    }

    func testSafeRegionDoesNotClaimTheDesktop() {
        let region = ExpandedHoverContainment.safeRegion(shellFrame: agentsShell)
        XCTAssertEqual(region.width, agentsShell.width + ExpandedHoverContainment.tolerance * 2)
        XCTAssertEqual(region.height, agentsShell.height + ExpandedHoverContainment.tolerance * 2)
        XCTAssertEqual(ExpandedHoverContainment.safeRegion(shellFrame: .zero), .zero)
    }

    func testEmptyGeometryNeverCollapsesSpuriously() {
        XCTAssertEqual(
            ExpandedHoverContainment.decide(pointer: .zero, shellFrame: .zero, holds: []),
            .keepExpanded
        )
    }

    func testFileDragHoldPreventsCollapseBeforeAccessoryFrameArrives() {
        let shell = CGRect(x: 100, y: 100, width: 700, height: 260)
        let outside = CGPoint(x: 450, y: 30)
        XCTAssertEqual(
            ExpandedHoverContainment.decide(pointer: outside, shellFrame: shell, holds: .fileDrag),
            .held(.fileDrag)
        )
    }

}

@MainActor
final class IslandLayoutStoreTextInputTests: XCTestCase {
    func testTextInputFocusFlag() {
        let store = IslandLayoutStore()
        XCTAssertFalse(store.isTextInputFocused)
        store.setTextInputFocused(true)
        XCTAssertTrue(store.isTextInputFocused)
        store.setTextInputFocused(false)
        XCTAssertFalse(store.isTextInputFocused)
    }
}

@MainActor
final class AgentComposerReachabilityTests: XCTestCase {
    func testSendButtonStaysInsideConsoleAtNarrowAndShortSizes() throws {
        for size in [
            CGSize(width: 900, height: 320),
            CGSize(width: 520, height: 200),
            CGSize(width: 320, height: 110),
            CGSize(width: 240, height: 90)
        ] {
            let frame = try controlFrame(label: "Send prompt", state: .ready, size: size)
            let bounds = CGRect(origin: .zero, size: size)
            XCTAssertTrue(bounds.contains(frame), "Send \(frame) outside \(bounds)")
            XCTAssertGreaterThan(frame.width, 8)
        }
    }

    func testStopButtonStaysInsideConsoleWhileWorking() throws {
        let size = CGSize(width: 300, height: 100)
        let frame = try controlFrame(label: "Stop current agent turn", state: .working(canInterrupt: true), size: size)
        XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame))
    }

    private final class FrameBox {
        var frame: CGRect = .null
    }

    private func controlFrame(
        label: String,
        state: AgentManagedInteractionState,
        size: CGSize
    ) throws -> CGRect {
        let box = FrameBox()
        let view = AgentEmbeddedConsoleView(
            session: Self.session(),
            mode: .interactive(canInterrupt: true),
            interactionState: state,
            transcriptEntries: [],
            approvalControl: AgentApprovalController(),
            onSelectSession: { _ in },
            onSubmit: { _ in true },
            onInterrupt: {}
        )
        .frame(width: size.width, height: size.height)
        .onPreferenceChange(AgentComposerActionFrameKey.self) { box.frame = $0 }

        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<5 where box.frame.isNull {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
            host.layoutSubtreeIfNeeded()
        }
        XCTAssertFalse(box.frame.isNull, "\(label) frame was not reported")
        return box.frame
    }

    private static func session() -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: "thread"),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: .working,
            project: AgentProjectContext(displayName: "DynamicIsland"),
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: Date(timeIntervalSince1970: 1_000),
            endedAt: nil,
            lastUpdatedAt: Date(timeIntervalSince1970: 1_000),
            availability: .loaded
        )
    }
}
