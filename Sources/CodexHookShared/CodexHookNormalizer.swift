import AgentBridgeShared
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
        let observationNonce = String(format: "%.6f", now.timeIntervalSince1970)
        var events: [[String: Any]] = []

        func baseEvent(
            _ type: String,
            correlationID: String? = nil,
            uniqueness: String? = nil,
            payload: [String: Any]? = nil
        ) -> [String: Any] {
            let stableIdentity = [hookName, sessionID, turnID ?? "", type, correlationID ?? "", uniqueness ?? ""]
                .joined(separator: "|")
            var event: [String: Any] = [
                "schemaVersion": 1,
                "eventID": "codex-hook-\(digest(Data(stableIdentity.utf8)).prefix(40))",
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
            // SessionStart is the first authoritative observation for this local
            // integration incarnation even when Codex itself is resuming a thread.
            // Later turn continuations use UserPromptSubmit/sessionResumed.
            events.append(baseEvent("sessionStarted", uniqueness: source, payload: metadataPayload()))
            let capabilities = [
                "sessionLifecycle", "toolLifecycle", "commandLifecycle", "approvalObservation",
                "subagentLifecycle", "taskLifecycle", "modelMetadata", "projectContext"
            ].map {
                ["name": $0, "authority": "lifecycle", "source": "codex-hooks-v1", "observedAt": timestamp]
            }
            events.append(baseEvent("capabilitiesUpdated", uniqueness: source, payload: ["capabilities": capabilities]))

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
            guard let tool = boundedString(root["tool_name"], maximumBytes: maximumTokenBytes),
                  let approvalID = approvalCorrelation(
                      prefix: "approval",
                      sessionID: sessionID,
                      turnID: turnID,
                      tool: tool,
                      toolInput: root["tool_input"]
                  ) else {
                throw CodexHookNormalizationError.invalidHook
            }
            let capabilities = ["approvalObservation", "approvalControl"].map {
                ["name": $0, "authority": "lifecycle", "source": "codex-permission-hook-v1", "observedAt": timestamp]
            }
            events.append(baseEvent(
                "capabilitiesUpdated",
                uniqueness: observationNonce,
                payload: ["capabilities": capabilities]
            ))
            var request: [String: Any] = [
                "summary": approvalSummary(tool: tool, toolInput: root["tool_input"]),
                "operationCorrelationID": operationHint(tool),
                "expiresAt": now.addingTimeInterval(75).timeIntervalSinceReferenceDate
            ]
            if request["summary"] == nil { request.removeValue(forKey: "summary") }
            events.append(baseEvent(
                "approvalRequested",
                correlationID: approvalID,
                uniqueness: observationNonce,
                payload: ["approvalRequest": request]
            ))

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

    package static func hookEventName(_ data: Data) -> String? {
        guard data.count <= maximumInputBytes,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return boundedString(root["hook_event_name"], maximumBytes: maximumTokenBytes)
    }

    private static func approvalSummary(tool: String, toolInput: Any?) -> String {
        guard let input = toolInput as? [String: Any] else {
            return "\(String(tool.prefix(96))) approval required"
        }
        if let description = boundedString(input["description"], maximumBytes: 320),
           let projected = safeApprovalText(description) {
            return projected
        }
        if isCommandTool(tool),
           let command = boundedString(input["command"], maximumBytes: 1_024),
           let projected = safeCommandPreview(command) {
            return "$ " + projected
        }
        return "\(String(tool.prefix(96))) approval required"
    }

    private static func safeApprovalText(_ value: String) -> String? {
        guard !containsSensitiveMarker(value), !value.contains("\n"), !value.contains("\r") else { return nil }
        return String(value.prefix(240))
    }

    private static func safeCommandPreview(_ value: String) -> String? {
        guard !containsSensitiveMarker(value), !value.contains("\n"), !value.contains("\r"),
              value.unicodeScalars.allSatisfy({ $0.isASCII && !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        let tokens = value.split(whereSeparator: { $0.isWhitespace })
        guard !tokens.isEmpty, tokens.count <= 12 else { return nil }
        var projected: [String] = []
        for rawToken in tokens {
            let token = String(rawToken)
            guard !token.contains("="), token.unicodeScalars.allSatisfy({
                CharacterSet.alphanumerics.contains($0) || "._/-:@+".unicodeScalars.contains($0)
            }) else { return nil }
            if token.hasPrefix("/") {
                let name = URL(fileURLWithPath: token).lastPathComponent
                guard !name.isEmpty else { return nil }
                projected.append(name)
            } else {
                projected.append(token)
            }
        }
        let result = projected.joined(separator: " ")
        return result.utf8.count <= 240 ? result : nil
    }

    private static func containsSensitiveMarker(_ value: String) -> Bool {
        let normalized = value.lowercased().replacingOccurrences(of: "-", with: "_")
        return [
            "password", "passwd", "secret", "token", "authorization", "bearer",
            "api_key", "apikey", "cookie", "credential", "private_key", "sshpass"
        ].contains { normalized.contains($0) }
    }

    private static func approvalCorrelation(
        prefix: String,
        sessionID: String,
        turnID: String?,
        tool: String,
        toolInput: Any?
    ) -> String? {
        guard let toolInput,
              JSONSerialization.isValidJSONObject(["input": toolInput]),
              let canonicalInput = try? JSONSerialization.data(
                  withJSONObject: ["input": toolInput],
                  options: [.sortedKeys]
              ) else {
            return nil
        }
        var material = Data("\(sessionID)|\(turnID ?? "")|\(tool.lowercased())|".utf8)
        material.append(canonicalInput)
        return prefix + "-" + String(digest(material).prefix(40))
    }

    private static func operationHint(_ tool: String) -> String {
        "operation-" + tool.lowercased()
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

package enum CodexPermissionHookOutput {
    package static func encode(_ decision: AgentBridgePermissionDecision) -> Data? {
        let value: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision == .allow
                    ? ["behavior": "allow"]
                    : ["behavior": "deny", "message": "Denied in DynamicIsland"]
            ]
        ]
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
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
