import Combine
import CryptoKit
import Darwin
import Foundation

enum AgentIntegrationProvider: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        }
    }

    var helperExecutableName: String {
        switch self {
        case .codex: "DynamicIslandCodexHookRelay"
        case .claude: "DynamicIslandClaudeHookRelay"
        }
    }

    var desiredEvents: [String] {
        switch self {
        case .codex:
            [
                "SessionStart", "SessionEnd", "UserPromptSubmit",
                "PreToolUse", "PermissionRequest", "PostToolUse",
                "Stop", "Interrupt", "SubagentStart", "SubagentStop"
            ]
        case .claude:
            [
                "SessionStart", "SessionEnd", "UserPromptSubmit",
                "PreToolUse", "PermissionRequest", "PostToolUse",
                "PostToolUseFailure", "PermissionDenied",
                "Elicitation", "ElicitationResult",
                "SubagentStart", "SubagentStop",
                "Stop", "StopFailure", "CwdChanged"
            ]
        }
    }

    var synchronousEvents: Set<String> {
        // Session teardown must be observed before the provider process exits.
        ["SessionEnd"]
    }
}

enum AgentIntegrationSetupState: Equatable, Sendable {
    case needsSetup
    case configured
    case repairRequired
    case helperUnavailable
    case blocked(String)

    var label: String {
        switch self {
        case .needsSetup: "Not configured"
        case .configured: "Configured"
        case .repairRequired: "Repair required"
        case .helperUnavailable: "Helper unavailable"
        case .blocked: "Needs manual setup"
        }
    }
}

struct AgentIntegrationSetupSnapshot: Equatable, Sendable {
    let provider: AgentIntegrationProvider
    let state: AgentIntegrationSetupState
    let configPath: String
    let backupAvailable: Bool
    let detail: String
}

struct AgentIntegrationSetupPreview: Equatable, Sendable {
    let provider: AgentIntegrationProvider
    let configPath: String
    let text: String
}

enum AgentIntegrationSetupError: Error, Equatable, Sendable {
    case helperUnavailable
    case unsafePath
    case fileTooLarge
    case invalidJSON
    case invalidHooks
    case readOnly
    case changedExternally
    case backupUnavailable
    case backupInvalid
    case writeFailed
}

struct AgentIntegrationSetupPaths: Sendable {
    let homeDirectory: URL
    let applicationSupportDirectory: URL
    let appBundleURL: URL

    static func production() -> AgentIntegrationSetupPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Library/Application Support", isDirectory: true)
        return AgentIntegrationSetupPaths(
            homeDirectory: home,
            applicationSupportDirectory: support,
            appBundleURL: Bundle.main.bundleURL
        )
    }

    func configURL(for provider: AgentIntegrationProvider) -> URL {
        switch provider {
        case .codex:
            homeDirectory.appendingPathComponent(".codex/hooks.json")
        case .claude:
            homeDirectory.appendingPathComponent(".claude/settings.json")
        }
    }

    func helperURL(for provider: AgentIntegrationProvider) -> URL {
        appBundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(provider.helperExecutableName)
    }

    func backupURL(for provider: AgentIntegrationProvider) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("DynamicIsland/AgentIntegrationBackups", isDirectory: true)
            .appendingPathComponent(provider.rawValue + "-hooks-backup-v1.json")
    }
}

enum AgentHookConfigurationPlanner {
    static let maximumConfigBytes = 1_048_576

    static func install(
        existing: Data?,
        provider: AgentIntegrationProvider,
        helperURL: URL
    ) throws -> Data {
        var root = try rootObject(existing)
        var hooks = try hooksObject(root["hooks"])
        let command = shellQuote(helperURL.path)

        for event in provider.desiredEvents {
            var groups = hooks[event] as? [Any] ?? []
            groups = removingOwnedHandlers(groups, provider: provider)
            groups.append(ownedMatcherGroup(provider: provider, event: event, command: command))
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try encoded(root)
    }

    static func remove(
        existing: Data,
        provider: AgentIntegrationProvider
    ) throws -> Data {
        var root = try rootObject(existing)
        guard root["hooks"] != nil else { return existing }
        var hooks = try hooksObject(root["hooks"])

        for key in Array(hooks.keys) {
            guard let groups = hooks[key] as? [Any] else { continue }
            let cleaned = removingOwnedHandlers(groups, provider: provider)
            if cleaned.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = cleaned
            }
        }

        if hooks.isEmpty {
            root.removeValue(forKey: "hooks")
        } else {
            root["hooks"] = hooks
        }
        return try encoded(root)
    }

    static func configurationState(
        existing: Data?,
        provider: AgentIntegrationProvider,
        helperURL: URL
    ) throws -> AgentIntegrationSetupState {
        guard let existing else { return .needsSetup }
        let root = try rootObject(existing)
        guard let rawHooks = root["hooks"] else { return .needsSetup }
        let hooks = try hooksObject(rawHooks)
        let exactCommand = shellQuote(helperURL.path)
        var exactEvents = Set<String>()
        var hasOwnedHandler = false

        for (event, rawGroups) in hooks {
            guard let groups = rawGroups as? [Any] else { continue }
            for case let group as [String: Any] in groups {
                guard let handlers = group["hooks"] as? [Any] else { continue }
                for case let handler as [String: Any] in handlers {
                    guard let command = handler["command"] as? String else { continue }
                    if isOwnedCommand(command, provider: provider) {
                        hasOwnedHandler = true
                        if command == exactCommand {
                            exactEvents.insert(event)
                        }
                    }
                }
            }
        }

        let desired = Set(provider.desiredEvents)
        if exactEvents.isSuperset(of: desired) { return .configured }
        return hasOwnedHandler ? .repairRequired : .needsSetup
    }

    static func preview(
        provider: AgentIntegrationProvider,
        helperURL: URL,
        configURL: URL
    ) throws -> AgentIntegrationSetupPreview {
        let command = shellQuote(helperURL.path)
        var additions: [String: Any] = [:]
        for event in provider.desiredEvents {
            additions[event] = [ownedMatcherGroup(provider: provider, event: event, command: command)]
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["hooks": additions],
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        guard let body = String(data: data, encoding: .utf8) else {
            throw AgentIntegrationSetupError.invalidJSON
        }
        return AgentIntegrationSetupPreview(
            provider: provider,
            configPath: configURL.path,
            text: "DynamicIsland will merge these observer hooks into \(configURL.path). Existing unrelated keys and hook handlers are preserved.\n\n" + body
        )
    }

    static func isOwnedCommand(_ command: String, provider: AgentIntegrationProvider) -> Bool {
        let name = provider.helperExecutableName
        return command.contains("/Contents/Helpers/" + name) ||
            command == name ||
            command.hasSuffix("/" + name + "'") ||
            command.hasSuffix("/" + name + "\"")
    }

    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func rootObject(_ data: Data?) throws -> [String: Any] {
        guard let data else { return [:] }
        guard data.count <= maximumConfigBytes else { throw AgentIntegrationSetupError.fileTooLarge }
        guard !data.isEmpty else { return [:] }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw AgentIntegrationSetupError.invalidJSON
        }
        guard let root = object as? [String: Any] else {
            throw AgentIntegrationSetupError.invalidJSON
        }
        return root
    }

    private static func hooksObject(_ raw: Any?) throws -> [String: Any] {
        guard let raw else { return [:] }
        guard let hooks = raw as? [String: Any] else {
            throw AgentIntegrationSetupError.invalidHooks
        }
        return hooks
    }

    private static func ownedMatcherGroup(
        provider: AgentIntegrationProvider,
        event: String,
        command: String
    ) -> [String: Any] {
        var handler: [String: Any] = [
            "type": "command",
            "command": command
        ]
        if provider.synchronousEvents.contains(event) {
            // Codex timeout units are seconds. Claude command-hook timeout units
            // are also seconds for hook handlers.
            handler["timeout"] = 3
        } else {
            // Observation-only hooks cannot block, approve or rewrite provider behavior.
            handler["async"] = true
        }
        return ["hooks": [handler]]
    }

    private static func removingOwnedHandlers(
        _ groups: [Any],
        provider: AgentIntegrationProvider
    ) -> [Any] {
        var output: [Any] = []
        output.reserveCapacity(groups.count)

        for rawGroup in groups {
            guard var group = rawGroup as? [String: Any],
                  let rawHandlers = group["hooks"] as? [Any] else {
                output.append(rawGroup)
                continue
            }
            let kept = rawHandlers.filter { rawHandler in
                guard let handler = rawHandler as? [String: Any],
                      let command = handler["command"] as? String else {
                    return true
                }
                return !isOwnedCommand(command, provider: provider)
            }
            guard !kept.isEmpty else { continue }
            group["hooks"] = kept
            output.append(group)
        }
        return output
    }

    private static func encoded(_ object: [String: Any]) throws -> Data {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw AgentIntegrationSetupError.invalidJSON
        }
        do {
            let data = try JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            guard data.count <= maximumConfigBytes else {
                throw AgentIntegrationSetupError.fileTooLarge
            }
            return data
        } catch let error as AgentIntegrationSetupError {
            throw error
        } catch {
            throw AgentIntegrationSetupError.invalidJSON
        }
    }
}

private struct AgentIntegrationBackupEnvelope: Codable, Sendable {
    let version: Int
    let provider: String
    let targetPath: String
    let originalExisted: Bool
    let originalDataBase64: String?
    let originalPermissions: Int?
    let installedDigest: String
}

struct AgentIntegrationSetupService: Sendable {
    private let paths: AgentIntegrationSetupPaths
    private let fileManager: FileManager

    init(
        paths: AgentIntegrationSetupPaths = .production(),
        fileManager: FileManager = .default
    ) {
        self.paths = paths
        self.fileManager = fileManager
    }

    func snapshot(for provider: AgentIntegrationProvider) -> AgentIntegrationSetupSnapshot {
        let config = paths.configURL(for: provider)
        let helper = paths.helperURL(for: provider)
        do {
            guard fileManager.isExecutableFile(atPath: helper.path) else {
                return snapshot(provider, .helperUnavailable, "The bundled helper is not available in this app build.")
            }
            let data = try secureReadIfPresent(config)
            let state = try AgentHookConfigurationPlanner.configurationState(
                existing: data,
                provider: provider,
                helperURL: helper
            )
            let detail: String
            switch state {
            case .configured:
                detail = "Observer hooks point to this DynamicIsland app bundle."
            case .repairRequired:
                detail = "DynamicIsland hooks exist but reference a different app location or incomplete event set."
            case .needsSetup:
                detail = "No DynamicIsland observer hooks are configured."
            case .helperUnavailable:
                detail = "Bundled helper unavailable."
            case .blocked(let message):
                detail = message
            }
            return snapshot(provider, state, detail)
        } catch let error as AgentIntegrationSetupError {
            return snapshot(provider, .blocked(error.safeDescription), error.safeDescription)
        } catch {
            return snapshot(provider, .blocked("Configuration could not be inspected safely."), "Configuration could not be inspected safely.")
        }
    }

    func preview(for provider: AgentIntegrationProvider) throws -> AgentIntegrationSetupPreview {
        let helper = paths.helperURL(for: provider)
        guard fileManager.isExecutableFile(atPath: helper.path) else {
            throw AgentIntegrationSetupError.helperUnavailable
        }
        _ = try secureReadIfPresent(paths.configURL(for: provider))
        return try AgentHookConfigurationPlanner.preview(
            provider: provider,
            helperURL: helper,
            configURL: paths.configURL(for: provider)
        )
    }

    func apply(_ provider: AgentIntegrationProvider) throws -> AgentIntegrationSetupSnapshot {
        let target = paths.configURL(for: provider)
        let helper = paths.helperURL(for: provider)
        guard fileManager.isExecutableFile(atPath: helper.path) else {
            throw AgentIntegrationSetupError.helperUnavailable
        }

        let before = try secureReadIfPresent(target)
        let beforeDigest = before.map(digest)
        let installed = try AgentHookConfigurationPlanner.install(
            existing: before,
            provider: provider,
            helperURL: helper
        )
        let originalPermissions = try existingPermissions(target)
        let backup = AgentIntegrationBackupEnvelope(
            version: 1,
            provider: provider.rawValue,
            targetPath: target.path,
            originalExisted: before != nil,
            originalDataBase64: before?.base64EncodedString(),
            originalPermissions: originalPermissions,
            installedDigest: digest(installed)
        )

        try writeBackup(backup, to: paths.backupURL(for: provider))
        try secureWrite(
            installed,
            to: target,
            expectedExistingDigest: beforeDigest,
            permissions: originalPermissions ?? 0o600
        )
        return snapshot(for: provider)
    }

    func remove(_ provider: AgentIntegrationProvider) throws -> AgentIntegrationSetupSnapshot {
        let target = paths.configURL(for: provider)
        guard let before = try secureReadIfPresent(target) else {
            return snapshot(for: provider)
        }
        let updated = try AgentHookConfigurationPlanner.remove(existing: before, provider: provider)
        guard updated != before else { return snapshot(for: provider) }
        try secureWrite(
            updated,
            to: target,
            expectedExistingDigest: digest(before),
            permissions: try existingPermissions(target) ?? 0o600
        )
        return snapshot(for: provider)
    }

    func rollback(_ provider: AgentIntegrationProvider) throws -> AgentIntegrationSetupSnapshot {
        let backupURL = paths.backupURL(for: provider)
        guard let backupData = try secureReadIfPresent(backupURL) else {
            throw AgentIntegrationSetupError.backupUnavailable
        }
        let backup: AgentIntegrationBackupEnvelope
        do {
            backup = try JSONDecoder().decode(AgentIntegrationBackupEnvelope.self, from: backupData)
        } catch {
            throw AgentIntegrationSetupError.backupInvalid
        }
        let target = paths.configURL(for: provider)
        guard backup.version == 1,
              backup.provider == provider.rawValue,
              backup.targetPath == target.path else {
            throw AgentIntegrationSetupError.backupInvalid
        }

        let current = try secureReadIfPresent(target)
        guard current.map(digest) == backup.installedDigest else {
            throw AgentIntegrationSetupError.changedExternally
        }

        if backup.originalExisted {
            guard let encoded = backup.originalDataBase64,
                  let original = Data(base64Encoded: encoded) else {
                throw AgentIntegrationSetupError.backupInvalid
            }
            try secureWrite(
                original,
                to: target,
                expectedExistingDigest: current.map(digest),
                permissions: backup.originalPermissions ?? 0o600
            )
        } else {
            guard let current else { return snapshot(for: provider) }
            guard digest(current) == backup.installedDigest else {
                throw AgentIntegrationSetupError.changedExternally
            }
            do {
                try fileManager.removeItem(at: target)
            } catch {
                throw AgentIntegrationSetupError.writeFailed
            }
        }

        try? fileManager.removeItem(at: backupURL)
        return snapshot(for: provider)
    }

    private func snapshot(
        _ provider: AgentIntegrationProvider,
        _ state: AgentIntegrationSetupState,
        _ detail: String
    ) -> AgentIntegrationSetupSnapshot {
        AgentIntegrationSetupSnapshot(
            provider: provider,
            state: state,
            configPath: paths.configURL(for: provider).path,
            backupAvailable: fileManager.fileExists(atPath: paths.backupURL(for: provider).path),
            detail: detail
        )
    }

    private func secureReadIfPresent(_ url: URL) throws -> Data? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        var info = stat()
        guard lstat(url.path, &info) == 0 else { throw AgentIntegrationSetupError.unsafePath }
        guard (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == geteuid(),
              info.st_size >= 0,
              info.st_size <= AgentHookConfigurationPlanner.maximumConfigBytes else {
            if info.st_size > AgentHookConfigurationPlanner.maximumConfigBytes {
                throw AgentIntegrationSetupError.fileTooLarge
            }
            throw AgentIntegrationSetupError.unsafePath
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard data.count <= AgentHookConfigurationPlanner.maximumConfigBytes else {
                throw AgentIntegrationSetupError.fileTooLarge
            }
            return data
        } catch let error as AgentIntegrationSetupError {
            throw error
        } catch {
            throw AgentIntegrationSetupError.unsafePath
        }
    }

    private func existingPermissions(_ url: URL) throws -> Int? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        if let permissions, permissions & 0o200 == 0 {
            throw AgentIntegrationSetupError.readOnly
        }
        return permissions
    }

    private func secureWrite(
        _ data: Data,
        to target: URL,
        expectedExistingDigest: String?,
        permissions: Int
    ) throws {
        let parent = target.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw AgentIntegrationSetupError.writeFailed
        }

        let current = try secureReadIfPresent(target)
        guard current.map(digest) == expectedExistingDigest else {
            throw AgentIntegrationSetupError.changedExternally
        }

        do {
            try data.write(to: target, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        } catch {
            throw AgentIntegrationSetupError.writeFailed
        }
    }

    private func writeBackup(_ backup: AgentIntegrationBackupEnvelope, to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(
                at: parent,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let data = try JSONEncoder().encode(backup)
            try data.write(to: url, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw AgentIntegrationSetupError.writeFailed
        }
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension AgentIntegrationSetupError {
    var safeDescription: String {
        switch self {
        case .helperUnavailable: "The bundled hook helper is unavailable."
        case .unsafePath: "The configuration path is not a safe user-owned regular file."
        case .fileTooLarge: "The configuration file exceeds the supported safety limit."
        case .invalidJSON: "The configuration is not valid JSON and was left unchanged."
        case .invalidHooks: "The existing hooks value has an unsupported shape and was left unchanged."
        case .readOnly: "The configuration file is read-only."
        case .changedExternally: "The configuration changed externally; refresh before trying again."
        case .backupUnavailable: "No DynamicIsland backup is available."
        case .backupInvalid: "The DynamicIsland backup is invalid or belongs to another configuration."
        case .writeFailed: "The configuration could not be written safely."
        }
    }
}

@MainActor
final class AgentIntegrationSetupController: ObservableObject {
    @Published private(set) var snapshots: [AgentIntegrationProvider: AgentIntegrationSetupSnapshot] = [:]
    @Published private(set) var preview: AgentIntegrationSetupPreview?
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    private let service: AgentIntegrationSetupService

    init(service: AgentIntegrationSetupService = AgentIntegrationSetupService()) {
        self.service = service
        refresh()
    }

    func refresh() {
        let service = service
        Task { [weak self] in
            let values = await Task.detached(priority: .utility) {
                Dictionary(uniqueKeysWithValues: AgentIntegrationProvider.allCases.map {
                    ($0, service.snapshot(for: $0))
                })
            }.value
            guard let self else { return }
            snapshots = values
        }
    }

    func prepare(_ provider: AgentIntegrationProvider) {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        let service = service
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try service.preview(for: provider) }
            }.value
            guard let self else { return }
            isWorking = false
            switch result {
            case .success(let value): preview = value
            case .failure(let error):
                lastError = (error as? AgentIntegrationSetupError)?.safeDescription
                    ?? "Setup preview could not be generated."
            }
            refresh()
        }
    }

    func cancelPreview() {
        preview = nil
    }

    func applyPreview() {
        guard let provider = preview?.provider, !isWorking else { return }
        preview = nil
        perform(provider) { service, provider in try service.apply(provider) }
    }

    func remove(_ provider: AgentIntegrationProvider) {
        perform(provider) { service, provider in try service.remove(provider) }
    }

    func rollback(_ provider: AgentIntegrationProvider) {
        perform(provider) { service, provider in try service.rollback(provider) }
    }

    private func perform(
        _ provider: AgentIntegrationProvider,
        operation: @escaping @Sendable (AgentIntegrationSetupService, AgentIntegrationProvider) throws -> AgentIntegrationSetupSnapshot
    ) {
        guard !isWorking else { return }
        isWorking = true
        lastError = nil
        let service = service
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Result { try operation(service, provider) }
            }.value
            guard let self else { return }
            isWorking = false
            switch result {
            case .success(let snapshot): snapshots[provider] = snapshot
            case .failure(let error):
                lastError = (error as? AgentIntegrationSetupError)?.safeDescription
                    ?? "Agent integration setup failed safely."
            }
            refresh()
        }
    }
}
