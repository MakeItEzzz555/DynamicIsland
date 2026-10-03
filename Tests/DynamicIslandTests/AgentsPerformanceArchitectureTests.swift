import AppKit
import Combine
import SwiftUI
import XCTest
@testable import DynamicIsland

/// Regression coverage for the Agents page performance architecture:
/// transcript publication is isolated from the chrome and coalesced, the
/// periodic discovery refresh only republishes real changes, and selection
/// writes are change-only. Each property here was measured in
/// AgentsPerformanceHarnessTests before it was relied on.
@MainActor
final class AgentsPerformanceArchitectureTests: XCTestCase {
    // MARK: Transcript store

    func testTranscriptWritesAreImmediateAndPublicationIsCoalescedWithoutLoss() async throws {
        let store = AgentTranscriptStore(minimumPublicationInterval: .milliseconds(60))
        let id = AgentSessionID(provider: .codex, nativeID: "thread")
        let feed = store.feed(for: id)
        var publications = 0
        let sink = feed.objectWillChange.sink { _ in publications += 1 }
        defer { sink.cancel() }

        store[id] = [entry("a", "1")]
        XCTAssertEqual(feed.entries.map(\.text), ["1"], "first change after quiet publishes immediately")
        XCTAssertEqual(publications, 1)

        store[id] = [entry("a", "12")]
        store[id] = [entry("a", "123")]
        XCTAssertEqual(store[id]?.first?.text, "123", "storage is always current")
        XCTAssertEqual(feed.entries.map(\.text), ["1"], "a burst is coalesced")

        for _ in 0..<100 where feed.entries.first?.text != "123" {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(feed.entries.map(\.text), ["123"], "the latest value always lands")
        XCTAssertEqual(publications, 2)

        store[id] = [entry("a", "1234")]
        store.flush()
        XCTAssertEqual(feed.entries.map(\.text), ["1234"])
    }

    func testFeedsAreSessionExactSoSwitchingNeverInheritsAnotherTranscript() {
        let store = AgentTranscriptStore()
        let first = AgentSessionID(provider: .codex, nativeID: "one")
        let second = AgentSessionID(provider: .claude, nativeID: "one")
        store[first] = [entry("x", "codex text")]
        XCTAssertTrue(store.feed(for: second).entries.isEmpty, "same native id, other provider: separate feed")
        XCTAssertFalse(store.feed(for: first) === store.feed(for: second))
        XCTAssertEqual(store.feed(for: first).entries.map(\.text), ["codex text"])
        store.removeAll()
        XCTAssertTrue(store.feed(for: first).entries.isEmpty)
    }

    // MARK: Controller publication scope

    func testStreamedDeltasNeverPublishOnTheControllerTheChromeObserves() async throws {
        let (provider, store, controller) = try await makeController()
        defer { controller.stop() }
        let session = try XCTUnwrap(store.sessions.first)
        let feed = controller.transcriptFeed(for: session)
        var chromePublications = 0
        var storePublications = 0
        let chromeSink = controller.objectWillChange.sink { _ in chromePublications += 1 }
        let storeSink = store.objectWillChange.sink { _ in storePublications += 1 }
        defer { chromeSink.cancel(); storeSink.cancel() }

        for index in 0..<30 {
            await provider.yield(.transcriptDelta(
                nativeSessionID: session.id.sessionID.nativeID,
                turnID: "turn",
                itemID: "item",
                delta: "t\(index) "
            ))
        }
        for _ in 0..<100 where !(controller.transcript(for: session).first?.text.hasSuffix("t29") ?? false) {
            try await Task.sleep(for: .milliseconds(5))
        }
        controller.flushTranscriptPublications()
        XCTAssertTrue(controller.transcript(for: session).first?.text.hasSuffix("t29") ?? false)
        XCTAssertEqual(feed.entries.first?.text, controller.transcript(for: session).first?.text)
        XCTAssertEqual(chromePublications, 0, "deltas must not invalidate provider/project/usage chrome")
        XCTAssertEqual(storePublications, 0)
    }

    func testUnchangedDiscoveryRefreshDoesNotRepublishTheStore() async throws {
        let (provider, store, controller) = try await makeController()
        defer { controller.stop() }
        var storePublications = 0
        let sink = store.objectWillChange.sink { _ in storePublications += 1 }
        defer { sink.cancel() }

        await controller.refreshPersistentSnapshot()
        XCTAssertEqual(storePublications, 0, "nothing changed, nothing republished")

        await provider.setCWD("/tmp/perf/renamed")
        await controller.refreshPersistentSnapshot()
        XCTAssertGreaterThan(storePublications, 0, "a real metadata change is still emitted")
        XCTAssertTrue(store.sessions.contains { $0.project.workingDirectory == "/tmp/perf/renamed" })
    }

    func testNewerProviderActivityIsStillEmittedForOrdering() {
        var session = AgentSession.fixture()
        session.lastUpdatedAt = Date(timeIntervalSince1970: 100)
        let project = AgentProjectContext(displayName: "repo", workingDirectory: "/tmp/repo", model: "m")
        session.project = AgentPrivacyProjection.project(project)
        session.availability = .loaded
        XCTAssertTrue(AgentManagedSessionController.metadataIsCurrent(session, project: project, availability: .loaded))
        XCTAssertFalse(AgentManagedSessionController.metadataIsCurrent(session, project: project, availability: .resumable))
        var changed = project
        changed.model = "other"
        XCTAssertFalse(AgentManagedSessionController.metadataIsCurrent(session, project: changed, availability: .loaded))
    }

    func testReselectingTheSameSessionOrProviderDoesNotPublish() async throws {
        let (_, store, controller) = try await makeController()
        defer { controller.stop() }
        let session = try XCTUnwrap(store.sessions.first)
        controller.selectSession(session.id)
        var publications = 0
        let sink = controller.objectWillChange.sink { _ in publications += 1 }
        defer { sink.cancel() }
        controller.selectSession(session.id)
        controller.selectProvider(session.id.sessionID.provider)
        XCTAssertEqual(publications, 0)
    }

    func testSelectingASessionDoesNotHydrateHistoryByItself() async throws {
        let (provider, store, controller) = try await makeController()
        defer { controller.stop() }
        let session = try XCTUnwrap(store.sessions.first)
        controller.selectSession(session.id)
        try await Task.sleep(for: .milliseconds(20))
        let reads = await provider.transcriptReads()
        XCTAssertEqual(reads, 0, "history is read only when the transcript is allowed to show")
        await controller.refreshTranscript(for: session)
        await controller.refreshTranscript(for: session)
        let afterReads = await provider.transcriptReads()
        XCTAssertEqual(afterReads, 1, "hydration happens once per session")
    }

    // MARK: Follow state

    func testRepeatedIdenticalViewportReportsSettleWithoutStateChurn() {
        var follow = AgentTranscriptFollowState()
        follow.jumpToLatest()
        for _ in 0..<AgentTranscriptFollowState.autoScrollGracePasses + 2 {
            follow.observeViewport(distanceFromBottom: 0, contentToken: "same")
        }
        let settled = follow
        follow.observeViewport(distanceFromBottom: 0, contentToken: "same")
        XCTAssertEqual(follow, settled, "a stable viewport must not keep writing view state")
    }

    // MARK: Usage and provider controls

    func testQuotaGaugesAreLargerThanContextAndStepDownOnlyWhenNarrow() {
        let standard = AgentUsageIndicatorMetrics.make(width: 760)
        XCTAssertEqual(standard.diameter(for: .fiveHour), 44)
        XCTAssertEqual(standard.diameter(for: .week), 44)
        XCTAssertEqual(standard.diameter(for: .context), 34)
        let narrow = AgentUsageIndicatorMetrics.make(width: 480)
        XCTAssertEqual(narrow.diameter(for: .fiveHour), 36)
        XCTAssertEqual(narrow.diameter(for: .context), 30)
        XCTAssertEqual(AgentUsageIndicatorMetrics.make(width: AgentUsageIndicatorMetrics.narrowWidth), .standard)
        XCTAssertGreaterThan(
            AgentUsageIndicatorMetrics.valueFontSize(for: 44),
            AgentUsageIndicatorMetrics.valueFontSize(for: 34),
            "values grow with the ring"
        )
        XCTAssertGreaterThanOrEqual(AgentUsageIndicatorMetrics.valueFontSize(for: 30), 7.5, "still legible when narrow")
    }

    func testWorkspaceUsageStripUsesTheFullRowWithLargerPairedGauges() {
        XCTAssertEqual(AgentWorkspaceUsageStrip.diameter(for: 960), 48)
        XCTAssertEqual(AgentWorkspaceUsageStrip.diameter(for: 620), 48)
        XCTAssertEqual(AgentWorkspaceUsageStrip.diameter(for: 560), 40)
        XCTAssertGreaterThan(AgentWorkspaceUsageStrip.rowHeight(for: 960), 60)
        XCTAssertGreaterThan(
            AgentWorkspaceUsageStrip.diameter(for: 960),
            32,
            "the workspace strip must not regress to the old tiny floating rings"
        )
    }

    func testProviderButtonsShowIconAndNameWithPracticalHitTargets() async throws {
        let (_, _, controller) = try await makeController(providers: [.codex, .claude])
        defer { controller.stop() }
        func fitting(_ compact: Bool) -> CGSize {
            let host = NSHostingView(rootView: AgentProviderButtons(managedControl: controller, compact: compact).fixedSize())
            return host.fittingSize
        }
        let named = fitting(false)
        let compact = fitting(true)
        XCTAssertGreaterThanOrEqual(named.height, AgentProviderButtons.minimumHitHeight)
        XCTAssertGreaterThanOrEqual(named.width, 2 * AgentProviderButtons.minimumNamedWidth, "both names fit")
        XCTAssertLessThan(named.width, 220, "named buttons fit a normal Agents control row")
        XCTAssertLessThan(compact.width, named.width, "icon-only is a genuine compaction")
        XCTAssertGreaterThanOrEqual(compact.height, AgentProviderButtons.minimumHitHeight)
    }

    // MARK: Fixtures

    private func entry(_ id: String, _ text: String) -> AgentManagedTranscriptEntry {
        AgentManagedTranscriptEntry(
            id: id, nativeSessionID: "thread", turnID: "turn", role: .agent,
            text: text, timestamp: Date(timeIntervalSince1970: 1)
        )
    }

    private func makeController(
        providers kinds: [AgentProvider] = [.codex]
    ) async throws -> (ArchitectureFakeProvider, AgentEventStore, AgentManagedSessionController) {
        let providers = kinds.map { ArchitectureFakeProvider(provider: $0) }
        let store = AgentEventStore()
        let controller = AgentManagedSessionController(
            providers: providers,
            coordinator: AgentIngestionCoordinator(eventStore: store),
            eventStore: store,
            approvals: AgentApprovalController()
        )
        controller.startObserving()
        await controller.refreshPersistentSnapshot()
        return (providers[0], store, controller)
    }
}

private extension AgentSession {
    static func fixture() -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: "fixture"),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: .idle,
            project: AgentProjectContext(),
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: Date(timeIntervalSince1970: 100),
            endedAt: nil,
            lastUpdatedAt: Date(timeIntervalSince1970: 100),
            availability: .loaded
        )
    }
}

private actor ArchitectureFakeProvider: AgentInteractiveProvider {
    nonisolated let provider: AgentProvider
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .resumeSession, .submitPrompt, .loadHistory, .streamMessages
    ]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = nil
    private var cwd = "/tmp/perf/repo"
    private var reads = 0
    private let stream: AsyncStream<AgentInteractiveProviderEvent>
    private let continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation

    init(provider: AgentProvider) {
        self.provider = provider
        var continuation: AsyncStream<AgentInteractiveProviderEvent>.Continuation!
        stream = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    func yield(_ event: AgentInteractiveProviderEvent) { continuation.yield(event) }
    func setCWD(_ value: String) { cwd = value }
    func transcriptReads() -> Int { reads }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent> { stream }

    private var descriptor: AgentManagedSessionDescriptor {
        AgentManagedSessionDescriptor(
            provider: provider, nativeSessionID: "\(provider.stableName)-arch",
            cwd: cwd, model: "m", acceptsDirectInput: true
        )
    }

    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        [AgentDiscoveredSessionDescriptor(session: descriptor, runtimeState: .idle, updatedAt: Date(timeIntervalSince1970: 1_000))]
    }

    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? { descriptor }
    func readAccountUsage() async throws -> AgentUsage { AgentUsage() }

    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] {
        reads += 1
        return []
    }

    func listModels() async throws -> [AgentManagedModelDescriptor] { [] }
    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor { descriptor }
    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor { descriptor }
    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor {
        AgentManagedTurnDescriptor(nativeSessionID: nativeSessionID, turnID: "turn")
    }
    func interrupt(nativeSessionID: String, turnID: String) async throws {}
    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {}
    func stop() async { continuation.finish() }
}
