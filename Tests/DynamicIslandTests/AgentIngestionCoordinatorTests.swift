import XCTest
@testable import DynamicIsland

@MainActor
final class AgentIngestionCoordinatorTests: XCTestCase {
    func testSingleProducerAllocatesGenerationAndPublishesProvenance() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "lifecycle")

        let result = await coordinator.ingest(event("start"), from: handle)

        XCTAssertSuccess(result)
        XCTAssertEqual(store.sessions.single?.id.generation.rawValue, 1)
        XCTAssertEqual(store.sessions.single?.recentActivity.count, 1)
        let leases = await coordinator.sessionLeases()
        XCTAssertEqual(leases.single?.owners, [handle])
    }

    func testPolicyRejectsProviderSourceAuthorityAndCapabilityEscalation() async throws {
        let (store, coordinator) = makeRuntime()
        let policy = AgentIngestionTestSupport.policy(
            providers: [.codex],
            sources: [.terminal],
            kinds: [.structuredRecovery],
            ceiling: .localStructuredRecord,
            capabilities: [.toolLifecycle]
        )
        let handle = try await registered(coordinator, id: "bounded", kind: .structuredRecovery, policy: policy)

        XCTAssertFailure(await coordinator.ingest(event("provider", provider: .claude), from: handle), .policyViolation)
        XCTAssertFailure(await coordinator.ingest(event("source", source: .vscode), from: handle), .policyViolation)
        XCTAssertFailure(await coordinator.ingest(event("authority", authority: .lifecycle), from: handle), .policyViolation)
        let capability = event(
            "capability",
            type: .capabilitiesUpdated,
            authority: .localStructuredRecord,
            payload: .capabilities(capabilities([.approvalControl], authority: .localStructuredRecord))
        )
        XCTAssertFailure(await coordinator.ingest(capability, from: handle), .policyViolation)
        XCTAssertTrue(store.sessions.isEmpty)
        let health = await coordinator.sourceHealth()
        XCTAssertEqual(health.single?.state, .degraded)
    }

    func testAuthenticatedProducerCannotUseAnotherPolicyOrOldEpoch() async throws {
        let (_, coordinator) = makeRuntime()
        let codex = try await registered(
            coordinator,
            id: "shared",
            policy: AgentIngestionTestSupport.policy(providers: [.codex], kinds: [.officialLifecycleProtocol])
        )
        let replacement = try await registered(
            coordinator,
            id: "shared",
            policy: AgentIngestionTestSupport.policy(providers: [.claude], kinds: [.officialLifecycleProtocol])
        )

        XCTAssertFailure(await coordinator.ingest(event("old"), from: codex), .staleProducer)
        XCTAssertFailure(await coordinator.ingest(event("wrong", provider: .codex), from: replacement), .policyViolation)
        XCTAssertSuccess(await coordinator.ingest(event("valid", provider: .claude), from: replacement))
    }

    func testSameNativeIDAcrossProvidersAndSameProjectSessionsStaySeparate() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "multi")
        let context = AgentProjectContext(displayName: "Same", workingDirectory: "/same")
        let events = [
            event("codex-a", nativeID: "same", payload: .sessionMetadata(.init(project: context))),
            event("claude-a", provider: .claude, nativeID: "same", payload: .sessionMetadata(.init(project: context))),
            event("codex-b", nativeID: "other", payload: .sessionMetadata(.init(project: context)))
        ]

        XCTAssertSuccess(await coordinator.ingestAtomically(events, from: handle))
        XCTAssertEqual(store.sessions.count, 3)
        XCTAssertEqual(Set(store.sessions.map(\.id.sessionID.provider)), [.codex, .claude])
    }

    func testCompatibleMultiSourceContinuityConvergesOnOneGeneration() async throws {
        let (store, coordinator) = makeRuntime()
        let hook = try await registered(coordinator, id: "hook", kind: .officialHook)
        let recovery = try await registered(coordinator, id: "recovery", kind: .structuredRecovery)
        let continuity = "immutable-session"

        XCTAssertSuccess(await coordinator.ingest(event("hook-start", continuity: continuity), from: hook))
        XCTAssertSuccess(await coordinator.ingest(event("recovery-start", authority: .localStructuredRecord, continuity: continuity), from: recovery))

        XCTAssertEqual(store.sessions.count, 1)
        let leases = await coordinator.sessionLeases()
        XCTAssertEqual(leases.single?.owners, [hook, recovery])
    }

    func testProducerRestartWithContinuityRetainsGenerationWithoutContinuityReplacesIt() async throws {
        let (store, coordinator) = makeRuntime()
        let first = try await registered(coordinator, id: "restart")
        XCTAssertSuccess(await coordinator.ingest(event("first", continuity: "stable"), from: first))
        let continued = try await registered(coordinator, id: "restart")
        XCTAssertSuccess(await coordinator.ingest(event("continued", continuity: "stable"), from: continued))
        XCTAssertEqual(store.sessions.map(\.id.generation.rawValue), [1])

        let unproven = try await registered(coordinator, id: "restart")
        XCTAssertSuccess(await coordinator.ingest(event("new-incarnation"), from: unproven))
        XCTAssertEqual(Set(store.sessions.map(\.id.generation.rawValue)), [1, 2])
        XCTAssertFailure(await coordinator.ingest(event("late", type: .agentWorking), from: continued), .staleProducer)
    }

    func testExplicitStartAfterTerminalAllocatesNewGenerationForSameOwner() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "terminal-restart")
        XCTAssertSuccess(await coordinator.ingest(event("start", continuity: "stable"), from: handle))
        XCTAssertSuccess(await coordinator.ingest(
            event("complete", type: .taskCompleted, payload: .terminal(.init(summary: "done")), continuity: "stable"),
            from: handle
        ))

        XCTAssertSuccess(await coordinator.ingest(event("restart", continuity: "stable"), from: handle))

        XCTAssertEqual(Set(store.sessions.map(\.id.generation.rawValue)), [1, 2])
        XCTAssertEqual(store.sessions.first(where: { $0.id.generation.rawValue == 2 })?.state, .idle)
    }

    func testConflictingVerifiedIdentityIsQuarantinedWithoutMerge() async throws {
        let (store, coordinator) = makeRuntime()
        let first = try await registered(coordinator, id: "first")
        let second = try await registered(coordinator, id: "second")
        XCTAssertSuccess(await coordinator.ingest(event("first", continuity: "identity-a"), from: first))
        XCTAssertFailure(
            await coordinator.ingest(event("conflict", continuity: "identity-b"), from: second),
            .identityConflict
        )
        XCTAssertEqual(store.sessions.count, 1)
        let conflicts = await coordinator.recordedIdentityConflicts()
        XCTAssertEqual(conflicts.count, 1)
    }

    func testWireGenerationIsAssertionAndCannotJumpLocalAuthority() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "generation")
        XCTAssertFailure(await coordinator.ingest(event("jump", generation: 999), from: handle), .generationConflict)
        XCTAssertTrue(store.sessions.isEmpty)
        let emptyLeases = await coordinator.sessionLeases()
        XCTAssertTrue(emptyLeases.isEmpty)
        XCTAssertSuccess(await coordinator.ingest(event("local"), from: handle))
        XCTAssertEqual(store.sessions.single?.id.generation.rawValue, 1)
    }

    func testFailedAtomicBatchDoesNotAllocateGhostLeaseOrCapability() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "atomic")
        let invalid = event("invalid", nativeID: "other", type: .agentWorking)

        XCTAssertFailure(await coordinator.ingestAtomically([event("start"), invalid], from: handle), .generationConflict)
        XCTAssertTrue(store.sessions.isEmpty)
        let emptyLeases = await coordinator.sessionLeases()
        XCTAssertTrue(emptyLeases.isEmpty)
        XCTAssertSuccess(await coordinator.ingest(event("retry"), from: handle))
        XCTAssertEqual(store.sessions.single?.id.generation.rawValue, 1)
    }

    func testTelemetryCannotCompleteTaskOrResolveApprovalButMayEnrichMetadata() async throws {
        let (store, coordinator) = makeRuntime()
        let lifecycle = try await registered(coordinator, id: "lifecycle")
        let allowed: Set<AgentEventType> = [.sessionStarted, .projectContextUpdated, .usageUpdated]
        let telemetryPolicy = AgentIngestionTestSupport.policy(
            kinds: [.structuredTelemetry],
            allowedTypes: allowed,
            ceiling: .structuredTelemetry
        )
        let telemetry = try await registered(
            coordinator, id: "telemetry", kind: .structuredTelemetry, policy: telemetryPolicy
        )
        XCTAssertSuccess(await coordinator.ingest(event("start", continuity: "same"), from: lifecycle))
        XCTAssertFailure(await coordinator.ingest(event("complete", type: .taskCompleted, authority: .structuredTelemetry, continuity: "same"), from: telemetry), .policyViolation)
        XCTAssertFailure(await coordinator.ingest(event("approve", type: .approvalResolved, authority: .structuredTelemetry, continuity: "same"), from: telemetry), .policyViolation)
        let metadata = event(
            "metadata", type: .projectContextUpdated, authority: .structuredTelemetry,
            payload: .projectContext(AgentProjectContext(model: "model")), continuity: "same"
        )
        XCTAssertSuccess(await coordinator.ingest(metadata, from: telemetry))
        XCTAssertEqual(store.sessions.single?.project.model, "model")
        XCTAssertFalse(store.sessions.single?.state.isTerminal == true)
    }

    func testCapabilityEvidenceAggregatesAndWithdrawsPerProducer() async throws {
        let (store, coordinator) = makeRuntime()
        let first = try await registered(coordinator, id: "caps-a")
        let second = try await registered(coordinator, id: "caps-b", kind: .structuredRecovery)
        XCTAssertSuccess(await coordinator.ingest(event("start", continuity: "same"), from: first))
        XCTAssertSuccess(await coordinator.ingest(event("join", authority: .localStructuredRecord, continuity: "same"), from: second))
        XCTAssertSuccess(await coordinator.ingest(capabilityEvent("a", [.toolLifecycle]), from: first))
        XCTAssertSuccess(await coordinator.ingest(capabilityEvent("b", [.toolLifecycle], authority: .localStructuredRecord), from: second))
        XCTAssertTrue(store.sessions.single?.capabilities.contains(.toolLifecycle) == true)

        XCTAssertSuccess(await coordinator.ingest(capabilityEvent("a-withdraw", []), from: first))
        XCTAssertTrue(store.sessions.single?.capabilities.contains(.toolLifecycle) == true)
        XCTAssertSuccess(await coordinator.ingest(capabilityEvent("b-withdraw", [], authority: .localStructuredRecord), from: second))
        XCTAssertFalse(store.sessions.single?.capabilities.contains(.toolLifecycle) == true)
    }

    func testPolicyReplacementWithdrawsOnlyDisallowedProducerEvidence() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "policy")
        XCTAssertSuccess(await coordinator.ingest(event("start"), from: handle))
        XCTAssertSuccess(await coordinator.ingest(capabilityEvent("caps", [.toolLifecycle, .contextUsage]), from: handle))
        let narrowed = AgentIngestionTestSupport.policy(
            kinds: [.officialLifecycleProtocol], capabilities: [.toolLifecycle]
        )
        XCTAssertSuccess(await coordinator.replacePolicy(narrowed, for: handle))
        XCTAssertTrue(store.sessions.single?.capabilities.contains(.toolLifecycle) == true)
        XCTAssertFalse(store.sessions.single?.capabilities.contains(.contextUsage) == true)
    }

    func testGenerationReplacementDoesNotCarryObsoleteCapabilityEvidence() async throws {
        let (store, coordinator) = makeRuntime()
        let first = try await registered(coordinator, id: "generation-a")
        XCTAssertSuccess(await coordinator.ingest(event("start-a"), from: first))
        XCTAssertSuccess(await coordinator.ingest(capabilityEvent("caps-a", [.toolLifecycle]), from: first))

        let second = try await registered(coordinator, id: "generation-b")
        XCTAssertSuccess(await coordinator.ingest(event("start-b"), from: second))

        let current = store.sessions.first { $0.id.generation.rawValue == 2 }
        XCTAssertNotNil(current)
        XCTAssertFalse(current?.capabilities.contains(.toolLifecycle) == true)
    }

    func testUnregisterWithdrawsCapabilitiesButDoesNotInventTerminalState() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "unregister")
        XCTAssertSuccess(await coordinator.ingest(event("start"), from: handle))
        XCTAssertSuccess(await coordinator.ingest(capabilityEvent("caps", [.toolLifecycle]), from: handle))
        XCTAssertSuccess(await coordinator.unregisterProducer(handle))
        XCTAssertFalse(store.sessions.single?.capabilities.contains(.toolLifecycle) == true)
        XCTAssertEqual(store.sessions.single?.state, .idle)
        let stoppedHealth = await coordinator.stoppedSourceHealth()
        XCTAssertEqual(stoppedHealth.last?.state, .stopped)
    }

    func testConcurrentSyntheticProducersRemainSerializedAndIsolated() async throws {
        let (store, coordinator) = makeRuntime()
        var inputs: [(AgentProducerHandle, AgentIngestionEvent)] = []
        for index in 0..<10 {
            let handle = try await registered(coordinator, id: "concurrent-\(index)")
            inputs.append((handle, event("start-\(index)", nativeID: "session-\(index)")))
        }
        await withTaskGroup(of: Void.self) { group in
            for (handle, evidence) in inputs {
                group.addTask { _ = await coordinator.ingest(evidence, from: handle) }
            }
        }
        XCTAssertEqual(store.sessions.count, 10)
        XCTAssertEqual(Set(store.sessions.map(\.id.sessionID.nativeID)).count, 10)
    }

    func testSchemaMismatchDegradesHealthAndNeverMutatesStore() async throws {
        let (store, coordinator) = makeRuntime()
        let handle = try await registered(coordinator, id: "schema")
        var invalid = event("schema")
        invalid = AgentIngestionEvent(
            schemaVersion: 99, eventID: invalid.eventID, provider: invalid.provider, source: invalid.source,
            nativeSessionID: invalid.nativeSessionID, assertedGeneration: nil, type: invalid.type,
            providerTimestamp: nil, receivedTimestamp: invalid.receivedTimestamp, correlationID: nil,
            sequence: nil, authority: invalid.authority, payload: invalid.payload, continuity: nil
        )
        XCTAssertFailure(await coordinator.ingest(invalid, from: handle), .unsupportedSchema)
        XCTAssertTrue(store.sessions.isEmpty)
        let health = (await coordinator.sourceHealth()).single
        XCTAssertEqual(health?.state, .degraded)
        XCTAssertEqual(health?.schemaMismatchCount, 1)
    }

    private func makeRuntime() -> (AgentEventStore, AgentIngestionCoordinator) {
        let store = AgentEventStore()
        return (store, AgentIngestionCoordinator(eventStore: store))
    }

    private func registered(
        _ coordinator: AgentIngestionCoordinator,
        id: String,
        kind: AgentSourceKind = .officialLifecycleProtocol,
        policy: AgentProducerPolicy? = nil
    ) async throws -> AgentProducerHandle {
        try await AgentIngestionTestSupport.registered(
            coordinator: coordinator, id: id, kind: kind, policy: policy
        )
    }

    private func event(
        _ id: String,
        provider: AgentProvider = .codex,
        source: AgentSource = .terminal,
        nativeID: String = "session",
        generation: UInt64? = nil,
        type: AgentEventType = .sessionStarted,
        authority: AgentEvidenceAuthority = .lifecycle,
        payload: AgentEventPayload? = nil,
        continuity: String? = nil
    ) -> AgentIngestionEvent {
        AgentIngestionTestSupport.event(
            id, provider: provider, source: source, nativeID: nativeID, generation: generation,
            type: type, authority: authority, payload: payload, continuity: continuity
        )
    }

    private func capabilityEvent(
        _ id: String,
        _ values: Set<AgentCapability>,
        authority: AgentEvidenceAuthority = .lifecycle
    ) -> AgentIngestionEvent {
        event(
            id, type: .capabilitiesUpdated, authority: authority,
            payload: .capabilities(capabilities(values, authority: authority)), continuity: "same"
        )
    }

    private func capabilities(
        _ values: Set<AgentCapability>,
        authority: AgentEvidenceAuthority = .lifecycle
    ) -> AgentCapabilities {
        AgentIngestionTestSupport.capabilities(values, authority: authority)
    }
}

private extension Array {
    var single: Element? { count == 1 ? first : nil }
}

private func XCTAssertSuccess<Success>(
    _ result: Result<Success, AgentIngestionError>,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if case .failure(let error) = result {
        XCTFail("Expected success, got \(error)", file: file, line: line)
    }
}

private func XCTAssertFailure<Success>(
    _ result: Result<Success, AgentIngestionError>,
    _ expected: AgentIngestionError,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .failure(let error) = result else {
        return XCTFail("Expected failure \(expected)", file: file, line: line)
    }
    XCTAssertEqual(error, expected, file: file, line: line)
}
