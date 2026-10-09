import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentSendRegressionTests: XCTestCase {
    private final class Frames { var action = CGRect.null }

    func testComposerClicksReachTheActionThroughShellGestures() async throws {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "AgentSendRegression-\(UUID())")!)
        settings.gesturesEnabled = true
        settings.gestureInputSource = .trackpad
        let layout = IslandLayoutStore()
        let frames = Frames()
        var sent = 0
        let view = AgentEmbeddedConsoleView(
            session: session(provider: .codex), mode: .interactive(canInterrupt: true),
            interactionState: .ready, layoutStore: layout, approvalControl: AgentApprovalController(),
            onSelectSession: { _ in }, onSubmit: { _ in sent += 1; return false }, onInterrupt: {},
            loadDraft: { _ in "Native Send regression" })
            .onPreferenceChange(AgentComposerActionFrameKey.self) { frames.action = $0 }
            .frame(width: 500, height: 250)
            .modifier(IslandPointerGestureModifier(settings: settings, coordinator: IslandGestureCoordinator(),
                context: IslandGestureContext(presentationState: .expanded, selectedPage: .agents,
                    mediaControlAvailable: false, timerIsRunning: false, timerCanResume: false,
                    collapsedPreviewActive: false, isShellMorphing: false, isCollapseShellOnly: false,
                    isExpandedContentExiting: false, isFileDropTargeted: false), callbacks: IslandGestureCallbacks(),
                swipeSensitivity: 1, layoutStore: layout))
            .coordinateSpace(name: IslandCanvasCoordinateSpace.name)
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 500, height: 250),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = NSHostingView(rootView: view)
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(200))
        window.contentView?.layoutSubtreeIfNeeded()
        let frame = frames.action
        XCTAssertFalse(frame.isNull)
        XCTAssertGreaterThanOrEqual(frame.width, 30)
        let points = [CGPoint(x: frame.midX, y: frame.midY),
            CGPoint(x: frame.minX + 1, y: frame.minY + 1),
            CGPoint(x: frame.maxX - 1, y: frame.minY + 1),
            CGPoint(x: frame.minX + 1, y: frame.maxY - 1),
            CGPoint(x: frame.maxX - 1, y: frame.maxY - 1)]
        for (index, point) in points.enumerated() {
            let local = CGPoint(x: point.x, y: 250 - point.y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: local,
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: index,
                    clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                window.sendEvent(event)
                try await Task.sleep(for: .milliseconds(20))
            }
            try await Task.sleep(for: .milliseconds(400))
            XCTAssertEqual(sent, index + 1, "Visible Send point \(point) must submit exactly once")
        }
    }

    func testActionRegionReleasesForEditingInactivePagesAndUnmount() async throws {
        let layout = IslandLayoutStore()
        var sent = 0
        let console = AgentEmbeddedConsoleView(session: session(provider: .codex),
            mode: .interactive(canInterrupt: true), interactionState: .ready, layoutStore: layout,
            approvalControl: AgentApprovalController(), onSelectSession: { _ in },
            onSubmit: { _ in sent += 1; return false }, onInterrupt: {}, loadDraft: { _ in "Draft" })
        func root(active: Bool, editing: Bool) -> some View {
            console.frame(width: 500, height: 250)
                .coordinateSpace(name: IslandCanvasCoordinateSpace.name)
                .environment(\.rightWorkspacePageIsActive, active)
                .environment(\.timerRulerInteractionRegistration, TimerRulerInteractionRegistration(enabled: !editing))
        }
        let host = NSHostingView(rootView: root(active: true, editing: false))
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 500, height: 250),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        func settle() async throws {
            for _ in 0..<6 { host.layoutSubtreeIfNeeded(); try await Task.sleep(for: .milliseconds(10)) }
        }
        try await settle()
        XCTAssertEqual(layout.nativeControlRegions.count, 1)
        host.rootView = root(active: true, editing: true)
        try await settle()
        XCTAssertTrue(layout.nativeControlRegions.isEmpty)
        host.rootView = root(active: false, editing: false)
        try await settle()
        XCTAssertTrue(layout.nativeControlRegions.isEmpty)
        host.rootView = root(active: true, editing: false)
        try await settle()
        XCTAssertEqual(layout.nativeControlRegions.count, 1)
        let action = try XCTUnwrap(layout.nativeControlRegions.values.first)
        try await clickAction(window, frame: action)
        XCTAssertEqual(sent, 1)
        window.contentView = nil
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(layout.nativeControlRegions.isEmpty, "An unmounted composer cannot retain native input ownership")
    }

    func testPendingSubmissionDoesNotDisableAnotherSessionOrClearItsDraft() async throws {
        let fixture = AgentSendSessionFixture(session: session(provider: .codex))
        let window = NSWindow(contentRect: CGRect(x: 40, y: 40, width: 500, height: 250),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { fixture.pending?.resume(returning: false); fixture.pending = nil; window.close() }
        window.contentView = NSHostingView(rootView: AgentSendSessionFixtureView(fixture: fixture))
        window.makeKeyAndOrderFront(nil)
        try await Task.sleep(for: .milliseconds(150))
        try await clickAction(window, frame: fixture.frame)
        XCTAssertEqual(fixture.submissions, [.codex])
        XCTAssertNotNil(fixture.pending)
        fixture.waitForReply = false
        fixture.session = session(provider: .claude)
        try await Task.sleep(for: .milliseconds(150))
        try await clickAction(window, frame: fixture.frame)
        XCTAssertEqual(fixture.submissions, [.codex, .claude], "A pending Codex submission cannot disable the Claude composer")
        fixture.pending?.resume(returning: true)
        fixture.pending = nil
        try await Task.sleep(for: .milliseconds(100))
        let editor = try XCTUnwrap(findEditor(window.contentView))
        XCTAssertEqual(editor.string, "Draft", "The old session's completion cannot clear the newly selected draft")
    }

    private func clickAction(_ window: NSWindow, frame: CGRect) async throws {
        XCTAssertFalse(frame.isNull)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type,
                location: CGPoint(x: frame.midX, y: 250 - frame.midY), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
            try await Task.sleep(for: .milliseconds(20))
        }
        try await Task.sleep(for: .milliseconds(60))
    }

    private func findEditor(_ view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let editor = view as? NSTextView, editor.isEditable { return editor }
        return view.subviews.lazy.compactMap { self.findEditor($0) }.first
    }

    private func session(provider: AgentProvider) -> AgentSession {
        AgentSession(id: AgentSessionInstanceID(sessionID: AgentSessionID(provider: provider, nativeID: "send-regression"),
            generation: AgentSessionGeneration(rawValue: 1)), source: .terminal, state: .working,
            project: AgentProjectContext(displayName: "DynamicIsland"), capabilities: AgentCapabilities(),
            usage: AgentUsage(), tools: [:], commands: [:], approvals: [:], subagents: [:],
            recentActivity: [], startedAt: Date(), endedAt: nil, lastUpdatedAt: Date(), availability: .loaded)
    }
}

@MainActor
private final class AgentSendSessionFixture: ObservableObject {
    @Published var session: AgentSession
    var frame = CGRect.null
    var waitForReply = true
    var pending: CheckedContinuation<Bool, Never>?
    var submissions: [AgentProvider] = []
    init(session: AgentSession) { self.session = session }
    func submit(provider: AgentProvider) async -> Bool {
        submissions.append(provider)
        if waitForReply { return await withCheckedContinuation { pending = $0 } }
        return false
    }
}

private struct AgentSendSessionFixtureView: View {
    @ObservedObject var fixture: AgentSendSessionFixture
    var body: some View {
        let provider = fixture.session.id.sessionID.provider
        AgentEmbeddedConsoleView(session: fixture.session, mode: .interactive(canInterrupt: true),
            interactionState: .ready, approvalControl: AgentApprovalController(),
            onSelectSession: { _ in }, onSubmit: { _ in await fixture.submit(provider: provider) },
            onInterrupt: {}, loadDraft: { _ in "Draft" })
            .onPreferenceChange(AgentComposerActionFrameKey.self) { fixture.frame = $0 }
            .frame(width: 500, height: 250)
    }
}
