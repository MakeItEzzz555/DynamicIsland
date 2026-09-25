import AgentBridgeShared
import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class AgentBridgeNetworkTests: XCTestCase {
    func testRealListenerUsesLoopbackEphemeralPortAndIngestsSignedEvent() async throws {
        let (directory, recordURL) = makePaths()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AgentEventStore()
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        let bridge = AgentBridge(
            eventStore: store,
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: publisher,
            codexDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("codex-hook-v1.json")
            ),
            claudeDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("claude-hook-v1.json")
            )
        )
        await bridge.start()
        defer { bridge.stop() }

        XCTAssertEqual(bridge.health.state, .running)
        let record = try decodeRecord(at: recordURL)
        XCTAssertEqual(record.host, "127.0.0.1")
        XCTAssertGreaterThan(record.port, 0)
        let body = try AgentBridgeTestSupport.body(
            producerID: record.producerID,
            event: AgentBridgeTestSupport.event()
        )
        let key = try XCTUnwrap(Data(base64Encoded: record.authenticationToken))
        let response = try await send(
            AgentBridgeTestSupport.signedRequest(
                body: body,
                key: key,
                timestamp: Int64(Date().timeIntervalSince1970),
                nonce: "network-event"
            ),
            to: record
        )

        XCTAssertEqual(response.statusCode, AgentBridgeHTTPStatus.accepted.rawValue)
        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.id.sessionID.provider, .other("unverified"))
    }

    func testCleanStopRemovesRealOwnedDiscoveryRecord() async throws {
        let (directory, recordURL) = makePaths()
        defer { try? FileManager.default.removeItem(at: directory) }
        let publisher = try AgentBridgeDiscoveryPublisher(recordURL: recordURL)
        let bridge = AgentBridge(
            eventStore: AgentEventStore(),
            credentialStore: FixedAgentBridgeCredentialStore(secret: AgentBridgeTestSupport.secret),
            discoveryPublisher: publisher,
            codexDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("codex-hook-v1.json")
            ),
            claudeDiscoveryPublisher: try AgentBridgeDiscoveryPublisher(
                recordURL: directory.appendingPathComponent("claude-hook-v1.json")
            )
        )
        await bridge.start()
        XCTAssertTrue(FileManager.default.fileExists(atPath: recordURL.path))
        bridge.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
    }

    private func makePaths() -> (URL, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DynamicIsland-AgentBridge-Network-\(UUID().uuidString)", isDirectory: true)
        return (directory, directory.appendingPathComponent("bridge-v1.json"))
    }

    private func decodeRecord(at recordURL: URL) throws -> AgentBridgeDiscoveryRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(AgentBridgeDiscoveryRecord.self, from: Data(contentsOf: recordURL))
    }

    private func send(
        _ request: AgentBridgeHTTPRequest,
        to record: AgentBridgeDiscoveryRecord
    ) async throws -> HTTPURLResponse {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(record.port)\(request.route)"))
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await URLSession.shared.data(for: urlRequest)
        return try XCTUnwrap(response as? HTTPURLResponse)
    }
}
