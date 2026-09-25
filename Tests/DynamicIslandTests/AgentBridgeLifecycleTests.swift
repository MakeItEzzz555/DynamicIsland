import Foundation
import AgentBridgeShared
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentBridgeLifecycleTests: XCTestCase {
    func testStartPublishesEphemeralPortAndRunningHealth() async throws {
        let discovery = DiscoverySpy()
        let servers = ServerFactorySpy(results: [.success(49_321)])
        let bridge = makeBridge(discovery: discovery, servers: servers)

        await bridge.start()

        XCTAssertEqual(bridge.health.state, .running)
        XCTAssertEqual(bridge.health.port, 49_321)
        XCTAssertEqual(servers.startCount, 1)
        XCTAssertEqual(discovery.records.first?.host, "127.0.0.1")
        XCTAssertEqual(discovery.records.first?.port, 49_321)
        XCTAssertNotNil(discovery.records.first?.authenticationToken)
        XCTAssertEqual(discovery.records.first?.producerID, discovery.records.first?.launchID)
    }

    func testRepeatedStartCreatesOnlyOneListener() async {
        let discovery = DiscoverySpy()
        let servers = ServerFactorySpy(results: [.success(49_321)])
        let bridge = makeBridge(discovery: discovery, servers: servers)
        await bridge.start()
        await bridge.start()
        XCTAssertEqual(servers.createdCount, 1)
        XCTAssertEqual(servers.startCount, 1)
        XCTAssertEqual(discovery.records.count, 1)
    }

    func testStopIsIdempotentAndRemovesOnlyOwnedDiscovery() async throws {
        let discovery = DiscoverySpy()
        let servers = ServerFactorySpy(results: [.success(49_321)])
        let bridge = makeBridge(discovery: discovery, servers: servers)
        await bridge.start()
        let launchID = try XCTUnwrap(discovery.records.first?.launchID)

        bridge.stop()
        bridge.stop()

        XCTAssertEqual(bridge.health.state, .stopped)
        XCTAssertNil(bridge.health.port)
        XCTAssertEqual(servers.stopCount, 1)
        XCTAssertEqual(discovery.removedLaunchIDs, [launchID])
    }

    func testRestartCreatesNewLaunchIdentityAndListener() async throws {
        let discovery = DiscoverySpy()
        let servers = ServerFactorySpy(results: [.success(49_321), .success(49_322)])
        let bridge = makeBridge(discovery: discovery, servers: servers)
        await bridge.start()
        let first = try XCTUnwrap(discovery.records.last?.launchID)
        bridge.stop()
        await bridge.start()
        let second = try XCTUnwrap(discovery.records.last?.launchID)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(servers.createdCount, 2)
        XCTAssertEqual(bridge.health.port, 49_322)
    }

    func testCredentialFailureDoesNotStartOrPublishAndNeverDowngradesAuthentication() async {
        let discovery = DiscoverySpy()
        let servers = ServerFactorySpy(results: [.success(49_321)])
        let bridge = AgentBridge(
            eventStore: AgentEventStore(),
            credentialStore: FixedAgentBridgeCredentialStore(secret: nil),
            discoveryPublisher: discovery,
            codexDiscoveryPublisher: DiscoverySpy(),
            claudeDiscoveryPublisher: DiscoverySpy(),
            serverFactory: servers.factory
        )
        await bridge.start()

        XCTAssertEqual(bridge.health.state, .failed)
        XCTAssertEqual(bridge.health.lastSafeError, "credential-unavailable")
        XCTAssertEqual(servers.createdCount, 0)
        XCTAssertTrue(discovery.records.isEmpty)
    }

    func testListenerFailureDoesNotPublishDiscovery() async {
        let discovery = DiscoverySpy()
        let servers = ServerFactorySpy(results: [.failure(.listenerFailed("safe"))])
        let bridge = makeBridge(discovery: discovery, servers: servers)
        await bridge.start()

        XCTAssertEqual(bridge.health.state, .failed)
        XCTAssertEqual(bridge.health.lastSafeError, "listener-unavailable")
        XCTAssertTrue(discovery.records.isEmpty)
        XCTAssertEqual(servers.stopCount, 1)
    }

    func testDiscoveryFailureStopsListenerAndLeavesBridgeFailed() async {
        let discovery = DiscoverySpy(publishError: AgentBridgeDiscoveryError.insecurePermissions)
        let servers = ServerFactorySpy(results: [.success(49_321)])
        let bridge = makeBridge(discovery: discovery, servers: servers)
        await bridge.start()

        XCTAssertEqual(bridge.health.state, .failed)
        XCTAssertEqual(bridge.health.lastSafeError, "discovery-unavailable")
        XCTAssertEqual(servers.stopCount, 1)
    }

    func testOldLaunchHandlerCannotMutateStoreAfterRestart() async throws {
        let store = AgentEventStore()
        let discovery = DiscoverySpy()
        let servers = ServerFactorySpy(results: [.success(49_321), .success(49_322)])
        let bridge = makeBridge(store: store, discovery: discovery, servers: servers)
        await bridge.start()
        let firstRecord = try XCTUnwrap(discovery.records.last)
        let firstHandler = try XCTUnwrap(servers.handlers.first)
        bridge.stop()
        await bridge.start()

        let body = try AgentBridgeTestSupport.body(
            producerID: firstRecord.producerID,
            event: AgentBridgeTestSupport.event()
        )
        let key = try XCTUnwrap(Data(base64Encoded: firstRecord.authenticationToken))
        let staleRequest = AgentBridgeTestSupport.signedRequest(
            body: body,
            key: key,
            timestamp: Int64(Date().timeIntervalSince1970),
            nonce: "old-launch"
        )
        let response = await firstHandler(staleRequest)

        XCTAssertEqual(response.status, .unprocessableContent)
        XCTAssertTrue(store.sessions.isEmpty)
        XCTAssertEqual(bridge.health.rejectedRequestCount, 0)
    }

    func testStopDuringListenerStartupCannotResurrectOrFailBridge() async {
        let discovery = DiscoverySpy()
        let server = DeferredServerSpy()
        let bridge = AgentBridge(
            eventStore: AgentEventStore(),
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: discovery,
            codexDiscoveryPublisher: DiscoverySpy(),
            claudeDiscoveryPublisher: DiscoverySpy(),
            serverFactory: { _ in server }
        )
        let startTask = Task { await bridge.start() }
        while server.startCount == 0 { await Task.yield() }

        bridge.stop()
        await startTask.value

        XCTAssertEqual(bridge.health.state, .stopped)
        XCTAssertNil(bridge.health.lastSafeError)
        XCTAssertTrue(discovery.records.isEmpty)
    }

    private func makeBridge(
        store: AgentEventStore = AgentEventStore(),
        discovery: DiscoverySpy,
        servers: ServerFactorySpy
    ) -> AgentBridge {
        AgentBridge(
            eventStore: store,
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: discovery,
            codexDiscoveryPublisher: DiscoverySpy(),
            claudeDiscoveryPublisher: DiscoverySpy(),
            serverFactory: servers.factory
        )
    }
}

private final class DiscoverySpy: AgentBridgeDiscoveryPublishing, @unchecked Sendable {
    let recordURL = URL(fileURLWithPath: "/private/test/bridge-v1.json")
    private let lock = NSLock()
    private let publishError: Error?
    private var storedRecords: [AgentBridgeDiscoveryRecord] = []
    private var storedRemovedLaunchIDs: [String] = []

    init(publishError: Error? = nil) {
        self.publishError = publishError
    }

    var records: [AgentBridgeDiscoveryRecord] { lock.withLock { storedRecords } }
    var removedLaunchIDs: [String] { lock.withLock { storedRemovedLaunchIDs } }

    func publish(_ record: AgentBridgeDiscoveryRecord) throws {
        if let publishError { throw publishError }
        lock.withLock { storedRecords.append(record) }
    }

    func removeIfOwned(launchID: String) throws {
        lock.withLock { storedRemovedLaunchIDs.append(launchID) }
    }
}

private final class ServerFactorySpy: @unchecked Sendable {
    private let lock = NSLock()
    private var results: [Result<UInt16, AgentBridgeNetworkError>]
    private var servers: [ServerSpy] = []

    init(results: [Result<UInt16, AgentBridgeNetworkError>]) {
        self.results = results
    }

    var createdCount: Int { lock.withLock { servers.count } }
    var startCount: Int { lock.withLock { servers.reduce(0) { $0 + $1.startCount } } }
    var stopCount: Int { lock.withLock { servers.reduce(0) { $0 + $1.stopCount } } }
    var handlers: [AgentBridgeNetworkServer.RequestHandler] { lock.withLock { servers.map(\.handler) } }

    var factory: AgentBridgeServerFactory {
        { [weak self] handler in
            guard let self else { return ServerSpy(handler: handler, result: .failure(.listenerCancelled)) }
            return self.lock.withLock {
                let result = self.results.isEmpty ? .failure(.listenerCancelled) : self.results.removeFirst()
                let server = ServerSpy(handler: handler, result: result)
                self.servers.append(server)
                return server
            }
        }
    }
}

private final class ServerSpy: AgentBridgeServing, @unchecked Sendable {
    let handler: AgentBridgeNetworkServer.RequestHandler
    private let result: Result<UInt16, AgentBridgeNetworkError>
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0

    init(
        handler: @escaping AgentBridgeNetworkServer.RequestHandler,
        result: Result<UInt16, AgentBridgeNetworkError>
    ) {
        self.handler = handler
        self.result = result
    }

    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }

    func start(completion: @escaping @Sendable (Result<UInt16, AgentBridgeNetworkError>) -> Void) {
        lock.withLock { starts += 1 }
        completion(result)
    }

    func stop() {
        lock.withLock { stops += 1 }
    }
}

private final class DeferredServerSpy: AgentBridgeServing, @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (@Sendable (Result<UInt16, AgentBridgeNetworkError>) -> Void)?
    private var starts = 0

    var startCount: Int { lock.withLock { starts } }

    func start(completion: @escaping @Sendable (Result<UInt16, AgentBridgeNetworkError>) -> Void) {
        lock.withLock {
            starts += 1
            self.completion = completion
        }
    }

    func stop() {
        let pending = lock.withLock {
            let pending = completion
            completion = nil
            return pending
        }
        pending?(.failure(.listenerCancelled))
    }
}
