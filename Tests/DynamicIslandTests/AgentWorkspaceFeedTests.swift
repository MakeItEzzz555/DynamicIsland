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
        XCTAssertEqual(feed.items.first?.title, "Command completed · echo · exit 0")
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

    func testSelectedFeedFiltersExactProviderNativeSessionAndGenerationAtomically() {
        let (store, feed) = runtime()
        for provider in [AgentProvider.codex, .claude] {
            start(store, provider: provider)
            ingest(store, provider: provider, name: "command", type: .commandStarted, offset: 1,
                   correlation: "shared-command", payload: .command(.init(executable: "swift", success: nil, exitCode: nil)))
        }
        let firstCodex = AgentSessionInstanceID(sessionID: id(.codex), generation: .init(rawValue: 1))
        let claude = AgentSessionInstanceID(sessionID: id(.claude), generation: .init(rawValue: 1))
        start(store, generation: 2)
        ingest(store, generation: 2, name: "next-command", type: .commandStarted, offset: 2,
               correlation: "shared-command", payload: .command(.init(executable: "git", success: nil, exitCode: nil)))
        let nextCodex = AgentSessionInstanceID(sessionID: id(.codex), generation: .init(rawValue: 2))
        XCTAssertEqual(feed.items(for: firstCodex).map(\.sessionID), [firstCodex])
        XCTAssertEqual(feed.items(for: claude).map(\.sessionID), [claude])
        XCTAssertEqual(feed.items(for: nextCodex).map(\.sessionID), [nextCodex])
        XCTAssertEqual(feed.items(for: firstCodex).first?.title, "Command: swift")
        XCTAssertEqual(feed.items(for: nextCodex).first?.title, "Command: git")
        XCTAssertTrue(feed.items(for: nil).isEmpty)
        XCTAssertTrue(feed.items(for: .init(sessionID: AgentTestFixture.sessionID(.codex, "foreign"), generation: .init(rawValue: 1))).isEmpty)
        XCTAssertEqual(feed.items.count, 3, "Selection projects history without mutating another provider")
    }

    func testAllTypedSemanticStatesEnterSelectedHistoryWithoutProviderProse() {
        let (store, feed) = runtime()
        start(store)
        let states: [AgentProcessingKind] = [.reasoning, .planning, .searching, .executing, .connecting, .listening, .composing, .synthesizing, .background]
        for (index, state) in states.enumerated() {
            ingest(store, name: "state-\(index)", type: .agentWorking, offset: Double(index + 1), correlation: "state-\(index)",
                   payload: .activity(.init(title: "private hidden reasoning", summary: "secret prompt", processingKind: state, processingStatus: .active)))
        }
        let selected = store.sessions[0].id
        XCTAssertEqual(Set(feed.items(for: selected).compactMap(\.processingKind)), Set(states))
        XCTAssertEqual(feed.items(for: selected).first?.title, "Background processing")
        XCTAssertFalse(String(describing: feed.items).contains("private hidden reasoning"))
        XCTAssertFalse(String(describing: feed.items).contains("secret prompt"))
    }

    func testRepeatedSemanticPublicationCoalescesButReturnAfterAnActionCreatesHistory() {
        let (store, feed) = runtime()
        start(store)
        var publications = 0
        let cancellable = feed.$items.dropFirst().sink { _ in publications += 1 }
        for index in 0..<12 {
            ingest(store, name: "reason-\(index)", type: .agentWorking, offset: Double(index + 1), correlation: "reasoning",
                   payload: .activity(.init(title: nil, summary: nil, processingKind: .reasoning, processingStatus: .active)))
        }
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(publications, 1, "Repeated semantic state must not republish the Feed")
        let firstIdentity = feed.items[0].id
        ingest(store, name: "next-reasoning-item", type: .agentWorking, offset: 13, correlation: "next-reasoning-item",
               payload: .activity(.init(title: nil, summary: nil, processingKind: .reasoning, processingStatus: .active)))
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].id, firstIdentity)
        XCTAssertEqual(feed.items[0].correlationID, AgentTestFixture.correlation("next-reasoning-item"))
        XCTAssertTrue(feed.items[0].isCurrentActivity(in: store.sessions[0]))
        ingest(store, name: "search", type: .toolStarted, offset: 14, correlation: "search",
               payload: .tool(.init(name: "search", category: nil, summary: nil, success: nil, processingKind: .searching)))
        ingest(store, name: "return-reasoning", type: .agentWorking, offset: 15, correlation: "return-reasoning",
               payload: .activity(.init(title: nil, summary: nil, processingKind: .reasoning, processingStatus: .active)))
        XCTAssertEqual(feed.items.count, 3)
        XCTAssertEqual(feed.items.filter { $0.kind == .processing }.count, 2)
        withExtendedLifetime(cancellable) {}
    }

    func testRecentSafeActionsRetainExecutableAndExitCodeButNoArgumentsPathsOrSecrets() {
        let (store, feed) = runtime()
        start(store)
        ingest(store, name: "safe-command", type: .commandStarted, offset: 1, correlation: "safe",
               payload: .command(.init(executable: "swift", success: nil, exitCode: nil)))
        ingest(store, name: "safe-completed", type: .commandCompleted, offset: 2, correlation: "safe",
               payload: .command(.init(executable: nil, success: true, exitCode: 0)))
        XCTAssertEqual(feed.items[0].title, "Command completed · swift · exit 0")
        let secret = "swift test /Users/private --api-key=private"
        ingest(store, name: "malformed-command", type: .commandStarted, offset: 3, correlation: "malformed",
               payload: .command(.init(executable: secret, success: nil, exitCode: nil)))
        ingest(store, name: "malformed-tool", type: .toolStarted, offset: 4, correlation: "malformed-tool",
               payload: .tool(.init(name: secret, category: nil, summary: secret, success: nil)))
        XCTAssertNil(feed.items.first { $0.correlationID == AgentTestFixture.correlation("malformed") }?.operationLabel)
        XCTAssertFalse(String(describing: feed.items).contains(secret))
        ingest(store, name: "safe-tool", type: .toolStarted, offset: 5, correlation: "read",
               payload: .tool(.init(name: "read_file", category: nil, summary: secret, success: nil)))
        XCTAssertEqual(feed.items[0].title, "Tool: Read file")
    }

    func testReturningToSameReasoningItemAfterAnActionPublishesLatestSemanticState() {
        let (store, feed) = runtime()
        start(store)
        let reasoning = AgentEventPayload.activity(.init(title: nil, summary: nil, processingKind: .reasoning, processingStatus: .active))
        ingest(store, name: "reasoning", type: .agentWorking, offset: 1, correlation: "reasoning", payload: reasoning)
        ingest(store, name: "command", type: .commandStarted, offset: 2, correlation: "command",
               payload: .command(.init(executable: "swift", success: nil, exitCode: nil)))
        ingest(store, name: "command-end", type: .commandCompleted, offset: 3, correlation: "command",
               payload: .command(.init(executable: nil, success: true, exitCode: 0)))
        XCTAssertEqual(feed.items.first?.kind, .command)
        ingest(store, name: "reasoning-return", type: .agentWorking, offset: 4, correlation: "reasoning", payload: reasoning)
        XCTAssertEqual(feed.items.first?.kind, .processing)
        XCTAssertEqual(feed.items.first?.processingKind, .reasoning)
        XCTAssertEqual(feed.items.first?.updatedAt, AgentTestFixture.baseDate.addingTimeInterval(4))
        XCTAssertEqual(feed.items.count, 2, "A concrete work item stays one item while its updated state becomes current")
    }

    func testOtherApprovalDoesNotEnterSelectedFeedButRemainsExactGlobalAttention() {
        let (store, feed) = runtime()
        start(store)
        start(store, provider: .claude)
        ingest(store, provider: .claude, name: "request", type: .approvalRequested, offset: 1, correlation: "exact",
               payload: .approvalRequest(.init(summary: nil, operationCorrelationID: nil, expiresAt: nil)))
        let codex = AgentSessionInstanceID(sessionID: id(.codex), generation: .init(rawValue: 1))
        let claude = AgentSessionInstanceID(sessionID: id(.claude), generation: .init(rawValue: 1))
        XCTAssertTrue(feed.items(for: codex).isEmpty)
        XCTAssertEqual(feed.items(for: claude).first?.approvalKey, .init(session: claude, requestID: AgentTestFixture.correlation("exact")))
        let request = AgentApprovalControlRequest(key: .init(session: claude, requestID: AgentTestFixture.correlation("exact")), summary: "Permission", expiresAt: .distantFuture)
        let attention = AgentWorkspaceApprovalAttentionProjection.requests(pending: [request], delivering: [], selectedSessionID: codex, now: AgentTestFixture.baseDate)
        XCTAssertEqual(attention.map(\.key.session), [claude])
        let policy = AgentAttentionPolicyEngine.apply(
            events: store.attentionEvents, sessions: store.sessions,
            now: AgentTestFixture.baseDate.addingTimeInterval(1),
            state: AgentAttentionPolicyState(), options: AgentAttentionPolicyOptions()
        )
        XCTAssertEqual(policy.state.badges[claude]?.session, claude,
                       "Existing global attention keeps the exact background owner discoverable")
        XCTAssertEqual(policy.state.presentation?.primary?.session, claude)
        XCTAssertEqual(feed.items(for: attention[0].key.session).first?.approvalKey, request.key,
                       "Navigating exact attention owner reveals its exact request")
        XCTAssertTrue(AgentWorkspaceApprovalAttentionProjection.requests(pending: [request], delivering: [], selectedSessionID: claude, now: AgentTestFixture.baseDate).isEmpty)
        ingest(store, provider: .claude, name: "ack", type: .approvalResolved, offset: 2, correlation: "exact", payload: .approvalResolution(.init(state: .approved)))
        XCTAssertEqual(feed.items(for: claude).first?.approvalPresentation(delivery: nil), .approved)
        XCTAssertTrue(feed.items(for: codex).isEmpty)
    }

    func testGlobalAttentionKeepsUnconfirmedDeliveryAndDeduplicatesExactRequestOnly() {
        let codex = AgentSessionInstanceID(sessionID: id(.codex), generation: .init(rawValue: 1))
        let nextCodex = AgentSessionInstanceID(sessionID: id(.codex), generation: .init(rawValue: 2))
        let make: (AgentSessionInstanceID, Date) -> AgentApprovalControlRequest = { session, expiry in
            .init(key: .init(session: session, requestID: AgentTestFixture.correlation("same-request")), summary: "Permission", expiresAt: expiry)
        }
        let first = make(codex, .distantFuture)
        let second = make(nextCodex, .distantFuture)
        let expired = make(.init(sessionID: id(.claude), generation: .init(rawValue: 1)), .distantPast)
        let attention = AgentWorkspaceApprovalAttentionProjection.requests(pending: [first, second, expired], delivering: [first, expired], selectedSessionID: nil, now: AgentTestFixture.baseDate)
        XCTAssertEqual(attention.count, 3)
        XCTAssertEqual(Set(attention.map(\.key.session)), [codex, nextCodex, expired.key.session])
        XCTAssertEqual(attention.filter { $0.key == first.key }.count, 1)
    }

    func testSelectedCanonicalApprovalSurvivesGlobalHistoryCapacityPressure() {
        let (store, feed) = runtime(maximumItems: 16)
        start(store)
        for index in 0..<20 {
            ingest(store, name: "request-\(index)", type: .approvalRequested, offset: Double(index + 1), correlation: "request-\(index)",
                   payload: .approvalRequest(.init(summary: nil, operationCorrelationID: nil, expiresAt: nil)))
        }
        let session = store.sessions[0]
        XCTAssertEqual(feed.items.count, 16, "Persistent Feed storage stays bounded")
        let selected = feed.items(for: session.id, session: session)
        XCTAssertEqual(selected.filter { $0.kind == .approval }.count, session.approvals.count)
        XCTAssertEqual(Set(selected.compactMap(\.approvalKey).map(\.requestID)), Set(session.approvals.keys))
        XCTAssertEqual(feed.items.count, 16, "Recovering visible requests creates no additional retained store")
        let foreign = AgentSessionInstanceID(sessionID: id(.claude), generation: .init(rawValue: 1))
        XCTAssertTrue(feed.items(for: foreign, session: session).isEmpty)
    }

    func testUncorrelatedClaudeThinkingEventUsesNormalizedSemanticsAndStopsAtEnd() {
        let (store, feed) = runtime()
        start(store, provider: .claude)
        ingest(store, provider: .claude, name: "thinking", type: .thinkingStarted, offset: 1,
               payload: .activity(.init(title: "private reasoning", summary: "private context")))
        XCTAssertEqual(feed.items.first?.processingKind, .reasoning)
        XCTAssertEqual(feed.items.first?.title, "Reasoning")
        XCTAssertTrue(feed.items[0].isCurrentActivity(in: store.sessions[0]))
        let identity = feed.items[0].id
        ingest(store, provider: .claude, name: "thinking-end", type: .thinkingEnded, offset: 2)
        XCTAssertEqual(feed.items.count, 1)
        XCTAssertEqual(feed.items[0].id, identity)
        XCTAssertEqual(feed.items[0].status, .completed)
        XCTAssertFalse(feed.items[0].isCurrentActivity(in: store.sessions[0]))
        XCTAssertFalse(String(describing: feed.items).contains("private reasoning"))
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
