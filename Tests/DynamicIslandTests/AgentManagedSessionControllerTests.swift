import Foundation
import XCTest
@testable import DynamicIsland

final class AgentManagedSessionControllerTests: XCTestCase {
    @MainActor
    func testCrossProviderIdentitySelectionAndUsageRemainIsolated() async throws {
        let codexUsage = AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: 20, limit: 100, unit: .fraction, scope: "5h",
                source: "codex", observedAt: Date()
            )
        ])
        let claudeUsage = AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: 70, limit: 100, unit: .fraction, scope: "5h",
                source: "claude", observedAt: Date()
            )
        ])
        let codex = PersistentSnapshotFakeProvider(
            provider: .codex,
            sessions: [Self.descriptor(id: "shared", state: .idle, provider: .codex)],
            usage: codexUsage
        )
        let claude = PersistentSnapshotFakeProvider(
            provider: .claude,
            sessions: [Self.descriptor(id: "shared", state: .idle, provider: .claude)],
            usage: claudeUsage
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            providers: [codex, claude],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        await controller.refreshPersistentSnapshot()

        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(Set(store.sessions.map(\.id.sessionID)), [
            AgentSessionID(provider: .codex, nativeID: "shared"),
            AgentSessionID(provider: .claude, nativeID: "shared")
        ])
        let codexSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .codex })
        let claudeSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .claude })
        controller.selectSession(codexSession.id)
        XCTAssertEqual(controller.accountUsage.samples(for: .quotaUsed).first?.value, 20)
        controller.selectSession(claudeSession.id)
        XCTAssertEqual(controller.accountUsage.samples(for: .quotaUsed).first?.value, 70)
        controller.selectProvider(.codex)
        XCTAssertEqual(controller.selectedSessionID, codexSession.id)
        controller.selectProvider(.claude)
        XCTAssertEqual(controller.selectedSessionID, claudeSession.id)
    }

    @MainActor
    func testModelCatalogAndScopeAreResolvedForExactSessionProvider() async throws {
        let codex = PersistentSnapshotFakeProvider(
            provider: .codex,
            sessions: [Self.descriptor(id: "codex-models", state: .idle, provider: .codex)],
            usage: AgentUsage()
        )
        let claude = PersistentSnapshotFakeProvider(
            provider: .claude,
            sessions: [Self.descriptor(id: "claude-models", state: .idle, provider: .claude)],
            usage: AgentUsage(),
            capabilities: [.resumeSession, .submitPrompt, .selectModel]
        )
        await codex.setModels([Self.model("codex-only")])
        await claude.setModels([Self.model("claude-only")])

        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            providers: [codex, claude],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        await controller.refreshPersistentSnapshot()
        let codexSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .codex })
        let claudeSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .claude })

        XCTAssertEqual(controller.availableModels(for: codexSession).map(\.model), ["codex-only"])
        XCTAssertEqual(controller.availableModels(for: claudeSession).map(\.model), ["claude-only"])
        XCTAssertEqual(controller.modelSelectionScope(for: codexSession), .turnAndSubsequent)
        XCTAssertEqual(controller.modelSelectionScope(for: claudeSession), .turnAndSubsequent)
        XCTAssertTrue(controller.selectModel("codex-only", for: codexSession))
        XCTAssertFalse(controller.selectModel("claude-only", for: codexSession))
        XCTAssertTrue(controller.selectModel("claude-only", for: claudeSession))
    }

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
        XCTAssertFalse(session.capabilities.contains(.approvalControl))
        XCTAssertTrue(controller.capabilities(for: .codex).contains(.loadHistory))
        XCTAssertTrue(controller.capabilities(for: .claude).isEmpty)
        XCTAssertEqual(controller.managedProviders, [.codex])
        XCTAssertEqual(controller.mode(for: session), .observed)
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
    func testDistinctThreadsWithSameProjectRemainDistinctAndSelectionPersists() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [
                Self.descriptor(id: "thread-a", state: .idle),
                Self.descriptor(id: "thread-b", state: .notLoaded)
            ],
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
        XCTAssertEqual(store.sessions.count, 2)
        let selected = try XCTUnwrap(store.sessions.first {
            $0.id.sessionID.nativeID == "thread-b"
        })
        controller.selectSession(selected.id)

        // Reconciliation is what a reconstructed Agents view performs.
        controller.reconcileSelection(with: store.sessions)
        await controller.refreshPersistentSnapshot()
        controller.reconcileSelection(with: store.sessions)

        XCTAssertEqual(controller.selectedSessionID, selected.id)
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
            sessions: [
                Self.descriptor(id: "model-thread", state: .idle),
                Self.descriptor(id: "other-thread", state: .idle)
            ],
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

        XCTAssertTrue(controller.selectModel("model-b", for: managedSession))
        XCTAssertEqual(controller.selectedModel(for: managedSession), "gpt-test")
        XCTAssertEqual(controller.pendingModel(for: managedSession), "model-b")
        XCTAssertFalse(controller.selectModel("unsupported-model", for: managedSession))
        XCTAssertEqual(controller.selectedModel(for: managedSession), "gpt-test")
        XCTAssertEqual(controller.pendingModel(for: managedSession), "model-b")
        let otherSession = try XCTUnwrap(store.sessions.first {
            $0.id.sessionID.nativeID == "other-thread"
        })
        XCTAssertEqual(controller.selectedModel(for: otherSession), "gpt-test")

        let accepted = await controller.submit("hello", for: managedSession)
        XCTAssertTrue(accepted)
        let submitted = await provider.submittedPrompts()
        XCTAssertEqual(submitted.last, "hello|model-b")

        controller.stop()
    }

    @MainActor
    func testPerSessionModelOverridesPersistAndRevalidateIndependently() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [
                Self.descriptor(id: "thread-a", state: .idle),
                Self.descriptor(id: "thread-b", state: .idle)
            ],
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
        let first = try XCTUnwrap(store.sessions.first {
            $0.id.sessionID.nativeID == "thread-a"
        })
        let second = try XCTUnwrap(store.sessions.first {
            $0.id.sessionID.nativeID == "thread-b"
        })

        XCTAssertTrue(controller.selectModel("model-a", for: first))
        XCTAssertTrue(controller.selectModel("model-b", for: second))
        controller.selectSession(first.id)
        controller.reconcileSelection(with: store.sessions)
        XCTAssertEqual(controller.selectedModel(for: first), first.project.model)
        XCTAssertEqual(controller.pendingModel(for: first), "model-a")
        controller.selectSession(second.id)
        XCTAssertEqual(controller.selectedModel(for: second), second.project.model)
        XCTAssertEqual(controller.pendingModel(for: second), "model-b")
        controller.selectSession(first.id)
        XCTAssertEqual(controller.pendingModel(for: first), "model-a")

        await provider.setModels([Self.model("model-b")])
        await controller.refreshPersistentSnapshot()

        XCTAssertEqual(controller.selectedModel(for: first), first.project.model)
        XCTAssertNil(controller.pendingModel(for: first))
        XCTAssertEqual(controller.selectedModel(for: second), second.project.model)
        XCTAssertEqual(controller.pendingModel(for: second), "model-b")
        XCTAssertEqual(controller.selectedSessionID, first.id)
    }

    @MainActor
    func testNewSessionUsesSelectedProviderModelAndFailureCreatesNoFakeSession() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [],
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

        XCTAssertTrue(controller.selectNewSessionModel("model-b", for: .codex))
        let started = await controller.startNewSession(cwd: "/tmp/DynamicIsland")
        XCTAssertEqual(started?.model, "model-b")
        let startedModels = await provider.startedSessionModels()
        XCTAssertEqual(startedModels, ["model-b"])
        XCTAssertEqual(store.sessions.count, 1)

        await provider.setStartFailure(true)
        let before = store.sessions.count
        let failed = await controller.startNewSession(cwd: "/tmp/DynamicIsland")
        XCTAssertNil(failed)
        XCTAssertEqual(store.sessions.count, before)
        controller.stop()
    }

    @MainActor
    func testActiveTurnBlocksModelSelectionUntilCompletion() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "model-active", state: .idle)],
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
        let managedSession = try XCTUnwrap(store.sessions.first)

        await provider.yield(.turnStarted(.init(
            nativeSessionID: "model-active",
            turnID: "turn-active"
        )))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertFalse(controller.canSelectModel(for: managedSession))
        XCTAssertFalse(controller.selectModel("model-b", for: managedSession))
        XCTAssertNil(controller.pendingModel(for: managedSession))

        await provider.yield(.turnCompleted(
            .init(nativeSessionID: "model-active", turnID: "turn-active"),
            state: .completed,
            summary: nil
        ))
        try await Task.sleep(for: .milliseconds(30))
        XCTAssertTrue(controller.canSelectModel(for: managedSession))
        controller.stop()
    }

    @MainActor
    func testManagedTurnBecomesActiveImmediatelyWithoutDiscoveryRefresh() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "managed-active", state: .idle)],
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
        try await Task.sleep(for: .milliseconds(20))

        await provider.yield(.turnStarted(.init(
            nativeSessionID: "managed-active",
            turnID: "turn-live"
        )))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertTrue(controller.activeManagedSessionIDs.contains(
            AgentSessionID(provider: .codex, nativeID: "managed-active")
        ))
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
        XCTAssertFalse(controller.managed[
            AgentSessionID(provider: .codex, nativeID: "quota-error")
        ]?.canInterrupt ?? true)
        controller.stop()
    }

    @MainActor
    func testConfiguredApprovalPolicyStillRequiresManualDecisionInProduction() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "approval-session", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )

        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        controller.connect(try XCTUnwrap(store.sessions.first))
        try await Task.sleep(for: .milliseconds(30))
        let session = try XCTUnwrap(store.sessions.first)
        controller.setApprovalPolicyChoice(.allowSession, for: session)

        await provider.yield(.approvalRequested(.init(
            requestToken: .string("request-1"),
            kind: .command,
            threadID: "approval-session",
            turnID: "turn-1",
            itemID: "item-1",
            summary: "Run tests"
        )))
        try await Task.sleep(for: .milliseconds(30))

        let beforeManualDecision = await provider.approvalDecisions()
        XCTAssertTrue(beforeManualDecision.isEmpty)
        let pending = try XCTUnwrap(approvals.pendingRequest(for: session.id))
        XCTAssertEqual(
            approvals.resolve(
                session: session.id,
                requestID: pending.key.requestID,
                decision: .allow
            ),
            .accepted
        )
        try await Task.sleep(for: .milliseconds(30))
        let afterManualDecision = await provider.approvalDecisions()
        XCTAssertEqual(afterManualDecision, ["item-1:allow"])
        XCTAssertFalse(controller.transcript(for: session).contains {
            $0.text.contains("Approved automatically")
        })
        controller.stop()
    }

    @MainActor
    func testTurnApprovalPolicyExpiresOnExactTurnCompletion() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "approval-turn", state: .notLoaded)],
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
            nativeSessionID: "approval-turn",
            turnID: "turn-a"
        )))
        try await Task.sleep(for: .milliseconds(30))
        let session = try XCTUnwrap(store.sessions.first)

        controller.setApprovalPolicyChoice(.allowTurn, for: session)
        XCTAssertEqual(controller.approvalPolicy(for: session), .allowTurn(turnID: "turn-a"))

        await provider.yield(.turnCompleted(
            .init(nativeSessionID: "approval-turn", turnID: "turn-a"),
            state: .completed,
            summary: nil
        ))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(controller.approvalPolicy(for: session), .askEveryTime)
        controller.stop()
    }

    @MainActor
    func testApprovalPolicyAndProviderControlStateDoNotLeakAcrossProviders() async throws {
        let codex = PersistentSnapshotFakeProvider(
            provider: .codex,
            sessions: [Self.descriptor(id: "shared-policy", state: .notLoaded, provider: .codex)],
            usage: AgentUsage()
        )
        let claude = PersistentSnapshotFakeProvider(
            provider: .claude,
            sessions: [Self.descriptor(id: "shared-policy", state: .notLoaded, provider: .claude)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            providers: [codex, claude],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        await controller.refreshPersistentSnapshot()
        let codexSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .codex })
        let claudeSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .claude })
        controller.connect(codexSession)
        try await Task.sleep(for: .milliseconds(30))
        let managedCodex = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .codex })

        controller.setApprovalPolicyChoice(.allowSession, for: managedCodex)
        XCTAssertEqual(controller.approvalPolicy(for: managedCodex), .allowSession)
        XCTAssertEqual(controller.approvalPolicy(for: claudeSession), .askEveryTime)

        controller.selectProvider(.claude)
        XCTAssertTrue(controller.accountUsage.scopedEntries.isEmpty)
        XCTAssertNil(controller.pendingModelOverrides[claudeSession.id.sessionID])
        XCTAssertEqual(controller.transcript(for: claudeSession), [])
        controller.selectProvider(.codex)
        XCTAssertEqual(controller.approvalPolicy(for: managedCodex), .allowSession)
        controller.stop()
    }

    @MainActor
    func testClaudeLimitedCapabilitiesHideUnsupportedControlAndUsage() async throws {
        let provider = PersistentSnapshotFakeProvider(
            provider: .claude,
            sessions: [Self.descriptor(id: "claude-limited", state: .notLoaded, provider: .claude)],
            usage: AgentUsage(scopedSamples: [
                AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                    value: 99, limit: 100, unit: .fraction, scope: "5h",
                    source: "should-not-surface", observedAt: Date()
                )
            ]),
            capabilities: [.resumeSession, .submitPrompt, .streamMessages, .streamToolActivity]
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
        let resumable = try XCTUnwrap(store.sessions.first)
        XCTAssertTrue(controller.accountUsage.scopedEntries.isEmpty)
        XCTAssertTrue(controller.availableModels.isEmpty)
        XCTAssertFalse(resumable.capabilities.contains(.approvalControl))
        XCTAssertFalse(resumable.capabilities.contains(.contextUsage))

        controller.connect(resumable)
        try await Task.sleep(for: .milliseconds(30))
        let managed = try XCTUnwrap(store.sessions.first)
        await provider.yield(.turnStarted(.init(
            nativeSessionID: "claude-limited",
            turnID: "turn-claude"
        )))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(controller.mode(for: managed), .interactive(canInterrupt: false))
        XCTAssertFalse(controller.capabilities(for: .claude).contains(.interrupt))
        XCTAssertFalse(controller.capabilities(for: .claude).contains(.selectModel))
        XCTAssertFalse(controller.capabilities(for: .claude).contains(.resolveApprovals))
        controller.stop()
    }

    @MainActor
    func testProviderTransportErrorDoesNotLeakAfterProviderSwitch() async throws {
        let codex = PersistentSnapshotFakeProvider(
            provider: .codex,
            sessions: [Self.descriptor(id: "codex-error", state: .notLoaded, provider: .codex)],
            usage: AgentUsage()
        )
        let claude = PersistentSnapshotFakeProvider(
            provider: .claude,
            sessions: [Self.descriptor(id: "claude-ok", state: .notLoaded, provider: .claude)],
            usage: AgentUsage(),
            capabilities: [.resumeSession, .submitPrompt, .streamMessages, .streamToolActivity]
        )
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            providers: [codex, claude],
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )

        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        let codexSession = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .codex })
        controller.connect(codexSession)
        try await Task.sleep(for: .milliseconds(30))
        await codex.setSubmitFailure(true)
        let managedCodex = try XCTUnwrap(store.sessions.first { $0.id.sessionID.provider == .codex })
        let accepted = await controller.submit("fail", for: managedCodex)
        XCTAssertFalse(accepted)
        XCTAssertNotNil(controller.lastTransportError)

        controller.selectProvider(.claude)
        XCTAssertNil(controller.lastTransportError)
        controller.selectProvider(.codex)
        XCTAssertNotNil(controller.lastTransportError)
        controller.stop()
    }

    @MainActor
    func testDuplicateManagedApprovalRequestResolvesAtMostOnce() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "approval-duplicate", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        controller.connect(try XCTUnwrap(store.sessions.first))
        try await Task.sleep(for: .milliseconds(30))
        let session = try XCTUnwrap(store.sessions.first)
        let request = AgentManagedApprovalRequest(
            requestToken: .string("duplicate"),
            kind: .command,
            threadID: "approval-duplicate",
            turnID: "turn-1",
            itemID: "item-duplicate",
            summary: "Run tests"
        )
        await provider.yield(.approvalRequested(request))
        await provider.yield(.approvalRequested(request))
        try await Task.sleep(for: .milliseconds(30))
        let pending = try XCTUnwrap(approvals.pendingRequest(for: session.id))
        XCTAssertEqual(
            approvals.resolve(session: session.id, requestID: pending.key.requestID, decision: .allow),
            .accepted
        )
        try await Task.sleep(for: .milliseconds(30))

        let decisions = await provider.approvalDecisions()
        XCTAssertEqual(decisions, ["item-duplicate:allow"])
        controller.stop()
    }

    @MainActor
    func testAutomaticApprovalInfrastructureFailureNeverProjectsSuccess() async throws {
        let provider = PersistentSnapshotFakeProvider(
            sessions: [Self.descriptor(id: "approval-failure", state: .notLoaded)],
            usage: AgentUsage()
        )
        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let controller = AgentManagedSessionController(
            provider: provider,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: approvals
        )
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        controller.connect(try XCTUnwrap(store.sessions.first))
        try await Task.sleep(for: .milliseconds(30))
        let session = try XCTUnwrap(store.sessions.first)
        controller.setApprovalPolicyChoice(.allowSession, for: session)

        await provider.yield(.approvalRequested(.init(
            requestToken: .string("failure"),
            kind: .command,
            threadID: "approval-failure",
            turnID: "turn-1",
            itemID: "item-failure",
            summary: "Run tests"
        )))
        try await Task.sleep(for: .milliseconds(30))

        let beforeManualDecision = await provider.approvalDecisions()
        XCTAssertTrue(beforeManualDecision.isEmpty)
        XCTAssertNotNil(approvals.pendingRequest(for: session.id))
        XCTAssertFalse(controller.transcript(for: session).contains {
            $0.text.contains("Approved automatically")
        })
        approvals.cancelAll()
        controller.stop()
    }

    private static func descriptor(
        id: String,
        state: AgentDiscoveredSessionRuntimeState,
        provider: AgentProvider = .codex
    ) -> AgentDiscoveredSessionDescriptor {
        AgentDiscoveredSessionDescriptor(
            session: AgentManagedSessionDescriptor(
                provider: provider,
                nativeSessionID: id,
                cwd: "/tmp/DynamicIsland",
                model: "gpt-test",
                acceptsDirectInput: state != .notLoaded
            ),
            runtimeState: state,
            updatedAt: Date(timeIntervalSince1970: 2_100_000_000)
        )
    }

    private static func model(_ id: String) -> AgentManagedModelDescriptor {
        AgentManagedModelDescriptor(
            id: id,
            model: id,
            displayName: id,
            description: nil,
            isDefault: false
        )
    }
}

private actor PersistentSnapshotFakeProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability>
    nonisolated let modelSelectionScope: AgentModelSelectionScope?

    private var discovered: [AgentDiscoveredSessionDescriptor]
    private let usage: AgentUsage
    private var usageFailure = false
    private var transcript: [AgentManagedTranscriptEntry] = []
    private var submitted: [String] = []
    private var submitFailure = false
    private var startFailure = false
    private var startedModels: [String?] = []
    private var approvalResolutionFailure = false
    private var approvalDecisionLog: [String] = []
    private var models: [AgentManagedModelDescriptor] = [
        AgentManagedModelDescriptor(
            id: "model-a", model: "model-a", displayName: "Model A",
            description: nil, isDefault: true
        ),
        AgentManagedModelDescriptor(
            id: "model-b", model: "model-b", displayName: "Model B",
            description: nil, isDefault: false
        )
    ]
    private let eventStream: AsyncStream<AgentInteractiveProviderEvent>
    private let eventContinuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(
        provider: AgentProvider = .codex,
        sessions: [AgentDiscoveredSessionDescriptor],
        usage: AgentUsage,
        capabilities: Set<AgentInteractiveCapability> = [
            .startSession, .resumeSession, .submitPrompt, .interrupt, .selectModel,
            .resolveApprovals, .accountUsage, .contextUsage, .streamMessages, .streamToolActivity, .loadHistory
        ]
    ) {
        self.provider = provider
        interactiveCapabilities = capabilities
        modelSelectionScope = capabilities.contains(.selectModel) ? .turnAndSubsequent : nil
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

    func listModels() async throws -> [AgentManagedModelDescriptor] {
        models
    }

    func setModels(_ value: [AgentManagedModelDescriptor]) {
        models = value
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

    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor {
        if startFailure { throw CodexAppServerError.rpcError(code: -1, message: "start failed") }
        startedModels.append(model)
        let nativeID = "started-\(startedModels.count)"
        return AgentManagedSessionDescriptor(
            provider: provider,
            nativeSessionID: nativeID,
            cwd: cwd,
            model: model,
            acceptsDirectInput: true
        )
    }

    func setStartFailure(_ value: Bool) {
        startFailure = value
    }

    func startedSessionModels() -> [String?] {
        startedModels
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

    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {
        if approvalResolutionFailure {
            throw CodexAppServerError.transportClosed(nil)
        }
        approvalDecisionLog.append("\(request.itemID):\(allow ? "allow" : "deny")")
    }

    func setApprovalResolutionFailure(_ value: Bool) {
        approvalResolutionFailure = value
    }

    func approvalDecisions() -> [String] {
        approvalDecisionLog
    }

    func stop() async {
        eventContinuation.finish()
    }
}
