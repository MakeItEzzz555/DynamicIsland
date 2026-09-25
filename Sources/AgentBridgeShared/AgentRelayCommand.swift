import Foundation

package enum AgentRelayExitCode: Int32, Equatable, Sendable {
    case accepted = 0
    case usage = 2
    case invalidInput = 3
    case discoveryUnavailable = 4
    case bridgeUnavailable = 5
    case authenticationFailed = 6
    case serverRejected = 7
    case temporaryFailure = 8
}

package struct AgentRelayCommandResult: Equatable, Sendable {
    package let exitCode: AgentRelayExitCode
    package let standardOutput: String
    package let standardError: String

    package init(
        exitCode: AgentRelayExitCode,
        standardOutput: String = "",
        standardError: String = ""
    ) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

package struct AgentRelayCommand: Sendable {
    private let client: AgentBridgeClient

    package init(client: AgentBridgeClient) {
        self.client = client
    }

    package func run(arguments: [String], standardInput: Data) async -> AgentRelayCommandResult {
        guard arguments.count == 1 else { return Self.usage }
        switch arguments[0] {
        case "send-event":
            guard standardInput.count <= AgentBridgeProtocol.maximumRequestBodyBytes else {
                return AgentRelayCommandResult(exitCode: .invalidInput, standardError: "invalid-input\n")
            }
            return await map { try await client.sendEvents(input: standardInput) }
        case "health":
            guard standardInput.isEmpty else { return Self.usage }
            return await map { try await client.health() }
        default:
            return Self.usage
        }
    }

    private func map(
        _ operation: () async throws -> AgentBridgeClientResult
    ) async -> AgentRelayCommandResult {
        do {
            let result = try await operation()
            switch result {
            case .accepted:
                return AgentRelayCommandResult(exitCode: .accepted, standardOutput: "accepted\n")
            case .rejected(let status, _):
                return AgentRelayCommandResult(
                    exitCode: .serverRejected,
                    standardError: "server-rejected:\(status)\n"
                )
            }
        } catch let error as AgentBridgeClientError {
            switch error {
            case .invalidInput:
                return AgentRelayCommandResult(exitCode: .invalidInput, standardError: "invalid-input\n")
            case .discoveryUnavailable:
                return AgentRelayCommandResult(
                    exitCode: .discoveryUnavailable,
                    standardError: "discovery-unavailable\n"
                )
            case .authenticationFailed:
                return AgentRelayCommandResult(
                    exitCode: .authenticationFailed,
                    standardError: "authentication-failed\n"
                )
            case .transportUnavailable:
                return AgentRelayCommandResult(
                    exitCode: .bridgeUnavailable,
                    standardError: "bridge-unavailable\n"
                )
            case .timedOut, .malformedResponse:
                return AgentRelayCommandResult(
                    exitCode: .temporaryFailure,
                    standardError: "temporary-failure\n"
                )
            }
        } catch {
            return AgentRelayCommandResult(exitCode: .temporaryFailure, standardError: "temporary-failure\n")
        }
    }

    private static let usage = AgentRelayCommandResult(
        exitCode: .usage,
        standardError: "usage: DynamicIslandAgentRelay <send-event|health>\n"
    )
}

package enum AgentRelayStandardInput {
    package static func readBounded(
        from handle: FileHandle = .standardInput,
        maximumBytes: Int = AgentBridgeProtocol.maximumRequestBodyBytes
    ) throws -> Data {
        var data = Data()
        while true {
            let remaining = maximumBytes - data.count
            let chunk = try handle.read(upToCount: min(64 * 1_024, remaining + 1)) ?? Data()
            guard !chunk.isEmpty else { break }
            guard chunk.count <= remaining else { throw AgentBridgeEnvelopeBuildError.inputTooLarge }
            data.append(chunk)
        }
        return data
    }
}
