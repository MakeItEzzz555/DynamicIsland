import CryptoKit
import Foundation

package enum CodexHookNormalizationError: Error, Equatable, Sendable {
    case emptyInput
    case inputTooLarge
    case malformedJSON
    case invalidHook
    case unsupportedHook
    case outputTooLarge
}

package enum CodexHookNormalizer {
    package static let maximumInputBytes = 1_024 * 1_024
    private static let maximumDepth = 12
    private static let maximumIdentifierBytes = 256
    private static let maximumTokenBytes = 128
    private static let maximumPathBytes = 4_096

    package static func normalize(_ data: Data, now: Date = Date()) throws -> Data {
        guard !data.isEmpty else { throw CodexHookNormalizationError.emptyInput }
        guard data.count <= maximumInputBytes else { throw CodexHookNormalizationError.inputTooLarge }
        guard String(data: data, encoding: .utf8) != nil else { throw CodexHookNormalizationError.malformedJSON }

        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw CodexHookNormalizationError.malformedJSON }
        try validateJSON(object, depth: 1)

        guard let root = object as? [String: Any],
              let hookName = boundedString(root["hook_event_name"], maximumBytes: maximumTokenBytes),
              let sessionID = boundedString(root["session_id"], maximumBytes: maximumIdentifierBytes) else {
            throw CodexHookNormalizationError.invalidHook
        }

        let timestamp = iso8601(now)
        let turnID = boundedString(root["turn_id"], maximumBytes: maximumIdentifierBytes)
        let cwd = boundedString(root["cwd"], maximumBytes: maximumPathBytes)
        let model = boundedString(root["model"], maximumBytes: maximumTokenBytes)
        let rawDigest = digest(data)
        var events: [[String: Any]] = []

        func baseEvent(_ type: String, correlationID: String? = nil, payload: [String: Any]? = nil) -> [String: Any] {
            var event: [String: Any] = [
                "schemaVersion": 1,
                "eventID": "codex-hook-\(digest(Data("\(hookName)|\(sessionID)|\(turnID ?? "")|\(type)|\(rawDigest)".utf8)).prefix(40))",
                "provider": "codex",
                "source": "unknown",
                "nativeSessionID": sessionID,
                "continuityIdentity": sessionID,
                "eventType": type,
                "authority": "lifecycle"
            ]
            if let correlationID { event["correlationID"] = correlationID }
            if let payload { event["payload"] = payload }
            return event
        }

        func metadataPayload() -> [String: Any] {
            var project: [String: Any] = [:]
            if let cwd {
                project["workingDirectory"] = cwd
                let display = URL(fileURLWithPath: cwd).lastPathComponent
                if !display.isEmpty { project["displayName"] = String(display.prefix(512)) }
            }
            if let model { project["model"] = model }
            return ["sessionMetadata": ["project": project]]
        }

        switch hookName {
        case "SessionStart":
            let source = boundedString(root["source"], maximumBytes: maximumTokenBytes) ?? "startup"
            events.append(baseEvent(source == "startup" ? "sessionStarted" : "sessionResumed", payload: metadataPayload()))
            let capabilities = [
                "sessionLifecycle", "toolLifecycle", "commandLifecycle", "approvalObservation",
                "subagentLifecycle", "taskLifecycle", "modelMetadata", "projectContext"
            ].map {
                ["name": $0, "authority": "lifecycle", "source": "codex-hooks-v1", "observedAt": timestamp]
            }
            events.append(baseEvent("capabilitiesUpdated", payload: ["capabilities": capabilities]))

        case "UserPromptSubmit":
            events.append(baseEvent("sessionResumed", payload: metadataPayload()))
            events.append(baseEvent("agentWorking", correlationID: turnID, payload: ["activity": ["title": "Working"]]))

        case "PreToolUse":
            guard let tool = boundedString(root["tool_name"], maximumBytes: maximumTokenBytes),
                  let toolUseID = boundedString(root["tool_use_id"], maximumBytes: maximumIdentifierBytes) else {
                throw CodexHookNormalizationError.invalidHook
            }
            if isCommandTool(tool) {
                events.append(baseEvent("commandStarted", correlationID: toolUseID, payload: ["command": ["executable": commandExecutable(for: tool)]]))
            } else {
                events.append(baseEvent("toolStarted", correlationID: toolUseID, payload: ["tool": ["name": tool, "category": toolCategory(tool)]]))
            }

        case "PostToolUse":
            guard let tool = boundedString(root["tool_name"], maximumBytes: maximumTokenBytes),
                  let toolUseID = boundedString(root["tool_use_id"], maximumBytes: maximumIdentifierBytes) else {
                throw CodexHookNormalizationError.invalidHook
            }
            if isCommandTool(tool) {
                events.append(baseEvent("commandCompleted", correlationID: toolUseID, payload: ["command": ["executable": commandExecutable(for: tool), "success": true]]))
            } else {
                events.append(baseEvent("toolCompleted", correlationID: toolUseID, payload: ["tool": ["name": tool, "category": toolCategory(tool), "success": true]]))
            }

        case "PermissionRequest":
            guard let tool = boundedString(root["tool_name"], maximumBytes: maximumTokenBytes) else {
                throw CodexHookNormalizationError.invalidHook
            }
            let approvalID = "approval-" + String(digest(Data("\(sessionID)|\(turnID ?? "")|\(tool)|\(rawDigest)".utf8)).prefix(40))
            events.append(baseEvent("approvalRequested", correlationID: approvalID, payload: ["approvalRequest": ["summary": "\(String(tool.prefix(96))) approval required"]]))

        case "Stop":
            events.append(baseEvent("taskCompleted", correlationID: turnID, payload: ["terminal": ["summary": "Codex turn completed"]]))

        case "Interrupt":
            events.append(baseEvent("interrupted", correlationID: turnID, payload: ["terminal": ["summary": "Codex turn interrupted"]]))

        case "SessionEnd":
            events.append(baseEvent("sessionEnded"))

        case "SubagentStart":
            guard let agentID = boundedString(root["agent_id"], maximumBytes: maximumIdentifierBytes) else {
                throw CodexHookNormalizationError.invalidHook
            }
            let display = boundedString(root["agent_type"], maximumBytes: maximumTokenBytes)
            events.append(baseEvent("subagentStarted", correlationID: agentID, payload: ["subagent": ["nativeID": agentID, "displayName": display ?? "Subagent"]]))

        case "SubagentStop":
            guard let agentID = boundedString(root["agent_id"], maximumBytes: maximumIdentifierBytes) else {
                throw CodexHookNormalizationError.invalidHook
            }
            let display = boundedString(root["agent_type"], maximumBytes: maximumTokenBytes)
            events.append(baseEvent("subagentEnded", correlationID: agentID, payload: ["subagent": ["nativeID": agentID, "displayName": display ?? "Subagent"]]))

        case "PreCompact", "PostCompact":
            throw CodexHookNormalizationError.unsupportedHook

        default:
            throw CodexHookNormalizationError.unsupportedHook
        }

        let envelope: [String: Any] = events.count == 1 ? ["event": events[0]] : ["events": events]
        let output: Data
        do { output = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) }
        catch { throw CodexHookNormalizationError.malformedJSON }
        guard output.count <= 64 * 1_024 else { throw CodexHookNormalizationError.outputTooLarge }
        return output
    }

    private static func isCommandTool(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "bash" || lower == "shell" || lower == "shell_command" || lower == "exec_command"
    }

    private static func commandExecutable(for tool: String) -> String {
        switch tool.lowercased() {
        case "bash": "bash"
        case "shell", "shell_command": "shell"
        case "exec_command": "exec"
        default: "command"
        }
    }

    private static func toolCategory(_ tool: String) -> String {
        let lower = tool.lowercased()
        if lower.contains("patch") || lower.contains("edit") || lower.contains("write") { return "edit" }
        if lower.contains("read") || lower.contains("search") || lower.contains("find") { return "read" }
        if lower.contains("browser") || lower.contains("web") { return "web" }
        return "tool"
    }

    private static func boundedString(_ value: Any?, maximumBytes: Int) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.utf8.count <= maximumBytes,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func validateJSON(_ value: Any, depth: Int) throws {
        guard depth <= maximumDepth else { throw CodexHookNormalizationError.malformedJSON }
        if let object = value as? [String: Any] {
            guard object.count <= 128 else { throw CodexHookNormalizationError.malformedJSON }
            for child in object.values { try validateJSON(child, depth: depth + 1) }
        } else if let array = value as? [Any] {
            guard array.count <= 256 else { throw CodexHookNormalizationError.malformedJSON }
            for child in array { try validateJSON(child, depth: depth + 1) }
        }
    }
}

package enum CodexHookStandardInput {
    package static func readBounded(
        from handle: FileHandle = .standardInput,
        maximumBytes: Int = CodexHookNormalizer.maximumInputBytes
    ) throws -> Data {
        var data = Data()
        while true {
            let remaining = maximumBytes - data.count
            let chunk = try handle.read(upToCount: min(64 * 1_024, remaining + 1)) ?? Data()
            guard !chunk.isEmpty else { break }
            guard chunk.count <= remaining else { throw CodexHookNormalizationError.inputTooLarge }
            data.append(chunk)
        }
        return data
    }
}
