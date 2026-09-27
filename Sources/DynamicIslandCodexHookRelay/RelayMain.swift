import AgentBridgeShared
import CodexHookShared
import Darwin
import Foundation

@main
struct DynamicIslandCodexHookRelayMain {
    static func main() async {
        // Observation hooks remain asynchronous/fail-open. PermissionRequest is
        // the sole synchronous path because Codex consumes its stdout decision.
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

        let isPermissionRequest = CodexHookNormalizer.hookEventName(raw) == "PermissionRequest"
        guard let profileURL = codexProfileURL(permissionControl: isPermissionRequest),
              let reader = try? AgentBridgeDiscoveryReader(recordURL: profileURL) else {
            exit(0)
        }

        let client = AgentBridgeClient(profiles: reader)
        if isPermissionRequest {
            if let decision = try? await client.requestCodexPermission(input: normalized),
               let output = CodexPermissionHookOutput.encode(decision) {
                try? FileHandle.standardOutput.write(contentsOf: output)
            }
        } else {
            _ = try? await client.sendEvents(input: normalized)
        }
        exit(0)
    }

    private static func codexProfileURL(permissionControl: Bool) -> URL? {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return applicationSupport
            .appendingPathComponent("DynamicIsland", isDirectory: true)
            .appendingPathComponent("AgentBridge", isDirectory: true)
            .appendingPathComponent(permissionControl ? "codex-permission-v1.json" : "codex-hook-v1.json")
    }
}
