import Foundation
import XCTest
@testable import AgentBridgeShared

final class AgentRelayCommandTests: XCTestCase {
    func testStableExitCodeValues() {
        XCTAssertEqual(AgentRelayExitCode.accepted.rawValue, 0)
        XCTAssertEqual(AgentRelayExitCode.usage.rawValue, 2)
        XCTAssertEqual(AgentRelayExitCode.invalidInput.rawValue, 3)
        XCTAssertEqual(AgentRelayExitCode.discoveryUnavailable.rawValue, 4)
        XCTAssertEqual(AgentRelayExitCode.bridgeUnavailable.rawValue, 5)
        XCTAssertEqual(AgentRelayExitCode.authenticationFailed.rawValue, 6)
        XCTAssertEqual(AgentRelayExitCode.serverRejected.rawValue, 7)
        XCTAssertEqual(AgentRelayExitCode.temporaryFailure.rawValue, 8)
    }

    func testAcceptedOutputIsMinimalAndContainsNoCredentialOrBody() async throws {
        let secret = Data(repeating: 0x24, count: 32)
        let command = AgentRelayCommand(client: AgentBridgeClient(
            profiles: RelayProfileProvider(secret: secret),
            transport: RelayTransport(response: .init(statusCode: 202, code: "accepted")),
            now: { Date(timeIntervalSince1970: 2_000_000_000) },
            nonce: { "nonce" }
        ))
        let input = try JSONSerialization.data(withJSONObject: [
            "event": ["eventID": "private-body-marker"]
        ])
        let result = await command.run(arguments: ["send-event"], standardInput: input)
        XCTAssertEqual(result, .init(exitCode: .accepted, standardOutput: "accepted\n"))
        XCTAssertFalse(result.standardOutput.contains(secret.base64EncodedString()))
        XCTAssertFalse(result.standardOutput.contains("private-body-marker"))
    }

    func testUsageInvalidInputAuthenticationAndSemanticExitCategories() async throws {
        let usage = await command(status: 202).run(arguments: [], standardInput: Data())
        XCTAssertEqual(usage.exitCode, .usage)

        let invalid = await command(status: 202).run(
            arguments: ["send-event"],
            standardInput: Data("not-json".utf8)
        )
        XCTAssertEqual(invalid.exitCode, .invalidInput)

        let auth = await command(status: 401).run(
            arguments: ["send-event"],
            standardInput: try validInput()
        )
        XCTAssertEqual(auth.exitCode, .authenticationFailed)

        let semantic = await command(status: 422).run(
            arguments: ["send-event"],
            standardInput: try validInput()
        )
        XCTAssertEqual(semantic.exitCode, .serverRejected)
        XCTAssertEqual(semantic.standardError, "server-rejected:422\n")
    }

    func testHealthRejectsUnexpectedInput() async {
        let result = await command(status: 200).run(
            arguments: ["health"],
            standardInput: Data("unexpected".utf8)
        )
        XCTAssertEqual(result.exitCode, .usage)
    }

    func testStandardInputReaderRejectsMoreThanBoundWithoutUnboundedRead() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentRelayInput-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 1, count: 33).write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        XCTAssertThrowsError(try AgentRelayStandardInput.readBounded(from: handle, maximumBytes: 32))
    }

    private func command(status: Int) -> AgentRelayCommand {
        AgentRelayCommand(client: AgentBridgeClient(
            profiles: RelayProfileProvider(secret: Data(repeating: 0x24, count: 32)),
            transport: RelayTransport(response: .init(statusCode: status, code: "bounded-code")),
            now: { Date(timeIntervalSince1970: 2_000_000_000) },
            nonce: { "nonce" }
        ))
    }

    private func validInput() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["event": ["eventID": "event-1"]])
    }
}

private struct RelayProfileProvider: AgentBridgeClientProfileProviding {
    let secret: Data
    func loadProfile() -> AgentBridgeClientProfile {
        AgentBridgeClientProfile(
            host: "127.0.0.1",
            port: 49_321,
            protocolVersion: 1,
            launchID: "launch",
            producerID: "producer",
            authenticationKey: secret
        )
    }
}

private struct RelayTransport: AgentBridgeClientTransport {
    let response: AgentBridgeClientResponse
    func send(
        _ request: AgentBridgeClientRequest,
        profile: AgentBridgeClientProfile,
        connectTimeout: Duration,
        requestTimeout: Duration
    ) async throws -> AgentBridgeClientResponse { response }
}
