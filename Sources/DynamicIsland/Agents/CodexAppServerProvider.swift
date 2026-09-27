import Foundation

actor CodexAppServerProvider: AgentInteractiveProvider {
    static let maximumDiscoveredSessions = 20
    static let contextBaselineTokens: Double = 12_000
    nonisolated let provider: AgentProvider = .codex
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .startSession,
        .resumeSession,
        .submitPrompt,
        .interrupt,
        .selectModel,
        .resolveApprovals,
        .accountUsage,
        .contextUsage,
        .streamToolActivity,
        .loadHistory
    ]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = .nextTurn
    private let client: CodexAppServerClient

    init(client: CodexAppServerClient) {
        self.client = client
    }

    static func makeDefault() throws -> CodexAppServerProvider {
        CodexAppServerProvider(client: try CodexAppServerClient())
    }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent> {
        let upstream = await client.events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream {
                    if let mapped = Self.map(event) {
                        continuation.yield(mapped)
                    } else if case .serverRequest(let id, let method, _) = event {
                        // Unknown server requests must never hang a managed turn.
                        // Reject them through JSON-RPC without broadening the
                        // provider-neutral control contract.
                        try? await client.respondUnsupportedRequest(
                            requestID: id,
                            method: method
                        )
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        let threads = try await client.listThreads(limit: 100)
        return Self.boundedDiscovery(threads).map { thread in
            return AgentDiscoveredSessionDescriptor(
                session: AgentManagedSessionDescriptor(
                    provider: .codex,
                    nativeSessionID: thread.id,
                    cwd: thread.cwd,
                    model: thread.model,
                    acceptsDirectInput: thread.canAcceptDirectInput
                ),
                runtimeState: thread.status,
                updatedAt: thread.updatedAt
            )
        }
    }

    func readTranscript(
        nativeSessionID: String,
        limit: Int
    ) async throws -> [AgentManagedTranscriptEntry] {
        let entries = try await client.listThreadItems(
            threadID: nativeSessionID,
            limit: min(max(limit, 1), 100)
        )
        return entries.compactMap {
            Self.mapTranscriptItem(
                $0.item,
                nativeSessionID: nativeSessionID,
                turnID: $0.turnID,
                timestamp: $0.timestamp,
                includesSafeActivities: true
            )
        }
    }

    func listModels() async throws -> [AgentManagedModelDescriptor] {
        try await client.listModels(limit: 100)
            .filter { !$0.hidden }
            .map {
                AgentManagedModelDescriptor(
                    id: $0.id,
                    model: $0.model,
                    displayName: $0.displayName,
                    description: $0.description,
                    isDefault: $0.isDefault
                )
            }
    }

    func readAccountUsage() async throws -> AgentUsage {
        let rateResult = try await client.readAccountRateLimits()
        return Self.mapAccountRateLimits(rateResult)
    }

    nonisolated static func boundedDiscovery(
        _ threads: [CodexListedThread],
        limit: Int = maximumDiscoveredSessions
    ) -> [CodexListedThread] {
        let boundedLimit = max(limit, 0)
        let ordered = threads.sorted {
            let lhsRank = runtimeRank($0.status)
            let rhsRank = runtimeRank($1.status)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        var seen = Set<String>()
        return Array(ordered.filter { seen.insert($0.id).inserted }.prefix(boundedLimit))
    }

    private nonisolated static func runtimeRank(_ state: AgentDiscoveredSessionRuntimeState) -> Int {
        switch state {
        case .active: 0
        case .idle: 1
        case .systemError: 2
        case .notLoaded: 3
        }
    }

    func startSession(cwd: String?) async throws -> AgentManagedSessionDescriptor {
        let thread = try await client.startThread(cwd: cwd)
        return descriptor(thread)
    }

    func resumeSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor {
        let thread = try await client.resumeThread(threadID: nativeSessionID)
        return descriptor(thread)
    }

    func submit(
        prompt: String,
        nativeSessionID: String,
        model: String?
    ) async throws -> AgentManagedTurnDescriptor {
        let turn = try await client.startTurn(
            threadID: nativeSessionID,
            prompt: prompt,
            model: model
        )
        return AgentManagedTurnDescriptor(nativeSessionID: nativeSessionID, turnID: turn.id)
    }

    func interrupt(nativeSessionID: String, turnID: String) async throws {
        try await client.interrupt(threadID: nativeSessionID, turnID: turnID)
    }

    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {
        try await client.respondToApproval(requestToken: request.requestToken, allow: allow)
    }

    func stop() async {
        await client.stop()
    }

    private nonisolated static func mapAccountRateLimits(_ payload: CodexJSONValue) -> AgentUsage {
        guard let snapshot = payload["rateLimits"] else { return AgentUsage() }
        let now = Date()
        var samples: [AgentUsageKey: AgentUsageSample] = [:]

        func appendWindow(_ key: String) {
            guard let window = snapshot[key],
                  let usedPercent = window["usedPercent"]?.doubleValue,
                  usedPercent.isFinite,
                  usedPercent >= 0 else {
                return
            }

            let duration = window["windowDurationMins"]?.intValue
            let scope: String = switch duration {
            case 300: "5h"
            case 10_080: "weekly"
            case .some(let minutes): "\(minutes)m"
            case nil: key
            }

            let sample = AgentUsageSample(
                value: min(max(usedPercent, 0), 100),
                limit: 100,
                unit: .fraction,
                scope: scope,
                source: "codex-account-rate-limits",
                observedAt: now
            )
            samples[AgentUsageKey(metric: .quotaUsed, scope: scope)] = sample
        }

        appendWindow("primary")
        appendWindow("secondary")
        return AgentUsage(scopedSamples: samples)
    }

    private nonisolated static func latestContextUsage(
        from threads: [CodexListedThread]
    ) -> AgentUsage? {
        for thread in threads.sorted(by: { $0.updatedAt > $1.updatedAt }) {
            guard let path = thread.rolloutPath,
                  let usage = contextUsageFromRollout(path: path, observedAt: thread.updatedAt) else {
                continue
            }
            return usage
        }
        return nil
    }

    private nonisolated static func contextUsageFromRollout(
        path: String,
        observedAt: Date
    ) -> AgentUsage? {
        let fileURL = URL(fileURLWithPath: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let sessionsRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey])
        guard fileURL.path.hasPrefix(sessionsRoot.path + "/"),
              resourceValues?.isRegularFile == true,
              let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let maximumTailBytes: UInt64 = 2 * 1_024 * 1_024
        let end = (try? handle.seekToEnd()) ?? 0
        let start = end > maximumTailBytes ? end - maximumTailBytes : 0
        do {
            try handle.seek(toOffset: start)
        } catch {
            return nil
        }
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        for rawLine in data.split(separator: 0x0A).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(rawLine)) as? [String: Any],
                  let type = object["type"] as? String,
                  type == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  let payloadType = payload["type"] as? String,
                  payloadType == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let last = info["last_token_usage"] as? [String: Any],
                  let used = numeric(last["total_tokens"]),
                  used >= 0 else {
                continue
            }

            let limit = numeric(info["model_context_window"])
            let timestamp = (object["timestamp"] as? String)
                .flatMap { ISO8601DateFormatter().date(from: $0) } ?? observedAt
            return contextUsage(
                currentTokens: used,
                modelContextWindow: limit,
                source: "codex-rollout-snapshot",
                observedAt: timestamp
            )
        }
        return nil
    }

    nonisolated static func contextUsage(
        currentTokens: Double,
        modelContextWindow: Double?,
        source: String,
        observedAt: Date
    ) -> AgentUsage? {
        guard currentTokens.isFinite, currentTokens >= 0 else { return nil }
        let value: Double
        let limit: Double?
        if let modelContextWindow,
           modelContextWindow.isFinite,
           modelContextWindow > contextBaselineTokens {
            let effectiveLimit = modelContextWindow - contextBaselineTokens
            limit = effectiveLimit
            value = min(max(currentTokens - contextBaselineTokens, 0), effectiveLimit)
        } else {
            value = currentTokens
            limit = nil
        }
        return AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .contextUsed, scope: "context"): AgentUsageSample(
                value: value,
                limit: limit,
                unit: .tokens,
                scope: "context",
                source: source,
                observedAt: observedAt
            )
        ])
    }

    private nonisolated static func numeric(_ value: Any?) -> Double? {
        switch value {
        case let value as NSNumber:
            let result = value.doubleValue
            return result.isFinite ? result : nil
        case let value as String:
            return Double(value)
        default:
            return nil
        }
    }

    private func descriptor(_ thread: CodexManagedThread) -> AgentManagedSessionDescriptor {
        AgentManagedSessionDescriptor(
            provider: .codex,
            nativeSessionID: thread.id,
            cwd: thread.cwd,
            model: thread.model,
            acceptsDirectInput: thread.canAcceptDirectInput
        )
    }

    private nonisolated static func map(
        _ event: CodexAppServerEvent
    ) -> AgentInteractiveProviderEvent? {
        switch event {
        case .transportClosed:
            return .transportClosed(nil)

        case .notification(let method, let params):
            switch method {
            case "thread/started":
                guard let thread = params["thread"],
                      let threadID = thread["id"]?.stringValue else { return nil }
                return .threadAvailable(AgentManagedSessionDescriptor(
                    provider: .codex,
                    nativeSessionID: threadID,
                    cwd: thread["cwd"]?.stringValue,
                    model: thread["model"]?.stringValue,
                    acceptsDirectInput: thread["canAcceptDirectInput"]?.boolValue ?? false
                ))

            case "turn/started":
                guard let threadID = params["threadId"]?.stringValue,
                      let turnID = params["turn"]?["id"]?.stringValue else { return nil }
                return .turnStarted(AgentManagedTurnDescriptor(
                    nativeSessionID: threadID,
                    turnID: turnID
                ))

            case "turn/completed":
                guard let threadID = params["threadId"]?.stringValue,
                      let turn = params["turn"],
                      let turnID = turn["id"]?.stringValue else { return nil }
                let status = turn["status"]?.stringValue
                let state: AgentState = switch status {
                case "completed": .completed
                case "interrupted": .interrupted
                case "failed": .failed
                default: .failed
                }
                let summary = safeProviderMessage(
                    turn["error"]?["message"]?.stringValue,
                    fallback: "Codex turn failed"
                )
                return .turnCompleted(
                    AgentManagedTurnDescriptor(nativeSessionID: threadID, turnID: turnID),
                    state: state,
                    summary: summary
                )

            case "error":
                guard params["willRetry"]?.boolValue != true else { return nil }
                return .providerFailure(
                    nativeSessionID: params["threadId"]?.stringValue,
                    summary: safeProviderMessage(
                        params["error"]?["message"]?.stringValue,
                        fallback: "Codex turn failed"
                    )
                )

            case "item/started":
                guard let threadID = params["threadId"]?.stringValue,
                      let turnID = params["turnId"]?.stringValue,
                      let item = params["item"] else { return nil }
                return mapItem(
                    item,
                    nativeSessionID: threadID,
                    turnID: turnID,
                    completed: false
                ).map(AgentInteractiveProviderEvent.normalized)

            case "item/completed":
                guard let threadID = params["threadId"]?.stringValue,
                      let turnID = params["turnId"]?.stringValue,
                      let item = params["item"] else { return nil }
                if let transcript = mapTranscriptItem(
                    item,
                    nativeSessionID: threadID,
                    turnID: turnID,
                    timestamp: Date(),
                    includesSafeActivities: false
                ) {
                    return .transcript(transcript)
                }
                return mapItem(
                    item,
                    nativeSessionID: threadID,
                    turnID: turnID,
                    completed: true
                ).map(AgentInteractiveProviderEvent.normalized)

            case "item/agentMessage/delta":
                guard let threadID = params["threadId"]?.stringValue,
                      let turnID = params["turnId"]?.stringValue,
                      let itemID = params["itemId"]?.stringValue,
                      let delta = params["delta"]?.stringValue,
                      !delta.isEmpty else { return nil }
                return .transcriptDelta(
                    nativeSessionID: threadID,
                    turnID: turnID,
                    itemID: itemID,
                    delta: String(delta.prefix(AgentManagedTranscriptEntry.maximumTextLength))
                )

            case "thread/tokenUsage/updated":
                guard let threadID = params["threadId"]?.stringValue,
                      let turnID = params["turnId"]?.stringValue,
                      let usage = mapUsage(params["tokenUsage"] ?? .object([:])) else { return nil }
                return .normalized(AgentManagedNormalizedEvent(
                    nativeSessionID: threadID,
                    turnID: turnID,
                    type: .usageUpdated,
                    correlationID: nil,
                    payload: .usage(usage)
                ))

            case "account/rateLimits/updated":
                return .accountUsageChanged

            default:
                return nil
            }

        case .serverRequest(let id, let method, let params):
            switch method {
            case "item/commandExecution/requestApproval":
                guard let threadID = params["threadId"]?.stringValue,
                      let turnID = params["turnId"]?.stringValue,
                      let itemID = params["itemId"]?.stringValue,
                      let requestToken = interactiveRequestToken(id) else { return nil }
                let commandSummary = AgentPrivacyProjection.commandSummary(
                    executable: params["command"]?.stringValue
                )
                let summary = safeProviderMessage(
                    params["reason"]?.stringValue,
                    fallback: "Command approval: \(commandSummary)"
                )
                return .approvalRequested(AgentManagedApprovalRequest(
                    requestToken: requestToken,
                    kind: .command,
                    threadID: threadID,
                    turnID: turnID,
                    itemID: itemID,
                    summary: String(summary.prefix(AgentDomainLimits.summaryLength))
                ))

            case "item/fileChange/requestApproval":
                guard let threadID = params["threadId"]?.stringValue,
                      let turnID = params["turnId"]?.stringValue,
                      let itemID = params["itemId"]?.stringValue,
                      let requestToken = interactiveRequestToken(id) else { return nil }
                let summary = safeProviderMessage(
                    params["reason"]?.stringValue,
                    fallback: "File change approval required"
                )
                return .approvalRequested(AgentManagedApprovalRequest(
                    requestToken: requestToken,
                    kind: .fileChange,
                    threadID: threadID,
                    turnID: turnID,
                    itemID: itemID,
                    summary: String(summary.prefix(AgentDomainLimits.summaryLength))
                ))

            default:
                return nil
            }
        }
    }

    private nonisolated static func interactiveRequestToken(
        _ id: CodexJSONValue
    ) -> AgentInteractiveRequestToken? {
        switch id {
        case .string(let value): .string(value)
        case .integer(let value): .integer(value)
        default: nil
        }
    }

    private nonisolated static func mapTranscriptItem(
        _ item: CodexJSONValue,
        nativeSessionID: String,
        turnID: String,
        timestamp: Date,
        includesSafeActivities: Bool
    ) -> AgentManagedTranscriptEntry? {
        guard let itemType = item["type"]?.stringValue,
              let itemID = item["id"]?.stringValue else { return nil }

        let role: AgentManagedTranscriptRole
        let rawText: String?

        switch itemType {
        case "agentMessage":
            role = .agent
            rawText = item["text"]?.stringValue
        case "userMessage":
            role = .user
            let textParts = item["content"]?.arrayValue?.compactMap { input -> String? in
                guard input["type"]?.stringValue == "text" else { return nil }
                return input["text"]?.stringValue
            } ?? []
            rawText = textParts.isEmpty ? nil : textParts.joined(separator: "\n")
        case "commandExecution" where includesSafeActivities:
            role = .command
            rawText = AgentPrivacyProjection.commandSummary(
                executable: item["command"]?.stringValue
            )
        case "fileChange" where includesSafeActivities:
            role = .tool
            let count = item["changes"]?.arrayValue?.count ?? 0
            rawText = count > 0 ? "Updated \(count) file\(count == 1 ? "" : "s")" : "Updated files"
        case "mcpToolCall" where includesSafeActivities:
            role = .tool
            rawText = "Used \(AgentPrivacyProjection.toolName(item["tool"]?.stringValue))"
        case "dynamicToolCall" where includesSafeActivities:
            role = .tool
            rawText = "Used \(AgentPrivacyProjection.toolName(item["tool"]?.stringValue))"
        case "webSearch" where includesSafeActivities:
            role = .tool
            rawText = "Searched the web"
        case "plan" where includesSafeActivities:
            role = .plan
            rawText = "Plan updated"
        default:
            // Explicitly exclude reasoning, raw command output, environment-bearing
            // items, and all other internal provider payloads from the transcript.
            return nil
        }

        guard let text = AgentManagedTranscriptEntry.boundedText(rawText) else { return nil }
        return AgentManagedTranscriptEntry(
            id: itemID,
            nativeSessionID: nativeSessionID,
            turnID: turnID,
            role: role,
            text: text,
            timestamp: timestamp
        )
    }

    private nonisolated static func mapItem(
        _ item: CodexJSONValue,
        nativeSessionID: String,
        turnID: String,
        completed: Bool
    ) -> AgentManagedNormalizedEvent? {
        guard let itemType = item["type"]?.stringValue,
              let itemID = item["id"]?.stringValue else {
            return nil
        }
        let correlation = AgentCorrelationID(rawValue: itemID)
        let mapped: (AgentEventType, AgentEventPayload)?

        switch itemType {
        case "commandExecution":
            let executable = AgentPrivacyProjection.commandSummary(
                executable: item["command"]?.stringValue
            )
            let success: Bool? = completed
                ? (item["status"]?.stringValue == "completed" &&
                    (item["exitCode"]?.intValue ?? 0) == 0)
                : nil
            mapped = (
                completed ? .commandCompleted : .commandStarted,
                .command(AgentCommandEvent(
                    executable: executable,
                    success: success,
                    exitCode: completed ? item["exitCode"]?.intValue : nil
                ))
            )

        case "fileChange":
            let count = item["changes"]?.arrayValue?.count ?? 0
            mapped = (
                completed ? .toolCompleted : .toolStarted,
                .tool(AgentToolEvent(
                    name: "File change",
                    category: "edit",
                    summary: count > 0 ? "\(count) file\(count == 1 ? "" : "s")" : nil,
                    success: completed ? item["status"]?.stringValue == "completed" : nil
                ))
            )

        case "mcpToolCall":
            mapped = (
                completed ? .toolCompleted : .toolStarted,
                .tool(AgentToolEvent(
                    name: AgentPrivacyProjection.toolName(item["tool"]?.stringValue),
                    category: "mcp",
                    summary: AgentPrivacyProjection.summary(item["server"]?.stringValue),
                    success: completed ? item["status"]?.stringValue == "completed" : nil
                ))
            )

        case "dynamicToolCall":
            mapped = (
                completed ? .toolCompleted : .toolStarted,
                .tool(AgentToolEvent(
                    name: AgentPrivacyProjection.toolName(item["tool"]?.stringValue),
                    category: "tool",
                    summary: nil,
                    success: completed ? item["success"]?.boolValue : nil
                ))
            )

        case "webSearch":
            mapped = (
                completed ? .toolCompleted : .toolStarted,
                .tool(AgentToolEvent(
                    name: "Web search",
                    category: "search",
                    summary: nil,
                    success: completed ? true : nil
                ))
            )

        case "plan" where completed:
            mapped = (
                .planUpdated,
                .plan(AgentPlanEvent(
                    summary: AgentPrivacyProjection.summary(item["text"]?.stringValue)
                ))
            )

        default:
            mapped = nil
        }

        guard let mapped else { return nil }
        return AgentManagedNormalizedEvent(
            nativeSessionID: nativeSessionID,
            turnID: turnID,
            type: mapped.0,
            correlationID: correlation,
            payload: mapped.1
        )
    }

    nonisolated static func mapUsage(_ payload: CodexJSONValue) -> AgentUsage? {
        guard let total = payload["total"] else { return nil }
        let observedAt = Date()
        var samples: [AgentUsageKey: AgentUsageSample] = [:]

        func add(_ metric: AgentUsageMetric, _ field: String, scope: String = "thread") {
            guard let value = total[field]?.doubleValue, value >= 0 else { return }
            samples[AgentUsageKey(metric: metric, scope: scope)] = AgentUsageSample(
                value: value,
                limit: nil,
                unit: .tokens,
                scope: scope,
                source: "codex-app-server",
                observedAt: observedAt
            )
        }

        add(.inputTokens, "inputTokens")
        add(.outputTokens, "outputTokens")
        add(.cachedInputTokens, "cachedInputTokens")
        add(.reasoningTokens, "reasoningOutputTokens")

        if let used = payload["last"]?["totalTokens"]?.doubleValue,
           let context = contextUsage(
               currentTokens: used,
               modelContextWindow: payload["modelContextWindow"]?.doubleValue,
               source: "codex-app-server",
               observedAt: observedAt
           ) {
            for entry in context.scopedEntries {
                samples[entry.key] = entry.value
            }
        }

        return samples.isEmpty ? nil : AgentUsage(scopedSamples: samples)
    }

    private nonisolated static func safeProviderMessage(
        _ value: String?,
        fallback: String
    ) -> String {
        guard let normalized = AgentPrivacyProjection.normalized(value) else { return fallback }
        let lower = normalized.lowercased()
        let sensitive = [
            "token", "secret", "password", "authorization", "bearer",
            "api_key", "api-key", "cookie", "environment="
        ]
        guard !sensitive.contains(where: lower.contains) else { return fallback }
        return AgentPrivacyProjection.title(normalized, fallback: fallback)
    }
}
