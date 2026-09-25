import AgentBridgeShared
import ClaudeHookShared
import Darwin
import Foundation

@main
struct DynamicIslandClaudeHookRelayMain {
    static func main() async {
        // Observability must never block Claude Code. Malformed input or a
        // missing DynamicIsland bridge therefore fail open with exit status 0.
        guard CommandLine.arguments.count == 1 else { exit(0) }

        let raw: Data
        do {
            raw = try ClaudeHookStandardInput.readBounded()
        } catch {
            exit(0)
        }

        let normalized: Data
        do {
            normalized = try ClaudeHookNormalizer.normalize(raw)
        } catch {
            exit(0)
        }

        guard let profileURL = claudeProfileURL(),
              let reader = try? AgentBridgeDiscoveryReader(recordURL: profileURL) else {
            exit(0)
        }

        let client = AgentBridgeClient(profiles: reader)
        _ = try? await client.sendEvents(input: normalized)
        exit(0)
    }

    private static func claudeProfileURL() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("AgentBridge", isDirectory: true)
            .appendingPathComponent("claude-hook-v1.json")
    }
}
