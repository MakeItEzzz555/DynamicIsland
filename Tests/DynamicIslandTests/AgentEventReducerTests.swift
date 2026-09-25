import XCTest
@testable import DynamicIsland

final class AgentEventReducerTests: XCTestCase {
    func testIdleThinkingToolPrecedenceAndReturnToIdle() throws {
        let id = AgentTestFixture.sessionID(.codex, "state-flow")
        var session = try startedSession(id)

        session = try apply(.init(
            name: "thinking",
            id: id,
            type: .thinkingStarted,
            offset: 1,
            payload: .activity(AgentActivityDescriptor(title: nil, summary: nil))
        ), to: session)
        XCTAssertEqual(session.state, .thinking)

        session = try apply(.init(
            name: "tool-start",
            id: id,
            type: .toolStarted,
            offset: 2,
            correlation: "tool",
            payload: .tool(AgentToolEvent(name: "Read", category: nil, summary: nil, success: nil))
        ), to: session)
        XCTAssertEqual(session.state, .runningTool)
        XCTAssertTrue(session.isThinking)

        session = try apply(.init(
            name: "tool-end",
            id: id,
            type: .toolCompleted,
            offset: 3,
            correlation: "tool",
            payload: .tool(AgentToolEvent(name: nil, category: nil, summary: nil, success: true))
        ), to: session)
        XCTAssertEqual(session.state, .thinking)

        session = try apply(.init(
            name: "thinking-end",
            id: id,
            type: .thinkingEnded,
            offset: 4
        ), to: session)
        XCTAssertEqual(session.state, .idle)
    }

    func testWorkingApprovalResolutionReturnsToUnderlyingWork() throws {
        let id = AgentTestFixture.sessionID(.codex, "approval-flow")
        var session = try startedSession(id)
        session = try apply(.init(
            name: "working",
            id: id,
            type: .agentWorking,
            offset: 1,
            payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil))
        ), to: session)
        session = try apply(approvalRequest(id: id, offset: 2), to: session)

        XCTAssertEqual(session.state, .waitingForApproval)
        XCTAssertEqual(session.approvals[AgentTestFixture.correlation("approval")]?.state, .pending)

        session = try apply(approvalResolution(id: id, offset: 3), to: session)
        XCTAssertEqual(session.state, .working)
        XCTAssertEqual(session.approvals[AgentTestFixture.correlation("approval")]?.state, .approved)
    }

    func testPlanReadyProducesStableAttentionPriority() throws {
        let id = AgentTestFixture.sessionID(.codex, "plan")
        let session = try startedSession(id)
        let event = AgentTestFixture.event(
            "plan-ready",
            sessionID: id,
            type: .planReady,
            offset: 1,
            payload: .plan(AgentPlanEvent(summary: "Review this plan"))
        )

        let result = AgentEventReducer.reduce(session: session, event: event)

        XCTAssertEqual(result.session?.state, .planReady)
        XCTAssertEqual(result.attention?.reason, .planReady)
        XCTAssertEqual(result.attention?.priority, .planReady)
    }

    func testPlanningAndCommandStatesReturnToUnderlyingWorkingState() throws {
        let id = AgentTestFixture.sessionID(.codex, "planning-command")
        var session = try startedSession(id)
        session = try apply(.init(
            name: "working",
            id: id,
            type: .agentWorking,
            offset: 1,
            payload: .activity(AgentActivityDescriptor(title: nil, summary: nil))
        ), to: session)
        session = try apply(.init(
            name: "planning",
            id: id,
            type: .planningStarted,
            offset: 2,
            payload: .activity(AgentActivityDescriptor(title: nil, summary: nil))
        ), to: session)
        XCTAssertEqual(session.state, .planning)

        session = try apply(AgentTestFixture.event(
            "plan-ready",
            sessionID: id,
            type: .planReady,
            offset: 2.5,
            payload: .plan(AgentPlanEvent(summary: "Ready"))
        ), to: session)
        session = try apply(.init(
            name: "continue-working",
            id: id,
            type: .agentWorking,
            offset: 2.75,
            payload: .activity(AgentActivityDescriptor(title: nil, summary: nil))
        ), to: session)
        session = try apply(.init(
            name: "command-start",
            id: id,
            type: .commandStarted,
            offset: 3,
            correlation: "command",
            payload: .command(AgentCommandEvent(executable: "swift", success: nil, exitCode: nil))
        ), to: session)
        XCTAssertEqual(session.state, .runningCommand)

        session = try apply(.init(
            name: "command-end",
            id: id,
            type: .commandCompleted,
            offset: 4,
            correlation: "command",
            payload: .command(AgentCommandEvent(executable: nil, success: true, exitCode: 0))
        ), to: session)
        XCTAssertEqual(session.state, .working)
    }

    func testWaitingForUserResolvesOnlyMatchingCorrelation() throws {
        let id = AgentTestFixture.sessionID(.claude, "waiting-user")
        var session = try startedSession(id)
        session = try apply(AgentTestFixture.event(
            "waiting",
            sessionID: id,
            type: .waitingForUser,
            offset: 1,
            correlationID: "question",
            payload: .userInput(AgentUserInputEvent(summary: "Choose an option"))
        ), to: session)
        XCTAssertEqual(session.state, .waitingForUser)

        session = try apply(AgentTestFixture.event(
            "wrong-resolution",
            sessionID: id,
            type: .userInputResolved,
            offset: 2,
            correlationID: "other"
        ), to: session)
        XCTAssertEqual(session.state, .waitingForUser)

        session = try apply(AgentTestFixture.event(
            "resolution",
            sessionID: id,
            type: .userInputResolved,
            offset: 3,
            correlationID: "question"
        ), to: session)
        XCTAssertEqual(session.state, .idle)
    }

    func testWeakerWorkingEvidenceCannotClearAuthoritativePlanReady() throws {
        let id = AgentTestFixture.sessionID(.codex, "authority-plan")
        var session = try startedSession(id)
        session = try apply(AgentTestFixture.event(
            "plan",
            sessionID: id,
            type: .planReady,
            offset: 1,
            authority: .lifecycle,
            payload: .plan(AgentPlanEvent(summary: "Ready"))
        ), to: session)

        session = try apply(AgentTestFixture.event(
            "weak-work",
            sessionID: id,
            type: .agentWorking,
            offset: 2,
            authority: .structuredTelemetry,
            payload: .activity(AgentActivityDescriptor(title: "Activity", summary: nil))
        ), to: session)

        XCTAssertEqual(session.state, .planReady)
        XCTAssertTrue(session.isPlanReady)
    }

    func testWeakerCapabilitySnapshotCannotRemoveStrongerCapability() throws {
        let id = AgentTestFixture.sessionID(.codex, "authority-capability")
        var session = try startedSession(id)
        session = try apply(AgentTestFixture.event(
            "strong-capability",
            sessionID: id,
            type: .capabilitiesUpdated,
            offset: 1,
            authority: .lifecycle,
            payload: .capabilities(AgentTestFixture.capabilities([.approvalObservation]))
        ), to: session)
        session = try apply(AgentTestFixture.event(
            "weak-empty-capability",
            sessionID: id,
            type: .capabilitiesUpdated,
            offset: 2,
            authority: .structuredTelemetry,
            payload: .capabilities(AgentCapabilities())
        ), to: session)

        XCTAssertTrue(session.capabilities.contains(.approvalObservation))
    }

    func testWeakerTerminalCannotOverrideStrongerActiveLifecycle() throws {
        let id = AgentTestFixture.sessionID(.codex, "weak-terminal")
        let session = try startedSession(id)
        let weakerTerminal = AgentTestFixture.event(
            "weak-complete",
            sessionID: id,
            type: .taskCompleted,
            offset: 1,
            authority: .localStructuredRecord,
            payload: .terminal(AgentTerminalEvent(summary: "Recovered completion"))
        )

        let result = AgentEventReducer.reduce(session: session, event: weakerTerminal)

        XCTAssertEqual(result.application, .ignoredWeakerEvidence)
        XCTAssertEqual(result.session?.state, .idle)
        XCTAssertEqual(result.session?.terminalAuthority, .lifecycle)
        XCTAssertNil(result.session?.endedAt)
        XCTAssertNil(result.attention)
    }

    func testStrongerJoiningStartRaisesLifecycleThreshold() throws {
        let id = AgentTestFixture.sessionID(.codex, "authority-upgrade")
        let recoveryStart = AgentTestFixture.event(
            "recovery-start",
            sessionID: id,
            type: .sessionStarted,
            offset: 0,
            authority: .localStructuredRecord,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil))
        )
        var session = try XCTUnwrap(AgentEventReducer.reduce(session: nil, event: recoveryStart).session)
        XCTAssertEqual(session.terminalAuthority, .localStructuredRecord)

        session = try apply(AgentTestFixture.event(
            "hook-start",
            sessionID: id,
            type: .sessionStarted,
            offset: 1,
            authority: .lifecycle,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil))
        ), to: session)
        XCTAssertEqual(session.terminalAuthority, .lifecycle)

        let result = AgentEventReducer.reduce(
            session: session,
            event: AgentTestFixture.event(
                "late-recovery-complete",
                sessionID: id,
                type: .taskCompleted,
                offset: 2,
                authority: .localStructuredRecord,
                payload: .terminal(AgentTerminalEvent(summary: "Late recovery"))
            )
        )

        XCTAssertEqual(result.application, .ignoredWeakerEvidence)
        XCTAssertEqual(result.session?.state, .idle)
    }

    func testTerminalTransitionOccursOnceAndLaterWorkCannotResurrectGeneration() throws {
        let id = AgentTestFixture.sessionID(.codex, "terminal")
        var session = try startedSession(id)
        let completed = terminalEvent("complete-1", id: id, type: .taskCompleted, offset: 1)
        let first = AgentEventReducer.reduce(session: session, event: completed)
        session = try XCTUnwrap(first.session)

        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(first.attention?.reason, .completed)

        let duplicateTerminal = terminalEvent("complete-2", id: id, type: .taskCompleted, offset: 2)
        let second = AgentEventReducer.reduce(session: session, event: duplicateTerminal)
        XCTAssertEqual(second.application, .ignoredAfterTerminal)
        XCTAssertNil(second.attention)

        let lateWork = AgentTestFixture.event(
            "late-work",
            sessionID: id,
            type: .toolStarted,
            offset: 3,
            correlationID: "late-tool",
            payload: .tool(AgentToolEvent(name: "Late", category: nil, summary: nil, success: nil))
        )
        let late = AgentEventReducer.reduce(session: second.session, event: lateWork)
        XCTAssertEqual(late.application, .ignoredAfterTerminal)
        XCTAssertEqual(late.session?.state, .completed)
        XCTAssertNil(late.session?.tools[AgentTestFixture.correlation("late-tool")])
    }

    func testFailureAndInterruptionAreDistinctTerminalStates() throws {
        let failedID = AgentTestFixture.sessionID(.codex, "failed")
        let interruptedID = AgentTestFixture.sessionID(.claude, "interrupted")

        let failed = AgentEventReducer.reduce(
            session: try startedSession(failedID),
            event: terminalEvent("failed-event", id: failedID, type: .taskFailed, offset: 1)
        )
        let interrupted = AgentEventReducer.reduce(
            session: try startedSession(interruptedID),
            event: terminalEvent("interrupted-event", id: interruptedID, type: .interrupted, offset: 1)
        )

        XCTAssertEqual(failed.session?.state, .failed)
        XCTAssertEqual(failed.attention?.priority, .failure)
        XCTAssertEqual(interrupted.session?.state, .interrupted)
        XCTAssertEqual(interrupted.attention?.priority, .interrupted)
    }

    func testGenerationMismatchIsRejectedBeforeMutation() throws {
        let id = AgentTestFixture.sessionID(.codex, "generation")
        let session = try startedSession(id)
        let future = AgentTestFixture.event(
            "future",
            sessionID: id,
            generation: 2,
            type: .agentWorking,
            offset: 1,
            payload: .activity(AgentActivityDescriptor(title: nil, summary: nil))
        )

        let result = AgentEventReducer.reduce(session: session, event: future)

        XCTAssertEqual(result.application, .staleGeneration)
        XCTAssertEqual(result.session, session)
    }

    func testExactDuplicateIsIdempotentAndConflictingDuplicateIsRejected() throws {
        let id = AgentTestFixture.sessionID(.codex, "dedupe")
        let session = try startedSession(id)
        let working = AgentTestFixture.event(
            "same-id",
            sessionID: id,
            type: .agentWorking,
            offset: 1,
            payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil))
        )
        let first = AgentEventReducer.reduce(session: session, event: working)
        let duplicate = AgentEventReducer.reduce(session: first.session, event: working)
        XCTAssertEqual(duplicate.application, .duplicate)
        XCTAssertEqual(duplicate.session?.recentActivity.count, first.session?.recentActivity.count)

        let conflict = AgentTestFixture.event(
            "same-id",
            sessionID: id,
            type: .thinkingStarted,
            offset: 2,
            payload: .activity(AgentActivityDescriptor(title: "Different", summary: nil))
        )
        let conflicting = AgentEventReducer.reduce(session: first.session, event: conflict)
        XCTAssertEqual(conflicting.application, .rejected(.conflictingDuplicate))
        XCTAssertEqual(conflicting.session, first.session)
    }

    func testToolCompletionBeforeStartReconcilesByCorrelation() throws {
        let id = AgentTestFixture.sessionID(.codex, "tool-reorder")
        var session = try startedSession(id)
        session = try apply(.init(
            name: "tool-end",
            id: id,
            type: .toolCompleted,
            offset: 2,
            correlation: "tool",
            payload: .tool(AgentToolEvent(name: nil, category: nil, summary: "done", success: true))
        ), to: session)
        XCTAssertNil(session.tools[AgentTestFixture.correlation("tool")])
        let pendingKey = AgentPendingOperationKey(
            kind: .tool,
            correlationID: AgentTestFixture.correlation("tool")
        )
        XCTAssertNotNil(session.pendingOperations[pendingKey])

        session = try apply(.init(
            name: "tool-start",
            id: id,
            type: .toolStarted,
            offset: 1,
            correlation: "tool",
            payload: .tool(AgentToolEvent(name: "Read", category: nil, summary: nil, success: nil))
        ), to: session)

        XCTAssertEqual(session.tools[AgentTestFixture.correlation("tool")]?.status, .completed)
        XCTAssertEqual(session.tools[AgentTestFixture.correlation("tool")]?.summary, "done")
        XCTAssertNil(session.pendingOperations[pendingKey])
    }

    func testApprovalResolutionBeforeRequestReconcilesWithoutFalseAttention() throws {
        let id = AgentTestFixture.sessionID(.claude, "approval-reorder")
        var session = try startedSession(id)
        session = try apply(approvalResolution(id: id, offset: 2), to: session)

        let request = approvalRequest(id: id, offset: 1)
        let result = AgentEventReducer.reduce(session: session, event: request)

        XCTAssertEqual(result.session?.approvals[AgentTestFixture.correlation("approval")]?.state, .approved)
        XCTAssertNotEqual(result.session?.state, .waitingForApproval)
        XCTAssertNil(result.attention)
    }

    func testMatchingOperationStartResolvesObservedApprovalWithoutFabricatedRequestID() throws {
        let id = AgentTestFixture.sessionID(.codex, "approval-operation")
        var session = try startedSession(id)
        session = try apply(AgentTestFixture.event(
            "approval-request",
            sessionID: id,
            type: .approvalRequested,
            offset: 1,
            correlationID: "semantic-request",
            payload: .approvalRequest(AgentApprovalRequest(
                summary: "Bash approval required",
                operationCorrelationID: AgentTestFixture.correlation("operation-bash"),
                expiresAt: nil
            ))
        ), to: session)
        XCTAssertEqual(session.state, .waitingForApproval)

        session = try apply(AgentTestFixture.event(
            "command-start",
            sessionID: id,
            type: .commandStarted,
            offset: 2,
            correlationID: "provider-tool-use-id",
            payload: .command(AgentCommandEvent(executable: "bash", success: nil, exitCode: nil))
        ), to: session)

        XCTAssertEqual(session.approvals[AgentTestFixture.correlation("semantic-request")]?.state, .approved)
        XCTAssertEqual(session.state, .runningCommand)
        XCTAssertEqual(
            session.commands[AgentTestFixture.correlation("provider-tool-use-id")]?.status,
            .active
        )
    }

    func testMismatchedOperationDoesNotResolvePendingApproval() throws {
        let id = AgentTestFixture.sessionID(.claude, "approval-mismatch")
        var session = try startedSession(id)
        session = try apply(AgentTestFixture.event(
            "approval-request",
            sessionID: id,
            type: .approvalRequested,
            offset: 1,
            correlationID: "semantic-request",
            payload: .approvalRequest(AgentApprovalRequest(
                summary: "Bash approval required",
                operationCorrelationID: AgentTestFixture.correlation("operation-bash"),
                expiresAt: nil
            ))
        ), to: session)

        session = try apply(AgentTestFixture.event(
            "read-start",
            sessionID: id,
            type: .toolStarted,
            offset: 2,
            correlationID: "read-1",
            payload: .tool(AgentToolEvent(name: "Read", category: "read", summary: nil, success: nil))
        ), to: session)

        XCTAssertEqual(session.approvals[AgentTestFixture.correlation("semantic-request")]?.state, .pending)
        XCTAssertEqual(session.state, .waitingForApproval)
    }

    func testResolvedSemanticApprovalCorrelationCanBeRequestedAgain() throws {
        let id = AgentTestFixture.sessionID(.claude, "approval-repeat")
        var session = try startedSession(id)
        let operation = AgentTestFixture.correlation("operation-bash")
        let requestID = "same-semantic-request"

        session = try apply(AgentTestFixture.event(
            "request-1",
            sessionID: id,
            type: .approvalRequested,
            offset: 1,
            correlationID: requestID,
            payload: .approvalRequest(AgentApprovalRequest(
                summary: "Bash approval required",
                operationCorrelationID: operation,
                expiresAt: nil
            ))
        ), to: session)
        session = try apply(AgentTestFixture.event(
            "resolve-1",
            sessionID: id,
            type: .approvalResolved,
            offset: 2,
            correlationID: requestID,
            payload: .approvalResolution(AgentApprovalResolution(state: .denied))
        ), to: session)

        let second = AgentEventReducer.reduce(
            session: session,
            event: AgentTestFixture.event(
                "request-2",
                sessionID: id,
                type: .approvalRequested,
                offset: 3,
                correlationID: requestID,
                payload: .approvalRequest(AgentApprovalRequest(
                    summary: "Bash approval required",
                    operationCorrelationID: operation,
                    expiresAt: nil
                ))
            )
        )

        XCTAssertEqual(second.application, .applied)
        XCTAssertEqual(second.session?.approvals[AgentTestFixture.correlation(requestID)]?.state, .pending)
        XCTAssertEqual(second.attention?.reason, .approvalRequired)
    }

    func testPendingApprovalExpiresDeterministicallyOnLaterEvent() throws {
        let id = AgentTestFixture.sessionID(.claude, "approval-expiry")
        var session = try startedSession(id)
        session = try apply(AgentTestFixture.event(
            "expiring-approval",
            sessionID: id,
            type: .approvalRequested,
            offset: 1,
            correlationID: "approval",
            payload: .approvalRequest(AgentApprovalRequest(
                summary: "Temporary request",
                operationCorrelationID: nil,
                expiresAt: AgentTestFixture.baseDate.addingTimeInterval(2)
            ))
        ), to: session)
        XCTAssertEqual(session.state, .waitingForApproval)

        session = try apply(AgentTestFixture.event(
            "heartbeat-after-expiry",
            sessionID: id,
            type: .heartbeat,
            offset: 3
        ), to: session)

        XCTAssertEqual(session.approvals[AgentTestFixture.correlation("approval")]?.state, .expired)
        XCTAssertEqual(session.state, .idle)
    }

    func testPendingOperationNamespacesPreventCorrelationCollision() throws {
        let id = AgentTestFixture.sessionID(.codex, "pending-namespaces")
        var session = try startedSession(id)
        session = try apply(.init(
            name: "early-tool",
            id: id,
            type: .toolCompleted,
            offset: 3,
            correlation: "shared",
            payload: .tool(AgentToolEvent(name: nil, category: nil, summary: nil, success: true))
        ), to: session)
        session = try apply(.init(
            name: "early-command",
            id: id,
            type: .commandCompleted,
            offset: 4,
            correlation: "shared",
            payload: .command(AgentCommandEvent(executable: nil, success: false, exitCode: 1))
        ), to: session)
        XCTAssertEqual(session.pendingOperations.count, 2)

        session = try apply(.init(
            name: "tool-start",
            id: id,
            type: .toolStarted,
            offset: 1,
            correlation: "shared",
            payload: .tool(AgentToolEvent(name: "Read", category: nil, summary: nil, success: nil))
        ), to: session)
        session = try apply(.init(
            name: "command-start",
            id: id,
            type: .commandStarted,
            offset: 2,
            correlation: "shared",
            payload: .command(AgentCommandEvent(executable: "swift", success: nil, exitCode: nil))
        ), to: session)

        XCTAssertEqual(session.tools[AgentTestFixture.correlation("shared")]?.status, .completed)
        XCTAssertEqual(session.commands[AgentTestFixture.correlation("shared")]?.status, .failed)
        XCTAssertTrue(session.pendingOperations.isEmpty)
    }

    func testUsageAfterTerminalEnrichesWithoutChangingTerminalState() throws {
        let id = AgentTestFixture.sessionID(.codex, "usage-terminal")
        var session = try startedSession(id)
        session = try apply(terminalEvent("complete", id: id, type: .taskCompleted, offset: 1), to: session)
        let sample = AgentUsageSample(
            value: 42,
            limit: nil,
            unit: .tokens,
            scope: "turn",
            source: "protocol",
            observedAt: AgentTestFixture.baseDate.addingTimeInterval(2)
        )
        session = try apply(AgentTestFixture.event(
            "usage",
            sessionID: id,
            type: .usageUpdated,
            offset: 2,
            payload: .usage(AgentUsage(samples: [.inputTokens: sample]))
        ), to: session)

        XCTAssertEqual(session.state, .completed)
        XCTAssertEqual(session.usage[.inputTokens]?.value, 42)
    }

    func testCapabilitySnapshotSupportsRemoval() throws {
        let id = AgentTestFixture.sessionID(.codex, "capabilities")
        var session = try startedSession(id)
        session = try apply(capabilityEvent(
            "caps-1",
            id: id,
            values: [.toolLifecycle, .approvalControl],
            offset: 1
        ), to: session)
        XCTAssertTrue(session.capabilities.contains(.approvalControl))

        session = try apply(capabilityEvent(
            "caps-2",
            id: id,
            values: [.toolLifecycle],
            offset: 2
        ), to: session)
        XCTAssertFalse(session.capabilities.contains(.approvalControl))
        XCTAssertTrue(session.capabilities.contains(.toolLifecycle))
    }

    func testFutureProviderTimestampIsClampedToReceivedTime() throws {
        let id = AgentTestFixture.sessionID(.codex, "clock-skew")
        let session = try startedSession(id)
        let event = AgentTestFixture.event(
            "skewed",
            sessionID: id,
            type: .agentWorking,
            offset: 10,
            providerOffset: 10_000,
            payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil))
        )

        let result = AgentEventReducer.reduce(session: session, event: event)

        XCTAssertEqual(result.session?.recentActivity.last?.timestamp, AgentTestFixture.baseDate.addingTimeInterval(10))
    }

    func testBackwardProviderClockDoesNotRegressSessionReceiveOrdering() throws {
        let id = AgentTestFixture.sessionID(.codex, "backward-clock")
        var session = try startedSession(id)
        session = try apply(AgentTestFixture.event(
            "newer-receive",
            sessionID: id,
            type: .agentWorking,
            offset: 10,
            providerOffset: -100,
            payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil))
        ), to: session)

        XCTAssertEqual(session.lastUpdatedAt, AgentTestFixture.baseDate.addingTimeInterval(10))
        XCTAssertEqual(session.recentActivity.last?.timestamp, AgentTestFixture.baseDate.addingTimeInterval(-100))
    }

    func testRepeatedSubagentIdentifiersDoNotDuplicateState() throws {
        let id = AgentTestFixture.sessionID(.claude, "subagent")
        var session = try startedSession(id)
        let start = AgentTestFixture.event(
            "sub-start",
            sessionID: id,
            type: .subagentStarted,
            offset: 1,
            correlationID: "sub",
            payload: .subagent(AgentSubagentEvent(nativeID: "child", displayName: "Worker"))
        )
        session = try apply(start, to: session)
        let secondStart = AgentTestFixture.event(
            "sub-start-2",
            sessionID: id,
            type: .subagentStarted,
            offset: 2,
            correlationID: "sub-duplicate-native",
            payload: .subagent(AgentSubagentEvent(nativeID: "child", displayName: "Worker"))
        )
        session = try apply(secondStart, to: session)
        XCTAssertEqual(session.subagents.count, 1)
    }

    func testMalformedNormalizedPayloadFailsWithoutSessionMutation() throws {
        let id = AgentTestFixture.sessionID(.codex, "malformed")
        let session = try startedSession(id)
        let malformed = AgentTestFixture.event(
            "malformed-event",
            sessionID: id,
            type: .toolStarted,
            offset: 1,
            correlationID: "tool",
            payload: .plan(AgentPlanEvent(summary: "wrong payload"))
        )

        let result = AgentEventReducer.reduce(session: session, event: malformed)

        XCTAssertEqual(result.application, .rejected(.validation(.payloadMismatch)))
        XCTAssertEqual(result.session, session)
    }

    func testExplicitResumeMayLeaveTerminalState() throws {
        let id = AgentTestFixture.sessionID(.codex, "resume")
        var session = try startedSession(id)
        session = try apply(terminalEvent("complete", id: id, type: .taskCompleted, offset: 1), to: session)
        session = try apply(AgentTestFixture.event(
            "resume",
            sessionID: id,
            type: .sessionResumed,
            offset: 2,
            payload: .none
        ), to: session)

        XCTAssertEqual(session.state, .working)
        XCTAssertNil(session.endedAt)
    }

    func testWeakerResumeCannotResurrectStrongerTerminalEvidence() throws {
        let id = AgentTestFixture.sessionID(.codex, "weak-resume")
        var session = try startedSession(id)
        session = try apply(terminalEvent("complete", id: id, type: .taskCompleted, offset: 1), to: session)
        let resume = AgentTestFixture.event(
            "weak-resume-event",
            sessionID: id,
            type: .sessionResumed,
            offset: 2,
            authority: .structuredTelemetry
        )

        let result = AgentEventReducer.reduce(session: session, event: resume)

        XCTAssertEqual(result.application, .ignoredWeakerEvidence)
        XCTAssertEqual(result.session?.state, .completed)
    }

    private func startedSession(_ id: AgentSessionID) throws -> AgentSession {
        let event = AgentTestFixture.event(
            "start-\(id.provider.stableName)-\(id.nativeID)",
            sessionID: id,
            type: .sessionStarted,
            offset: 0,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil))
        )
        return try XCTUnwrap(AgentEventReducer.reduce(session: nil, event: event).session)
    }

    private func apply(_ event: AgentEvent, to session: AgentSession) throws -> AgentSession {
        let result = AgentEventReducer.reduce(session: session, event: event)
        XCTAssertEqual(result.application, .applied)
        return try XCTUnwrap(result.session)
    }

    private func approvalRequest(id: AgentSessionID, offset: TimeInterval) -> AgentEvent {
        AgentTestFixture.event(
            "approval-request-\(offset)",
            sessionID: id,
            type: .approvalRequested,
            offset: offset,
            correlationID: "approval",
            payload: .approvalRequest(AgentApprovalRequest(
                summary: "Approve operation",
                operationCorrelationID: nil,
                expiresAt: nil
            ))
        )
    }

    private func approvalResolution(id: AgentSessionID, offset: TimeInterval) -> AgentEvent {
        AgentTestFixture.event(
            "approval-resolution-\(offset)",
            sessionID: id,
            type: .approvalResolved,
            offset: offset,
            correlationID: "approval",
            payload: .approvalResolution(AgentApprovalResolution(state: .approved))
        )
    }

    private func terminalEvent(
        _ name: String,
        id: AgentSessionID,
        type: AgentEventType,
        offset: TimeInterval
    ) -> AgentEvent {
        AgentTestFixture.event(
            name,
            sessionID: id,
            type: type,
            offset: offset,
            payload: .terminal(AgentTerminalEvent(summary: name))
        )
    }

    private func capabilityEvent(
        _ name: String,
        id: AgentSessionID,
        values: Set<AgentCapability>,
        offset: TimeInterval
    ) -> AgentEvent {
        AgentTestFixture.event(
            name,
            sessionID: id,
            type: .capabilitiesUpdated,
            offset: offset,
            payload: .capabilities(AgentTestFixture.capabilities(values))
        )
    }
}

private extension AgentEvent {
    init(
        name: String,
        id: AgentSessionID,
        type: AgentEventType,
        offset: TimeInterval,
        correlation: String? = nil,
        payload: AgentEventPayload = .none
    ) {
        self = AgentTestFixture.event(
            name,
            sessionID: id,
            type: type,
            offset: offset,
            correlationID: correlation,
            payload: payload
        )
    }
}
