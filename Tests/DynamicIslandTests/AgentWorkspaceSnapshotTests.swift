import AgentBridgeShared
import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Development-only production-view review. Provider inputs and terminal output
/// are deterministic fixtures, never evidence of live provider acceptance.
@MainActor
final class AgentWorkspaceSnapshotTests: XCTestCase {
    private let fixtureDate = AgentTestFixture.baseDate

    func testRenderAgentsWorkspaceReview() async throws {
        guard let path = ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set DYNAMIC_ISLAND_WORKSPACE_SNAPSHOT_DIR for the native workspace review harness.")
        }
        let output = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let cases = [
            "01-codex-idle", "02-codex-solving", "03-codex-searching", "04-codex-command",
            "05-codex-approval", "06-codex-composing", "07-claude-working", "08-concurrent-providers",
            "09-feed-pending", "10-feed-denied", "11-feed-approved", "12-feed-history",
            "13-terminal", "14-right-workspace-expanded", "15-chat-mode", "16-compact-active",
            "17-expanded-active", "18-reduce-motion", "19-six-usage-indicators", "20-narrow-width",
            "21-feed-delivering", "22-feed-failed", "23-light-theme"
        ]
        for name in cases {
            let fixture = try await makeFixture()
            defer { fixture.controller.stop(); fixture.approvals.cancelAll(); fixture.terminal.terminate() }
            let isClaude = name == "07-claude-working"
            let owner = isClaude ? AgentProvider.claude : .codex
            let activeID = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == owner }?.id)
            fixture.controller.selectProvider(owner)
            fixture.controller.selectSession(activeID)
            var approvalWaiter: Task<AgentBridgePermissionDecision?, Never>?
            defer { approvalWaiter?.cancel() }

            if name.contains("approval") || name.contains("feed-pending") || name.contains("feed-denied") ||
                name.contains("feed-approved") || name.contains("feed-delivering") || name.contains("feed-failed") {
                emit(fixture, session: activeID, type: .approvalRequested, correlation: "turn/request", offset: 10,
                     payload: .approvalRequest(.init(summary: "Run the repository validation command", operationCorrelationID: nil, expiresAt: nil)))
                let key = AgentApprovalControlKey(session: activeID, requestID: AgentTestFixture.correlation("turn/request"))
                approvalWaiter = Task {
                    await fixture.approvals.request(.init(key: key, summary: "Run the repository validation command", expiresAt: .distantFuture), maximumWait: nil)
                }
                for _ in 0..<500 where fixture.approvals.pendingRequests[key] == nil { await Task.yield() }
                XCTAssertNotNil(fixture.approvals.pendingRequests[key])
                if name.contains("denied") || name.contains("approved") || name.contains("delivering") || name.contains("failed") {
                    let denied = name.contains("denied")
                    XCTAssertEqual(fixture.approvals.resolve(session: activeID, requestID: key.requestID, decision: denied ? .deny : .allow), .accepted)
                    _ = await approvalWaiter?.value
                    if name.contains("delivering") {
                        XCTAssertEqual(fixture.feed.items.first?.approvalPresentation(delivery: fixture.approvals.deliveryState(for: key)), .submitting)
                    } else if name.contains("failed") {
                        fixture.approvals.failDelivery(key, reason: "Fixture transport did not acknowledge this decision")
                    } else {
                        // Explicit simulated provider acknowledgement, separate
                        // from selecting a decision in the approval controller.
                        fixture.approvals.confirmDelivery(key)
                        emit(fixture, session: activeID, type: .approvalResolved, correlation: key.requestID.rawValue, offset: 11,
                             payload: .approvalResolution(.init(state: denied ? .denied : .approved)))
                    }
                }
            } else if name != "01-codex-idle" && name != "19-six-usage-indicators" {
                let kind: AgentProcessingKind = name.contains("search") ? .searching : name.contains("compos") ? .composing : .reasoning
                if name.contains("command") || isClaude {
                    emit(fixture, session: activeID, type: .commandStarted, correlation: "command", offset: 10,
                         payload: .command(.init(executable: "swift", success: nil, exitCode: nil, processingKind: .executing)))
                } else {
                    emit(fixture, session: activeID, type: .agentWorking, correlation: "processing", offset: 10,
                         payload: .activity(.init(title: nil, summary: nil, processingKind: kind, processingStatus: .active)))
                }
            }
            if name == "08-concurrent-providers" || name == "12-feed-history" {
                let claudeID = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .claude }?.id)
                emit(fixture, session: claudeID, type: .toolStarted, correlation: "claude-tool", offset: 12,
                     payload: .tool(.init(name: "Read", category: "read", summary: nil, success: nil, processingKind: .listening)))
                if name == "12-feed-history" {
                    emit(fixture, session: claudeID, type: .toolCompleted, correlation: "claude-tool", offset: 13,
                         payload: .tool(.init(name: "Read", category: "read", summary: nil, success: true)))
                    emit(fixture, session: claudeID, type: .taskCompleted, offset: 14, payload: .terminal(.init(summary: nil)))
                    emit(fixture, session: activeID, type: .commandStarted, correlation: "validation", offset: 15,
                         payload: .command(.init(executable: "swift", success: nil, exitCode: nil)))
                }
            }
            if name == "13-terminal" {
                fixture.presentation.interact(.terminal)
                try fixture.terminal.run(command: "swift test --filter AgentWorkspace")
                await Task.yield()
                XCTAssertEqual(fixture.presentation.mode, .terminal)
                XCTAssertEqual(fixture.presentation.interactionMode, .terminal)
                XCTAssertEqual(fixture.runner.startCount, 1)
            }
            if name == "14-right-workspace-expanded" { fixture.presentation.toggleEmphasis() }
            if name == "15-chat-mode" { fixture.presentation.interact(.terminal); fixture.presentation.interact(.chat); fixture.presentation.select(.feed) }
            let reduceMotion = name == "18-reduce-motion"
            let width: CGFloat = name == "20-narrow-width" ? 560 : 960
            let size = CGSize(width: width, height: 510)
            let selected = try XCTUnwrap(fixture.store.session(for: activeID))
            if name == "16-compact-active" {
                try await hosted(compact(selected), size: CGSize(width: 410, height: 70), reduceMotion: false, light: false,
                                 to: output.appendingPathComponent(name + ".png"))
            } else if name == "19-six-usage-indicators" {
                let selectedByProvider = Dictionary(uniqueKeysWithValues: fixture.store.sessions.map { ($0.id.sessionID.provider, $0) })
                let groups = AgentWorkspaceUsageProjection.make(accountUsage: fixture.controller.accountUsageByProvider,
                                                               selectedSessions: selectedByProvider, now: fixtureDate)
                XCTAssertEqual(groups.count, 3)
                XCTAssertEqual(groups.map(\.count), [2, 2, 2])
                try await hosted(AgentWorkspaceUsageStrip(groups: groups).padding(20), size: CGSize(width: 700, height: 100),
                                 reduceMotion: false, light: false, to: output.appendingPathComponent(name + ".png"))
            } else {
                let columns = AgentWorkspaceColumns.make(width: width - 28, emphasized: fixture.presentation.isEmphasized)
                XCTAssertGreaterThan(columns.chat, 0)
                XCTAssertGreaterThan(columns.workspace, 0)
                XCTAssertLessThanOrEqual(columns.chat + columns.workspace + columns.gap, width - 28 + 0.001)
                let view = AgentDashboardContentView(
                    sessions: fixture.store.sessions, accountUsage: fixture.controller.accountUsage, showsUsage: true,
                    approvalControl: fixture.approvals, managedControl: fixture.controller, availableHeight: size.height - 28,
                    initialSelectedSessionID: activeID, contentVisible: true, reduceMotion: reduceMotion,
                    transcriptPresentationReady: true, transcriptLoadDelay: 0,
                    workspaceFeed: fixture.feed, workspacePresentation: fixture.presentation, terminal: fixture.terminal
                ).padding(14)
                try await hosted(view, size: size, reduceMotion: reduceMotion, light: name == "23-light-theme",
                                 to: output.appendingPathComponent(name + ".png"))
            }
        }
        try """
        Evidence: PASS — automated/fixture
        23 deterministic production-view workspace review scenarios.
        Native providers, approval acknowledgements, usage and terminal traffic are fixture inputs.
        Native NSHostingView/window snapshots exercise actual workspace view hierarchy.
        Metal-backed BorderBeam pixel fidelity is NOT VERIFIED by bitmapImageRepForCachingDisplay;
        use the dedicated native GPU/offscreen Beam reference harness for shader parity.
        Reduce Motion here is view-input/fixture coverage, not actual macOS-setting acceptance.
        These snapshots do not establish live provider or human-interaction acceptance.
        """.write(to: output.appendingPathComponent("EVIDENCE.txt"), atomically: true, encoding: .utf8)
    }



    func testPlainReturnSubmitsAgentPromptFromNativeEditor() async throws {
        let fixture = try await makeFixture()
        defer {
            fixture.controller.stop()
            fixture.approvals.cancelAll()
            fixture.terminal.terminate()
        }

        let selected = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .codex })
        fixture.controller.selectProvider(.codex)
        fixture.controller.selectSession(selected.id)

        let size = CGSize(width: 900, height: 480)
        let view = AgentDashboardContentView(
            sessions: fixture.store.sessions,
            accountUsage: fixture.controller.accountUsage,
            showsUsage: true,
            approvalControl: fixture.approvals,
            managedControl: fixture.controller,
            availableHeight: 460,
            initialSelectedSessionID: selected.id,
            contentVisible: true,
            reduceMotion: true,
            transcriptPresentationReady: true,
            transcriptLoadDelay: 0,
            workspaceFeed: fixture.feed,
            workspacePresentation: fixture.presentation,
            terminal: fixture.terminal
        )
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<10 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }
        let editor = try XCTUnwrap(Self.findPromptEditor(in: hosting))
        XCTAssertTrue(window.makeFirstResponder(editor))
        editor.insertText("plain return sends", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(8))

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ))
        editor.keyDown(with: event)

        for _ in 0..<20 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        fixture.controller.flushTranscriptPublications()
        XCTAssertTrue(
            fixture.controller.transcript(for: selected).contains {
                $0.role == .user && $0.text == "plain return sends"
            }
        )
    }

    func testTerminalReturnRunsCommandFromFocusedWorkspaceField() async throws {
        let fixture = try await makeFixture()
        defer {
            fixture.controller.stop()
            fixture.approvals.cancelAll()
            fixture.terminal.terminate()
        }
        let selected = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .codex })
        fixture.presentation.select(.terminal)

        let size = CGSize(width: 440, height: 300)
        let view = AgentWorkspaceTerminalView(
            controller: fixture.terminal,
            session: selected,
            isVisible: true,
            focusRequest: fixture.presentation.terminalFocusRequest,
            layoutStore: nil
        )
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<10 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }
        let field = try XCTUnwrap(Self.findTerminalCommandField(in: hosting))
        XCTAssertTrue(window.makeFirstResponder(field))
        guard let editor = field.currentEditor() as? NSTextView else {
            return XCTFail("Terminal field editor unavailable")
        }
        editor.insertText("printf terminal-enter-ok", replacementRange: editor.selectedRange())
        try await Task.sleep(for: .milliseconds(8))
        editor.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        for _ in 0..<20 where fixture.runner.startCount == 0 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(fixture.runner.startCount, 1)
        XCTAssertTrue(fixture.terminal.isRunning)
        XCTAssertEqual(field.stringValue, "", "Successful Return submission must clear the live native field editor")
    }

    func testRapidAgentsMountUnmountWithFocusedNativeEditorAndTerminalSwitching() async throws {
        let fixture = try await makeFixture()
        defer {
            fixture.controller.stop()
            fixture.approvals.cancelAll()
            fixture.terminal.terminate()
        }

        let selected = try XCTUnwrap(fixture.store.sessions.first { $0.id.sessionID.provider == .codex })
        fixture.controller.selectProvider(.codex)
        fixture.controller.selectSession(selected.id)

        let state = AgentWorkspaceMountStressState()
        let size = CGSize(width: 960, height: 510)
        let root = AgentWorkspaceMountStressHarness(
            state: state,
            sessions: fixture.store.sessions,
            controller: fixture.controller,
            approvals: fixture.approvals,
            feed: fixture.feed,
            presentation: fixture.presentation,
            terminal: fixture.terminal,
            selectedID: selected.id
        )
        .frame(width: size.width, height: size.height)
        .environment(\.nativeVisualSnapshotTime, 1.35)

        let hosting = NSHostingView(rootView: root)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(
            contentRect: CGRect(origin: CGPoint(x: -5000, y: -5000), size: size),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer {
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            window.contentView = nil
        }

        for _ in 0..<8 {
            await Task.yield()
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(5))
        }

        for cycle in 0..<48 {
            if cycle.isMultiple(of: 2) {
                fixture.presentation.select(.terminal)
            } else {
                fixture.presentation.select(.feed)
            }
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(3))

            if let editor = Self.findPromptEditor(in: hosting) {
                XCTAssertTrue(window.makeFirstResponder(editor))
            }

            state.generation &+= 1
            state.showsAgents = false
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()

            state.generation &+= 1
            state.showsAgents = true
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }

        for _ in 0..<8 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(4))
            hosting.layoutSubtreeIfNeeded()
        }

        XCTAssertTrue(state.showsAgents)
        XCTAssertNotNil(Self.findPromptEditor(in: hosting))
    }

    private static func findPromptEditor(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView, text.accessibilityLabel() == "Agent prompt" {
            return text
        }
        for child in view.subviews {
            if let found = findPromptEditor(in: child) { return found }
        }
        return nil
    }

    private static func findTerminalCommandField(in view: NSView) -> NSTextField? {
        // SwiftUI may expose the accessibility label on an ancestor rather than
        // the backing NSTextField itself. This harness hosts only the terminal
        // command field, so the first editable text field is the command input.
        if let field = view as? NSTextField, field.isEditable {
            return field
        }
        for child in view.subviews {
            if let found = findTerminalCommandField(in: child) { return found }
        }
        return nil
    }

    private func compact(_ session: AgentSession) -> some View {
        HStack(spacing: 12) {
            AgentCompactRoutineLeadingView(session: session)
            Spacer(minLength: 35)
            AgentCompactAttentionTrailingView(text: AgentSessionPresentation.stateLabel(session.state), accent: .cyan)
        }
        .padding(.horizontal, 16).frame(height: 44)
        .background(.black, in: RoundedRectangle(cornerRadius: 17, style: .continuous)).padding(10)
    }

    private func hosted<V: View>(_ view: V, size: CGSize, reduceMotion: Bool, light: Bool, to url: URL) async throws {
        let hosting = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(light ? Color(red: 0.92, green: 0.93, blue: 0.95) : Color(red: 0.025, green: 0.027, blue: 0.055))
            .environment(\.nativeVisualSnapshotTime, 1.35)
            .environment(\.colorScheme, light ? .light : .dark))
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -4000, y: -4000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil }
        // Snapshot settling is not a wall-clock state-transition assertion.
        for _ in 0..<6 { await Task.yield(); hosting.layoutSubtreeIfNeeded() }
        try await Task.sleep(for: .milliseconds(100))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(png.count, 1_000)
        XCTAssertEqual(hosting.bounds.size, size)
        try png.write(to: url, options: .atomic)
    }

    private struct Fixture {
        let store: AgentEventStore
        let feed: AgentWorkspaceFeedStore
        let approvals: AgentApprovalController
        let controller: AgentManagedSessionController
        let presentation: AgentWorkspacePresentation
        let terminal: TerminalSessionController
        let runner: WorkspaceSnapshotTerminalRunner
    }

    private func makeFixture() async throws -> Fixture {
        let store = AgentEventStore()
        let feed = AgentWorkspaceFeedStore()
        store.appliedEventObserver = { [weak feed] event, session in feed?.handleApplied(event, session: session) }
        let approvals = AgentApprovalController(now: { AgentTestFixture.baseDate })
        let controller = AgentManagedSessionController(providers: [WorkspaceSnapshotProvider(provider: .codex), WorkspaceSnapshotProvider(provider: .claude)],
            coordinator: AgentIngestionCoordinator(eventStore: store), eventStore: store, approvals: approvals)
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        for session in store.sessions {
            controller.connect(session)
            for _ in 0..<1_000 where !controller.isManaged(session) { await Task.yield() }
            XCTAssertTrue(controller.isManaged(session))
            await controller.refreshTranscript(for: session)
        }
        controller.flushTranscriptPublications()
        let runner = WorkspaceSnapshotTerminalRunner()
        let terminal = TerminalSessionController(liveActivities: LiveActivityStore(), capabilities: IslandCapabilityRegistry(), runner: runner,
                                                 workingDirectoryPath: "/tmp", now: { AgentTestFixture.baseDate })
        return Fixture(store: store, feed: feed, approvals: approvals, controller: controller,
                       presentation: AgentWorkspacePresentation(), terminal: terminal, runner: runner)
    }

    private func emit(_ fixture: Fixture, session: AgentSessionInstanceID, type: AgentEventType,
                      correlation: String? = nil, offset: Double, payload: AgentEventPayload) {
        XCTAssertEqual(fixture.store.ingest(AgentTestFixture.event("fixture-\(type.stableName)-\(offset)", sessionID: session.sessionID,
            generation: session.generation.rawValue, type: type, offset: offset, correlationID: correlation, payload: payload)), .applied)
    }
}


@MainActor
private final class AgentWorkspaceMountStressState: ObservableObject {
    @Published var showsAgents = true
    @Published var generation = 0
}

private struct AgentWorkspaceMountStressHarness: View {
    @ObservedObject var state: AgentWorkspaceMountStressState
    let sessions: [AgentSession]
    let controller: AgentManagedSessionController
    let approvals: AgentApprovalController
    let feed: AgentWorkspaceFeedStore
    let presentation: AgentWorkspacePresentation
    let terminal: TerminalSessionController
    let selectedID: AgentSessionInstanceID

    var body: some View {
        ZStack {
            if state.showsAgents {
                AgentDashboardContentView(
                    sessions: sessions,
                    accountUsage: controller.accountUsage,
                    showsUsage: true,
                    approvalControl: approvals,
                    managedControl: controller,
                    availableHeight: 482,
                    initialSelectedSessionID: selectedID,
                    contentVisible: true,
                    reduceMotion: false,
                    transcriptPresentationReady: true,
                    transcriptLoadDelay: 0,
                    workspaceFeed: feed,
                    workspacePresentation: presentation,
                    terminal: terminal
                )
                .id("agents-\(state.generation)")
            } else {
                Color.black.opacity(0.01)
                    .id("other-\(state.generation)")
            }
        }
        .animation(.easeOut(duration: 0.01), value: state.showsAgents)
    }
}

private actor WorkspaceSnapshotProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [.resumeSession, .submitPrompt, .interrupt, .resolveApprovals,
        .accountUsage, .contextUsage, .streamMessages, .streamToolActivity, .loadHistory, .selectModel, .selectReasoningEffort]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = .turnAndSubsequent
    private let stream: AsyncStream<AgentInteractiveProviderEvent>
    private let continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(provider: AgentProvider) {
        self.provider = provider
        let pair = AsyncStream<AgentInteractiveProviderEvent>.makeStream()
        stream = pair.stream; continuation = pair.continuation
    }
    private var descriptor: AgentManagedSessionDescriptor {
        .init(provider: provider, nativeSessionID: "\(provider.stableName)-workspace-fixture", cwd: "/tmp/DynamicIsland-fixture",
              model: provider == .codex ? "gpt-fixture" : "claude-fixture", acceptsDirectInput: true)
    }
    func events() async -> AsyncStream<AgentInteractiveProviderEvent> { stream }
    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        [.init(session: descriptor, runtimeState: .idle, updatedAt: AgentTestFixture.baseDate)]
    }
    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? { descriptor.nativeSessionID == nativeSessionID ? descriptor : nil }
    func readAccountUsage() async throws -> AgentUsage {
        AgentUsage(scopedSamples: Dictionary(uniqueKeysWithValues: [("5h", provider == .codex ? 28.0 : 41.0), ("weekly", provider == .codex ? 35.0 : 57.0)].map { scope, used in
            (.init(metric: .quotaUsed, scope: scope), .init(value: used, limit: 100, unit: .fraction, scope: scope,
                source: "\(provider.stableName)-account-rate-limits", observedAt: AgentTestFixture.baseDate))
        }))
    }
    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] {
        [.init(id: "user", nativeSessionID: nativeSessionID, turnID: "fixture-turn", role: .user,
               text: "Inspect the workspace, search its files and validate the implementation.", timestamp: AgentTestFixture.baseDate),
         .init(id: "agent", nativeSessionID: nativeSessionID, turnID: "fixture-turn", role: .agent,
               text: "I’ll inspect the native workspace and preserve exact session ownership while checking the focused tests.", timestamp: AgentTestFixture.baseDate.addingTimeInterval(1))]
    }
    func listModels() async throws -> [AgentManagedModelDescriptor] {
        [.init(id: descriptor.model!, model: descriptor.model!, displayName: provider == .codex ? "Codex fixture" : "Claude fixture", description: nil, isDefault: true,
               supportedReasoningEfforts: [.init(id: "medium", description: "Balanced"), .init(id: "high", description: "Detailed")], defaultReasoningEffort: "medium")]
    }
    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor { descriptor }
    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor { descriptor }
    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor { .init(nativeSessionID: nativeSessionID, turnID: "fixture-turn") }
    func interrupt(nativeSessionID: String, turnID: String) async throws {}
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}
    func stop() async { continuation.finish() }
}

private final class WorkspaceSnapshotTerminalHandle: TerminalProcessHandle {
    var isRunning = true
    func terminate() { isRunning = false }
}
private final class WorkspaceSnapshotTerminalRunner: TerminalProcessRunning {
    var startCount = 0
    let handle = WorkspaceSnapshotTerminalHandle()
    func start(command: String, shellPath: String, workingDirectory: URL?, onOutput: @escaping @Sendable (String) -> Void,
               onExit: @escaping @Sendable (Int32) -> Void) throws -> TerminalProcessHandle {
        startCount += 1
        onOutput("\u{001B}[32mFixture terminal\u{001B}[0m\n$ swift test --filter AgentWorkspace\nOperational terminal output stays owned by one controller.\n")
        return handle
    }
}
