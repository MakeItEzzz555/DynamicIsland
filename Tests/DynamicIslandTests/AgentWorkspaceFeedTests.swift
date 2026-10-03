import Combine
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentWorkspaceFeedTests: XCTestCase {
    func testBothProvidersAndGenerationsKeepExactOperationOwnership() {
        let (store, feed) = runtime()
        for provider in [AgentProvider.codex, .claude] {
            start(store, provider: provider, generation: 1)
            ingest(store, provider: provider, generation: 1, name: "operation", type: .commandStarted, offset: 1,
                   correlation: "shared-request", payload: .command(.init(executable: "echo", success: nil, exitCode: nil)))
        }
        start(store, provider: .codex, generation: 2)
        ingest(store, generation: 2, name: "operation", type: .commandStarted, offset: 2,
               correlation: "shared-request", payload: .command(.init(executable: "echo", success: nil, exitCode: nil)))
        XCTAssertEqual(feed.items.count, 3)
        XCTAssertEqual(Set(feed.items.map(\.sessionID)).count, 3)
        XCTAssertEqual(Set(feed.items.map(\.provider)), [.codex, .claude])
        XCTAssertEqual(Set(feed.items.map(\.id)).count, 3)
    }

    func testOperationUpdatesPreserveIdentityAndSortByLatestTraffic() {
        let (store, feed) = runtime()
        start(store)
        ingest(store, name: "command-start", type: .commandStarted, offset: 1,
               correlation: "command", payload: .command(.init(executable: "echo", success: nil, exitCode: nil)))
        let identity = feed.items[0].id
        ingest(store, name: "tool-start", type: .toolStarted, offset: 2, correlation: "tool",
               payload: .tool(.init(name: "test", category: nil, summary: nil, success: nil)))
        ingest(store, name: "command-end", type: .commandCompleted, offset: 3, correlation: "command",
               payload: .command(.init(executable: nil, success: true, exitCode: 0)))
        XCTAssertEqual(feed.items.count, 2)
        XCTAssertEqual(feed.items.first?.id, identity)
        XCTAssertEqual(feed.items.first?.title, "Command completed")
        XCTAssertEqual(feed.items.first?.status, .completed)
        XCTAssertEqual(feed.items.first?.timestamp, AgentTestFixture.baseDate.addingTimeInterval(1))
        XCTAssertEqual(feed.items.first?.updatedAt, AgentTestFixture.baseDate.addingTimeInterval(3))
    }

    func testApprovalWaitDeliveryFailureAndAcknowledgementRemainDistinct() {
        let (store, feed) = runtime()
        start(store)
        ingest(store, name: "request", type: .approvalRequested, offset: 1, correlation: "exact",
               payload: .approvalRequest(.init(summary: "Private operation", operationCorrelationID: nil, expiresAt: nil)))
        let request = feed.items[0]
        XCTAssertEqual(request.approvalKey?.requestID, AgentTestFixture.correlation("exact"))
        XCTAssertEqual(request.approvalPresentation(delivery: .awaitingDecision), .pending)
        XCTAssertEqual(request.approvalPresentation(delivery: .submitting(.allow)), .submitting)
        XCTAssertEqual(request.approvalPresentation(delivery: .submitting(.deny)), .submitting)
        XCTAssertEqual(request.approvalPresentation(delivery: .failed(.allow, reason: "Transport failure")), .failed)
        XCTAssertEqual(request.approvalState, .pending, "Presentation must not mutate normalized provider truth")
        ingest(store, name: "ack", type: .approvalResolved, offset: 2, correlation: "exact",
               payload: .approvalResolution(.init(state: .denied)))
        XCTAssertEqual(feed.items.count, 1, "Acknowledged request remains in Feed history")
        XCTAssertEqual(feed.items[0].id, request.id)
        XCTAssertEqual(feed.items[0].approvalPresentation(delivery: nil), .denied)
        XCTAssertEqual(feed.items[0].approvalPresentation(delivery: .submitting(.allow)), .denied)
    }

    func testUnknownDeliveryNeverBecomesApprovedOrDenied() {
        let (store, feed) = runtime()
        start(store)
        ingest(store, name: "request", type: .approvalRequested, offset: 1, correlation: "exact",
               payload: .approvalRequest(.init(summary: nil, operationCorrelationID: nil, expiresAt: nil)))
        ingest(store, name: "unconfirmed", type: .approvalResolved, offset: 2, correlation: "exact",
               payload: .approvalResolution(.init(state: .unknown)))
        XCTAssertEqual(feed.items[0].approvalPresentation(delivery: nil), .failed)
        XCTAssertEqual(feed.items[0].status, .failed)
    }

    func testExistingPendingAndFailedRequestsRecoverFromCanonicalSnapshotWithoutDuplicates() {
        let (store, originalFeed) = runtime()
        start(store)
        ingest(store, name: "request", type: .approvalRequested, offset: 1, correlation: "exact",
               payload: .approvalRequest(.init(summary: "Private operation", operationCorrelationID: nil, expiresAt: nil)))
        let mountedFeed = AgentWorkspaceFeedStore()
        mountedFeed.reconcileApprovals(sessions: store.sessions)
        let identity = mountedFeed.items[0].id
        XCTAssertEqual(mountedFeed.items[0].approvalKey, originalFeed.items[0].approvalKey)
        mountedFeed.reconcileApprovals(sessions: store.sessions)
        XCTAssertEqual(mountedFeed.items.count, 1)
        ingest(store, name: "failed", type: .approvalResolved, offset: 2, correlation: "exact",
               payload: .approvalResolution(.init(state: .unknown)))
        mountedFeed.reconcileApprovals(sessions: store.sessions)
        XCTAssertEqual(mountedFeed.items[0].id, identity)
        XCTAssertEqual(mountedFeed.items[0].approvalPresentation(delivery: nil), .failed)
        XCTAssertFalse(String(describing: mountedFeed.items).contains("Private operation"))
    }

    func testHistoryFloodDoesNotHideAnUnresolvedApproval() {
        let (store, feed) = runtime(maximumItems: 16)
        start(store)
        ingest(store, name: "request", type: .approvalRequested, offset: 1, correlation: "exact",
               payload: .approvalRequest(.init(summary: nil, operationCorrelationID: nil, expiresAt: nil)))
        for index in 0..<40 {
            ingest(store, name: "tool-\(index)", type: .toolStarted, offset: Double(index + 2),
                   correlation: "tool-\(index)", payload: .tool(.init(name: nil, category: nil, summary: nil, success: nil)))
        }
        XCTAssertEqual(feed.items.count, 16)
        XCTAssertEqual(feed.items.filter { $0.kind == .approval }.count, 1)
        XCTAssertEqual(feed.items.first(where: { $0.kind == .approval })?.approvalPresentation(delivery: nil), .pending)
    }

    func testNoiseAndTranscriptLikePayloadDoNotPublishOrRetainContent() {
        let (store, feed) = runtime()
        start(store)
        var publications = 0
        let cancellable = feed.$items.dropFirst().sink { _ in publications += 1 }
        let secret = "api-key=private /Users/private/project Prompt and transcript text"
        ingest(store, name: "work", type: .agentWorking, offset: 1,
               payload: .activity(.init(title: secret, summary: secret)))
        ingest(store, name: "heartbeat", type: .heartbeat, offset: 2)
        XCTAssertTrue(feed.items.isEmpty)
        XCTAssertEqual(publications, 0)
        ingest(store, name: "typed-work", type: .agentWorking, offset: 3, correlation: "reasoning",
               payload: .activity(.init(title: secret, summary: secret, processingKind: .reasoning, processingStatus: .active)))
        XCTAssertEqual(feed.items.first?.title, "Reasoning")
        XCTAssertFalse(String(describing: feed.items).contains(secret))
        XCTAssertEqual(publications, 1)
        withExtendedLifetime(cancellable) {}
    }

    func testBoundedHistoryAndDuplicateAppliedCallbacks() {
        let (store, feed) = runtime(maximumItems: 16)
        start(store)
        for index in 0..<80 {
            ingest(store, name: "tool-\(index)", type: .toolStarted, offset: Double(index * 2 + 1),
                   correlation: "operation-\(index)", payload: .tool(.init(name: nil, category: nil, summary: nil, success: nil)))
            ingest(store, name: "tool-end-\(index)", type: .toolCompleted, offset: Double(index * 2 + 2),
                   correlation: "operation-\(index)", payload: .tool(.init(name: nil, category: nil, summary: nil, success: true)))
        }
        XCTAssertEqual(feed.items.count, 16)
        XCTAssertEqual(feed.items.first?.correlationID, AgentTestFixture.correlation("operation-79"))
        XCTAssertFalse(feed.items.contains { $0.correlationID == AgentTestFixture.correlation("operation-0") })
        let event = AgentTestFixture.event("tool-79", sessionID: id(), type: .toolStarted, offset: 159,
                                          correlationID: "operation-79", payload: .tool(.init(name: nil, category: nil, summary: nil, success: nil)))
        let prior = feed.items
        feed.handleApplied(event, session: store.sessions[0])
        XCTAssertEqual(feed.items, prior)
        XCTAssertEqual(AgentWorkspaceFeedStore(maximumItems: -5).maximumItems, 16)
        XCTAssertEqual(AgentWorkspaceFeedStore(maximumItems: 50_000).maximumItems, 1_024)
    }

    func testAvatarAnimationUsesCanonicalActivityAndStopsForBlockingOrTerminalState() {
        let (store, feed) = runtime()
        start(store)
        ingest(store, name: "command", type: .commandStarted, offset: 1, correlation: "command",
               payload: .command(.init(executable: "echo", success: nil, exitCode: nil)))
        let command = feed.items[0]
        XCTAssertTrue(command.isCurrentActivity(in: store.sessions[0]))
        var other = store.sessions[0]
        other.state = .waitingForApproval
        XCTAssertFalse(command.isCurrentActivity(in: other))
        other.state = .waitingForUser
        XCTAssertFalse(command.isCurrentActivity(in: other))
        ingest(store, name: "interrupt", type: .interrupted, offset: 2, payload: .terminal(.init(summary: nil)))
        XCTAssertFalse(command.isCurrentActivity(in: store.sessions[0]))
        XCTAssertTrue(feed.items.contains { $0.kind == .interruption })
        XCTAssertEqual(feed.items.first(where: { $0.kind == .command })?.status, .cancelled)
        XCTAssertFalse(command.isCurrentActivity(in: nil))
    }

    func testTerminalCleanupWithdrawsApprovalWithoutFabricatingAUserDecision() {
        let (store, feed) = runtime()
        start(store)
        ingest(store, name: "request", type: .approvalRequested, offset: 1, correlation: "exact",
               payload: .approvalRequest(.init(summary: nil, operationCorrelationID: nil, expiresAt: nil)))
        ingest(store, name: "interrupted", type: .interrupted, offset: 2, payload: .terminal(.init(summary: nil)))
        let approval = feed.items.first { $0.kind == .approval }
        XCTAssertEqual(approval?.approvalState, .cancelled)
        XCTAssertEqual(approval?.approvalPresentation(delivery: nil), .withdrawn)
    }

    func testStaleGenerationAndForeignSessionCannotLeakIntoFeed() {
        let (store, feed) = runtime()
        start(store)
        start(store, generation: 2)
        let stale = AgentTestFixture.event("stale", sessionID: id(), type: .taskCompleted, offset: 3,
                                           payload: .terminal(.init(summary: nil)))
        XCTAssertEqual(store.ingest(stale), .staleGeneration)
        XCTAssertTrue(feed.items.isEmpty)
        feed.handleApplied(stale, session: store.sessions[0])
        XCTAssertTrue(feed.items.isEmpty)
    }

    private func runtime(maximumItems: Int = 256) -> (AgentEventStore, AgentWorkspaceFeedStore) {
        let store = AgentEventStore()
        let feed = AgentWorkspaceFeedStore(maximumItems: maximumItems)
        store.appliedEventObserver = { [weak feed] event, session in feed?.handleApplied(event, session: session) }
        return (store, feed)
    }

    private func id(_ provider: AgentProvider = .codex) -> AgentSessionID {
        AgentTestFixture.sessionID(provider, "same-native-session")
    }

    private func start(_ store: AgentEventStore, provider: AgentProvider = .codex, generation: UInt64 = 1) {
        ingest(store, provider: provider, generation: generation, name: "start-\(generation)", type: .sessionStarted,
               offset: 0, payload: .sessionMetadata(.init(project: AgentTestFixture.project())))
    }

    private func ingest(_ store: AgentEventStore, provider: AgentProvider = .codex, generation: UInt64 = 1,
                        name: String, type: AgentEventType, offset: Double, correlation: String? = nil,
                        payload: AgentEventPayload = .none) {
        XCTAssertEqual(store.ingest(AgentTestFixture.event(name, sessionID: id(provider), generation: generation,
                                                          type: type, offset: offset, correlationID: correlation,
                                                          payload: payload)), .applied)
    }
}
