import Foundation

struct AgentSourceOpenTarget: Equatable, Sendable {
    let displayName: String
    let bundleIdentifier: String
}

/// Resolves an app-focus action only from source identity that the ingestion
/// layer has already marked as verified. Project paths, foreground apps and
/// display names never create an action on their own.
enum AgentSourceAssociationResolver {
    private static let terminalBundles: [String: String] = [
        "com.apple.Terminal": "Terminal",
        "com.googlecode.iterm2": "iTerm2"
    ]

    private static let editorBundles: [String: String] = [
        "com.microsoft.VSCode": "Visual Studio Code",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "co.anysphere.cursor.nightly": "Cursor Nightly"
    ]

    private static let desktopAgentBundles: [String: String] = [
        "com.openai.codex": "Codex",
        "com.anthropic.claudefordesktop": "Claude"
    ]

    static func openTarget(for session: AgentSession) -> AgentSourceOpenTarget? {
        guard session.capabilities.contains(.verifiedSourceIdentity),
              session.capabilities.contains(.sourceAppOpen),
              let app = session.project.sourceApplication,
              let bundleID = normalizedBundleIdentifier(app.bundleIdentifier) else {
            return nil
        }

        switch session.source {
        case .terminal:
            guard let name = terminalBundles[bundleID] else { return nil }
            return AgentSourceOpenTarget(displayName: name, bundleIdentifier: bundleID)

        case .vscode:
            guard let name = editorBundles[bundleID] else { return nil }
            return AgentSourceOpenTarget(displayName: name, bundleIdentifier: bundleID)

        case .jetbrains:
            guard bundleID.hasPrefix("com.jetbrains."),
                  bundleID.count <= 128 else { return nil }
            let suppliedName = app.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = suppliedName.isEmpty
                ? "JetBrains"
                : String(suppliedName.prefix(80))
            return AgentSourceOpenTarget(displayName: displayName, bundleIdentifier: bundleID)

        case .desktopApp:
            guard let name = desktopAgentBundles[bundleID] else { return nil }
            return AgentSourceOpenTarget(displayName: name, bundleIdentifier: bundleID)

        case .cloud, .mcp, .unknown:
            return nil
        }
    }

    private static func normalizedBundleIdentifier(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= 128,
              trimmed.unicodeScalars.allSatisfy({
                  $0.isASCII &&
                  (CharacterSet.alphanumerics.contains($0) ||
                   $0 == "." || $0 == "-")
              }) else {
            return nil
        }
        return trimmed
    }
}
