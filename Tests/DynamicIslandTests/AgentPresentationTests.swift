import XCTest
@testable import DynamicIsland

final class AgentPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_200_000_000)

    func testZeroSessionsAndDisabledActivityHaveNoCompactPresentation() {
        XCTAssertNil(AgentCompactPresentation.make(sessions: []))
        XCTAssertNil(AgentCompactPresentation.make(sessions: [session()], enabled: false))
        XCTAssertNil(AgentCompactPresentation.make(sessions: [session(state: .completed)]))
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
        XCTAssertEqual(presentation.sessions.map(\.state), [.waitingForApproval, .runningCommand, .thinking])
        XCTAssertEqual(presentation.overflowCount, 1)
        XCTAssertEqual(presentation.summary, "1 waiting · 1 working")
    }

    func testRoutineCompactPresentationExcludesTerminalHistory() throws {
        let active = session(provider: .codex, nativeID: "active", state: .working)
        let completed = session(provider: .codex, nativeID: "completed", state: .completed)
        let failed = session(provider: .claude, nativeID: "failed", state: .failed)

        let presentation = try XCTUnwrap(
            AgentCompactPresentation.make(sessions: [completed, failed, active])
        )

        XCTAssertEqual(presentation.sessions.map { $0.id.sessionID.nativeID }, ["active"])
        XCTAssertEqual(presentation.overflowCount, 0)
        XCTAssertEqual(presentation.summary, "Codex working")
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

    func testProjectGroupingUsesSourcedMetadataAndNeutralFallbacks() {
        var storefrontOne = session(provider: .codex, nativeID: "one", projectName: "storefront")
        storefrontOne.project.repositoryIdentity = "makeit/storefront"
        var storefrontTwo = session(provider: .claude, nativeID: "two", projectName: "storefront")
        storefrontTwo.project.repositoryIdentity = "makeit/storefront"
        var unknown = session(provider: .claude, nativeID: "unknown", projectName: "")
        unknown.project.displayName = nil
        unknown.project.repositoryIdentity = nil

        let dashboard = AgentDashboardPresentation.make(sessions: [unknown, storefrontTwo, storefrontOne])

        XCTAssertEqual(dashboard.groups.count, 2)
        XCTAssertEqual(dashboard.groups.first?.title, "storefront")
        XCTAssertEqual(dashboard.groups.first?.sessions.count, 2)
        XCTAssertEqual(dashboard.groups.last?.title, "Claude sessions")
    }

    func testAttentionRowSelectionIsLimitedToActionableOrFailureStates() {
        XCTAssertTrue(AgentSessionPresentation.requiresAttention(session(state: .waitingForApproval)))
        XCTAssertTrue(AgentSessionPresentation.requiresAttention(session(state: .waitingForUser)))
        XCTAssertTrue(AgentSessionPresentation.requiresAttention(session(state: .failed)))
        XCTAssertTrue(AgentSessionPresentation.requiresAttention(session(state: .interrupted)))
        XCTAssertTrue(AgentSessionPresentation.requiresAttention(session(state: .planReady)))
        XCTAssertFalse(AgentSessionPresentation.requiresAttention(session(state: .working)))
        XCTAssertFalse(AgentSessionPresentation.requiresAttention(session(state: .completed)))
    }

    func testRepeatedOperationsAggregateWithoutChangingUnderlyingEvents() throws {
        var value = session(state: .runningTool)
        for index in 0..<3 {
            let correlation = AgentCorrelationID(rawValue: "bash-\(index)")
            value.tools[correlation] = AgentTool(
                correlationID: correlation,
                name: "bash",
                category: "shell",
                summary: nil,
                status: .completed,
                startedAt: now.addingTimeInterval(Double(index)),
                completedAt: now.addingTimeInterval(Double(index) + 0.5),
                success: true
            )
        }

        let operation = try XCTUnwrap(AgentOperationAggregation.make(for: value).first)
        XCTAssertEqual(operation.title, "Run command")
        XCTAssertEqual(operation.displayTitle, "Run command ×3")
        XCTAssertEqual(operation.count, 3)
        XCTAssertEqual(value.tools.count, 3)
    }

    func testActiveOperationsStayExplicitAndHistoryIsBounded() {
        var value = session(state: .runningTool)
        for index in 0..<8 {
            let correlation = AgentCorrelationID(rawValue: "read-\(index)")
            value.tools[correlation] = AgentTool(
                correlationID: correlation,
                name: "Read",
                category: "filesystem",
                summary: "File\(index).swift",
                status: index >= 6 ? .active : .completed,
                startedAt: now.addingTimeInterval(Double(index)),
                completedAt: index >= 6 ? nil : now.addingTimeInterval(Double(index) + 0.5),
                success: index >= 6 ? nil : true
            )
        }

        let entries = AgentOperationAggregation.make(for: value, limit: 4)
        XCTAssertLessThanOrEqual(entries.count, 4)
        XCTAssertEqual(entries.filter { $0.status == .active }.count, 2)
        XCTAssertEqual(entries.first { $0.status == .completed }?.displayTitle, "Read file ×6")
    }

    func testActivityStagesUseTypedEventsWithoutReasoningOrRawOutput() {
        var value = session(state: .planning)
        value.recentActivity = [
            AgentActivity(
                id: AgentEventID(rawValue: "plan"), kind: .plan,
                title: "private chain of thought", summary: "raw terminal output",
                status: .active, correlationID: nil, timestamp: now
            )
        ]

        let entry = AgentOperationAggregation.make(for: value).first
        XCTAssertEqual(entry?.title, "Planning")
        XCTAssertNil(entry?.detail)
        XCTAssertFalse(entry?.displayTitle.contains("private") ?? true)
        XCTAssertFalse(entry?.displayTitle.contains("raw") ?? true)
    }

    func testSafeActivityDetailRejectsSecretLookingValues() {
        var value = session(state: .runningTool)
        let correlation = AgentCorrelationID(rawValue: "secret")
        value.tools[correlation] = AgentTool(
            correlationID: correlation, name: "Read", category: "filesystem",
            summary: "Authorization: Bearer abc", status: .active,
            startedAt: now, completedAt: nil, success: nil
        )
        XCTAssertNil(AgentOperationAggregation.make(for: value).first?.detail)
    }

    func testAttentionPrimaryTitleAvoidsRepeatingApprovalActivity() {
        var value = session(state: .waitingForApproval, projectName: "DynamicIsland")
        value.recentActivity = [
            AgentActivity(
                id: AgentEventID(rawValue: "approval-event"),
                kind: .approval,
                title: "Bash approval required",
                summary: "Bash approval required",
                status: .pending,
                correlationID: AgentCorrelationID(rawValue: "approval"),
                timestamp: now
            )
        ]

        XCTAssertEqual(AgentSessionPresentation.primaryTitle(for: value), "DynamicIsland")
    }

    func testAttentionOperationListCanSuppressRedundantPendingApproval() {
        var value = session(state: .waitingForApproval)
        let request = AgentCorrelationID(rawValue: "approval")
        value.approvals[request] = AgentApproval(
            requestID: request,
            summary: "Bash approval required",
            operationCorrelationID: nil,
            requestedAt: now,
            resolvedAt: nil,
            expiresAt: nil,
            state: .pending
        )

        XCTAssertEqual(AgentOperationAggregation.make(for: value).first?.title, "Approval requested")
        XCTAssertTrue(
            AgentOperationAggregation.make(
                for: value,
                includePendingApprovals: false
            ).isEmpty
        )
    }

    func testAttentionPrimaryTitlePreservesDistinctStructuredTaskTitle() {
        var value = session(state: .waitingForApproval, projectName: "storefront")
        let request = AgentCorrelationID(rawValue: "approval-task")
        value.approvals[request] = AgentApproval(
            requestID: request,
            summary: "Apply the checkout schema migration",
            operationCorrelationID: request,
            requestedAt: now,
            resolvedAt: nil,
            expiresAt: nil,
            state: .pending
        )
        value.recentActivity = [
            AgentActivity(
                id: AgentEventID(rawValue: "approval-task-event"),
                kind: .approval,
                title: "Improve the checkout flow",
                summary: "Apply the checkout schema migration",
                status: .pending,
                correlationID: request,
                timestamp: now
            )
        ]

        XCTAssertEqual(
            AgentSessionPresentation.primaryTitle(for: value),
            "Improve the checkout flow"
        )
    }

    func testNarrowLayoutDropsLowerPriorityMetadataBeforeCoreState() {
        let narrow = AgentDashboardLayoutProjection.make(width: 500)
        let wide = AgentDashboardLayoutProjection.make(width: 800)

        XCTAssertTrue(narrow.isNarrow)
        XCTAssertFalse(narrow.showsModel)
        XCTAssertEqual(narrow.maximumGaugeCount, 2)
        XCTAssertFalse(wide.isNarrow)
        XCTAssertTrue(wide.showsModel)
        XCTAssertEqual(wide.maximumGaugeCount, 5)
        XCTAssertLessThan(narrow.trailingColumnWidth, wide.trailingColumnWidth)
    }

    func testGlobalUsageKeepsOnlySourcedMetricsAndHonorsLimit() {
        let unsupported = session(
            nativeID: "unsupported",
            capabilities: [],
            usage: AgentUsage(samples: [.contextUsed: usageSample(value: 20, limit: 100)])
        )
        let supported = session(
            nativeID: "supported",
            capabilities: [.contextUsage],
            usage: AgentUsage(samples: [.contextUsed: usageSample(value: 40, limit: 100)])
        )

        let metrics = AgentGlobalUsagePresentation.make(sessions: [unsupported, supported], limit: 1)
        XCTAssertEqual(metrics.count, 1)
        XCTAssertEqual(metrics.first?.metric.progress, 0.4)
    }

    func testGlobalUsageChoosesFreshestSourcedMetricPerProvider() throws {
        let stalePrioritySession = session(
            nativeID: "waiting",
            state: .waitingForApproval,
            capabilities: [.contextUsage],
            usage: AgentUsage(samples: [
                .contextUsed: usageSample(value: 20, limit: 100, observedAt: now)
            ])
        )
        let freshSession = session(
            nativeID: "working",
            state: .working,
            capabilities: [.contextUsage],
            usage: AgentUsage(samples: [
                .contextUsed: usageSample(
                    value: 70,
                    limit: 100,
                    observedAt: now.addingTimeInterval(30)
                )
            ])
        )

        let metric = try XCTUnwrap(
            AgentGlobalUsagePresentation.make(
                sessions: [stalePrioritySession, freshSession],
                limit: 1
            ).first?.metric
        )
        XCTAssertEqual(metric.progress, 0.7)
        XCTAssertEqual(metric.sample.observedAt, now.addingTimeInterval(30))
    }

    func testFiveHourAndWeeklyQuotaScopesCoexistAndKeepFreshestPerScope() {
        var usage = AgentUsage(samples: [
            .quotaUsed: usageSample(value: 20, limit: 100, observedAt: now, scope: "5h")
        ])
        usage.merge(AgentUsage(samples: [
            .quotaUsed: usageSample(value: 50, limit: 100, observedAt: now, scope: "weekly")
        ]))
        usage.merge(AgentUsage(samples: [
            .quotaUsed: usageSample(value: 10, limit: 100, observedAt: now.addingTimeInterval(-10), scope: "5h")
        ]))
        let value = session(capabilities: [.quotaUsage], usage: usage)
        let metrics = AgentUsagePresentation.make(for: value).filter { $0.id.hasPrefix("quota:") }

        XCTAssertEqual(Set(metrics.map(\.label)), ["Quota · 5h", "Quota · Week"])
        XCTAssertEqual(metrics.first { $0.label == "Quota · 5h" }?.sample.value, 20)
        XCTAssertEqual(metrics.first { $0.label == "Quota · Week" }?.sample.value, 50)
    }

    func testActiveSessionPresentationBecomesStaleWithoutChangingLifecycleTruth() {
        var value = session(nativeID: "stale", state: .working)
        value.lastUpdatedAt = now.addingTimeInterval(
            -(AgentSessionPresentation.activeSignalFreshnessInterval + 1)
        )

        XCTAssertTrue(AgentSessionPresentation.hasStaleActiveSignal(value, at: now))
        XCTAssertEqual(
            AgentSessionPresentation.displayedStateLabel(for: value, at: now),
            "Awaiting update"
        )
        XCTAssertEqual(
            AgentSessionPresentation.displayedPrimaryTitle(for: value, at: now),
            "Awaiting provider update"
        )
        XCTAssertEqual(value.state, .working)
        XCTAssertTrue(value.isActive)
    }

    func testFreshActiveSessionKeepsAuthoritativeWorkingPresentation() {
        var value = session(nativeID: "fresh", state: .working)
        value.lastUpdatedAt = now

        XCTAssertFalse(AgentSessionPresentation.hasStaleActiveSignal(value, at: now))
        XCTAssertEqual(
            AgentSessionPresentation.displayedStateLabel(for: value, at: now),
            "Working"
        )
    }

    func testWorkspaceSelectionKeepsExistingSessionAndFallsBackByPriority() throws {
        let working = session(nativeID: "working", state: .working)
        let approval = session(nativeID: "approval", state: .waitingForApproval)
        let completed = session(nativeID: "completed", state: .completed)

        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: working.id, sessions: [approval, working, completed]),
            working.id
        )

        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: nil, sessions: [completed, working, approval]),
            approval.id
        )

        XCTAssertNil(AgentWorkspaceSelection.resolve(current: approval.id, sessions: []))
    }

    func testWorkspaceSelectionUsesRequiredFallbackPriority() {
        let sessions = [
            session(nativeID: "completed", state: .completed),
            session(nativeID: "idle", state: .idle),
            session(nativeID: "plan", state: .planReady),
            session(nativeID: "thinking", state: .thinking),
            session(nativeID: "working", state: .runningTool),
            session(nativeID: "failed", state: .failed),
            session(nativeID: "approval", state: .waitingForApproval)
        ]

        XCTAssertEqual(
            sessions.sorted(by: AgentSessionPresentation.isOrderedBefore).map(\.id.sessionID.nativeID),
            ["approval", "failed", "working", "plan", "thinking", "idle", "completed"]
        )
        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: nil, sessions: sessions)?.sessionID.nativeID,
            "approval"
        )
    }

    func testWorkspaceSelectionSurvivesUnrelatedArrivalAndSelectedStateUpdate() {
        let selected = session(nativeID: "selected", state: .idle)
        let unrelated = session(nativeID: "urgent", state: .waitingForApproval)
        let updated = session(nativeID: "selected", state: .runningCommand)

        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: selected.id, sessions: [selected, unrelated]),
            selected.id
        )
        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: selected.id, sessions: [updated, unrelated]),
            selected.id
        )
    }

    func testWorkspaceSelectionRemovalAndGenerationReplacementChooseExactFallback() {
        let selected = session(nativeID: "same", generation: 1, state: .working)
        let replacement = session(nativeID: "same", generation: 2, state: .working)
        let fallback = session(provider: .claude, nativeID: "fallback", state: .thinking)

        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: selected.id, sessions: [replacement, fallback]),
            replacement.id
        )
        XCTAssertNotEqual(replacement.id, selected.id)
        XCTAssertEqual(
            AgentWorkspaceSelection.session(current: selected.id, sessions: [replacement, fallback])?.id,
            replacement.id
        )
    }

    func testWorkspaceSelectionKeepsProviderNamespaceDistinctForSameNativeID() {
        let codex = session(provider: .codex, nativeID: "shared", state: .working)
        let claude = session(provider: .claude, nativeID: "shared", state: .working)

        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: claude.id, sessions: [codex, claude]),
            claude.id
        )
        XCTAssertNotEqual(codex.id, claude.id)
    }

    func testSelectedTerminalSessionRemainsInspectableUntilRetentionRemovesIt() {
        let completed = session(nativeID: "completed", state: .completed)
        let active = session(nativeID: "active", state: .working)

        XCTAssertEqual(
            AgentWorkspaceSelection.session(current: completed.id, sessions: [active, completed])?.id,
            completed.id
        )
        XCTAssertEqual(
            AgentWorkspaceSelection.session(current: completed.id, sessions: [active])?.id,
            active.id
        )
    }

    func testProjectPresentationSeparatesPrimaryAndRecentWithoutChangingCounts() throws {
        let approval = session(nativeID: "approval", state: .waitingForApproval, projectName: "App")
        let active = session(nativeID: "active", state: .working, projectName: "App")
        let interrupted = session(nativeID: "interrupted", state: .interrupted, projectName: "App")
        let completed = session(nativeID: "completed", state: .completed, projectName: "App")
        let group = try XCTUnwrap(
            AgentDashboardPresentation.make(sessions: [completed, active, interrupted, approval]).groups.first
        )

        XCTAssertEqual(group.sessions.count, 4)
        XCTAssertEqual(
            group.primarySessions.map(\.id.sessionID.nativeID),
            ["approval", "interrupted", "active"]
        )
        XCTAssertEqual(group.recentSessions.map(\.id.sessionID.nativeID), ["completed"])
        XCTAssertTrue(group.showsRecentSection)

        let activeOnly = try XCTUnwrap(
            AgentDashboardPresentation.make(sessions: [active]).groups.first
        )
        XCTAssertFalse(activeOnly.showsRecentSection)
    }

    func testSelectedAttentionEmphasisOutranksSelectionAndHover() {
        let attention = session(state: .waitingForApproval)
        let ordinary = session(state: .working)

        XCTAssertEqual(
            AgentSessionRowEmphasis.resolve(session: attention, selected: true, hovering: true),
            .selectedAttention
        )
        XCTAssertEqual(
            AgentSessionRowEmphasis.resolve(session: attention, selected: false, hovering: true),
            .attention
        )
        XCTAssertEqual(
            AgentSessionRowEmphasis.resolve(session: ordinary, selected: true, hovering: true),
            .selected
        )
    }

    func testWorkspaceVerticalLayoutKeepsObservedDetailBounded() {
        let compact = AgentWorkspaceVerticalLayoutProjection.make(availableHeight: 220)
        let regular = AgentWorkspaceVerticalLayoutProjection.make(availableHeight: 270)
        let large = AgentWorkspaceVerticalLayoutProjection.make(availableHeight: 320)

        XCTAssertEqual(compact.sessionWorkspaceMinimumHeight, 96)
        XCTAssertEqual(compact.selectedDetailHeight, 68)
        XCTAssertEqual(compact.selectedDetailActivityLimit, 2)
        XCTAssertEqual(regular.sessionWorkspaceMinimumHeight, 118)
        XCTAssertEqual(regular.selectedDetailHeight, 80)
        XCTAssertEqual(regular.selectedDetailActivityLimit, 3)
        XCTAssertEqual(large.sessionWorkspaceMinimumHeight, 142)
        XCTAssertEqual(large.selectedDetailHeight, 94)
        XCTAssertEqual(large.selectedDetailActivityLimit, 4)
    }

    func testScreenshotFixtureUsesSyntheticScopedUsageWithoutControlAuthority() throws {
        let sessions = AgentDashboardPreviewFactory.sessions(now: now)
        XCTAssertEqual(sessions.count, 3)

        let approval = try XCTUnwrap(
            sessions.first { $0.state == .waitingForApproval }
        )
        XCTAssertFalse(approval.capabilities.contains(.approvalControl))
        XCTAssertFalse(approval.capabilities.contains(.verifiedSourceIdentity))
        XCTAssertFalse(approval.capabilities.contains(.sourceAppOpen))

        let metrics = AgentGlobalUsagePresentation.make(sessions: sessions, limit: 5)
        XCTAssertTrue(metrics.contains { $0.metric.label == "Quota · 5h" })
        XCTAssertTrue(metrics.contains { $0.metric.label == "Quota · Week" })
        XCTAssertTrue(metrics.contains { $0.metric.label == "Context" })
    }

    func testApprovalControlsRequireExactPendingControlEvidence() {
        var value = session(provider: .codex, state: .waitingForApproval, capabilities: [.approvalObservation])
        let request = AgentApprovalControlRequest(
            key: AgentApprovalControlKey(session: value.id, requestID: AgentCorrelationID(rawValue: "request")),
            summary: "Run migration", expiresAt: now.addingTimeInterval(30)
        )
        XCTAssertFalse(AgentApprovalPresentation.isActionable(session: value, pending: request))
        value.capabilities = AgentCapabilities(evidence: [
            .approvalControl: AgentCapabilityEvidence(authority: .lifecycle, source: "official-hook", observedAt: now)
        ])
        XCTAssertTrue(AgentApprovalPresentation.isActionable(session: value, pending: request))

        let claude = session(provider: .claude, state: .waitingForApproval, capabilities: [.approvalControl])
        XCTAssertFalse(AgentApprovalPresentation.isActionable(session: claude, pending: request))
    }

    private func session(
        provider: AgentProvider = .codex,
        nativeID: String = "session",
        generation: UInt64 = 1,
        state: AgentState = .working,
        projectName: String = "DynamicIsland",
        model: String? = "model",
        capabilities: Set<AgentCapability> = [],
        usage: AgentUsage = AgentUsage()
    ) -> AgentSession {
        AgentSession(
            id: AgentSessionInstanceID(
                sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
                generation: AgentSessionGeneration(rawValue: generation)
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
        observedAt: Date? = nil,
        scope: String = "session"
    ) -> AgentUsageSample {
        AgentUsageSample(
            value: value,
            limit: limit,
            unit: .tokens,
            scope: scope,
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
