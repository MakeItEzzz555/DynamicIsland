import AgentBridgeShared
import CodexHookShared
import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentBridgeSharedNetworkIntegrationTests: XCTestCase {
    func testSharedClientAuthenticatesToRealBridgeAndMutatesRealStore() async throws {
        let fixture = try makeBridgeFixture()
        defer {
            fixture.bridge.stop()
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        await fixture.bridge.start()
        XCTAssertEqual(fixture.bridge.health.state, .running)

        let reader = try AgentBridgeDiscoveryReader(recordURL: fixture.recordURL)
        let client = AgentBridgeClient(profiles: reader)
        let result = try await client.sendEvents(input: try normalizedInput(eventID: "shared-client-real"))

        XCTAssertEqual(result, .accepted)
        XCTAssertEqual(fixture.store.sessions.count, 1)
        XCTAssertEqual(fixture.store.sessions.first?.id.sessionID.provider, .other("unverified"))
    }

    func testRealBridgeRestartReloadsChangedProfileOnlyOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentBridgeSharedRestart-\(UUID().uuidString)", isDirectory: true)
        let recordURL = directory.appendingPathComponent("bridge-v1.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let firstStore = AgentEventStore()
        let firstBridge = AgentBridge(
            eventStore: firstStore,
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: try AgentBridgeDiscoveryPublisher(recordURL: recordURL),
            codexDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("codex-hook-v1.json")
            ),
            codexPermissionDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("codex-permission-v1.json")
            ),
            claudeDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("claude-hook-v1.json")
            )
        )
        await firstBridge.start()
        let stale = try await AgentBridgeDiscoveryReader(recordURL: recordURL).loadProfile()
        firstBridge.stop()

        let secondStore = AgentEventStore()
        let secondBridge = AgentBridge(
            eventStore: secondStore,
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: try AgentBridgeDiscoveryPublisher(recordURL: recordURL),
            codexDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("codex-hook-v1.json")
            ),
            codexPermissionDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("codex-permission-v1.json")
            ),
            claudeDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("claude-hook-v1.json")
            )
        )
        await secondBridge.start()
        defer { secondBridge.stop() }

        let provider = StaleThenCurrentProfileProvider(
            stale: stale,
            current: try AgentBridgeDiscoveryReader(recordURL: recordURL)
        )
        let result = try await AgentBridgeClient(profiles: provider)
            .sendEvents(input: try normalizedInput(eventID: "restart-event"))

        XCTAssertEqual(result, .accepted)
        let loadCount = await provider.currentLoadCount()
        XCTAssertEqual(loadCount, 2)
        XCTAssertEqual(secondStore.sessions.count, 1)
    }

    func testDedicatedCodexPermissionRouteReturnsExactOneShotAllowAndDeny() async throws {
        let fixture = try makeBridgeFixture()
        defer {
            fixture.bridge.stop()
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        await fixture.bridge.start()

        let client = AgentBridgeClient(
            profiles: try AgentBridgeDiscoveryReader(recordURL: fixture.permissionRecordURL)
        )
        let observerClient = AgentBridgeClient(
            profiles: try AgentBridgeDiscoveryReader(recordURL: fixture.codexRecordURL)
        )
        for (index, expected) in [AgentBridgePermissionDecision.allow, .deny].enumerated() {
            let start = Data("""
            {"session_id":"permission-\(index)","cwd":"/tmp/project","hook_event_name":"SessionStart","source":"startup"}
            """.utf8)
            let startResult = try await observerClient.sendEvents(
                input: CodexHookNormalizer.normalize(start)
            )
            XCTAssertEqual(startResult, .accepted)
            let input = Data("""
            {"session_id":"permission-\(index)","turn_id":"turn-\(index)","cwd":"/tmp/project","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git status"}}
            """.utf8)
            let normalized = try CodexHookNormalizer.normalize(input)
            let response = Task { try await client.requestCodexPermission(input: normalized) }

            for _ in 0..<100 where fixture.approvals.pendingRequests.isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
            let pending = try XCTUnwrap(fixture.approvals.pendingRequests.values.first)
            XCTAssertEqual(
                fixture.approvals.resolve(
                    session: pending.key.session,
                    requestID: pending.key.requestID,
                    decision: expected
                ),
                .accepted
            )
            let received = try await response.value
            XCTAssertEqual(received, expected)
            XCTAssertEqual(
                fixture.approvals.resolve(
                    session: pending.key.session,
                    requestID: pending.key.requestID,
                    decision: expected
                ),
                .missing
            )
        }
    }

    func testDedicatedCodexPermissionRouteHonorsExactSessionAutoApproveOnce() async throws {
        let fixture = try makeBridgeFixture()
        defer {
            fixture.bridge.stop()
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        await fixture.bridge.start()
        let permissionClient = AgentBridgeClient(
            profiles: try AgentBridgeDiscoveryReader(recordURL: fixture.permissionRecordURL)
        )
        let observerClient = AgentBridgeClient(
            profiles: try AgentBridgeDiscoveryReader(recordURL: fixture.codexRecordURL)
        )
        let start = Data("""
        {"session_id":"auto-hook","cwd":"/tmp/project","hook_event_name":"SessionStart","source":"startup"}
        """.utf8)
        let startResult = try await observerClient.sendEvents(
            input: CodexHookNormalizer.normalize(start)
        )
        XCTAssertEqual(startResult, .accepted)
        let session = try XCTUnwrap(fixture.store.sessions.first)
        fixture.approvals.setAutoApprove(true, for: session.id)
        let permission = Data("""
        {"session_id":"auto-hook","turn_id":"turn-auto","cwd":"/tmp/project","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"description":"Run focused tests","command":"swift test --filter AgentApprovalControllerTests"}}
        """.utf8)
        let normalized = try CodexHookNormalizer.normalize(permission)

        let decision = try await permissionClient.requestCodexPermission(input: normalized)
        XCTAssertEqual(decision, .allow)
        XCTAssertTrue(fixture.approvals.pendingRequests.isEmpty)
        // Replaying the exact hook event is rejected by ingestion/replay
        // protection and can never produce a second allow decision.
        let replayed = try await permissionClient.requestCodexPermission(input: normalized)
        XCTAssertNil(replayed)
    }

    func testGenericBridgeCredentialCannotControlCodexApproval() async throws {
        let fixture = try makeBridgeFixture()
        defer {
            fixture.bridge.stop()
            try? FileManager.default.removeItem(at: fixture.directory)
        }
        await fixture.bridge.start()
        let genericClient = AgentBridgeClient(
            profiles: try AgentBridgeDiscoveryReader(recordURL: fixture.recordURL)
        )
        let input = Data("""
        {"session_id":"generic-denied","turn_id":"turn","cwd":"/tmp/project","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"git status"}}
        """.utf8)
        let normalized = try CodexHookNormalizer.normalize(input)

        do {
            _ = try await genericClient.requestCodexPermission(input: normalized)
            XCTFail("Generic bridge credential must not authenticate the permission route")
        } catch let error as AgentBridgeClientError {
            XCTAssertEqual(error, .authenticationFailed)
        }
        XCTAssertTrue(fixture.approvals.pendingRequests.isEmpty)
    }

    private func makeBridgeFixture() throws -> (
        directory: URL,
        recordURL: URL,
        codexRecordURL: URL,
        permissionRecordURL: URL,
        store: AgentEventStore,
        approvals: AgentApprovalController,
        bridge: AgentBridge
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentBridgeSharedNetwork-\(UUID().uuidString)", isDirectory: true)
        let recordURL = directory.appendingPathComponent("bridge-v1.json")
        let codexRecordURL = directory.appendingPathComponent("codex-hook-v1.json")
        let permissionRecordURL = directory.appendingPathComponent("codex-permission-v1.json")
        let store = AgentEventStore()
        let approvals = AgentApprovalController()
        let bridge = AgentBridge(
            eventStore: store,
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: try AgentBridgeDiscoveryPublisher(recordURL: recordURL),
            codexDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: codexRecordURL
            ),
            codexPermissionDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: permissionRecordURL
            ),
            claudeDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("claude-hook-v1.json")
            ),
            approvals: approvals
        )
        return (directory, recordURL, codexRecordURL, permissionRecordURL, store, approvals, bridge)
    }

    private func normalizedInput(eventID: String) throws -> Data {
        try AgentBridgeTestSupport.body(
            producerID: "caller-cannot-own-transport-identity",
            event: AgentBridgeTestSupport.event(id: eventID)
        )
    }
}

private actor StaleThenCurrentProfileProvider: AgentBridgeClientProfileProviding {
    private let stale: AgentBridgeClientProfile
    private let current: AgentBridgeDiscoveryReader
    private var loadCount = 0

    init(stale: AgentBridgeClientProfile, current: AgentBridgeDiscoveryReader) {
        self.stale = stale
        self.current = current
    }

    func loadProfile() async throws -> AgentBridgeClientProfile {
        loadCount += 1
        if loadCount == 1 { return stale }
        return try await current.loadProfile()
    }

    func currentLoadCount() -> Int { loadCount }
}
