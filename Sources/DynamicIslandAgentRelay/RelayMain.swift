import AgentBridgeShared
import Darwin
import Foundation

@main
struct DynamicIslandAgentRelayMain {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments == ["send-event"] || arguments == ["health"] else {
            write("usage: DynamicIslandAgentRelay <send-event|health>\n", to: .standardError)
            exit(AgentRelayExitCode.usage.rawValue)
        }
        let input: Data
        do {
            input = arguments == ["send-event"]
                ? try AgentRelayStandardInput.readBounded()
                : Data()
        } catch {
            write("invalid-input\n", to: .standardError)
            exit(AgentRelayExitCode.invalidInput.rawValue)
        }

        let reader: AgentBridgeDiscoveryReader
        do {
            reader = try AgentBridgeDiscoveryReader()
        } catch {
            write("discovery-unavailable\n", to: .standardError)
            exit(AgentRelayExitCode.discoveryUnavailable.rawValue)
        }
        let command = AgentRelayCommand(client: AgentBridgeClient(profiles: reader))
        let result = await command.run(arguments: arguments, standardInput: input)
        if !result.standardOutput.isEmpty { write(result.standardOutput, to: .standardOutput) }
        if !result.standardError.isEmpty { write(result.standardError, to: .standardError) }
        exit(result.exitCode.rawValue)
    }

    private static func write(_ value: String, to handle: FileHandle) {
        try? handle.write(contentsOf: Data(value.utf8))
    }
}
