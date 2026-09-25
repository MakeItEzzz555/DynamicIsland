import AgentBridgeShared
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

    private func makeBridgeFixture() throws -> (
        directory: URL,
        recordURL: URL,
        store: AgentEventStore,
        bridge: AgentBridge
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentBridgeSharedNetwork-\(UUID().uuidString)", isDirectory: true)
        let recordURL = directory.appendingPathComponent("bridge-v1.json")
        let store = AgentEventStore()
        let bridge = AgentBridge(
            eventStore: store,
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        )
        return (directory, recordURL, store, bridge)
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
