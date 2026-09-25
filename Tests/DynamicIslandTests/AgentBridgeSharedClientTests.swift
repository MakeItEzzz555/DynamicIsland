import Foundation
import XCTest
@testable import AgentBridgeShared

final class AgentBridgeSharedClientTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    func testEnvelopeOverwritesCallerTransportIdentity() throws {
        let input = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 999,
            "producerID": "attacker",
            "event": ["eventID": "event-1"]
        ])
        let output = try AgentBridgeEnvelopeBuilder.build(input: input, producerID: "trusted")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertEqual(root["protocolVersion"] as? Int, 1)
        XCTAssertEqual(root["producerID"] as? String, "trusted")
    }

    func testEnvelopeRejectsOversizeInputAndTooManyEvents() throws {
        XCTAssertThrowsError(try AgentBridgeEnvelopeBuilder.build(
            input: Data(repeating: 1, count: AgentBridgeProtocol.maximumRequestBodyBytes + 1),
            producerID: "trusted"
        ))
        let events = (0...AgentBridgeProtocol.maximumBatchEvents).map { ["eventID": "event-\($0)"] }
        let input = try JSONSerialization.data(withJSONObject: ["events": events])
        XCTAssertThrowsError(try AgentBridgeEnvelopeBuilder.build(input: input, producerID: "trusted"))
    }

    func testValidBatchRetainsEventsAndUsesTrustedTransportIdentity() throws {
        let input = try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 999,
            "producerID": "caller",
            "events": [
                ["eventID": "event-1"],
                ["eventID": "event-2"]
            ]
        ])
        let output = try AgentBridgeEnvelopeBuilder.build(input: input, producerID: "trusted")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: output) as? [String: Any])
        XCTAssertEqual(root["protocolVersion"] as? Int, AgentBridgeProtocol.version)
        XCTAssertEqual(root["producerID"] as? String, "trusted")
        XCTAssertEqual((root["events"] as? [[String: Any]])?.count, 2)
    }

    func testValidEventIsSignedWithTrustedProfile() async throws {
        let profiles = SequenceProfileProvider(profiles: [profile(producerID: "trusted")])
        let transport = SequenceClientTransport(outcomes: [.response(.init(statusCode: 202, code: "accepted"))])
        let client = makeClient(profiles: profiles, transport: transport)
        let result = try await client.sendEvents(input: try eventInput(producerID: "attacker"))
        XCTAssertEqual(result, .accepted)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
        XCTAssertEqual(root["producerID"] as? String, "trusted")
        XCTAssertEqual(request.route, "/v1/events")
        XCTAssertNotNil(request.headers[AgentBridgeProtocol.signatureHeader])
    }

    func testHealthUsesAuthenticatedEmptyGet() async throws {
        let profiles = SequenceProfileProvider(profiles: [profile()])
        let transport = SequenceClientTransport(outcomes: [.response(.init(statusCode: 200, code: "healthy"))])
        let result = try await makeClient(profiles: profiles, transport: transport).health()
        XCTAssertEqual(result, .accepted)
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.route, "/v1/health")
        XCTAssertTrue(request.body.isEmpty)
    }

    func testUnavailableReloadsOnceAndRetriesOnlyWhenProfileChanged() async throws {
        let profiles = SequenceProfileProvider(profiles: [profile(launchID: "old"), profile(launchID: "new")])
        let transport = SequenceClientTransport(outcomes: [
            .failure(.unavailable),
            .response(.init(statusCode: 202, code: "accepted"))
        ])
        let result = try await makeClient(profiles: profiles, transport: transport)
            .sendEvents(input: try eventInput())
        XCTAssertEqual(result, .accepted)
        let profileLoads = await profiles.currentLoadCount()
        let requestCount = await transport.currentRequestCount()
        XCTAssertEqual(profileLoads, 2)
        XCTAssertEqual(requestCount, 2)
    }

    func testSameProfileDoesNotRetryAndSemanticRejectionNeverReloads() async throws {
        let same = profile()
        let unavailableProfiles = SequenceProfileProvider(profiles: [same, same])
        let unavailableTransport = SequenceClientTransport(outcomes: [.failure(.unavailable)])
        do {
            _ = try await self.makeClient(profiles: unavailableProfiles, transport: unavailableTransport)
                .sendEvents(input: try self.eventInput())
            XCTFail("Expected unavailable transport")
        } catch {
            XCTAssertEqual(error as? AgentBridgeClientError, .transportUnavailable)
        }
        let unavailableCount = await unavailableTransport.currentRequestCount()
        XCTAssertEqual(unavailableCount, 1)

        let semanticProfiles = SequenceProfileProvider(profiles: [same])
        let semanticTransport = SequenceClientTransport(outcomes: [
            .response(.init(statusCode: 422, code: "semanticValidation"))
        ])
        let result = try await makeClient(profiles: semanticProfiles, transport: semanticTransport)
            .sendEvents(input: try eventInput())
        XCTAssertEqual(result, .rejected(statusCode: 422, code: "semanticValidation"))
        let semanticLoads = await semanticProfiles.currentLoadCount()
        let semanticCount = await semanticTransport.currentRequestCount()
        XCTAssertEqual(semanticLoads, 1)
        XCTAssertEqual(semanticCount, 1)
    }

    func testTimeoutIsBoundedFailureWithoutRetry() async throws {
        let profiles = SequenceProfileProvider(profiles: [profile()])
        let transport = SequenceClientTransport(outcomes: [.failure(.requestTimedOut)])
        do {
            _ = try await makeClient(profiles: profiles, transport: transport)
                .sendEvents(input: try eventInput())
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(error as? AgentBridgeClientError, .timedOut)
        }
        let requestCount = await transport.currentRequestCount()
        XCTAssertEqual(requestCount, 1)
    }

    private func makeClient(
        profiles: SequenceProfileProvider,
        transport: SequenceClientTransport
    ) -> AgentBridgeClient {
        AgentBridgeClient(
            profiles: profiles,
            transport: transport,
            now: { Date(timeIntervalSince1970: 2_000_000_000) },
            nonce: { "nonce-fixed" }
        )
    }

    private func profile(
        launchID: String = "launch",
        producerID: String = "producer"
    ) -> AgentBridgeClientProfile {
        AgentBridgeClientProfile(
            host: "127.0.0.1",
            port: 49_321,
            protocolVersion: 1,
            launchID: launchID,
            producerID: producerID,
            authenticationKey: Data(repeating: 0x24, count: 32)
        )
    }

    private func eventInput(producerID: String = "caller") throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "protocolVersion": 1,
            "producerID": producerID,
            "event": ["eventID": "event-1"]
        ])
    }
}

private actor SequenceProfileProvider: AgentBridgeClientProfileProviding {
    private let profiles: [AgentBridgeClientProfile]
    private var index = 0
    private(set) var loadCount = 0

    init(profiles: [AgentBridgeClientProfile]) { self.profiles = profiles }

    func loadProfile() throws -> AgentBridgeClientProfile {
        loadCount += 1
        let selected = profiles[min(index, profiles.count - 1)]
        index += 1
        return selected
    }

    func currentLoadCount() -> Int { loadCount }
}

private actor SequenceClientTransport: AgentBridgeClientTransport {
    enum Outcome: Sendable {
        case response(AgentBridgeClientResponse)
        case failure(AgentBridgeClientTransportError)
    }

    private var outcomes: [Outcome]
    private var requests: [AgentBridgeClientRequest] = []

    init(outcomes: [Outcome]) { self.outcomes = outcomes }

    func send(
        _ request: AgentBridgeClientRequest,
        profile: AgentBridgeClientProfile,
        connectTimeout: Duration,
        requestTimeout: Duration
    ) throws -> AgentBridgeClientResponse {
        requests.append(request)
        let outcome = outcomes.removeFirst()
        switch outcome {
        case .response(let response): return response
        case .failure(let error): throw error
        }
    }

    func recordedRequests() -> [AgentBridgeClientRequest] { requests }
    func currentRequestCount() -> Int { requests.count }
}
