import XCTest
@testable import DynamicIsland

@MainActor
final class AgentIntegrationRouterTests: XCTestCase {
    func testMCPNormalizesExactSessionAndRetainsProvenance() async throws {
        let runtime = makeRuntime()
        let producer = try await mcpProducer(runtime.router, id: "mcp.tools.local")

        let result = await runtime.router.routeMCP(
            AgentMCPObservation(
                observationID: "session-1",
                provider: .codex,
                nativeSessionID: "official-thread-1",
                timestamp: Date(timeIntervalSince1970: 10),
                kind: .sessionObserved(project: AgentProjectContext(
                    displayName: "DynamicIsland",
                    workingDirectory: "/Users/example/private",
                    repositoryIdentity: "repo-1",
                    gitBranch: "feature/router"
                ))
            ),
            from: producer
        )

        XCTAssertSuccess(result)
        XCTAssertEqual(runtime.store.sessions.single?.id.sessionID, AgentSessionID(
            provider: .codex,
            nativeID: "official-thread-1"
        ))
        XCTAssertEqual(runtime.store.sessions.single?.source, .mcp)
        XCTAssertNil(runtime.store.sessions.single?.project.workingDirectory)
        XCTAssertEqual(runtime.capture.events.first?.provenance?.sourceKind, .mcpObservation)
        XCTAssertEqual(runtime.capture.events.first?.provenance?.sourceInstanceID.rawValue, "mcp.tools.local")
        XCTAssertTrue(runtime.store.sessions.single?.capabilities.contains(.toolLifecycle) == true)
        XCTAssertFalse(runtime.store.sessions.single?.capabilities.contains(.approvalControl) == true)
    }

    func testNativeObservationSuppressesEquivalentMCPFallback() async throws {
        let runtime = makeRuntime()
        let native = try await nativeProducer(runtime.coordinator)
        let mcp = try await mcpProducer(runtime.router, id: "mcp.dedup")
        let session = nativeEvent(
            id: "native-start",
            nativeSessionID: "shared-thread",
            type: .sessionStarted,
            payload: .sessionMetadata(.init(project: nil))
        )
        XCTAssertSuccess(await runtime.router.route(session, from: native, precedence: .providerNative))

        let nativeTool = nativeEvent(
            id: "native-tool",
            nativeSessionID: "shared-thread",
            type: .toolStarted,
            correlationID: .init(rawValue: "tool-1"),
            payload: .tool(.init(name: "Read", category: "file", summary: "Read source", success: nil))
        )
        XCTAssertSuccess(await runtime.router.route(nativeTool, from: native, precedence: .providerNative))

        let fallback = await runtime.router.routeMCP(
            AgentMCPObservation(
                observationID: "mcp-tool",
                provider: .codex,
                nativeSessionID: "shared-thread",
                correlationID: .init(rawValue: "tool-1"),
                kind: .toolStarted(name: "Read", category: "file", summary: "Read source")
            ),
            from: mcp
        )

        guard case .success(let routed) = fallback else { return XCTFail("MCP fallback failed") }
        XCTAssertEqual(routed.acceptedEvents, 0)
        XCTAssertEqual(runtime.store.sessions.single?.tools.count, 1)
        XCTAssertEqual(runtime.store.sessions.single?.source, .desktopApp)
    }

    func testLaterNativeEvidenceUpgradesMCPToolWithoutDuplicateActivity() async throws {
        let runtime = makeRuntime()
        let mcp = try await mcpProducer(runtime.router, id: "mcp.upgrade")
        let native = try await nativeProducer(runtime.coordinator)
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "session",
                provider: .codex,
                nativeSessionID: "upgrade-thread",
                kind: .sessionObserved(project: nil)
            ),
            from: mcp
        ))
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "mcp-tool",
                provider: .codex,
                nativeSessionID: "upgrade-thread",
                correlationID: .init(rawValue: "tool-1"),
                kind: .toolStarted(name: "Read", category: "file", summary: "Read source")
            ),
            from: mcp
        ))

        let nativeTool = nativeEvent(
            id: "native-tool",
            nativeSessionID: "upgrade-thread",
            type: .toolStarted,
            correlationID: .init(rawValue: "tool-1"),
            payload: .tool(.init(name: "Read", category: "file", summary: "Read source", success: nil))
        )
        XCTAssertSuccess(await runtime.router.route(nativeTool, from: native, precedence: .providerNative))

        XCTAssertEqual(runtime.store.sessions.single?.source, .desktopApp)
        XCTAssertEqual(runtime.store.sessions.single?.tools.count, 1)
        XCTAssertEqual(
            runtime.store.sessions.single?.recentActivity.filter { $0.correlationID?.rawValue == "tool-1" }.count,
            1
        )
        XCTAssertEqual(runtime.capture.events.last?.source, .desktopApp)
        XCTAssertEqual(runtime.capture.events.last?.provenance?.sourceKind, .officialLifecycleProtocol)
    }

    func testMCPAttentionIsObservedOnlyAndCannotResolveApproval() async throws {
        let runtime = makeRuntime()
        let producer = try await mcpProducer(runtime.router, id: "mcp.approvals")
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "session",
                provider: .codex,
                nativeSessionID: "approval-thread",
                kind: .sessionObserved(project: nil)
            ),
            from: producer
        ))
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "approval",
                provider: .codex,
                nativeSessionID: "approval-thread",
                correlationID: .init(rawValue: "request-1"),
                kind: .attention(
                    summary: "Run tests",
                    operationCorrelationID: nil,
                    expiresAt: nil
                )
            ),
            from: producer
        ))

        XCTAssertEqual(runtime.store.sessions.single?.state, .waitingForApproval)
        XCTAssertTrue(runtime.store.sessions.single?.capabilities.contains(.approvalObservation) == true)
        XCTAssertFalse(runtime.store.sessions.single?.capabilities.contains(.approvalControl) == true)

        let forbidden = AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: .init(rawValue: "mcp-resolution"),
            provider: .codex,
            source: .mcp,
            nativeSessionID: "approval-thread",
            assertedGeneration: nil,
            type: .approvalResolved,
            providerTimestamp: nil,
            receivedTimestamp: Date(),
            correlationID: .init(rawValue: "request-1"),
            sequence: nil,
            authority: .processObservation,
            payload: .approvalResolution(.init(state: .approved)),
            continuity: .init(immutableIdentity: "approval-thread")
        )
        let resolution = await runtime.router.route(
            forbidden,
            from: producer,
            precedence: .mcpFallback
        )
        XCTAssertEqual(resolution, .failure(.policyViolation))
    }

    func testMCPRejectsMalformedIdentityAndUnauthoritativeUsage() async throws {
        let runtime = makeRuntime()
        let producer = try await mcpProducer(runtime.router, id: "mcp.invalid")
        let malformed = await runtime.router.routeMCP(
            .init(
                observationID: "bad\nidentifier",
                provider: .other(""),
                nativeSessionID: "",
                kind: .heartbeat
            ),
            from: producer
        )
        XCTAssertEqual(malformed, .failure(.invalidEvent))

        let usage = AgentUsage(samples: [
            .contextUsed: AgentUsageSample(
                value: 5,
                limit: 100,
                unit: .tokens,
                scope: "thread",
                source: "mcp",
                observedAt: Date()
            )
        ])
        let untrustedUsage = await runtime.router.routeMCP(
            .init(
                observationID: "usage",
                provider: .codex,
                nativeSessionID: "thread",
                kind: .usage(usage, authoritative: false)
            ),
            from: producer
        )
        XCTAssertEqual(untrustedUsage, .failure(.invalidEvent))
        XCTAssertTrue(runtime.store.sessions.isEmpty)
    }

    func testMCPProducerRejectsNonMCPSourceFailClosed() async throws {
        let runtime = makeRuntime()
        let producer = try await mcpProducer(runtime.router, id: "mcp.source-boundary")
        let event = AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: .init(rawValue: "wrong-source"),
            provider: .other("future-provider"),
            source: .unknown,
            nativeSessionID: "future-session",
            assertedGeneration: nil,
            type: .sessionStarted,
            providerTimestamp: nil,
            receivedTimestamp: Date(),
            correlationID: nil,
            sequence: nil,
            authority: .processObservation,
            payload: .sessionMetadata(.init(project: nil)),
            continuity: .init(immutableIdentity: "future-session")
        )

        let result = await runtime.router.route(event, from: producer, precedence: .mcpFallback)
        XCTAssertEqual(result, .failure(.policyViolation))
        XCTAssertTrue(runtime.store.sessions.isEmpty)
    }

    func testAuthoritativeMCPUsageIsNormalizedWithoutControlAuthority() async throws {
        let runtime = makeRuntime()
        let producer = try await mcpProducer(runtime.router, id: "mcp.usage")
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "session",
                provider: .other("future-provider"),
                nativeSessionID: "future-thread",
                kind: .sessionObserved(project: nil)
            ),
            from: producer
        ))
        let sample = AgentUsageSample(
            value: 42,
            limit: 100,
            unit: .tokens,
            scope: "future-thread",
            source: "authoritative-mcp-server",
            observedAt: Date()
        )
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "usage",
                provider: .other("future-provider"),
                nativeSessionID: "future-thread",
                kind: .usage(AgentUsage(samples: [.contextUsed: sample]), authoritative: true)
            ),
            from: producer
        ))

        XCTAssertEqual(runtime.store.sessions.single?.usage[.contextUsed]?.value, 42)
        XCTAssertTrue(runtime.store.sessions.single?.capabilities.contains(.contextUsage) == true)
        XCTAssertFalse(runtime.store.sessions.single?.capabilities.contains(.approvalControl) == true)
    }

    func testMCPCommandProjectionDropsArgumentsAndSecrets() async throws {
        let runtime = makeRuntime()
        let producer = try await mcpProducer(runtime.router, id: "mcp.privacy")
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "session",
                provider: .codex,
                nativeSessionID: "privacy-thread",
                kind: .sessionObserved(project: nil)
            ),
            from: producer
        ))
        XCTAssertSuccess(await runtime.router.routeMCP(
            .init(
                observationID: "command",
                provider: .codex,
                nativeSessionID: "privacy-thread",
                correlationID: .init(rawValue: "command-1"),
                kind: .commandStarted(executable: "/usr/bin/curl --header Authorization:secret")
            ),
            from: producer
        ))

        XCTAssertEqual(
            runtime.store.sessions.single?.commands[.init(rawValue: "command-1")]?.displaySummary,
            "curl"
        )
    }

    private func makeRuntime() -> (
        store: AgentEventStore,
        coordinator: AgentIngestionCoordinator,
        router: AgentIntegrationRouter,
        capture: EventCapture
    ) {
        let store = AgentEventStore()
        let capture = EventCapture()
        let coordinator = AgentIngestionCoordinator(storeSink: { events in
            capture.events.append(contentsOf: events)
            return store.ingestAtomically(events)
        })
        return (store, coordinator, AgentIntegrationRouter(coordinator: coordinator), capture)
    }

    private func mcpProducer(
        _ router: AgentIntegrationRouter,
        id: String
    ) async throws -> AgentProducerHandle {
        switch await router.registerMCPSource(id: .init(rawValue: id)) {
        case .success(let handle): return handle
        case .failure(let error): throw error
        }
    }

    private func nativeProducer(_ coordinator: AgentIngestionCoordinator) async throws -> AgentProducerHandle {
        switch await coordinator.registerProducer(
            descriptor: .init(
                sourceInstanceID: .init(rawValue: "codex.app-server.test"),
                sourceKind: .officialLifecycleProtocol
            ),
            policy: .codexAppServer,
            authenticatedProducerID: "codex-app-server"
        ) {
        case .success(let handle): return handle
        case .failure(let error): throw error
        }
    }

    private func nativeEvent(
        id: String,
        nativeSessionID: String,
        type: AgentEventType,
        correlationID: AgentCorrelationID? = nil,
        payload: AgentEventPayload
    ) -> AgentIngestionEvent {
        AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: .init(rawValue: id),
            provider: .codex,
            source: .desktopApp,
            nativeSessionID: nativeSessionID,
            assertedGeneration: nil,
            type: type,
            providerTimestamp: nil,
            receivedTimestamp: Date(),
            correlationID: correlationID,
            sequence: nil,
            authority: .lifecycle,
            payload: payload,
            continuity: .init(immutableIdentity: nativeSessionID)
        )
    }
}

@MainActor
private final class EventCapture {
    var events: [AgentEvent] = []
}

private extension Collection {
    var single: Element? { count == 1 ? first : nil }
}

private extension XCTestCase {
    func XCTAssertSuccess<T, E>(
        _ result: Result<T, E>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .success = result else {
            return XCTFail("Expected success, got \(result)", file: file, line: line)
        }
    }
}
