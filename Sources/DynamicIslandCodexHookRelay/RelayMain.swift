import AgentBridgeShared
import CodexHookShared
import Darwin
import Foundation

@main
struct DynamicIslandCodexHookRelayMain {
    static func main() async {
        // Observability hooks must never block Codex. Every integration failure
        // is therefore fail-open with a zero exit status.
        guard CommandLine.arguments.count == 1 else { exit(0) }

        let raw: Data
        do {
            raw = try CodexHookStandardInput.readBounded()
        } catch {
            exit(0)
        }

        let normalized: Data
        do {
            normalized = try CodexHookNormalizer.normalize(raw)
        } catch {
            exit(0)
        }

        guard let profileURL = codexProfileURL(),
              let reader = try? AgentBridgeDiscoveryReader(recordURL: profileURL) else {
            exit(0)
        }

        let client = AgentBridgeClient(profiles: reader)
        _ = try? await client.sendEvents(input: normalized)
        exit(0)
    }

    private static func codexProfileURL() -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("AgentBridge", isDirectory: true)
            .appendingPathComponent("codex-hook-v1.json")
    }
}
