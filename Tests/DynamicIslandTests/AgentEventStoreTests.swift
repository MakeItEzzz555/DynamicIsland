import XCTest
@testable import DynamicIsland

@MainActor
final class AgentEventStoreTests: XCTestCase {
    func testOneSessionIsPublishedFromNormalizedStart() {
        let store = AgentEventStore()
        let id = AgentTestFixture.sessionID(.codex, "one")

        XCTAssertEqual(store.ingest(start(id, name: "start")), .applied)

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.activeSessions.map(\.id.sessionID), [id])
    }

    func testMixedProvidersAndSameProjectRemainSeparate() {
        let store = AgentEventStore()
        let codex = AgentTestFixture.sessionID(.codex, "codex")
        let claude = AgentTestFixture.sessionID(.claude, "claude")

        store.ingest(start(codex, name: "codex-start", project: AgentTestFixture.project()))
        store.ingest(start(claude, name: "claude-start", project: AgentTestFixture.project()))

        XCTAssertEqual(store.sessions.count, 2)
        XCTAssertEqual(Set(store.sessions.map(\.id.sessionID.provider)), [.codex, .claude])
    }

    func testTwoSessionsInSameProviderAndProjectRemainSeparate() {
        let store = AgentEventStore()
        let first = AgentTestFixture.sessionID(.codex, "session-a")
        let second = AgentTestFixture.sessionID(.codex, "session-b")

        store.ingest(start(first, name: "start-a", project: AgentTestFixture.project()))
        store.ingest(start(second, name: "start-b", project: AgentTestFixture.project()))

        XCTAssertEqual(Set(store.sessions.map(\.id.sessionID)), [first, second])
    }

    func testSameNativeIDAcrossProvidersDoesNotCollide() {
        let store = AgentEventStore()
        let codex = AgentTestFixture.sessionID(.codex, "shared")
        let claude = AgentTestFixture.sessionID(.claude, "shared")

        store.ingest(start(codex, name: "codex"))
        store.ingest(start(claude, name: "claude"))

        XCTAssertNotNil(store.session(for: instance(codex, generation: 1)))
        XCTAssertNotNil(store.session(for: instance(claude, generation: 1)))
    }

    func testNewGenerationRejectsLateOldGenerationMutation() {
        let store = AgentEventStore()
        let id = AgentTestFixture.sessionID(.codex, "reused")
        store.ingest(start(id, name: "generation-1", generation: 1))
        store.ingest(start(id, name: "generation-2", generation: 2))

        let late = AgentTestFixture.event(
            "late-generation-1",
            sessionID: id,
            generation: 1,
            type: .taskFailed,
            offset: 5,
            payload: .terminal(AgentTerminalEvent(summary: "stale failure"))
        )

        XCTAssertEqual(store.ingest(late), .staleGeneration)
        XCTAssertEqual(store.session(for: instance(id, generation: 2))?.state, .idle)
        XCTAssertEqual(store.activeSessions.map(\.id.generation), [AgentTestFixture.generation(2)])
    }

    func testEventDeduplicationDoesNotDuplicateAttentionOrHistory() {
        let store = AgentEventStore()
        let id = AgentTestFixture.sessionID(.codex, "dedupe")
        store.ingest(start(id, name: "start"))
        let completed = terminal(id, name: "complete", offset: 1)

        XCTAssertEqual(store.ingest(completed), .applied)
        let historyCount = store.sessions[0].recentActivity.count
        XCTAssertEqual(store.ingest(completed), .duplicate)

        XCTAssertEqual(store.sessions[0].recentActivity.count, historyCount)
        XCTAssertEqual(store.attentionEvents.filter { $0.eventID == completed.eventID }.count, 1)
    }

    func testSameProviderEventIDInDifferentSessionsKeepsBothAttentionEvents() {
        let store = AgentEventStore()
        let first = AgentTestFixture.sessionID(.codex, "attention-a")
        let second = AgentTestFixture.sessionID(.codex, "attention-b")
        store.ingest(start(first, name: "first-start"))
        store.ingest(start(second, name: "second-start"))
        store.ingest(terminal(first, name: "shared-completion-id", offset: 1))
        store.ingest(terminal(second, name: "shared-completion-id", offset: 2))

        XCTAssertEqual(store.attentionEvents.count, 2)
        XCTAssertEqual(Set(store.attentionEvents.map(\.session.sessionID)), [first, second])
    }

    func testPerSessionAndRememberedEventBoundsHoldUnderFlood() {
        let limits = makeLimits(activity: 3, remembered: 5)
        let store = AgentEventStore(limits: limits)
        let id = AgentTestFixture.sessionID(.codex, "bounded")
        store.ingest(start(id, name: "start"))

        for index in 0..<30 {
            store.ingest(AgentTestFixture.event(
                "work-\(index)",
                sessionID: id,
                type: .agentWorking,
                offset: TimeInterval(index + 1),
                payload: .activity(AgentActivityDescriptor(title: "Work \(index)", summary: nil))
            ))
        }

        let session = store.sessions[0]
        XCTAssertEqual(session.recentActivity.count, 3)
        XCTAssertEqual(session.recentEventOrder.count, 5)
        XCTAssertEqual(session.eventFingerprints.count, 5)
    }

    func testGlobalHistoryBoundSpansSessions() {
        var limits = makeLimits(activity: 10, remembered: 20)
        limits.maximumGlobalActivity = 4
        let store = AgentEventStore(limits: limits)
        for sessionIndex in 0..<2 {
            let id = AgentTestFixture.sessionID(.codex, "global-\(sessionIndex)")
            store.ingest(start(id, name: "start-\(sessionIndex)", offset: TimeInterval(sessionIndex)))
            for eventIndex in 0..<4 {
                store.ingest(AgentTestFixture.event(
                    "s\(sessionIndex)-e\(eventIndex)",
                    sessionID: id,
                    type: .agentWorking,
                    offset: TimeInterval(10 + sessionIndex * 10 + eventIndex),
                    payload: .activity(AgentActivityDescriptor(title: "Work", summary: nil))
                ))
            }
        }

        XCTAssertEqual(store.sessions.reduce(0) { $0 + $1.recentActivity.count }, 4)
    }

    func testPendingAndTrackedOperationCollectionsAreBounded() {
        var limits = makeLimits(activity: 20, remembered: 40)
        limits.maximumPendingOperations = 2
        limits.maximumTrackedOperations = 2
        let store = AgentEventStore(limits: limits)
        let id = AgentTestFixture.sessionID(.codex, "operation-bounds")
        store.ingest(start(id, name: "start"))

        for index in 0..<3 {
            store.ingest(AgentTestFixture.event(
                "early-complete-\(index)",
                sessionID: id,
                type: .toolCompleted,
                offset: TimeInterval(index + 1),
                correlationID: "pending-\(index)",
                payload: .tool(AgentToolEvent(name: nil, category: nil, summary: nil, success: true))
            ))
        }
        XCTAssertEqual(store.sessions[0].pendingOperations.count, 2)
        XCTAssertFalse(store.sessions[0].pendingOperations.keys.contains {
            $0.correlationID == AgentTestFixture.correlation("pending-0")
        })

        for index in 0..<3 {
            store.ingest(AgentTestFixture.event(
                "tool-start-\(index)",
                sessionID: id,
                type: .toolStarted,
                offset: TimeInterval(10 + index * 2),
                correlationID: "tool-\(index)",
                payload: .tool(AgentToolEvent(name: "Tool", category: nil, summary: nil, success: nil))
            ))
            store.ingest(AgentTestFixture.event(
                "tool-end-\(index)",
                sessionID: id,
                type: .toolCompleted,
                offset: TimeInterval(11 + index * 2),
                correlationID: "tool-\(index)",
                payload: .tool(AgentToolEvent(name: nil, category: nil, summary: nil, success: true))
            ))
        }

        XCTAssertEqual(store.sessions[0].tools.count, 2)
        XCTAssertNil(store.sessions[0].tools[AgentTestFixture.correlation("tool-0")])
    }

    func testAttentionHistoryIsBounded() {
        var limits = makeLimits()
        limits.maximumAttentionEvents = 2
        let store = AgentEventStore(limits: limits)
        for index in 0..<3 {
            let id = AgentTestFixture.sessionID(.codex, "attention-bound-\(index)")
            store.ingest(start(id, name: "start-\(index)", offset: TimeInterval(index)))
            store.ingest(terminal(id, name: "complete-\(index)", offset: TimeInterval(index + 10)))
        }

        XCTAssertEqual(store.attentionEvents.count, 2)
    }

    func testCompletedTurnStaysUntilExplicitSessionEndThenPrunesAfterRetention() {
        var limits = makeLimits()
        limits.completedSessionRetention = 10
        let store = AgentEventStore(limits: limits)
        let completedID = AgentTestFixture.sessionID(.codex, "old-completed")
        let activeID = AgentTestFixture.sessionID(.claude, "old-active")
        store.ingest(start(completedID, name: "completed-start"))
        store.ingest(terminal(completedID, name: "completed", offset: 1))
        store.ingest(start(activeID, name: "active-start"))

        store.prune(at: AgentTestFixture.baseDate.addingTimeInterval(100))

        XCTAssertNotNil(store.session(for: instance(completedID, generation: 1)))
        XCTAssertNotNil(store.session(for: instance(activeID, generation: 1)))

        store.ingest(AgentTestFixture.event(
            "completed-session-end",
            sessionID: completedID,
            type: .sessionEnded,
            offset: 101,
            payload: .none
        ))
        store.prune(at: AgentTestFixture.baseDate.addingTimeInterval(200))

        XCTAssertNil(store.session(for: instance(completedID, generation: 1)))
        XCTAssertNotNil(store.session(for: instance(activeID, generation: 1)))
    }

    func testCapacityEvictsOldTerminalBeforeActiveSession() {
        var limits = makeLimits()
        limits.maximumSessions = 2
        let store = AgentEventStore(limits: limits)
        let terminalID = AgentTestFixture.sessionID(.codex, "terminal")
        let activeID = AgentTestFixture.sessionID(.claude, "active")
        let newID = AgentTestFixture.sessionID(.codex, "new")
        store.ingest(start(terminalID, name: "terminal-start"))
        store.ingest(terminal(terminalID, name: "terminal-end", offset: 1))
        store.ingest(start(activeID, name: "active-start", offset: 2))

        XCTAssertEqual(store.ingest(start(newID, name: "new-start", offset: 3)), .applied)
        XCTAssertNil(store.session(for: instance(terminalID, generation: 1)))
        XCTAssertNotNil(store.session(for: instance(activeID, generation: 1)))
        XCTAssertNotNil(store.session(for: instance(newID, generation: 1)))
    }

    func testCapacityRejectsNewSessionRatherThanEvictingActiveSessions() {
        var limits = makeLimits()
        limits.maximumSessions = 2
        let store = AgentEventStore(limits: limits)
        store.ingest(start(AgentTestFixture.sessionID(.codex, "a"), name: "a"))
        store.ingest(start(AgentTestFixture.sessionID(.claude, "b"), name: "b"))

        let result = store.ingest(start(AgentTestFixture.sessionID(.codex, "c"), name: "c"))

        XCTAssertEqual(result, .rejected(.sessionCapacity))
        XCTAssertEqual(store.sessions.count, 2)
    }

    func testGenerationReplacementCanUseCapacityOwnedByPriorGeneration() {
        var limits = makeLimits()
        limits.maximumSessions = 1
        let store = AgentEventStore(limits: limits)
        let id = AgentTestFixture.sessionID(.codex, "capacity-generation")
        store.ingest(start(id, name: "generation-1", generation: 1))

        XCTAssertEqual(store.ingest(start(id, name: "generation-2", generation: 2)), .applied)
        XCTAssertEqual(store.sessions.map(\.id.generation), [AgentTestFixture.generation(2)])
    }

    func testTenConcurrentSessionsRemainIndependent() {
        let store = AgentEventStore()
        for index in 0..<10 {
            let provider: AgentProvider = index.isMultiple(of: 2) ? .codex : .claude
            store.ingest(start(
                AgentTestFixture.sessionID(provider, "session-\(index)"),
                name: "start-\(index)",
                offset: TimeInterval(index)
            ))
        }

        XCTAssertEqual(store.activeSessions.count, 10)
        XCTAssertEqual(Set(store.activeSessions.map(\.id.sessionID)).count, 10)
    }

    func testAttentionDerivationUsesBlockingStatesOnly() {
        let store = AgentEventStore()
        let approvalID = AgentTestFixture.sessionID(.codex, "approval")
        let completedID = AgentTestFixture.sessionID(.claude, "completed")
        store.ingest(start(approvalID, name: "approval-start"))
        store.ingest(start(completedID, name: "completed-start"))
        store.ingest(AgentTestFixture.event(
            "approval-request",
            sessionID: approvalID,
            type: .approvalRequested,
            offset: 1,
            correlationID: "approval",
            payload: .approvalRequest(AgentApprovalRequest(summary: nil, operationCorrelationID: nil, expiresAt: nil))
        ))
        store.ingest(terminal(completedID, name: "completed", offset: 2))

        XCTAssertEqual(store.sessionsRequiringAttention.map(\.id.sessionID), [approvalID])
        XCTAssertEqual(Set(store.attentionEvents.map(\.reason)), [.approvalRequired, .completed])
    }

    func testCapabilityChangeAndOptionalMetadataStayProviderLocal() {
        let store = AgentEventStore()
        let codex = AgentTestFixture.sessionID(.codex, "metadata")
        let claude = AgentTestFixture.sessionID(.claude, "metadata")
        store.ingest(start(codex, name: "codex"))
        store.ingest(start(claude, name: "claude"))
        store.ingest(AgentTestFixture.event(
            "codex-caps",
            sessionID: codex,
            type: .capabilitiesUpdated,
            offset: 1,
            payload: .capabilities(AgentTestFixture.capabilities([.contextUsage]))
        ))
        store.ingest(AgentTestFixture.event(
            "codex-project",
            sessionID: codex,
            type: .projectContextUpdated,
            offset: 2,
            payload: .projectContext(AgentProjectContext(model: "gpt", sourceApplication: nil))
        ))

        XCTAssertTrue(store.session(for: instance(codex, generation: 1))?.capabilities.contains(.contextUsage) == true)
        XCTAssertEqual(store.session(for: instance(codex, generation: 1))?.project.model, "gpt")
        XCTAssertFalse(store.session(for: instance(claude, generation: 1))?.capabilities.contains(.contextUsage) == true)
        XCTAssertNil(store.session(for: instance(claude, generation: 1))?.project.model)
    }

    func testUnknownFutureProviderIsIsolatedLikeKnownProviders() {
        let store = AgentEventStore()
        let future = AgentTestFixture.sessionID(.other("com.example.future"), "future-session")
        XCTAssertEqual(store.ingest(start(future, name: "future")), .applied)
        XCTAssertEqual(store.sessions.first?.id.sessionID.provider, .other("com.example.future"))
    }

    func testFutureProviderWithKnownProviderSpellingStillSortsDeterministically() {
        let store = AgentEventStore()
        let custom = start(AgentTestFixture.sessionID(.other("codex"), "same"), name: "custom-start")
        let known = start(AgentTestFixture.sessionID(.codex, "same"), name: "known-start")

        store.ingest(custom)
        store.ingest(known)

        XCTAssertEqual(store.sessions.map(\.id.sessionID.provider), [.codex, .other("codex")])
    }

    func testHundredsOfDuplicatesRemainBoundedAndIdempotent() {
        let store = AgentEventStore(limits: makeLimits(activity: 5, remembered: 8))
        let id = AgentTestFixture.sessionID(.codex, "duplicate-flood")
        store.ingest(start(id, name: "start"))
        let event = AgentTestFixture.event(
            "single-work",
            sessionID: id,
            type: .agentWorking,
            offset: 1,
            payload: .activity(AgentActivityDescriptor(title: "Work", summary: nil))
        )
        store.ingest(event)
        for _ in 0..<500 {
            XCTAssertEqual(store.ingest(event), .duplicate)
        }

        XCTAssertEqual(store.sessions[0].recentActivity.filter { $0.id == event.eventID }.count, 1)
        XCTAssertLessThanOrEqual(store.sessions[0].eventFingerprints.count, 8)
    }

    private func start(
        _ id: AgentSessionID,
        name: String,
        generation: UInt64 = 1,
        offset: TimeInterval = 0,
        project: AgentProjectContext? = nil
    ) -> AgentEvent {
        AgentTestFixture.event(
            name,
            sessionID: id,
            generation: generation,
            type: .sessionStarted,
            offset: offset,
            payload: .sessionMetadata(AgentSessionMetadata(project: project))
        )
    }

    private func terminal(_ id: AgentSessionID, name: String, offset: TimeInterval) -> AgentEvent {
        AgentTestFixture.event(
            name,
            sessionID: id,
            type: .taskCompleted,
            offset: offset,
            payload: .terminal(AgentTerminalEvent(summary: "Done"))
        )
    }

    private func instance(_ id: AgentSessionID, generation: UInt64) -> AgentSessionInstanceID {
        AgentSessionInstanceID(sessionID: id, generation: AgentTestFixture.generation(generation))
    }

    private func makeLimits(activity: Int = 20, remembered: Int = 40) -> AgentEventStoreLimits {
        AgentEventStoreLimits(
            maximumSessions: 32,
            maximumActivityPerSession: activity,
            maximumGlobalActivity: 200,
            maximumRememberedEventIDs: remembered,
            maximumPendingOperations: 8,
            maximumTrackedOperations: 8,
            maximumAttentionEvents: 16,
            completedSessionRetention: 100
        )
    }
}


final class AgentAttentionPolicyTests: XCTestCase {
    func testNewerGenerationCannotBeRetractedByOlderDeadline() {
        let base = Date(timeIntervalSince1970: 100)
        var state = AgentAttentionPolicyState()
        let options = AgentAttentionPolicyOptions()

        state = AgentAttentionPolicyEngine.apply(
            events: [attention("a", reason: .completed, priority: .completed, at: base)],
            sessions: [],
            now: base,
            state: state,
            options: options
        ).state
        let staleGeneration = try! XCTUnwrap(state.presentation?.generation)

        state = AgentAttentionPolicyEngine.apply(
            events: [attention("b", reason: .failed, priority: .failure, at: base.addingTimeInterval(1))],
            sessions: [],
            now: base.addingTimeInterval(1),
            state: state,
            options: options
        ).state
        let currentGeneration = try! XCTUnwrap(state.presentation?.generation)

        let afterStaleExpiry = AgentAttentionPolicyEngine.expire(
            generation: staleGeneration,
            now: base.addingTimeInterval(10),
            state: state
        )
        XCTAssertEqual(afterStaleExpiry.presentation?.generation, currentGeneration)
    }

    func testTenCompletionsAggregateWithoutUnboundedPresentation() {
        let now = Date(timeIntervalSince1970: 200)
        let events = (0..<10).map {
            attention(
                "completion-\($0)",
                sessionSuffix: "\($0)",
                reason: .completed,
                priority: .completed,
                at: now
            )
        }
        let result = AgentAttentionPolicyEngine.apply(
            events: events,
            sessions: [],
            now: now,
            state: AgentAttentionPolicyState(),
            options: AgentAttentionPolicyOptions()
        )

        XCTAssertEqual(result.state.presentation?.items.count, 3)
        XCTAssertEqual(result.state.presentation?.totalCount, 10)
    }

    func testFailureWinsSameSessionCoalescingWindow() {
        let now = Date(timeIntervalSince1970: 300)
        var state = AgentAttentionPolicyState()
        let options = AgentAttentionPolicyOptions()
        state = AgentAttentionPolicyEngine.apply(
            events: [attention("complete", reason: .completed, priority: .completed, at: now)],
            sessions: [],
            now: now,
            state: state,
            options: options
        ).state
        state = AgentAttentionPolicyEngine.apply(
            events: [attention("fail", reason: .failed, priority: .failure, at: now.addingTimeInterval(0.2))],
            sessions: [],
            now: now.addingTimeInterval(0.2),
            state: state,
            options: options
        ).state

        XCTAssertEqual(state.presentation?.primary?.reason, .failed)
        XCTAssertEqual(state.presentation?.items.count, 1)
    }

    func testSoundIntentIsOncePerEventAndGloballyThrottled() {
        let now = Date(timeIntervalSince1970: 400)
        let options = AgentAttentionPolicyOptions()
        let first = AgentAttentionPolicyEngine.apply(
            events: [attention("one", reason: .completed, priority: .completed, at: now)],
            sessions: [],
            now: now,
            state: AgentAttentionPolicyState(),
            options: options
        )
        XCTAssertNotNil(first.soundIntent)

        let duplicate = AgentAttentionPolicyEngine.apply(
            events: [attention("one", reason: .completed, priority: .completed, at: now)],
            sessions: [],
            now: now.addingTimeInterval(0.1),
            state: first.state,
            options: options
        )
        XCTAssertNil(duplicate.soundIntent)

        let throttled = AgentAttentionPolicyEngine.apply(
            events: [attention("two", sessionSuffix: "two", reason: .completed, priority: .completed, at: now.addingTimeInterval(1))],
            sessions: [],
            now: now.addingTimeInterval(1),
            state: duplicate.state,
            options: options
        )
        XCTAssertNil(throttled.soundIntent)

        let allowed = AgentAttentionPolicyEngine.apply(
            events: [attention("three", sessionSuffix: "three", reason: .failed, priority: .failure, at: now.addingTimeInterval(2))],
            sessions: [],
            now: now.addingTimeInterval(2),
            state: throttled.state,
            options: options
        )
        XCTAssertNotNil(allowed.soundIntent)
    }

    func testApprovalCreatesPersistentBadgeWhileCompletionDoesNot() {
        let now = Date(timeIntervalSince1970: 500)
        var state = AgentAttentionPolicyState()
        state = AgentAttentionPolicyEngine.apply(
            events: [
                attention("approval", reason: .approvalRequired, priority: .approvalRequired, at: now),
                attention("done", sessionSuffix: "done", reason: .completed, priority: .completed, at: now)
            ],
            sessions: [],
            now: now,
            state: state,
            options: AgentAttentionPolicyOptions()
        ).state

        XCTAssertEqual(state.badges.count, 1)
        XCTAssertEqual(state.badges.values.first?.reason, .approvalRequired)
    }

    private func attention(
        _ id: String,
        sessionSuffix: String = "shared",
        reason: AgentAttentionReason,
        priority: AgentAttentionPriority,
        at date: Date
    ) -> AgentAttentionEvent {
        AgentAttentionEvent(
            eventID: AgentEventID(rawValue: id),
            session: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: .codex, nativeID: "session-" + sessionSuffix),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .unknown,
            reason: reason,
            priority: priority,
            timestamp: date,
            displaySummary: id
        )
    }
}
