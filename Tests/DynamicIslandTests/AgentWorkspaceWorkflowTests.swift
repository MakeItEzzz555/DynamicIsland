import AppKit
import Foundation
import SwiftUI
import XCTest
@testable import DynamicIsland

/// End-to-end workspace state for the Agents page: the same flow,
/// controller, store and projection the view uses, with fake providers
/// that stream replies. Covers the transition that used to dead-end:
/// New Session → launcher → Start → exact managed session selected →
/// composer → Send → streamed reply.
@MainActor
final class AgentWorkspaceWorkflowTests: XCTestCase {
    private var folders: [URL] = []

    override func tearDown() async throws {
        for folder in folders { try? FileManager.default.removeItem(at: folder) }
        folders = []
    }

    // MARK: New session end to end

    func testNewClaudeSessionFromEmptyWorkspaceReachesComposerAndStreams() async throws {
        try await assertNewSessionWorkflow(.claude)
    }

    func testNewCodexSessionFromEmptyWorkspaceReachesComposerAndStreams() async throws {
        try await assertNewSessionWorkflow(.codex)
    }

    private func assertNewSessionWorkflow(_ provider: AgentProvider) async throws {
        let harness = Harness(providers: [.claude, .codex])
        await harness.controller.refreshPersistentSnapshot()
        harness.controller.selectProvider(provider)
        let folder = try makeFolder("project-\(provider.stableName)")

        // Empty workspace offers New Session.
        XCTAssertEqual(harness.projection().surface, .empty(provider))

        // New Session opens the launcher, preselecting provider; no session yet.
        harness.flow.present(.newSession, provider: provider, folder: nil)
        XCTAssertEqual(harness.projection().surface, .launcher)
        XCTAssertFalse(harness.flow.canStart, "Start requires a folder")
        XCTAssertTrue(harness.flow.useFolder(folder.path))
        XCTAssertTrue(harness.controller.selectNewSessionModel("model-b", for: provider))

        let maybeStarted = await harness.flow.start(using: harness.controller)
        let started = try XCTUnwrap(maybeStarted)

        // Launcher closed; the exact new session is selected, managed, in
        // the chosen folder and composer-ready.
        XCTAssertFalse(harness.flow.isPresented)
        let projection = harness.projection()
        guard case .session(let session, let surface) = projection.surface else {
            return XCTFail("expected selected session, got \(projection.surface)")
        }
        XCTAssertEqual(session.id, started.instance)
        XCTAssertEqual(session.id.sessionID.provider, provider)
        XCTAssertEqual(session.project.workingDirectory, folder.path)
        XCTAssertEqual(surface, .composer)
        XCTAssertEqual(harness.controller.interactionState(for: session), .ready)
        let fake = harness.fake(provider)
        let startedCalls = await fake.startedCalls()
        XCTAssertEqual(startedCalls.map(\.cwd), [folder.path])
        XCTAssertEqual(startedCalls.map(\.model), ["model-b"])

        // Send "hello" and receive the streamed reply.
        let accepted = await harness.controller.submit("hello", for: session)
        XCTAssertTrue(accepted)
        try await waitFor {
            harness.controller.transcript(for: session).contains {
                $0.role == .agent && $0.text == "Hi from \(provider.stableName)"
            }
        }
        try await waitFor { harness.controller.interactionState(for: session) == .ready }
        let submitted = await fake.submittedPrompts()
        XCTAssertEqual(submitted, ["hello"])
        XCTAssertEqual(harness.projection().surface, .session(
            try XCTUnwrap(harness.store.session(for: started.instance)),
            .composer
        ))
    }

    // MARK: Failure

    func testStartFailureKeepsLauncherOpenWithErrorAndNoPhantomSession() async throws {
        let harness = Harness(providers: [.claude])
        await harness.fake(.claude).setStartFailure(true)
        harness.flow.present(.newSession, provider: .claude, folder: try makeFolder("fail").path)

        let started = await harness.flow.start(using: harness.controller)

        XCTAssertNil(started)
        XCTAssertTrue(harness.flow.isPresented)
        XCTAssertNotNil(harness.flow.errorMessage)
        XCTAssertTrue(harness.store.sessions.isEmpty)
        XCTAssertNil(harness.controller.selectedSessionID)
        XCTAssertEqual(harness.projection().surface, .launcher)
        harness.flow.dismiss()
        XCTAssertEqual(harness.projection().surface, .empty(.claude))
    }

    func testPrimaryNewSessionPathNeverStartsWithoutAFolder() async throws {
        let harness = Harness(providers: [.claude])
        harness.flow.present(.newSession, provider: .claude, folder: nil)

        let withoutFolder = await harness.flow.start(using: harness.controller)
        XCTAssertNil(withoutFolder)
        XCTAssertEqual(harness.flow.errorMessage, "Choose a project folder first")

        XCTAssertFalse(harness.flow.useFolder("/nonexistent/DynamicIsland-\(UUID().uuidString)"))
        let viaWrapper = await harness.controller.startNewSession(cwd: nil)
        XCTAssertNil(viaWrapper)
        let missing = await harness.controller.startManagedSession(
            provider: .claude,
            cwd: "/nonexistent/DynamicIsland-\(UUID().uuidString)"
        )
        XCTAssertEqual(missing, .failure(AgentManagedStartFailure("Folder not found. Choose an existing folder")))
        let calls = await harness.fake(.claude).startedCalls()
        XCTAssertTrue(calls.isEmpty)
        XCTAssertTrue(harness.store.sessions.isEmpty)
    }

    // MARK: Root cause regression

    /// Persisted history used to fill the 32-session store and make every
    /// new session fail silently ("New session" did nothing).
    func testLargeDiscoveredHistoryNeverBlocksNewSessions() async throws {
        let harness = Harness(providers: [.claude, .codex])
        let history = (0..<120).map { index in
            AgentDiscoveredSessionDescriptor(
                session: AgentManagedSessionDescriptor(
                    provider: .codex,
                    nativeSessionID: "history-\(index)",
                    cwd: "/tmp/history-\(index % 7)",
                    model: nil,
                    acceptsDirectInput: true
                ),
                runtimeState: .notLoaded,
                updatedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
            )
        }
        await harness.fake(.codex).setDiscovered(history)
        await harness.fake(.claude).setDiscovered([AgentDiscoveredSessionDescriptor(
            session: AgentManagedSessionDescriptor(
                provider: .claude, nativeSessionID: "claude-history", cwd: "/tmp/c",
                model: nil, acceptsDirectInput: true
            ),
            runtimeState: .notLoaded,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )])
        await harness.controller.refreshPersistentSnapshot()

        let codexHistory = harness.store.sessions.filter { $0.id.sessionID.provider == .codex }
        XCTAssertEqual(codexHistory.count, AgentManagedSessionController.maximumDiscoveredSessionsPerProvider)
        XCTAssertTrue(harness.store.sessions.contains { $0.id.sessionID.nativeID == "claude-history" },
                      "Claude history must not be crowded out by Codex history")

        for provider in [AgentProvider.claude, .codex] {
            let result = await harness.controller.startManagedSession(
                provider: provider,
                cwd: try makeFolder("capacity-\(provider.stableName)").path
            )
            guard case .success(let started) = result else {
                return XCTFail("\(provider.stableName) start failed: \(result)")
            }
            XCTAssertEqual(harness.controller.selectedSessionID, started.instance)
        }
    }

    // MARK: Existing sessions

    func testResumableSessionOffersResumeAndBecomesComposerReady() async throws {
        let harness = Harness(providers: [.claude])
        await harness.fake(.claude).setDiscovered([AgentDiscoveredSessionDescriptor(
            session: AgentManagedSessionDescriptor(
                provider: .claude, nativeSessionID: "resume-me", cwd: try makeFolder("resume").path,
                model: nil, acceptsDirectInput: true
            ),
            runtimeState: .notLoaded,
            updatedAt: Date()
        )])
        await harness.controller.refreshPersistentSnapshot()
        let session = try XCTUnwrap(harness.store.sessions.first)
        harness.controller.selectSession(session.id)
        XCTAssertEqual(harness.projection().surface, .session(session, .resumable))
        XCTAssertEqual(
            AgentSessionControlBanner.content(for: .resumable, provider: .claude).action,
            "Resume"
        )

        harness.controller.connect(session)
        try await waitFor {
            harness.store.sessions.contains { harness.controller.isManaged($0) }
        }
        let resumed = try XCTUnwrap(harness.store.sessions.first { harness.controller.isManaged($0) })
        XCTAssertEqual(resumed.id.sessionID.nativeID, "resume-me")
        XCTAssertEqual(harness.controller.selectedSessionID, resumed.id)
        XCTAssertEqual(harness.projection().surface, .session(resumed, .composer))
    }

    func testObservedSessionIsExplicitlyReadOnlyWhenProviderCannotControlIt() async throws {
        let harness = Harness(providers: [.claude])
        let other = AgentSession.fixture(provider: .other("cursor"), nativeID: "observed", cwd: "/tmp/x")
        XCTAssertEqual(AgentWorkspaceProjection.controlSurface(for: other, controller: harness.controller), .readOnly)
        XCTAssertEqual(
            AgentSessionControlBanner.content(for: .readOnly, provider: .other("cursor")).title,
            "Read-only observed session"
        )
        XCTAssertEqual(
            AgentSessionControlBanner.content(for: .controllable, provider: .claude).action,
            "Take Control"
        )
    }

    // MARK: Project filter and provider switching

    func testNewSessionInAnotherProjectIsNeverFilteredOut() async throws {
        let harness = Harness(providers: [.claude])
        let projectA = try makeFolder("project-a")
        let projectB = try makeFolder("project-b")
        let first = try await harness.start(.claude, in: projectA)
        let keyA = AgentProjectGrouping.key(
            for: try XCTUnwrap(harness.store.session(for: first.instance)),
            locations: .empty
        ).rawValue

        let second = try await harness.start(.claude, in: projectB)
        let secondSession = try XCTUnwrap(harness.store.session(for: second.instance))

        // Filtered to A, the new B session would be hidden; the post-start
        // key moves the filter to B so it stays visible and selected.
        let key = AgentWorkspaceProjection.projectKey(
            afterStarting: secondSession,
            currentKey: keyA,
            locations: .empty
        )
        XCTAssertNotEqual(key, keyA)
        let projection = harness.projection(projectKey: key)
        XCTAssertEqual(projection.surface, .session(secondSession, .composer))

        // A session started inside the current project keeps the filter.
        XCTAssertEqual(
            AgentWorkspaceProjection.projectKey(
                afterStarting: try XCTUnwrap(harness.store.session(for: first.instance)),
                currentKey: keyA,
                locations: .empty
            ),
            keyA
        )
    }

    func testProviderSwitchKeepsExactSessionsAndDraftsSeparate() async throws {
        let harness = Harness(providers: [.claude, .codex])
        let claude = try await harness.start(.claude, in: try makeFolder("switch-a"))
        harness.controller.setComposerDraft("draft for claude", for: claude.instance)

        let codex = try await harness.start(.codex, in: try makeFolder("switch-b"))
        XCTAssertEqual(harness.controller.selectedSessionID, codex.instance)
        XCTAssertEqual(harness.controller.composerDraft(for: codex.instance), "")
        harness.controller.setComposerDraft("draft for codex", for: codex.instance)

        harness.controller.selectProvider(.claude)
        XCTAssertEqual(harness.controller.selectedSessionID, claude.instance)
        guard case .session(let selected, .composer) = harness.projection().surface else {
            return XCTFail("Claude session should be selected and composer-ready")
        }
        XCTAssertEqual(selected.id, claude.instance)
        XCTAssertEqual(harness.controller.composerDraft(for: claude.instance), "draft for claude")
        XCTAssertEqual(harness.controller.composerDraft(for: codex.instance), "draft for codex")

        harness.controller.selectProvider(.codex)
        XCTAssertEqual(harness.controller.selectedSessionID, codex.instance)
    }

    // MARK: Folder handling

    func testFolderValidationKeepsExactPathIncludingSymlinks() throws {
        let real = try makeFolder("real")
        let link = real.deletingLastPathComponent().appendingPathComponent("link-\(UUID().uuidString.prefix(6))")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        folders.append(link)
        let file = real.appendingPathComponent("file.txt")
        try Data().write(to: file)

        XCTAssertEqual(AgentManagedSessionController.validatedWorkingDirectory(real.path + "/"), real.path)
        XCTAssertEqual(AgentManagedSessionController.validatedWorkingDirectory(link.path), link.path)
        XCTAssertNil(AgentManagedSessionController.validatedWorkingDirectory(file.path))
        XCTAssertNil(AgentManagedSessionController.validatedWorkingDirectory("relative/path"))
        XCTAssertNil(AgentManagedSessionController.validatedWorkingDirectory(real.path + "/../real"))
        XCTAssertNil(AgentManagedSessionController.validatedWorkingDirectory("  "))
    }

    func testNewFolderIsCreatedEmptyAndNeverOverwritesExistingItems() throws {
        let flow = AgentNewSessionFlow()
        let parent = try makeFolder("parent")
        let target = parent.appendingPathComponent("New Project")

        XCTAssertTrue(flow.createFolder(at: target))
        XCTAssertEqual(flow.folderPath, target.path)
        XCTAssertEqual(flow.mode, .newSession)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(".git").path))

        try Data("keep".utf8).write(to: target.appendingPathComponent("keep.txt"))
        XCTAssertFalse(flow.createFolder(at: target))
        XCTAssertEqual(flow.errorMessage, "A file or folder with that name already exists")
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("keep.txt")), Data("keep".utf8))
    }

    // MARK: Provider visuals

    func testProviderColorsAreAgentNotchSourceConstants() {
        func rgb(_ color: Color) -> [Double] {
            let ns = NSColor(color).usingColorSpace(.sRGB)!
            return [ns.redComponent, ns.greenComponent, ns.blueComponent].map { (Double($0) * 100).rounded() / 100 }
        }
        XCTAssertEqual(rgb(AgentVisualStyle.providerAccent(.claude)), [1.0, 0.55, 0.2])
        XCTAssertEqual(rgb(AgentVisualStyle.providerAccent(.codex)), [0.2, 0.45, 0.9])
        XCTAssertNotEqual(AgentVisualStyle.providerSymbol(.codex), "terminal")
        XCTAssertNotEqual(AgentVisualStyle.providerSymbol(.claude), "terminal")
    }

    // MARK: Helpers

    private func makeFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentWorkflow-\(name)-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folders.append(url)
        return url
    }

    private func waitFor(timeout: TimeInterval = 3, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("condition not met")
    }
}

// MARK: - Harness

@MainActor
private final class Harness {
    let store = AgentEventStore()
    let controller: AgentManagedSessionController
    let flow = AgentNewSessionFlow()
    private let fakes: [AgentProvider: WorkflowFakeProvider]

    init(providers: [AgentProvider]) {
        let fakes = Dictionary(uniqueKeysWithValues: providers.map { ($0, WorkflowFakeProvider(provider: $0)) })
        self.fakes = fakes
        controller = AgentManagedSessionController(
            providers: providers.compactMap { fakes[$0] },
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        controller.startObserving()
    }

    deinit {
        MainActor.assumeIsolated { controller.stop() }
    }

    func fake(_ provider: AgentProvider) -> WorkflowFakeProvider {
        fakes[provider]!
    }

    func projection(projectKey: String? = nil) -> AgentWorkspaceProjection {
        AgentWorkspaceProjection.make(
            sessions: store.sessions.filter(controller.shouldPresent),
            controller: controller,
            projectKey: projectKey,
            locations: .empty,
            launcherOpen: flow.isPresented
        )
    }

    func start(_ provider: AgentProvider, in folder: URL) async throws -> AgentManagedStartedSession {
        flow.present(.newSession, provider: provider, folder: folder.path)
        let started = await flow.start(using: controller)
        return try XCTUnwrap(started, flow.errorMessage ?? "start failed")
    }
}

private actor WorkflowFakeProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .startSession, .resumeSession, .submitPrompt, .interrupt, .selectModel, .streamMessages
    ]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = nil

    private var discovered: [AgentDiscoveredSessionDescriptor] = []
    private var started: [(cwd: String?, model: String?)] = []
    private var prompts: [String] = []
    private var startFailure = false
    private let stream: AsyncStream<AgentInteractiveProviderEvent>
    private let continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(provider: AgentProvider) {
        self.provider = provider
        var continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent> { stream }
    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] { discovered }
    func setDiscovered(_ value: [AgentDiscoveredSessionDescriptor]) { discovered = value }
    func setStartFailure(_ value: Bool) { startFailure = value }
    func startedCalls() -> [(cwd: String?, model: String?)] { started }
    func submittedPrompts() -> [String] { prompts }

    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? {
        discovered.first { $0.session.nativeSessionID == nativeSessionID }?.session
    }

    func readAccountUsage() async throws -> AgentUsage { AgentUsage() }
    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] { [] }

    func listModels() async throws -> [AgentManagedModelDescriptor] {
        [
            AgentManagedModelDescriptor(id: "model-a", model: "model-a", displayName: "Model A", description: nil, isDefault: true),
            AgentManagedModelDescriptor(id: "model-b", model: "model-b", displayName: "Model B", description: nil, isDefault: false)
        ]
    }

    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor {
        if startFailure { throw ClaudeCodeStreamingError.executableNotFound }
        started.append((cwd, model))
        return AgentManagedSessionDescriptor(
            provider: provider,
            nativeSessionID: "\(provider.stableName)-new-\(started.count)",
            cwd: cwd,
            model: model,
            acceptsDirectInput: true
        )
    }

    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor {
        guard let descriptor = discovered.first(where: { $0.session.nativeSessionID == nativeSessionID })?.session else {
            throw ClaudeCodeStreamingError.sessionNotRunning
        }
        return descriptor
    }

    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor {
        prompts.append(prompt)
        let turn = AgentManagedTurnDescriptor(nativeSessionID: nativeSessionID, turnID: "turn-\(prompts.count)")
        let reply = "Hi from \(provider.stableName)"
        let continuation = continuation
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            continuation.yield(.turnStarted(turn))
            continuation.yield(.transcriptDelta(
                nativeSessionID: nativeSessionID, turnID: turn.turnID, itemID: "reply-\(turn.turnID)", delta: "Hi from "
            ))
            continuation.yield(.transcript(AgentManagedTranscriptEntry(
                id: "reply-\(turn.turnID)", nativeSessionID: nativeSessionID, turnID: turn.turnID,
                role: .agent, text: reply, timestamp: Date()
            )))
            continuation.yield(.turnCompleted(turn, state: .completed, summary: nil))
        }
        return turn
    }

    func interrupt(nativeSessionID: String, turnID: String) async throws {}
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}
    func stop() async {}
}

private extension AgentSession {
    @MainActor
    static func fixture(provider: AgentProvider, nativeID: String, cwd: String) -> AgentSession {
        let store = AgentEventStore()
        store.ingest(AgentTestFixture.event(
            "observed-start",
            sessionID: AgentTestFixture.sessionID(provider, nativeID),
            type: .sessionStarted,
            offset: 0,
            payload: .sessionMetadata(AgentSessionMetadata(project: AgentTestFixture.project(path: cwd)))
        ))
        return store.sessions[0]
    }
}
