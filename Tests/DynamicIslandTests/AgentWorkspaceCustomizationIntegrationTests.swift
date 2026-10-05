import AppKit
import Darwin
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Actual native views and an owned forkpty shell. Provider/session content is
/// deterministic fixture input; this is not live provider or packaged evidence.
@MainActor
final class AgentWorkspaceCustomizationIntegrationTests: XCTestCase {
    private func fixture() throws -> CustomizationFixture {
        _ = NSApplication.shared
        let events = AgentEventStore()
        let native = AgentTestFixture.sessionID(.codex, "customization-\(UUID().uuidString)")
        events.ingest(AgentTestFixture.event("start-\(native.nativeID)", sessionID: native,
            type: .sessionStarted, offset: 0,
            payload: .sessionMetadata(.init(project: AgentTestFixture.project(path: "/tmp")))))
        let session = try XCTUnwrap(events.sessions.first)
        let approvals = AgentApprovalController()
        let managed = AgentManagedSessionController(provider: nil,
            coordinator: AgentIngestionCoordinator(eventStore: events), eventStore: events, approvals: approvals)
        managed.selectSession(session.id)
        let terminal = TerminalSessionController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry(),
            shellPath: "/bin/zsh", workingDirectoryPath: "/tmp")
        return CustomizationFixture(session: session, events: events, managed: managed,
            approvals: approvals, terminal: terminal, presentation: AgentWorkspacePresentation())
    }

    private func wait(_ description: String, host: NSView? = nil, until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            host?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), description)
    }
    private func hasLine(_ line: String, terminal: TerminalSessionController) -> Bool {
        terminal.output.components(separatedBy: "\n").contains { $0.trimmingCharacters(in: .whitespacesAndNewlines) == line }
    }
    private func settle(_ host: NSView) async {
        for _ in 0..<12 { host.layoutSubtreeIfNeeded(); await Task.yield() }
    }
    private func window<V: View>(_ root: V) -> (NSWindow, NSHostingView<V>) {
        let host = NSHostingView(rootView: root)
        host.frame = CGRect(x: 0, y: 0, width: 700, height: 380)
        let window = NSWindow(contentRect: CGRect(x: -3000, y: -3000, width: 700, height: 380),
            styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host; window.orderFrontRegardless()
        return (window, host)
    }

    func testActualPTYCommandCWDEnvironmentAndScrollbackSurviveLayoutAndStackCycles() async throws {
        let fixture = try fixture()
        defer { fixture.terminal.terminate(); fixture.managed.stop(); fixture.approvals.cancelAll() }
        try fixture.terminal.startShell()
        let pid = try XCTUnwrap(fixture.terminal.processID)
        let emulator = fixture.terminal.terminalView
        let descriptor = emulator.process.childfd
        try fixture.terminal.run(command: "cd /; export DI_CUSTOMIZATION=preserved; printf 'DI_CUSTOMIZATION_BEFORE\\n'; sleep 30")
        try await wait("Owned foreground command is running") {
            self.hasLine("DI_CUSTOMIZATION_BEFORE", terminal: fixture.terminal) && tcgetpgrp(descriptor) > 0 && tcgetpgrp(descriptor) != pid
        }
        let foregroundPID = tcgetpgrp(descriptor)
        let state = CustomizationRenderState(session: fixture.session)
        state.configuration.add(.terminal, on: .agents)
        let terminalID = state.configuration.placement(kind: .terminal, on: .agents)!.id
        let root = CustomizationRenderHarness(state: state, fixture: fixture)
        let (window, host) = window(root)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.orderOut(nil) }
        await settle(host)
        for _ in 0..<4 {
            state.configuration.remove(terminalID)
            await settle(host)
            XCTAssertTrue(fixture.terminal.isRunning, "Removing presentation cannot kill the shell")
            XCTAssertEqual(fixture.terminal.processID, pid)
            XCTAssertEqual(tcgetpgrp(descriptor), foregroundPID, "An active foreground job survives hidden Terminal")
            XCTAssertNil(emulator.superview, "Hidden Terminal must release its renderer")
            state.configuration.add(.terminal, on: .agents)
            state.configuration.combineTerminalWithChat()
            let stack = try XCTUnwrap(state.configuration.groups.first)
            fixture.presentation.showStack(.terminal)
            try await wait("One native renderer mounts on the Terminal stack page", host: host) { emulator.superview != nil }
            XCTAssertEqual(nativeTerminalCount(in: host), 1)
            fixture.presentation.swipeStack(by: -1)
            try await wait("Chat page detaches Terminal rendering", host: host) { emulator.superview == nil }
            XCTAssertEqual(fixture.presentation.stackPage, .chat)
            fixture.presentation.swipeStack(by: 1)
            try await wait("Same renderer returns", host: host) { emulator.superview != nil }
            state.configuration.shift(stack.id, by: 1)
            await settle(host)
            state.showsWorkspace = false
            await settle(host)
            XCTAssertEqual(tcgetpgrp(descriptor), foregroundPID, "Collapse or leaving the page cannot interrupt work")
            state.showsWorkspace = true
            await settle(host)
            state.configuration.separateStack(stack.id)
            await settle(host)
            XCTAssertTrue(fixture.terminal.terminalView === emulator)
            XCTAssertEqual(fixture.terminal.processID, pid)
            XCTAssertEqual(fixture.managed.selectedSessionID, fixture.session.id)
            XCTAssertTrue(hasLine("DI_CUSTOMIZATION_BEFORE", terminal: fixture.terminal))
        }
        fixture.terminal.interrupt()
        try await wait("Ctrl-C returns to the existing shell") { tcgetpgrp(descriptor) == pid }
        try fixture.terminal.run(command: "printf 'ENV=%s\\n' \"$DI_CUSTOMIZATION\"; pwd; printf 'DI_CUSTOMIZATION_AFTER\\n'")
        try await wait("Shell still accepts commands") { self.hasLine("DI_CUSTOMIZATION_AFTER", terminal: fixture.terminal) }
        XCTAssertTrue(hasLine("ENV=preserved", terminal: fixture.terminal))
        XCTAssertTrue(hasLine("/", terminal: fixture.terminal), "Presentation startup cannot cd the running shell back to the selected project")
        XCTAssertTrue(hasLine("DI_CUSTOMIZATION_BEFORE", terminal: fixture.terminal), "Scrollback remains emulator-owned")
        XCTAssertEqual(fixture.terminal.processID, pid)
    }

    func testNativeStackRetainsPromptHistoryIntentAndExactSessionAcrossSwipesAndRemounts() async throws {
        let fixture = try fixture()
        defer { fixture.terminal.terminate(); fixture.managed.stop(); fixture.approvals.cancelAll() }
        let state = CustomizationRenderState(session: fixture.session)
        state.configuration.remove(state.configuration.placement(kind: .feed, on: .agents)!.id)
        state.configuration.add(.terminal, on: .agents)
        state.configuration.combineTerminalWithChat()
        let root = CustomizationRenderHarness(state: state, fixture: fixture)
        let (window, host) = window(root)
        defer { window.makeFirstResponder(nil); window.contentView = nil; window.orderOut(nil) }
        try await wait("Native prompt and transcript are mounted", host: host) {
            self.prompt(in: host) != nil && self.transcript(in: host) != nil
        }
        await settle(host)
        let editor = try XCTUnwrap(prompt(in: host))
        editor.insertText("draft remains with exact session", replacementRange: NSRange(location: NSNotFound, length: 0))
        await settle(host)
        let scroll = try XCTUnwrap(transcript(in: host))
        NotificationCenter.default.post(name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 50))
        scroll.reflectScrolledClipView(scroll.contentView)
        NotificationCenter.default.post(name: NSScrollView.didEndLiveScrollNotification, object: scroll)
        await settle(host)
        let readingOrigin = scroll.contentView.bounds.origin.y
        let saved = AgentTranscriptViewportStore.shared.position(for: fixture.session.id)
        XCTAssertFalse(saved.followingLatest)
        for _ in 0..<5 {
            fixture.presentation.swipeStack(by: 1)
            await settle(host)
            fixture.presentation.swipeStack(by: -1)
            await settle(host)
            XCTAssertTrue(prompt(in: host) === editor, "Retained Chat does not replace its editor on a stack swipe")
            XCTAssertEqual(prompt(in: host)?.string, "draft remains with exact session")
            XCTAssertEqual(transcript(in: host)?.contentView.bounds.origin.y ?? -1, readingOrigin, accuracy: 1)
            XCTAssertEqual(fixture.managed.selectedSessionID, fixture.session.id)
        }
        // A real layout change/remount persists the draft and the measured reading intent.
        state.showsWorkspace = false
        await settle(host)
        XCTAssertEqual(fixture.managed.composerDraft(for: fixture.session.id), "draft remains with exact session")
        state.entries.append(.init(id: "arrived-hidden", nativeSessionID: fixture.session.id.sessionID.nativeID,
            turnID: "hidden-turn", role: .agent, text: "New response while the workspace is hidden",
            // Newest entry: arrives after every history row, below the reading anchor.
            timestamp: AgentTestFixture.baseDate.addingTimeInterval(10_000)))
        state.showsWorkspace = true
        try await wait("Chat remounts", host: host) { self.prompt(in: host) != nil && self.transcript(in: host) != nil }
        await settle(host)
        XCTAssertEqual(prompt(in: host)?.string, "draft remains with exact session")
        XCTAssertFalse(AgentTranscriptViewportStore.shared.position(for: fixture.session.id).followingLatest)
        XCTAssertEqual(transcript(in: host)?.contentView.bounds.origin.y ?? -1, readingOrigin, accuracy: 2)
        XCTAssertEqual(fixture.managed.selectedSessionID, fixture.session.id)
        XCTAssertEqual(fixture.events.session(for: fixture.session.id)?.id, fixture.session.id)
    }

    private func nativeTerminalCount(in view: NSView) -> Int {
        (view is InteractiveTerminalView ? 1 : 0) + view.subviews.reduce(0) { $0 + nativeTerminalCount(in: $1) }
    }
    private func prompt(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.accessibilityLabel() == "Agent prompt" { return text }
        return view.subviews.lazy.compactMap { self.prompt(in: $0) }.first
    }
    private func transcript(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView,
           scroll.documentView != nil,
           !containsPrompt(scroll), !(scroll.documentView is InteractiveTerminalView) { return scroll }
        return view.subviews.lazy.compactMap { self.transcript(in: $0) }.first
    }
    private func containsPrompt(_ view: NSView) -> Bool { prompt(in: view) != nil }
}

private struct CustomizationFixture {
    let session: AgentSession
    let events: AgentEventStore
    let managed: AgentManagedSessionController
    let approvals: AgentApprovalController
    let terminal: TerminalSessionController
    let presentation: AgentWorkspacePresentation
}

@MainActor
private final class CustomizationRenderState: ObservableObject {
    @Published var configuration = WorkspaceConfiguration.initial
    @Published var showsWorkspace = true
    @Published var entries: [AgentManagedTranscriptEntry]
    init(session: AgentSession) {
        entries = (0..<8).map { index in
            .init(id: "history-\(index)", nativeSessionID: session.id.sessionID.nativeID,
                turnID: "history-turn", role: .agent,
                text: (0..<12).map { "History response \(index), line \($0)" }.joined(separator: "\n"),
                timestamp: AgentTestFixture.baseDate.addingTimeInterval(Double(index)))
        }
    }
}

private struct CustomizationRenderHarness: View {
    @ObservedObject var state: CustomizationRenderState
    let fixture: CustomizationFixture
    @ObservedObject private var presentation: AgentWorkspacePresentation
    init(state: CustomizationRenderState, fixture: CustomizationFixture) {
        self.state = state; self.fixture = fixture; presentation = fixture.presentation
    }
    var body: some View {
        Group {
            if state.showsWorkspace {
                HStack(spacing: 8) {
                    ForEach(state.configuration.regions(on: .agents)) { region in
                        if region.isStack {
                            AgentChatTerminalStack(presentation: presentation, isVisible: true, reduceMotion: true, layoutStore: nil,
                                chat: { AnyView(chat(active: presentation.stackPage == .chat)) },
                                terminal: { AnyView(terminal(active: presentation.stackPage == .terminal)) })
                        } else {
                            switch region.widgets.first?.kind {
                            case .chat: chat(active: true)
                            case .terminal: terminal(active: true)
                            case .agentUsage, .codexUsage, .claudeUsage: Text("Usage fixture").frame(height: 20)
                            default: Text("Feed fixture").frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            } else { Color.clear }
        }
        .frame(width: 700, height: 380)
        .environment(\.nativeVisualSnapshotTime, 1.35)
    }
    private func chat(active: Bool) -> some View {
        AgentEmbeddedConsoleView(session: fixture.session, mode: .interactive(canInterrupt: false), interactionState: .ready,
            showsOperationalTraffic: false, showsActivityOrb: false, transcriptEntries: state.entries,
            approvalControl: fixture.approvals, onSelectSession: { _ in }, onSubmit: { _ in false }, onInterrupt: {},
            loadDraft: fixture.managed.composerDraft(for:), saveDraft: fixture.managed.setComposerDraft(_:for:))
            .environment(\.rightWorkspacePageIsActive, active)
    }
    @ViewBuilder private func terminal(active: Bool) -> some View {
        if active {
            AgentWorkspaceTerminalView(controller: fixture.terminal, session: fixture.session,
                isVisible: true, focusRequest: presentation.terminalFocusRequest, layoutStore: nil)
        } else { Color.clear }
    }
}
