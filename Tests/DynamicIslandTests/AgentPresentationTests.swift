import XCTest
@testable import DynamicIsland

final class AgentPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_200_000_000)

    func testZeroSessionsAndDisabledActivityHaveNoCompactPresentation() {
        XCTAssertNil(AgentCompactPresentation.make(sessions: []))
        XCTAssertNil(AgentCompactPresentation.make(sessions: [session()], enabled: false))
        XCTAssertNil(AgentCompactPresentation.make(sessions: [session(state: .idle)]))
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
        XCTAssertEqual(presentation.overflowCount, 0)
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

    func testResolvedApprovalRemainsInOperationHistory() {
        var value = session(state: .idle)
        let request = AgentCorrelationID(rawValue: "resolved-approval")
        value.approvals[request] = AgentApproval(
            requestID: request,
            summary: "Command approval",
            operationCorrelationID: nil,
            requestedAt: now,
            resolvedAt: now.addingTimeInterval(1),
            expiresAt: nil,
            state: .approved
        )

        let operation = AgentOperationAggregation.make(
            for: value,
            includePendingApprovals: false
        ).first
        XCTAssertEqual(operation?.title, "Approved")
        XCTAssertEqual(operation?.status, .resolved)
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

    func testQuotaGaugeShowsRemainingWhileContextGaugeShowsUsed() {
        let fiveHour = AgentUsagePresentation(
            id: "quota:5h",
            label: "Quota · 5h",
            sample: usageSample(value: 18, limit: 100, observedAt: now, scope: "5h"),
            effectiveLimit: 100
        )
        let weekly = AgentUsagePresentation(
            id: "quota:weekly",
            label: "Quota · Week",
            sample: usageSample(value: 29, limit: 100, observedAt: now, scope: "weekly"),
            effectiveLimit: 100
        )
        let context = AgentUsagePresentation(
            id: "context",
            label: "Context",
            sample: usageSample(value: 19, limit: 100, observedAt: now, scope: "context"),
            effectiveLimit: 100
        )

        XCTAssertEqual(fiveHour.progress ?? -1, 0.18, accuracy: 0.0001)
        XCTAssertEqual(fiveHour.gaugeProgress ?? -1, 0.82, accuracy: 0.0001)
        XCTAssertEqual(fiveHour.gaugeValueText, "82% left")
        XCTAssertEqual(weekly.gaugeProgress ?? -1, 0.71, accuracy: 0.0001)
        XCTAssertEqual(weekly.gaugeValueText, "71% left")
        XCTAssertEqual(context.gaugeProgress ?? -1, 0.19, accuracy: 0.0001)
        XCTAssertEqual(context.gaugeValueText, "19%")
    }

    func testQuotaGaugeRemainingClampsAtBounds() {
        let over = AgentUsagePresentation(
            id: "quota:5h",
            label: "Quota · 5h",
            sample: usageSample(value: 140, limit: 100, observedAt: now, scope: "5h"),
            effectiveLimit: 100
        )
        let under = AgentUsagePresentation(
            id: "quota:weekly",
            label: "Quota · Week",
            sample: usageSample(value: -25, limit: 100, observedAt: now, scope: "weekly"),
            effectiveLimit: 100
        )
        XCTAssertEqual(over.gaugeProgress ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(under.gaugeProgress ?? -1, 1, accuracy: 0.0001)
    }

    func testProviderVisualIdentityDoesNotMislabelCodexAsTerminal() {
        XCTAssertEqual(AgentProviderVisualIdentity.resolve(.codex).accessibilityName, "Codex")
        XCTAssertNotEqual(AgentProviderVisualIdentity.resolve(.codex).systemSymbolName, "terminal")
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
            "DynamicIsland"
        )
        XCTAssertEqual(value.state, .working)
        XCTAssertTrue(value.isActive)
    }

    func testManagedSessionDoesNotUseObservationSilenceFallback() {
        var value = session(nativeID: "managed", state: .working)
        value.lastUpdatedAt = now.addingTimeInterval(-600)
        value.capabilities = AgentCapabilities(evidence: [
            .sessionLifecycle: AgentCapabilityEvidence(
                authority: .lifecycle,
                source: "codex-app-server-v2",
                observedAt: now.addingTimeInterval(-600)
            )
        ])

        XCTAssertFalse(AgentSessionPresentation.hasStaleActiveSignal(value, at: now))
        XCTAssertEqual(
            AgentSessionPresentation.displayedStateLabel(for: value, at: now),
            "Working"
        )
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

    func testWorkspaceSelectionPrefersLoadedIdleBeforeResumableAndRetained() {
        let loaded = session(nativeID: "loaded", state: .idle, availability: .loaded)
        let resumable = session(nativeID: "resumable", state: .idle, availability: .resumable)
        let retained = session(nativeID: "retained", state: .completed)

        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(
                current: nil,
                sessions: [retained, resumable, loaded]
            ),
            loaded.id
        )
        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(current: nil, sessions: [retained, resumable]),
            resumable.id
        )
    }

    func testWorkspaceSelectionPrioritizesExactManagedTurnBeforeObservedActive() {
        let managed = session(nativeID: "managed", state: .idle, availability: .loaded)
        let observed = session(nativeID: "observed", state: .working)
        let managedIDs: Set<AgentSessionID> = [managed.id.sessionID]

        XCTAssertEqual(
            AgentWorkspaceSelection.resolve(
                current: nil,
                sessions: [observed, managed],
                activeManagedSessionIDs: managedIDs
            ),
            managed.id
        )
        XCTAssertTrue(AgentWorkspaceSelection.isActive(
            managed,
            activeManagedSessionIDs: managedIDs
        ))
        XCTAssertTrue(AgentWorkspaceSelection.isActive(observed))
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

    func testProjectPresentationGroupsSameProjectWithoutCollapsingDistinctThreads() throws {
        let first = session(nativeID: "thread-a8f2", state: .working)
        let second = session(nativeID: "thread-b7e1", state: .idle, availability: .loaded)
        let third = session(nativeID: "thread-c6d0", state: .idle, availability: .resumable)

        let presentation = AgentDashboardPresentation.make(
            orderedSessions: AgentWorkspaceSelection.ordered(
                sessions: [third, second, first]
            )
        )
        let group = try XCTUnwrap(presentation.groups.first)

        XCTAssertEqual(presentation.groups.count, 1)
        XCTAssertEqual(group.title, "DynamicIsland")
        XCTAssertEqual(group.sessions.count, 3)
        XCTAssertEqual(
            Set(group.sessions.map(\.id.sessionID.nativeID)),
            ["thread-a8f2", "thread-b7e1", "thread-c6d0"]
        )
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

    func testSelectedSessionContextOverridesAccountContextWithoutChangingQuotas() {
        var account = AgentUsage(samples: [
            .quotaUsed: usageSample(value: 20, limit: 100, observedAt: now, scope: "5h"),
            .contextUsed: usageSample(value: 90, limit: 100, observedAt: now, scope: "context")
        ])
        account.merge(AgentUsage(samples: [
            .quotaUsed: usageSample(value: 40, limit: 100, observedAt: now, scope: "weekly")
        ]))

        var selectedUsage = AgentUsage(samples: [
            .contextUsed: usageSample(value: 25, limit: 100, observedAt: now, scope: "context")
        ])
        selectedUsage.merge(AgentUsage(samples: [
            .contextLimit: usageSample(value: 100, limit: nil, observedAt: now, scope: "context")
        ]))
        let selected = session(capabilities: [.contextUsage], usage: selectedUsage)

        let metrics = AgentGlobalUsagePresentation.makeForSelectedSession(
            provider: .codex,
            accountUsage: account,
            selectedSession: selected,
            limit: 3
        )

        XCTAssertEqual(metrics.map(\.metric.label), ["Quota · 5h", "Quota · Week", "Context"])
        XCTAssertEqual(metrics[0].metric.sample.value, 20)
        XCTAssertEqual(metrics[1].metric.sample.value, 40)
        XCTAssertEqual(metrics[2].metric.sample.value, 25)
    }

    func testNoSelectedSessionDoesNotBorrowAccountContext() {
        let account = AgentUsage(samples: [
            .contextUsed: usageSample(value: 55, limit: 100, observedAt: now, scope: "context")
        ])
        let metrics = AgentGlobalUsagePresentation.makeForSelectedSession(
            provider: .codex,
            accountUsage: account,
            selectedSession: nil,
            limit: 3
        )
        XCTAssertFalse(metrics.contains { $0.metric.id == "context" })
    }

    func testAccountUsageRendersCanonicalMetricsWithoutAnySession() {
        let accountUsage = AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "weekly"): AgentUsageSample(
                value: 16,
                limit: 100,
                unit: .fraction,
                scope: "weekly",
                source: "account-test",
                observedAt: now
            ),
            AgentUsageKey(metric: .contextUsed, scope: "context"): AgentUsageSample(
                value: 25_800,
                limit: 258_000,
                unit: .tokens,
                scope: "context",
                source: "account-test",
                observedAt: now
            ),
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: 100,
                limit: 100,
                unit: .fraction,
                scope: "5h",
                source: "account-test",
                observedAt: now
            )
        ])

        let metrics = AgentGlobalUsagePresentation.make(
            sessions: [],
            providerUsage: [.codex: accountUsage],
            limit: 5
        )

        XCTAssertEqual(metrics.map { $0.metric.label }, ["Quota · 5h", "Quota · Week", "Context"])
        XCTAssertEqual(metrics[0].metric.progress, 1)
        XCTAssertEqual(metrics[1].metric.progress, 0.16)
        XCTAssertEqual(metrics[2].metric.progress, 0.1)
    }

    func testCompletedTurnCanRemainAnActiveIdlePresentedSessionUntilSessionEnd() {
        var value = session(nativeID: "open-thread", state: .completed)
        value.endedAt = nil

        XCTAssertFalse(value.isActive)
        XCTAssertTrue(value.isOpen)
        XCTAssertEqual(AgentSessionPresentation.priority(for: value), .idle)
        XCTAssertEqual(AgentSessionPresentation.displayedStateLabel(for: value, at: now), "Idle")
        XCTAssertNil(AgentCompactPresentation.make(sessions: [value]))
    }

    func testResumableSessionIsLabeledTruthfullyWithoutCompactActivity() {
        var value = session(nativeID: "resumable", state: .idle)
        value.availability = .resumable

        XCTAssertEqual(
            AgentSessionPresentation.displayedStateLabel(for: value, at: now),
            "Resumable"
        )
        XCTAssertNil(AgentCompactPresentation.make(sessions: [value]))
    }


    func testRecentActivityProjectionMapsNormalizedEventsAndStaysBounded() {
        var value = session(state: .runningCommand)
        let readID = AgentCorrelationID(rawValue: "read")
        let commandID = AgentCorrelationID(rawValue: "command")
        value.tools[readID] = AgentTool(
            correlationID: readID,
            name: "read_file",
            category: "read",
            summary: "AgentConsoleViews.swift",
            status: .completed,
            startedAt: now.addingTimeInterval(-8),
            completedAt: now.addingTimeInterval(-7),
            success: true
        )
        value.commands[commandID] = AgentCommand(
            correlationID: commandID,
            displaySummary: "swift test",
            status: .active,
            startedAt: now.addingTimeInterval(-2),
            completedAt: nil,
            exitCode: nil,
            success: nil
        )
        value.recentActivity = [
            AgentActivity(
                id: AgentEventID(rawValue: "plan"),
                kind: .plan,
                title: "Plan",
                summary: nil,
                status: .completed,
                correlationID: nil,
                timestamp: now.addingTimeInterval(-6)
            ),
            AgentActivity(
                id: AgentEventID(rawValue: "failure"),
                kind: .failure,
                title: "Failure",
                summary: nil,
                status: .failed,
                correlationID: nil,
                timestamp: now.addingTimeInterval(-5)
            ),
            AgentActivity(
                id: AgentEventID(rawValue: "completion"),
                kind: .completion,
                title: "Completed",
                summary: nil,
                status: .completed,
                correlationID: nil,
                timestamp: now.addingTimeInterval(-4)
            )
        ]

        let items = AgentRecentActivityPresentation.make(for: value, limit: 3)

        XCTAssertEqual(items.count, 3)
        XCTAssertTrue(items.contains { $0.title == "Run tests" && $0.isCommand })
        XCTAssertTrue(items.contains { $0.title == "Failed" && $0.status == .failed })
        XCTAssertNotNil(AgentRecentActivityPresentation.active(for: value))
    }


    func testRecentActivityGroupsEquivalentActiveOperationsWithoutLosingTruth() {
        var value = session(state: .runningCommand)
        for index in 0..<3 {
            let id = AgentCorrelationID(rawValue: "bash-\(index)")
            value.tools[id] = AgentTool(
                correlationID: id,
                name: "bash",
                category: "shell",
                summary: nil,
                status: .active,
                startedAt: now.addingTimeInterval(Double(-index)),
                completedAt: nil,
                success: nil
            )
        }

        let items = AgentRecentActivityPresentation.make(for: value, limit: 4)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.title, "Run command ×3")
        XCTAssertEqual(items.first?.status, .active)
        XCTAssertEqual(value.tools.count, 3)
    }

    func testCompactSummaryUsesCurrentNormalizedOperationWhenAvailable() {
        var value = session(state: .runningCommand)
        let command = AgentCorrelationID(rawValue: "command")
        value.commands[command] = AgentCommand(
            correlationID: command,
            displaySummary: "swift test",
            status: .active,
            startedAt: now,
            completedAt: nil,
            exitCode: nil,
            success: nil
        )

        XCTAssertEqual(
            AgentCompactPresentation.make(sessions: [value])?.summary,
            "Codex · Run tests"
        )
    }

    func testContextPresentationUsesOnlySourcedLimitAndNeverFabricatesOne() throws {
        var withLimit = session(
            capabilities: [.contextUsage],
            usage: AgentUsage(scopedSamples: [
                AgentUsageKey(metric: .contextUsed, scope: "session"): AgentUsageSample(
                    value: 83_400,
                    limit: 200_000,
                    unit: .tokens,
                    scope: "session",
                    source: "provider",
                    observedAt: now
                )
            ])
        )
        let context = try XCTUnwrap(AgentContextPresentation.make(for: withLimit, now: now))
        XCTAssertEqual(try XCTUnwrap(context.progress), 0.417, accuracy: 0.0001)
        XCTAssertEqual(context.valueText, "83.4k / 200k")
        XCTAssertFalse(context.isStale)

        withLimit.usage = AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .contextUsed, scope: "session"): AgentUsageSample(
                value: 41_000,
                limit: nil,
                unit: .tokens,
                scope: "session",
                source: "provider",
                observedAt: now.addingTimeInterval(-400)
            )
        ])
        let noLimit = try XCTUnwrap(AgentContextPresentation.make(for: withLimit, now: now))
        XCTAssertNil(noLimit.limit)
        XCTAssertNil(noLimit.progress)
        XCTAssertEqual(noLimit.valueText, "41k")
        XCTAssertTrue(noLimit.isStale)
    }

    func testWorkspaceMetadataDistinguishesManagedObservedResumableAndUnavailable() {
        var loaded = session(nativeID: "loaded", state: .working)
        loaded.project.gitBranch = "feature/agents-ui"
        let managed = AgentWorkspaceMetadataPresentation.make(
            session: loaded,
            isManaged: true,
            canConnect: false
        )
        XCTAssertEqual(managed.ownership, .managed)
        XCTAssertEqual(managed.branch, "feature/agents-ui")
        XCTAssertEqual(managed.threadSuffix, "…aded")

        let observed = AgentWorkspaceMetadataPresentation.make(
            session: loaded,
            isManaged: false,
            canConnect: false
        )
        XCTAssertEqual(observed.ownership, .observed)

        var resumable = session(
            nativeID: "resume",
            state: .idle,
            availability: .resumable
        )
        resumable.endedAt = nil
        XCTAssertEqual(
            AgentWorkspaceMetadataPresentation.make(
                session: resumable,
                isManaged: false,
                canConnect: true
            ).ownership,
            .resumable
        )
        XCTAssertEqual(
            AgentWorkspaceMetadataPresentation.make(
                session: resumable,
                isManaged: false,
                canConnect: false
            ).ownership,
            .unavailable
        )
    }

    func testTurnTimingUsesActiveElapsedAndIdleRelativeUpdateSemantics() {
        XCTAssertEqual(
            AgentTurnTimingPresentation.elapsedText(
                startedAt: now.addingTimeInterval(-98),
                now: now
            ),
            "1m 38s"
        )
        XCTAssertNil(
            AgentTurnTimingPresentation.elapsedText(
                startedAt: nil,
                now: now
            )
        )
        XCTAssertEqual(
            AgentTurnTimingPresentation.relativeUpdateText(
                lastUpdatedAt: now.addingTimeInterval(-8 * 60),
                now: now
            ),
            "Updated 8m ago"
        )
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

        var claude = session(provider: .claude, state: .waitingForApproval, capabilities: [.approvalControl])
        let claudeRequest = AgentApprovalControlRequest(
            key: AgentApprovalControlKey(
                session: claude.id,
                requestID: AgentCorrelationID(rawValue: "claude-request")
            ),
            summary: "Claude approval",
            expiresAt: now.addingTimeInterval(30)
        )
        XCTAssertTrue(AgentApprovalPresentation.isActionable(session: claude, pending: claudeRequest))
        claude.capabilities = AgentCapabilities()
        XCTAssertFalse(AgentApprovalPresentation.isActionable(session: claude, pending: claudeRequest))
    }

    private func session(
        provider: AgentProvider = .codex,
        nativeID: String = "session",
        generation: UInt64 = 1,
        state: AgentState = .working,
        projectName: String = "DynamicIsland",
        model: String? = "model",
        capabilities: Set<AgentCapability> = [],
        usage: AgentUsage = AgentUsage(),
        availability: AgentSessionAvailability? = nil
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
            lastUpdatedAt: now,
            availability: availability
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
