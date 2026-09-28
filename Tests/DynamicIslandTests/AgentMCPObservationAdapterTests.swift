import XCTest
@testable import DynamicIsland

@MainActor
final class AgentMCPObservationAdapterTests: XCTestCase {
    func testAdapterDiscoversConnectsRoutesInitialAndStreamingObservations() async throws {
        let store = AgentEventStore()
        let coordinator = AgentIngestionCoordinator(eventStore: store)
        let router = AgentIntegrationRouter(coordinator: coordinator)
        let stream = AsyncStream<Data>.makeStream()

        let source = AgentMCPSourceDescriptor(
            sourceInstanceID: .init(rawValue: "mcp.local.observer"),
            displayName: "Local Observer",
            runtimeVersion: "1.0"
        )
        let connector = MCPTestConnector(connection: .init(
            initialObservations: [
                try payload(
                    id: "session-1",
                    type: "sessionObserved",
                    provider: "codex",
                    nativeSessionID: "thread-1"
                )
            ],
            observations: stream.stream,
            disconnect: {}
        ))
        let adapter = AgentMCPObservationAdapter(
            discovery: MCPTestDiscovery(sources: [source]),
            connector: connector,
            router: router
        )

        let result = await adapter.start()

        XCTAssertEqual(result.discovered, 1)
        XCTAssertEqual(result.connected, 1)
        XCTAssertEqual(result.rejectedSources, 0)
        XCTAssertEqual(result.rejectedObservations, 0)
        let connectedIDs = await adapter.connectedSourceIDs()
        XCTAssertEqual(connectedIDs, [source.sourceInstanceID])
        XCTAssertEqual(store.sessions.first?.id.sessionID.nativeID, "thread-1")
        XCTAssertEqual(store.sessions.first?.source, .mcp)

        stream.continuation.yield(try payload(
            id: "tool-1",
            type: "toolStarted",
            provider: "codex",
            nativeSessionID: "thread-1",
            correlationID: "tool-1",
            extra: [
                "name": "read_file",
                "category": "read",
                "summary": "Read AgentModels.swift"
            ]
        ))
        try await Task.sleep(for: .milliseconds(30))

        XCTAssertEqual(
            store.sessions.first?.tools[.init(rawValue: "tool-1")]?.name,
            "read_file"
        )

        await adapter.stop()
        let connectedAfterStop = await adapter.connectedSourceIDs()
        XCTAssertTrue(connectedAfterStop.isEmpty)
        stream.continuation.finish()
    }

    func testAdapterRejectsInvalidSourceAndMalformedInitialObservationFailClosed() async throws {
        let store = AgentEventStore()
        let coordinator = AgentIngestionCoordinator(eventStore: store)
        let router = AgentIntegrationRouter(coordinator: coordinator)
        let validSource = AgentMCPSourceDescriptor(
            sourceInstanceID: .init(rawValue: "mcp.valid"),
            displayName: "Valid",
            runtimeVersion: nil
        )
        let invalidSource = AgentMCPSourceDescriptor(
            sourceInstanceID: .init(rawValue: "mcp\ninvalid"),
            displayName: "Invalid",
            runtimeVersion: nil
        )
        let connector = MCPTestConnector(connection: .init(
            initialObservations: [Data("{not json".utf8)],
            observations: AsyncStream { $0.finish() },
            disconnect: {}
        ))
        let adapter = AgentMCPObservationAdapter(
            discovery: MCPTestDiscovery(sources: [validSource, invalidSource]),
            connector: connector,
            router: router
        )

        let result = await adapter.start()

        XCTAssertEqual(result.discovered, 2)
        XCTAssertEqual(result.connected, 1)
        XCTAssertEqual(result.rejectedSources, 1)
        XCTAssertEqual(result.rejectedObservations, 1)
        XCTAssertTrue(store.sessions.isEmpty)
        await adapter.stop()
    }

    func testDecoderSupportsProjectPlanCommandAttentionHeartbeatAndAuthoritativeUsage() throws {
        let project = try AgentMCPObservationDecoder.decode(try payload(
            id: "project",
            type: "project",
            provider: "claude",
            nativeSessionID: "session-1",
            extra: [
                "project": [
                    "displayName": "DynamicIsland",
                    "repositoryIdentity": "repo",
                    "gitBranch": "feature/mcp",
                    "gitCommit": "abc",
                    "model": "claude"
                ]
            ]
        ))
        guard case .project(let context) = project.kind else {
            return XCTFail("Expected project observation")
        }
        XCTAssertEqual(context.gitBranch, "feature/mcp")

        let plan = try AgentMCPObservationDecoder.decode(try payload(
            id: "plan",
            type: "planReady",
            provider: "codex",
            nativeSessionID: "session-1",
            extra: ["summary": "Ready"]
        ))
        guard case .planReady(let summary) = plan.kind else {
            return XCTFail("Expected plan-ready observation")
        }
        XCTAssertEqual(summary, "Ready")

        let command = try AgentMCPObservationDecoder.decode(try payload(
            id: "command",
            type: "commandCompleted",
            provider: "codex",
            nativeSessionID: "session-1",
            correlationID: "cmd-1",
            extra: [
                "executable": "/usr/bin/swift test",
                "success": true,
                "exitCode": 0
            ]
        ))
        guard case .commandCompleted(_, let success, let exitCode) = command.kind else {
            return XCTFail("Expected command completion")
        }
        XCTAssertEqual(success, true)
        XCTAssertEqual(exitCode, 0)

        let attention = try AgentMCPObservationDecoder.decode(try payload(
            id: "attention",
            type: "permissionRequired",
            provider: "codex",
            nativeSessionID: "session-1",
            correlationID: "approval-1",
            extra: [
                "summary": "Run tests",
                "operationCorrelationID": "cmd-1"
            ]
        ))
        guard case .attention(let summary, let operation, _) = attention.kind else {
            return XCTFail("Expected attention observation")
        }
        XCTAssertEqual(summary, "Run tests")
        XCTAssertEqual(operation?.rawValue, "cmd-1")

        let heartbeat = try AgentMCPObservationDecoder.decode(try payload(
            id: "heartbeat",
            type: "heartbeat",
            provider: "future-provider",
            nativeSessionID: "session-1"
        ))
        guard case .heartbeat = heartbeat.kind else {
            return XCTFail("Expected heartbeat")
        }

        let usage = try AgentMCPObservationDecoder.decode(try payload(
            id: "usage",
            type: "usage",
            provider: "codex",
            nativeSessionID: "session-1",
            extra: [
                "usage": [
                    "authoritative": true,
                    "samples": [[
                        "metric": "contextUsed",
                        "value": 42.0,
                        "limit": 100.0,
                        "unit": "tokens",
                        "scope": "session-1",
                        "source": "mcp-authoritative",
                        "observedAt": 1000.0
                    ]]
                ]
            ]
        ))
        guard case .usage(let projected, let authoritative) = usage.kind else {
            return XCTFail("Expected usage observation")
        }
        XCTAssertTrue(authoritative)
        XCTAssertEqual(projected[.contextUsed]?.value, 42)
    }

    func testDecoderRejectsUnknownFieldsUnsupportedTypeAndUnauthoritativeUsage() throws {
        XCTAssertThrowsError(try AgentMCPObservationDecoder.decode(try payload(
            id: "unknown-field",
            type: "heartbeat",
            provider: "codex",
            nativeSessionID: "session",
            extra: ["unexpected": "value"]
        )))

        XCTAssertThrowsError(try AgentMCPObservationDecoder.decode(try payload(
            id: "unsupported",
            type: "promptSubmit",
            provider: "codex",
            nativeSessionID: "session"
        )))

        XCTAssertThrowsError(try AgentMCPObservationDecoder.decode(try payload(
            id: "usage",
            type: "usage",
            provider: "codex",
            nativeSessionID: "session",
            extra: [
                "usage": [
                    "authoritative": false,
                    "samples": [[
                        "metric": "contextUsed",
                        "value": 1.0,
                        "unit": "tokens",
                        "scope": "session",
                        "source": "mcp",
                        "observedAt": 1.0
                    ]]
                ]
            ]
        )))
    }

    func testDecoderRejectsOversizedPayloadBeforeJSONDecode() {
        let data = Data(repeating: 0x20, count: AgentMCPAdapterLimits.maximumObservationBytes + 1)
        XCTAssertThrowsError(try AgentMCPObservationDecoder.decode(data)) { error in
            XCTAssertEqual(error as? AgentMCPAdapterError, .payloadTooLarge)
        }
    }

    private func payload(
        id: String,
        type: String,
        provider: String,
        nativeSessionID: String,
        correlationID: String? = nil,
        extra: [String: Any] = [:]
    ) throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": 1,
            "observationID": id,
            "provider": provider,
            "nativeSessionID": nativeSessionID,
            "timestamp": 1_000.0,
            "type": type
        ]
        if let correlationID {
            object["correlationID"] = correlationID
        }
        extra.forEach { object[$0.key] = $0.value }
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

private struct MCPTestDiscovery: AgentMCPSourceDiscovering {
    let sources: [AgentMCPSourceDescriptor]

    func discoverSources() async throws -> [AgentMCPSourceDescriptor] {
        sources
    }
}

private struct MCPTestConnector: AgentMCPSourceConnecting {
    let connection: AgentMCPSourceConnection

    func connect(to source: AgentMCPSourceDescriptor) async throws -> AgentMCPSourceConnection {
        connection
    }
}
