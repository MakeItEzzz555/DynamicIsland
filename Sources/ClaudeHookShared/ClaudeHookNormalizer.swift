import CryptoKit
import Foundation

package enum ClaudeHookNormalizationError: Error, Equatable, Sendable {
    case emptyInput
    case inputTooLarge
    case malformedJSON
    case invalidHook
    case unsupportedHook
    case outputTooLarge
}

package enum ClaudeHookNormalizer {
    package static let maximumInputBytes = 1_024 * 1_024
    private static let maximumDepth = 12
    private static let maximumIdentifierBytes = 256
    private static let maximumTokenBytes = 128
    private static let maximumPathBytes = 4_096

    package static func normalize(_ data: Data, now: Date = Date()) throws -> Data {
        guard !data.isEmpty else { throw ClaudeHookNormalizationError.emptyInput }
        guard data.count <= maximumInputBytes else { throw ClaudeHookNormalizationError.inputTooLarge }
        guard String(data: data, encoding: .utf8) != nil else { throw ClaudeHookNormalizationError.malformedJSON }

        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw ClaudeHookNormalizationError.malformedJSON }
        try validateJSON(object, depth: 1)

        guard let root = object as? [String: Any],
              let hookName = boundedString(root["hook_event_name"], maximumBytes: maximumTokenBytes),
              let sessionID = boundedString(root["session_id"], maximumBytes: maximumIdentifierBytes) else {
            throw ClaudeHookNormalizationError.invalidHook
        }

        let promptID = boundedString(root["prompt_id"], maximumBytes: maximumIdentifierBytes)
        let cwd = boundedString(root["cwd"], maximumBytes: maximumPathBytes)
        let model = boundedString(root["model"], maximumBytes: maximumTokenBytes)
        let observationNonce = String(format: "%.6f", now.timeIntervalSince1970)
        let timestamp = iso8601(now)
        var events: [[String: Any]] = []

        func baseEvent(
            _ type: String,
            correlationID: String? = nil,
            uniqueness: String? = nil,
            payload: [String: Any]? = nil
        ) -> [String: Any] {
            let identity = [hookName, sessionID, promptID ?? "", type, correlationID ?? "", uniqueness ?? ""]
                .joined(separator: "|")
            var event: [String: Any] = [
                "schemaVersion": 1,
                "eventID": "claude-hook-\(digest(identity).prefix(40))",
                "provider": "claude",
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

        func metadataPayload(overrideCwd: String? = nil, overrideModel: String? = nil) -> [String: Any] {
            var project: [String: Any] = [:]
            let effectiveCwd = overrideCwd ?? cwd
            if let effectiveCwd {
                project["workingDirectory"] = effectiveCwd
                let display = URL(fileURLWithPath: effectiveCwd).lastPathComponent
                if !display.isEmpty { project["displayName"] = String(display.prefix(512)) }
            }
            if let effectiveModel = overrideModel ?? model { project["model"] = effectiveModel }
            return ["sessionMetadata": ["project": project]]
        }

        switch hookName {
        case "SessionStart":
            let source = boundedString(root["source"], maximumBytes: maximumTokenBytes) ?? "startup"
            events.append(baseEvent("sessionStarted", uniqueness: source, payload: metadataPayload()))
            let capabilities = [
                "sessionLifecycle", "toolLifecycle", "commandLifecycle", "approvalObservation",
                "userInputObservation", "subagentLifecycle", "taskLifecycle",
                "modelMetadata", "projectContext"
            ].map {
                ["name": $0, "authority": "lifecycle", "source": "claude-hooks-v1", "observedAt": timestamp]
            }
            events.append(baseEvent("capabilitiesUpdated", uniqueness: source, payload: ["capabilities": capabilities]))

        case "UserPromptSubmit":
            events.append(baseEvent("sessionResumed", correlationID: promptID, payload: metadataPayload()))
            events.append(baseEvent(
                "agentWorking",
                correlationID: promptID,
                payload: ["activity": ["title": "Working"]]
            ))

        case "PreToolUse":
            try appendToolLifecycle(root: root, success: nil, completed: false, baseEvent: baseEvent, events: &events)

        case "PostToolUse":
            try appendToolLifecycle(root: root, success: true, completed: true, baseEvent: baseEvent, events: &events)

        case "PostToolUseFailure":
            try appendToolLifecycle(root: root, success: false, completed: true, baseEvent: baseEvent, events: &events)

        case "PermissionDenied":
            guard let tool = boundedString(root["tool_name"], maximumBytes: maximumTokenBytes),
                  let approvalID = approvalCorrelation(
                      prefix: "permission",
                      sessionID: sessionID,
                      promptID: promptID,
                      tool: tool,
                      toolInput: root["tool_input"]
                  ) else {
                throw ClaudeHookNormalizationError.invalidHook
            }
            events.append(baseEvent(
                "approvalResolved",
                correlationID: approvalID,
                uniqueness: observationNonce,
                payload: ["approvalResolution": ["state": "denied"]]
            ))
            try appendToolLifecycle(root: root, success: false, completed: true, baseEvent: baseEvent, events: &events)

        case "PermissionRequest":
            guard let tool = boundedString(root["tool_name"], maximumBytes: maximumTokenBytes),
                  let approvalID = approvalCorrelation(
                      prefix: "permission",
                      sessionID: sessionID,
                      promptID: promptID,
                      tool: tool,
                      toolInput: root["tool_input"]
                  ) else {
                throw ClaudeHookNormalizationError.invalidHook
            }
            events.append(baseEvent(
                "approvalRequested",
                correlationID: approvalID,
                uniqueness: observationNonce,
                payload: ["approvalRequest": [
                    "summary": "\(String(tool.prefix(96))) approval required",
                    "operationCorrelationID": operationHint(tool)
                ]]
            ))

        case "Elicitation":
            guard let correlation = elicitationCorrelation(
                root: root,
                sessionID: sessionID,
                promptID: promptID
            ) else {
                throw ClaudeHookNormalizationError.invalidHook
            }
            events.append(baseEvent(
                "waitingForUser",
                correlationID: correlation,
                uniqueness: observationNonce,
                payload: ["userInput": ["summary": "Claude needs input"]]
            ))

        case "ElicitationResult":
            guard let correlation = elicitationCorrelation(
                root: root,
                sessionID: sessionID,
                promptID: promptID
            ) else {
                throw ClaudeHookNormalizationError.invalidHook
            }
            events.append(baseEvent("userInputResolved", correlationID: correlation))

        case "SubagentStart":
            guard let agentID = boundedString(root["agent_id"], maximumBytes: maximumIdentifierBytes) else {
                throw ClaudeHookNormalizationError.invalidHook
            }
            let agentType = boundedString(root["agent_type"], maximumBytes: maximumTokenBytes) ?? "Subagent"
            events.append(baseEvent(
                "subagentStarted",
                correlationID: agentID,
                payload: ["subagent": ["nativeID": agentID, "displayName": agentType]]
            ))

        case "SubagentStop":
            guard let agentID = boundedString(root["agent_id"], maximumBytes: maximumIdentifierBytes) else {
                throw ClaudeHookNormalizationError.invalidHook
            }
            let agentType = boundedString(root["agent_type"], maximumBytes: maximumTokenBytes) ?? "Subagent"
            events.append(baseEvent(
                "subagentEnded",
                correlationID: agentID,
                payload: ["subagent": ["nativeID": agentID, "displayName": agentType]]
            ))

        case "Stop":
            let backgroundActive = nonEmptyArray(root["background_tasks"]) || nonEmptyArray(root["session_crons"])
            if backgroundActive {
                events.append(baseEvent(
                    "agentWorking",
                    correlationID: promptID,
                    payload: ["activity": ["title": "Background work continues"]]
                ))
            } else {
                events.append(baseEvent(
                    "taskCompleted",
                    correlationID: promptID,
                    payload: ["terminal": ["summary": "Claude turn completed"]]
                ))
            }

        case "StopFailure":
            let category = boundedString(root["error"], maximumBytes: maximumTokenBytes) ?? "unknown"
            events.append(baseEvent(
                "taskFailed",
                correlationID: promptID,
                uniqueness: category,
                payload: ["terminal": ["summary": "Claude stopped: \(String(category.prefix(80)))"]]
            ))

        case "SessionEnd":
            events.append(baseEvent("sessionEnded"))

        case "CwdChanged":
            let newCwd = boundedString(root["new_cwd"], maximumBytes: maximumPathBytes) ?? cwd
            var project: [String: Any] = [:]
            if let newCwd {
                project["workingDirectory"] = newCwd
                let display = URL(fileURLWithPath: newCwd).lastPathComponent
                if !display.isEmpty { project["displayName"] = String(display.prefix(512)) }
            }
            events.append(baseEvent("projectContextUpdated", payload: ["projectContext": project]))

        default:
            throw ClaudeHookNormalizationError.unsupportedHook
        }

        let envelope: [String: Any] = events.count == 1 ? ["event": events[0]] : ["events": events]
        let output: Data
        do { output = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys]) }
        catch { throw ClaudeHookNormalizationError.malformedJSON }
        guard output.count <= 64 * 1_024 else { throw ClaudeHookNormalizationError.outputTooLarge }
        return output
    }

    private static func elicitationCorrelation(
        root: [String: Any],
        sessionID: String,
        promptID: String?
    ) -> String? {
        if let explicit = boundedString(root["elicitation_id"], maximumBytes: maximumIdentifierBytes) {
            return explicit
        }
        guard let server = boundedString(root["mcp_server_name"], maximumBytes: maximumTokenBytes) else {
            return nil
        }
        let mode = boundedString(root["mode"], maximumBytes: maximumTokenBytes) ?? "unspecified"
        return "elicitation-" + String(
            digest("\(sessionID)|\(promptID ?? "")|\(server.lowercased())|\(mode.lowercased())").prefix(40)
        )
    }

    private static func approvalCorrelation(
        prefix: String,
        sessionID: String,
        promptID: String?,
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
        var material = Data("\(sessionID)|\(promptID ?? "")|\(tool.lowercased())|".utf8)
        material.append(canonicalInput)
        return prefix + "-" + String(digest(material).prefix(40))
    }

    private static func operationHint(_ tool: String) -> String {
        "operation-" + tool.lowercased()
    }

    private static func appendToolLifecycle(
        root: [String: Any],
        success: Bool?,
        completed: Bool,
        baseEvent: (String, String?, String?, [String: Any]?) -> [String: Any],
        events: inout [[String: Any]]
    ) throws {
        guard let tool = boundedString(root["tool_name"], maximumBytes: maximumTokenBytes),
              let toolUseID = boundedString(root["tool_use_id"], maximumBytes: maximumIdentifierBytes) else {
            throw ClaudeHookNormalizationError.invalidHook
        }
        if isCommandTool(tool) {
            var command: [String: Any] = ["executable": commandExecutable(for: tool)]
            if let success { command["success"] = success }
            events.append(baseEvent(
                completed ? "commandCompleted" : "commandStarted",
                toolUseID,
                nil,
                ["command": command]
            ))
        } else {
            var toolPayload: [String: Any] = ["name": tool, "category": toolCategory(tool)]
            if let success { toolPayload["success"] = success }
            events.append(baseEvent(
                completed ? "toolCompleted" : "toolStarted",
                toolUseID,
                nil,
                ["tool": toolPayload]
            ))
        }
    }

    private static func isCommandTool(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "bash" || lower == "powershell" || lower == "shell"
    }

    private static func commandExecutable(for tool: String) -> String {
        switch tool.lowercased() {
        case "bash": "bash"
        case "powershell": "powershell"
        default: "shell"
        }
    }

    private static func toolCategory(_ tool: String) -> String {
        let lower = tool.lowercased()
        if lower == "edit" || lower == "write" || lower.contains("patch") { return "edit" }
        if lower == "read" || lower.contains("search") || lower.contains("glob") || lower.contains("grep") { return "read" }
        if lower.contains("web") || lower.contains("browser") { return "web" }
        return "tool"
    }

    private static func nonEmptyArray(_ value: Any?) -> Bool {
        (value as? [Any])?.isEmpty == false
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

    private static func digest(_ value: String) -> String {
        digest(Data(value.utf8))
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
        guard depth <= maximumDepth else { throw ClaudeHookNormalizationError.malformedJSON }
        if let object = value as? [String: Any] {
            guard object.count <= 128 else { throw ClaudeHookNormalizationError.malformedJSON }
            for child in object.values { try validateJSON(child, depth: depth + 1) }
        } else if let array = value as? [Any] {
            guard array.count <= 256 else { throw ClaudeHookNormalizationError.malformedJSON }
            for child in array { try validateJSON(child, depth: depth + 1) }
        }
    }
}

package enum ClaudeHookStandardInput {
    package static func readBounded(
        from handle: FileHandle = .standardInput,
        maximumBytes: Int = ClaudeHookNormalizer.maximumInputBytes
    ) throws -> Data {
        var data = Data()
        while true {
            let remaining = maximumBytes - data.count
            let chunk = try handle.read(upToCount: min(64 * 1_024, remaining + 1)) ?? Data()
            guard !chunk.isEmpty else { break }
            guard chunk.count <= remaining else { throw ClaudeHookNormalizationError.inputTooLarge }
            data.append(chunk)
        }
        return data
    }
}
