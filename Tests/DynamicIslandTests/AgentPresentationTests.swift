import XCTest
@testable import DynamicIsland

final class AgentPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_200_000_000)

    func testZeroSessionsAndDisabledActivityHaveNoCompactPresentation() {
        XCTAssertNil(AgentCompactPresentation.make(sessions: []))
        XCTAssertNil(AgentCompactPresentation.make(sessions: [session()], enabled: false))
    }

    func testSingleProviderSummaryUsesSemanticState() {
        XCTAssertEqual(
            AgentCompactPresentation.make(sessions: [session(provider: .codex, state: .working)])?.summary,
            "Codex working"
        )
        XCTAssertEqual(
            AgentCompactPresentation.make(sessions: [session(provider: .claude, state: .thinking)])?.summary,
            "Claude thinking"
        )
    }

    func testMultipleSessionsUseRequiredPriorityAndBoundedOverflow() {
        let sessions = [
            session(provider: .codex, nativeID: "idle", state: .idle),
            session(provider: .claude, nativeID: "thinking", state: .thinking),
            session(provider: .codex, nativeID: "working", state: .runningCommand),
            session(provider: .claude, nativeID: "failed", state: .failed),
            session(provider: .codex, nativeID: "approval", state: .waitingForApproval)
        ]
        let presentation = try! XCTUnwrap(AgentCompactPresentation.make(sessions: sessions))
        XCTAssertEqual(presentation.sessions.map(\.state), [.waitingForApproval, .failed, .runningCommand])
        XCTAssertEqual(presentation.overflowCount, 2)
        XCTAssertEqual(presentation.summary, "1 waiting · 1 failed")
    }

    func testStableTieBreakUsesProviderThenIdentity() {
        let sessions = [
            session(provider: .claude, nativeID: "b", state: .working),
            session(provider: .codex, nativeID: "z", state: .working),
            session(provider: .codex, nativeID: "a", state: .working)
        ]
        let ordered = sessions.sorted(by: AgentSessionPresentation.isOrderedBefore)
        XCTAssertEqual(ordered.map { $0.id.sessionID.nativeID }, ["a", "z", "b"])
    }

    func testSemanticLabelsCoverAttentionAndTerminalStates() {
        XCTAssertEqual(AgentSessionPresentation.stateLabel(.waitingForUser), "Waiting for input")
        XCTAssertEqual(AgentSessionPresentation.stateLabel(.waitingForApproval), "Approval requested")
        XCTAssertEqual(AgentSessionPresentation.stateLabel(.failed), "Failed")
        XCTAssertEqual(AgentSessionPresentation.stateLabel(.completed), "Completed")
        XCTAssertEqual(AgentSessionPresentation.stateLabel(.interrupted), "Interrupted")
    }

    func testUnsupportedUsageIsHiddenEvenWhenSamplesExist() {
        let sample = usageSample(value: 10, limit: 100)
        let value = session(
            capabilities: [],
            usage: AgentUsage(samples: [.contextUsed: sample])
        )
        XCTAssertTrue(AgentUsagePresentation.make(for: value).isEmpty)
    }

    func testSupportedUsageUsesSourcedLimitOnly() throws {
        let withLimit = session(
            capabilities: [.contextUsage],
            usage: AgentUsage(samples: [
                .contextUsed: usageSample(value: 50, limit: nil),
                .contextLimit: usageSample(value: 100, limit: nil)
            ])
        )
        let metric = try XCTUnwrap(AgentUsagePresentation.make(for: withLimit).first)
        XCTAssertEqual(metric.progress, 0.5)

        let withoutLimit = session(
            capabilities: [.contextUsage],
            usage: AgentUsage(samples: [.contextUsed: usageSample(value: 50, limit: nil)])
        )
        XCTAssertNil(try XCTUnwrap(AgentUsagePresentation.make(for: withoutLimit).first).progress)
    }

    func testStaleUsageUsesObservationTimestamp() throws {
        let value = session(
            capabilities: [.tokenUsage],
            usage: AgentUsage(samples: [.inputTokens: usageSample(value: 42, limit: nil, observedAt: now)])
        )
        let metric = try XCTUnwrap(AgentUsagePresentation.make(for: value).first)
        XCTAssertFalse(metric.isStale(at: now.addingTimeInterval(300)))
        XCTAssertTrue(metric.isStale(at: now.addingTimeInterval(301)))
    }

    func testLongProjectAndModelValuesRemainAvailableToAdaptiveViews() {
        let project = String(repeating: "LongProject", count: 30)
        let model = String(repeating: "long-model-", count: 30)
        let value = session(projectName: project, model: model)
        XCTAssertEqual(value.project.displayName, project)
        XCTAssertEqual(value.project.model, model)
    }

    func testDiagnosticsDistinguishAwaitingActiveAndSchemaMismatch() {
        let awaiting = AgentIntegrationDiagnostics.make(
            provider: .codex,
            setup: .configured,
            active: [health(provider: .codex, state: .starting)],
            stopped: []
        )
        XCTAssertEqual(awaiting.state, .awaitingFirstEvent)

        let active = AgentIntegrationDiagnostics.make(
            provider: .codex,
            setup: .configured,
            active: [health(provider: .codex, state: .healthy, accepted: 7)],
            stopped: []
        )
        XCTAssertEqual(active.state, .active)
        XCTAssertEqual(active.acceptedCount, 7)

        let mismatch = AgentIntegrationDiagnostics.make(
            provider: .codex,
            setup: .configured,
            active: [health(provider: .codex, state: .degraded, accepted: 2, rejected: 1, dropped: 1, mismatches: 1, error: .schemaMismatch)],
            stopped: []
        )
        XCTAssertEqual(mismatch.state, .degraded)
        XCTAssertEqual(mismatch.schemaMismatchCount, 1)
        XCTAssertEqual(mismatch.lastError, .schemaMismatch)
    }

    func testDiagnosticsDoNotMixProviders() {
        let diagnostics = AgentIntegrationDiagnostics.make(
            provider: .claude,
            setup: .configured,
            active: [
                health(provider: .codex, state: .healthy, accepted: 9),
                health(provider: .claude, state: .healthy, accepted: 3)
            ],
            stopped: []
        )
        XCTAssertEqual(diagnostics.acceptedCount, 3)
    }

    private func session(
        provider: AgentProvider = .codex,
        nativeID: String = "session",
        state: AgentState = .working,
        projectName: String = "DynamicIsland",
        model: String? = "model",
        capabilities: Set<AgentCapability> = [],
        usage: AgentUsage = AgentUsage()
    ) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: 1)
            ),
            source: .terminal,
            state: state,
            project: AgentProjectContext(displayName: projectName, model: model),
            capabilities: AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: capabilities.map {
                ($0, AgentCapabilityEvidence(authority: .lifecycle, source: "test", observedAt: now))
            })),
            usage: usage,
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: now,
            endedAt: state.isTerminal ? now : nil,
            lastUpdatedAt: now
        )
    }

    private func usageSample(
        value: Double,
        limit: Double?,
        observedAt: Date? = nil
    ) -> AgentUsageSample {
        AgentUsageSample(
            value: value,
            limit: limit,
            unit: .tokens,
            scope: "session",
            source: "structured-test",
            observedAt: observedAt ?? now
        )
    }

    private func health(
        provider: AgentIntegrationProvider,
        state: AgentSourceHealthState,
        accepted: UInt64 = 0,
        rejected: UInt64 = 0,
        dropped: UInt64 = 0,
        mismatches: UInt64 = 0,
        error: AgentSourceHealthError? = nil
    ) -> AgentSourceHealthSnapshot {
        AgentSourceHealthSnapshot(
            sourceInstanceID: AgentSourceInstanceID(rawValue: "dynamic-island.\(provider.rawValue)-hook"),
            epoch: AgentProducerEpoch(rawValue: 1),
            sourceKind: .authenticatedBridge,
            state: state,
            lastAcceptedEventAt: accepted > 0 ? now : nil,
            acceptedCount: accepted,
            rejectedCount: rejected,
            dropCount: dropped,
            schemaMismatchCount: mismatches,
            lastError: error
        )
    }
}
