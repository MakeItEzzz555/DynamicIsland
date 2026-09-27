import Foundation
import XCTest
@testable import DynamicIsland

final class AgentManagedSessionControllerTests: XCTestCase {
    @MainActor
    func testPersistentSnapshotPublishesUsageAndIdleSessionWithoutActiveTurn() async throws {
        let observedAt = Date(timeIntervalSince1970: 2_100_000_000)
        let usage = AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: 72,
                limit: 100,
                unit: .fraction,
                scope: "5h",
                source: "fake-account",
                observedAt: observedAt
            ),
            AgentUsageKey(metric: .quotaUsed, scope: "weekly"): AgentUsageSample(
                value: 19,
                limit: 100,
                unit: .fraction,
                scope: "weekly",
                source: "fake-account",
                observedAt: observedAt
            )
        ])
        let provider = PersistentSnapshotFakeProvider(
            sessions: [
                AgentDiscoveredSessionDescriptor(
                    session: AgentManagedSessionDescriptor(
                        provider: .codex,
                        nativeSessionID: "idle-thread",
                        cwd: "/tmp/DynamicIsland",
                        model: "gpt-test",
                        acceptsDirectInput: false
                    ),
                    runtimeState: .idle,
                    updatedAt: observedAt
                )
            ],
            usage: usage
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        await controller.refreshPersistentSnapshot()

        XCTAssertEqual(
            controller.accountUsage.samples(for: .quotaUsed).first { $0.scope == "5h" }?.value,
            72
        )
        XCTAssertEqual(store.sessions.count, 1)
        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(session.id.sessionID.provider, .codex)
        XCTAssertEqual(session.id.sessionID.nativeID, "idle-thread")
        XCTAssertEqual(session.state, .idle)
        XCTAssertTrue(session.isActive)
        XCTAssertNil(session.endedAt)
    }

    @MainActor
    func testNotLoadedSessionIsAvailableButNotWorking() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "resumable", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        await controller.refreshPersistentSnapshot()

        let session = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(session.id.sessionID.nativeID, "resumable")
        XCTAssertEqual(session.state, .idle)
        XCTAssertEqual(session.availability, .resumable)
        XCTAssertEqual(
            AgentSessionPresentation.displayedStateLabel(for: session, at: Date()),
            "Resumable"
        )
        XCTAssertTrue(controller.canConnect(session))
    }

    @MainActor
    func testActiveDiscoveredSessionBecomesWorking() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "active", state: .active)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        await controller.refreshPersistentSnapshot()

        XCTAssertEqual(store.sessions.first?.state, .working)
    }

    @MainActor
    func testLastTrustworthyUsageSurvivesTransientFailure() async throws {
        let sample = AgentUsageSample(
            value: 16, limit: 100, unit: .fraction, scope: "weekly",
            source: "fake-account", observedAt: Date()
        )
        let provider = PersistentSnapshotFakeProvider(
            sessions: [],
            usage: AgentUsage(scopedSamples: [
                AgentUsageKey(metric: .quotaUsed, scope: "weekly"): sample
            ])
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        await controller.refreshPersistentSnapshot()
        await provider.setUsageFailure(true)

        await controller.refreshPersistentSnapshot()

        XCTAssertEqual(
            controller.accountUsage.samples(for: .quotaUsed).first { $0.scope == "weekly" }?.value,
            16
        )
        XCTAssertNotNil(controller.lastTransportError)
    }

    @MainActor
    func testDiscoveryConvergesWithExistingSessionIdentity() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "shared-thread", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let coordinator = AgentIngestionCoordinator(eventStore: store)
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: coordinator,
            eventStore: store,
            approvals: AgentApprovalController()
        )

        await controller.refreshPersistentSnapshot()
        await controller.refreshPersistentSnapshot()

        XCTAssertEqual(store.sessions.filter {
            $0.id.sessionID.nativeID == "shared-thread"
        }.count, 1)
    }

    @MainActor
    func testSessionsFallingOutsideBoundedDiscoveryStopPresenting() async throws {
        let first = Self.descriptor(id: "first", state: .notLoaded)
        let second = Self.descriptor(id: "second", state: .notLoaded)
        let provider = PersistentSnapshotFakeProvider(
            sessions: [first, second],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        await controller.refreshPersistentSnapshot()
        await provider.setDiscovered([second])

        await controller.refreshPersistentSnapshot()

        let firstSession = try XCTUnwrap(store.sessions.first {
            $0.id.sessionID.nativeID == "first"
        })
        let secondSession = try XCTUnwrap(store.sessions.first {
            $0.id.sessionID.nativeID == "second"
        })
        XCTAssertFalse(controller.shouldPresent(firstSession))
        XCTAssertTrue(controller.shouldPresent(secondSession))
    }

    @MainActor
    func testManagedTurnCompletionReturnsThreadToIdleResumableState() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "managed", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        let session = try XCTUnwrap(store.sessions.first)
        controller.connect(session)
        try await Task.sleep(for: .milliseconds(30))
        await provider.yield(.turnStarted(.init(nativeSessionID: "managed", turnID: "turn-1")))
        try await Task.sleep(for: .milliseconds(30))
        await provider.yield(.turnCompleted(
            .init(nativeSessionID: "managed", turnID: "turn-1"),
            state: .completed,
            summary: nil
        ))
        try await Task.sleep(for: .milliseconds(30))

        let completed = try XCTUnwrap(store.sessions.first)
        XCTAssertEqual(completed.state, .completed)
        XCTAssertNil(completed.endedAt)
        XCTAssertEqual(
            AgentSessionPresentation.displayedStateLabel(for: completed, at: Date()),
            "Resumable"
        )
        controller.stop()
    }

    @MainActor
    func testSelectedModelOverrideIsAppliedToManagedSubmission() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "model-thread", state: .idle)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        controller.startObserving()
        await controller.refreshPersistentSnapshot()

        guard let session = store.sessions.first(where: {
            $0.id.sessionID.nativeID == "model-thread"
        }) else {
            return XCTFail("Expected discovered session")
        }

        controller.connect(session)
        try await Task.sleep(for: .milliseconds(30))
        await controller.refreshPersistentSnapshot()

        guard let managedSession = store.sessions.first(where: {
            $0.id.sessionID.nativeID == "model-thread"
        }) else {
            return XCTFail("Expected managed session")
        }

        XCTAssertTrue(controller.interactiveCapabilities.contains(.selectModel))
        XCTAssertTrue(controller.availableModels.contains { $0.model == "model-b" })

        controller.selectModel("model-b", for: managedSession)
        XCTAssertEqual(controller.selectedModel(for: managedSession), "model-b")

        let accepted = await controller.submit("hello", for: managedSession)
        XCTAssertTrue(accepted)
        let submitted = await provider.submittedPrompts()
        XCTAssertEqual(submitted.last, "hello|model-b")

        controller.stop()
    }

    @MainActor
    func testSubmitReportsProviderAcceptanceAndFailureSynchronouslyToComposer() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "submit-thread", state: .idle)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        await controller.refreshPersistentSnapshot()
        let session = try XCTUnwrap(store.sessions.first)
        controller.connect(session)
        try await Task.sleep(for: .milliseconds(20))

        let accepted = await controller.submit("hello", for: session)
        XCTAssertTrue(accepted)
        let submitted = await provider.submittedPrompts()
        XCTAssertEqual(submitted, ["hello"])
        XCTAssertEqual(controller.transcript(for: session).map(\.text), ["hello"])

        controller.startObserving()
        await provider.yield(.transcript(AgentManagedTranscriptEntry(
            id: "authoritative-user",
            nativeSessionID: "submit-thread",
            turnID: "turn-submit",
            role: .user,
            text: "hello",
            timestamp: Date()
        )))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.transcript(for: session).map(\.text), ["hello"])

        await provider.setSubmitFailure(true)
        let rejected = await controller.submit("keep this draft", for: session)
        XCTAssertFalse(rejected)
        XCTAssertNotNil(controller.statusMessage(for: session))
    }

    @MainActor
    func testTranscriptHistoryAndStreamingDeltaStayBoundedAndReplaceByIdentity() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "managed", state: .idle)],
            usage: AgentUsage()
        )
        await provider.setTranscript([
            AgentManagedTranscriptEntry(
                id: "user-1",
                nativeSessionID: "managed",
                turnID: "turn-1",
                role: .user,
                text: "hello",
                timestamp: Date(timeIntervalSince1970: 10)
            )
        ])
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        await controller.refreshPersistentSnapshot()
        let session = try XCTUnwrap(store.sessions.first)
        await controller.refreshTranscript(for: session)

        XCTAssertEqual(controller.transcript(for: session).map(\.text), ["hello"])

        controller.startObserving()
        await provider.yield(.transcriptDelta(
            nativeSessionID: "managed",
            turnID: "turn-1",
            itemID: "agent-1",
            delta: "hel"
        ))
        await provider.yield(.transcriptDelta(
            nativeSessionID: "managed",
            turnID: "turn-1",
            itemID: "agent-1",
            delta: "lo"
        ))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.transcript(for: session).last?.text, "hello")

        await provider.yield(.transcript(AgentManagedTranscriptEntry(
            id: "agent-1",
            nativeSessionID: "managed",
            turnID: "turn-1",
            role: .agent,
            text: "hello final",
            timestamp: Date(timeIntervalSince1970: 20)
        )))
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(controller.transcript(for: session).last?.text, "hello final")
        controller.stop()
    }

    @MainActor
    func testManagedTransportFailureExitsWorkingState() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "managed-error", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        controller.connect(try XCTUnwrap(store.sessions.first))
        try await Task.sleep(for: .milliseconds(30))
        await provider.yield(.turnStarted(.init(
            nativeSessionID: "managed-error",
            turnID: "turn-1"
        )))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(store.sessions.first?.state, .working)

        await provider.yield(.transportClosed("credential=must-not-surface"))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.sessions.first?.state, .failed)
        XCTAssertEqual(controller.lastTransportError, "Codex app-server disconnected")
        XCTAssertFalse(controller.lastTransportError?.contains("credential") ?? true)
        controller.stop()
    }

    @MainActor
    func testManagedProviderQuotaFailureExitsWorkingState() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "quota-error", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        controller.connect(try XCTUnwrap(store.sessions.first))
        try await Task.sleep(for: .milliseconds(30))
        await provider.yield(.turnStarted(.init(
            nativeSessionID: "quota-error",
            turnID: "turn-1"
        )))
        try await Task.sleep(for: .milliseconds(30))

        await provider.yield(.providerFailure(
            nativeSessionID: "quota-error",
            summary: "Usage limit reached"
        ))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(store.sessions.first?.state, .failed)
        XCTAssertFalse(controller.managed["quota-error"]?.canInterrupt ?? true)
        controller.stop()
    }

    private static func descriptor(
        id: String,
        state: AgentDiscoveredSessionRuntimeState
    ) -> AgentDiscoveredSessionDescriptor {
        AgentDiscoveredSessionDescriptor(
            session: AgentManagedSessionDescriptor(
                provider: .codex,
                nativeSessionID: id,
                cwd: "/tmp/DynamicIsland",
                model: "gpt-test",
                acceptsDirectInput: state != .notLoaded
            ),
            runtimeState: state,
            updatedAt: Date(timeIntervalSince1970: 2_100_000_000)
        )
    }
}

private actor PersistentSnapshotFakeProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider = .codex
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .startSession, .resumeSession, .submitPrompt, .interrupt, .selectModel,
        .resolveApprovals, .accountUsage, .contextUsage, .streamToolActivity
    ]

    private var discovered: [AgentDiscoveredSessionDescriptor]
    private let usage: AgentUsage
    private var usageFailure = false
    private var transcript: [AgentManagedTranscriptEntry] = []
    private var submitted: [String] = []
    private var submitFailure = false
    private let eventStream: AsyncStream<AgentInteractiveProviderEvent>
    private let eventContinuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(sessions: [AgentDiscoveredSessionDescriptor], usage: AgentUsage) {
        discovered = sessions
        self.usage = usage
        var continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation!
        eventStream = AsyncStream { continuation = $0 }
        eventContinuation = continuation
    }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent> {
        eventStream
    }

    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        discovered
    }

    func readAccountUsage() async throws -> AgentUsage {
        if usageFailure { throw CodexAppServerError.transportClosed(nil) }
        return usage
    }

    func listModels() async throws -> [AgentInteractiveModelOption] {
        [
            AgentInteractiveModelOption(
                id: "model-a",
                model: "model-a",
                displayName: "Model A",
                description: nil,
                isDefault: true
            ),
            AgentInteractiveModelOption(
                id: "model-b",
                model: "model-b",
                displayName: "Model B",
                description: nil,
                isDefault: false
            )
        ]
    }

    func readTranscript(
        nativeSessionID: String,
        limit: Int
    ) async throws -> [AgentManagedTranscriptEntry] {
        Array(transcript.filter { $0.nativeSessionID == nativeSessionID }.suffix(max(limit, 0)))
    }

    func setTranscript(_ value: [AgentManagedTranscriptEntry]) {
        transcript = value
    }

    func setUsageFailure(_ value: Bool) {
        usageFailure = value
    }

    func setDiscovered(_ value: [AgentDiscoveredSessionDescriptor]) {
        discovered = value
    }

    func yield(_ event: AgentInteractiveProviderEvent) {
        eventContinuation.yield(event)
    }

    func startSession(cwd: String?) async throws -> AgentManagedSessionDescriptor {
        throw CodexAppServerError.invalidResponse("unused")
    }

    func resumeSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor {
        guard let descriptor = discovered.first(where: {
            $0.session.nativeSessionID == nativeSessionID
        })?.session else {
            throw CodexAppServerError.invalidResponse("thread/resume")
        }
        return AgentManagedSessionDescriptor(
            provider: descriptor.provider,
            nativeSessionID: descriptor.nativeSessionID,
            cwd: descriptor.cwd,
            model: descriptor.model,
            acceptsDirectInput: true
        )
    }

    func submit(
        prompt: String,
        nativeSessionID: String,
        model: String?
    ) async throws -> AgentManagedTurnDescriptor {
        if submitFailure { throw CodexAppServerError.rpcError(code: -1, message: "failed") }
        submitted.append(model.map { "\(prompt)|\($0)" } ?? prompt)
        return AgentManagedTurnDescriptor(nativeSessionID: nativeSessionID, turnID: "turn-submit")
    }

    func setSubmitFailure(_ value: Bool) {
        submitFailure = value
    }

    func submittedPrompts() -> [String] {
        submitted
    }

    func interrupt(nativeSessionID: String, turnID: String) async throws {}

    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}

    func stop() async {
        eventContinuation.finish()
    }
}
