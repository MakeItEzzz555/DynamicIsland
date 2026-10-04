import Foundation

/// A configured agent/profile Claude Code itself exposes (system/init
/// `agents`). Selected with `--agent` at session start.
struct AgentManagedAgentDescriptor: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

/// Managed Claude Code sessions over the supported CLI stream-json
/// transport (see ClaudeCodeStreamingClient for the verified flags).
///
/// Identity: new sessions get a UUID passed as `--session-id`; resumed
/// sessions keep their exact id. Model and agent are fixed at session
/// start (no in-place switching is claimed). Permission prompts arrive as
/// `can_use_tool` control requests and are answered once, per exact
/// request id, through the shared approval flow.
actor ClaudeInteractiveProvider: AgentInteractiveProvider {
    static let maximumKnownSessions = 20
    static let maximumPendingPermissions = 32
    static let usageProbeInterval: TimeInterval = 5 * 60

    /// CLI model aliases. `fable`, `opus` and `sonnet` are the aliases the
    /// installed CLI documents; `haiku` was verified by launch. The actual
    /// resolved model is shown from the session's init message.
    static let modelAliases: [AgentManagedModelDescriptor] = [
        AgentManagedModelDescriptor(id: "fable", model: "fable", displayName: "Fable", description: "Latest Fable (CLI alias)", isDefault: false),
        AgentManagedModelDescriptor(id: "opus", model: "opus", displayName: "Opus", description: "Latest Opus (CLI alias)", isDefault: false),
        AgentManagedModelDescriptor(id: "sonnet", model: "sonnet", displayName: "Sonnet", description: "Latest Sonnet (CLI alias)", isDefault: false),
        AgentManagedModelDescriptor(id: "haiku", model: "haiku", displayName: "Haiku", description: "Latest Haiku (CLI alias)", isDefault: false)
    ]

    nonisolated let provider: AgentProvider = .claude
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .startSession,
        .resumeSession,
        .submitPrompt,
        .interrupt,
        .selectModel,
        .resolveApprovals,
        .accountUsage,
        .contextUsage,
        .streamMessages,
        .streamToolActivity
    ]
    /// Claude cannot switch a running session's model; model selection
    /// applies only when starting a new session.
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = nil

    private struct PendingPermission {
        let request: AgentManagedApprovalRequest
        let input: CodexJSONValue
    }

    private let client: ClaudeCodeStreamingClient
    private let usageProbe: ClaudeUsageProbing?
    private let catalog: ClaudeSessionCataloging
    private let now: @Sendable () -> Date
    private var knownSessions: [String: AgentDiscoveredSessionDescriptor] = [:]
    private var launchSpecs: [String: ClaudeLaunchSpec] = [:]
    private var streamMessageIDs: [String: String] = [:]
    /// Last `content_block_start` per session. With partial messages the
    /// CLI sends one `assistant` event per block (content = that block
    /// only), so the stream index is the block's true identity.
    private var streamBlockStarts: [String: (messageID: String, index: Int)] = [:]
    private var pendingPermissions: [String: PendingPermission] = [:]
    /// Answered permissions awaiting the CLI's `tool_result` for the exact
    /// tool use (session:toolUseID -> request id). Bounded like pending ones.
    private var answeredPermissions: [String: String] = [:]
    private var lastAssistantContext: [String: Double] = [:]
    private var accountUsage = AgentUsage()
    private var accountUsageUpdatedAt: Date?
    private var probeInFlight = false
    private var availableAgents: [AgentManagedAgentDescriptor] = []

    init(
        client: ClaudeCodeStreamingClient,
        usageProbe: ClaudeUsageProbing? = nil,
        catalog: ClaudeSessionCataloging = ClaudeSessionCatalog(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.usageProbe = usageProbe
        self.catalog = catalog
        self.now = now
    }

    static func makeDefault() throws -> ClaudeInteractiveProvider {
        ClaudeInteractiveProvider(
            client: try ClaudeCodeStreamingClient(),
            usageProbe: ClaudeUsageCommandProbe.makeDefault()
        )
    }

    func events() async -> AsyncStream<AgentInteractiveProviderEvent> {
        let upstream = await client.events()
        return AsyncStream { continuation in
            let task = Task {
                for await event in upstream {
                    for mapped in self.map(event) {
                        continuation.yield(mapped)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: Sessions

    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        var merged = knownSessions
        for entry in (try? catalog.recentSessions(limit: Self.maximumKnownSessions)) ?? [] where merged[entry.nativeSessionID] == nil {
            merged[entry.nativeSessionID] = AgentDiscoveredSessionDescriptor(
                session: AgentManagedSessionDescriptor(
                    provider: .claude,
                    nativeSessionID: entry.nativeSessionID,
                    cwd: entry.cwd,
                    model: nil,
                    acceptsDirectInput: true
                ),
                runtimeState: .notLoaded,
                updatedAt: entry.updatedAt
            )
        }
        return Array(merged.values)
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.session.nativeSessionID < $1.session.nativeSessionID
            }
            .prefix(Self.maximumKnownSessions)
            .map { $0 }
    }

    func inspectSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor? {
        if let known = knownSessions[nativeSessionID]?.session { return known }
        guard let entry = try? catalog.session(nativeSessionID: nativeSessionID) else { return nil }
        return AgentManagedSessionDescriptor(
            provider: .claude,
            nativeSessionID: entry.nativeSessionID,
            cwd: entry.cwd,
            model: nil,
            acceptsDirectInput: true
        )
    }

    func readTranscript(nativeSessionID: String, limit: Int) async throws -> [AgentManagedTranscriptEntry] { [] }

    func listModels() async throws -> [AgentManagedModelDescriptor] {
        Self.modelAliases
    }

    func listAgents() async throws -> [AgentManagedAgentDescriptor] {
        if availableAgents.isEmpty { await refreshUsage(force: true) }
        return availableAgents
    }

    func startSession(cwd: String?, model: String?) async throws -> AgentManagedSessionDescriptor {
        try await startSession(cwd: cwd, model: model, agent: nil)
    }

    func startSession(cwd: String?, model: String?, agent: String?) async throws -> AgentManagedSessionDescriptor {
        if let model, !Self.modelAliases.contains(where: { $0.model == model }) {
            throw ClaudeCodeStreamingError.unsupported
        }
        if let agent, !availableAgents.isEmpty, !availableAgents.contains(where: { $0.name == agent }) {
            throw ClaudeCodeStreamingError.unsupported
        }
        let nativeID = UUID().uuidString.lowercased()
        let spec = ClaudeLaunchSpec(nativeSessionID: nativeID, mode: .new, cwd: cwd, model: model, agent: agent)
        launchSpecs[nativeID] = spec
        let descriptor = AgentManagedSessionDescriptor(
            provider: .claude,
            nativeSessionID: nativeID,
            cwd: cwd,
            model: model,
            acceptsDirectInput: true
        )
        remember(descriptor, state: .idle)
        return descriptor
    }

    func resumeSession(nativeSessionID: String, cwd: String?) async throws -> AgentManagedSessionDescriptor {
        let existingCwd = launchSpecs[nativeSessionID]?.cwd
        let spec = ClaudeLaunchSpec(
            nativeSessionID: nativeSessionID,
            mode: .resume,
            cwd: cwd ?? existingCwd,
            model: launchSpecs[nativeSessionID]?.model,
            agent: launchSpecs[nativeSessionID]?.agent
        )
        // A new session that has not sent its first turn keeps `.new`.
        if launchSpecs[nativeSessionID]?.mode != .new {
            launchSpecs[nativeSessionID] = spec
        }
        let descriptor = AgentManagedSessionDescriptor(
            provider: .claude,
            nativeSessionID: nativeSessionID,
            cwd: spec.cwd,
            model: spec.model,
            acceptsDirectInput: true
        )
        remember(descriptor, state: .idle)
        return descriptor
    }

    func submit(prompt: String, nativeSessionID: String, model: String?) async throws -> AgentManagedTurnDescriptor {
        // Model is fixed per session; a different model needs a new session.
        if let model, model != launchSpecs[nativeSessionID]?.model {
            throw ClaudeCodeStreamingError.unsupported
        }
        let spec = launchSpecs[nativeSessionID] ?? ClaudeLaunchSpec(
            nativeSessionID: nativeSessionID,
            mode: .resume,
            cwd: knownSessions[nativeSessionID]?.session.cwd,
            model: nil,
            agent: nil
        )
        let turn = try await client.submit(prompt: prompt, spec: spec)
        // After the first turn a new session exists on disk; later launches resume it.
        launchSpecs[nativeSessionID] = ClaudeLaunchSpec(
            nativeSessionID: nativeSessionID,
            mode: .resume,
            cwd: spec.cwd,
            model: spec.model,
            agent: spec.agent
        )
        if let current = knownSessions[nativeSessionID] {
            knownSessions[nativeSessionID] = AgentDiscoveredSessionDescriptor(
                session: current.session,
                runtimeState: .active,
                updatedAt: now()
            )
        }
        return turn
    }

    func interrupt(nativeSessionID: String, turnID: String) async throws {
        guard await client.activeTurn(nativeSessionID) == turnID else {
            throw ClaudeCodeStreamingError.sessionNotRunning
        }
        try await client.interrupt(nativeSessionID: nativeSessionID)
    }

    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {
        guard let pending = pendingPermissions.removeValue(
            forKey: Self.permissionKey(request.threadID, request.requestID)
        ),
              pending.request.threadID == request.threadID,
              pending.request.turnID == request.turnID else {
            // Unknown or already-answered request: one-shot, never reused.
            throw ClaudeCodeStreamingError.malformedMessage
        }
        if answeredPermissions.count >= Self.maximumPendingPermissions {
            answeredPermissions.removeAll()
        }
        answeredPermissions[Self.permissionKey(request.threadID, pending.request.itemID)] = request.requestID
        try await client.respondToPermission(
            nativeSessionID: request.threadID,
            requestID: request.requestID,
            allow: allow,
            input: pending.input
        )
    }

    func stop() async {
        await client.stop()
    }

    // MARK: Usage

    func readAccountUsage() async throws -> AgentUsage {
        await refreshUsage(force: false)
        return accountUsage
    }

    /// Runs the local `/usage` probe at most every few minutes; turn-driven
    /// rate-limit events keep usage fresh while Claude is active.
    private func refreshUsage(force: Bool) async {
        guard let usageProbe, !probeInFlight else { return }
        if !force, let updated = accountUsageUpdatedAt, now().timeIntervalSince(updated) < Self.usageProbeInterval {
            return
        }
        probeInFlight = true
        defer { probeInFlight = false }
        guard let result = try? await usageProbe.probe() else { return }
        if !result.availableAgents.isEmpty {
            availableAgents = result.availableAgents.sorted().map { AgentManagedAgentDescriptor(id: $0, name: $0) }
        }
        if let windows = result.windows {
            applyUsage(windows, source: ClaudeUsageSource.usageCommand)
        } else {
            // Probe ran but produced nothing parseable: mark as refreshed so we
            // do not hammer it; indicators age into stale/unavailable.
            accountUsageUpdatedAt = now()
        }
    }

    private func applyUsage(_ windows: ClaudeUsageWindows, source: String) {
        let observed = now()
        var merged = accountUsage
        merged.merge(windows.usage(source: source, observedAt: observed))
        accountUsage = merged
        accountUsageUpdatedAt = observed
    }

    // MARK: Event mapping

    private func map(_ event: ClaudeCodeStreamEvent) -> [AgentInteractiveProviderEvent] {
        switch event {
        case .transportFailed(let nativeSessionID, _):
            streamMessageIDs.removeValue(forKey: nativeSessionID)
            streamBlockStarts.removeValue(forKey: nativeSessionID)
            dropPermissions(for: nativeSessionID)
            markIdle(nativeSessionID)
            return [.providerFailure(nativeSessionID: nativeSessionID, summary: "Claude Code stopped unexpectedly")]
        case .sessionExited(let nativeSessionID):
            dropPermissions(for: nativeSessionID)
            markIdle(nativeSessionID)
            return []
        case .message(let envelope):
            return project(envelope)
        }
    }

    func project(_ envelope: ClaudeCodeStreamEnvelope) -> [AgentInteractiveProviderEvent] {
        let message = envelope.message
        guard let type = message["type"]?.stringValue else { return [] }
        switch type {
        case "system" where message["subtype"]?.stringValue == "init":
            if let agents = message["agents"]?.arrayValue?.compactMap(\.stringValue), !agents.isEmpty {
                availableAgents = agents.sorted().map { AgentManagedAgentDescriptor(id: $0, name: $0) }
            }
            let descriptor = AgentManagedSessionDescriptor(
                provider: .claude,
                nativeSessionID: envelope.nativeSessionID,
                cwd: message["cwd"]?.stringValue ?? launchSpecs[envelope.nativeSessionID]?.cwd,
                model: message["model"]?.stringValue,
                acceptsDirectInput: true
            )
            remember(descriptor, state: .active)
            return [.threadAvailable(descriptor)]

        case "stream_event":
            return mapStreamEvent(envelope)

        case "user":
            return mapToolResultAcknowledgements(envelope)

        case "assistant":
            recordAssistantContext(envelope)
            return mapAssistantMessage(envelope)

        case "control_request":
            return mapControlRequest(envelope)

        case "control_cancel_request":
            // The CLI withdrew one exact pending permission (for example after
            // an interrupt). It must never be answered afterwards.
            guard let requestID = message["request_id"]?.stringValue,
                  pendingPermissions.removeValue(
                      forKey: Self.permissionKey(envelope.nativeSessionID, requestID)
                  ) != nil else { return [] }
            return [.approvalCancelled(nativeSessionID: envelope.nativeSessionID, requestID: requestID)]

        case "rate_limit_event":
            guard let windows = ClaudeRateLimitParser.parse(message["rate_limit_info"]) else { return [] }
            applyUsage(windows, source: ClaudeUsageSource.rateLimitEvent)
            return [.accountUsageChanged]

        case "result":
            return mapResult(envelope)

        default:
            return []
        }
    }

    private func mapResult(_ envelope: ClaudeCodeStreamEnvelope) -> [AgentInteractiveProviderEvent] {
        let message = envelope.message
        let aborted = message["terminal_reason"]?.stringValue == "aborted_streaming"
        let failed = message["is_error"]?.boolValue == true || message["subtype"]?.stringValue != "success"
        let state: AgentState = aborted ? .interrupted : (failed ? .failed : .completed)
        markIdle(envelope.nativeSessionID)
        streamMessageIDs.removeValue(forKey: envelope.nativeSessionID)
        streamBlockStarts.removeValue(forKey: envelope.nativeSessionID)
        dropPermissions(for: envelope.nativeSessionID)
        var events: [AgentInteractiveProviderEvent] = []
        if let context = contextUsage(from: message, nativeSessionID: envelope.nativeSessionID) {
            events.append(.normalized(AgentManagedNormalizedEvent(
                nativeSessionID: envelope.nativeSessionID,
                turnID: nil,
                type: .usageUpdated,
                correlationID: nil,
                payload: .usage(context)
            )))
        }
        events.append(.turnCompleted(
            AgentManagedTurnDescriptor(nativeSessionID: envelope.nativeSessionID, turnID: envelope.turnID),
            state: state,
            summary: state == .failed ? "Claude turn failed" : nil
        ))
        return events
    }

    /// Context used = the latest main-thread request size; the window size
    /// comes from `result.modelUsage[model].contextWindow` (authoritative).
    private func contextUsage(from result: CodexJSONValue, nativeSessionID: String) -> AgentUsage? {
        guard let used = lastAssistantContext[nativeSessionID] else { return nil }
        let windows = result["modelUsage"]?.objectValue?.values.compactMap { $0["contextWindow"]?.doubleValue } ?? []
        let limit = windows.max()
        return AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .contextUsed, scope: "context"): AgentUsageSample(
                value: limit.map { min(used, $0) } ?? used,
                limit: limit,
                unit: .tokens,
                scope: "context",
                source: "claude-stream-json",
                observedAt: now()
            )
        ])
    }

    private func recordAssistantContext(_ envelope: ClaudeCodeStreamEnvelope) {
        guard envelope.message["parent_tool_use_id"]?.stringValue == nil,
              let usage = envelope.message["message"]?["usage"] else { return }
        let parts = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
            .compactMap { usage[$0]?.doubleValue }
        guard !parts.isEmpty else { return }
        let total = parts.reduce(0, +)
        if total > 0 { lastAssistantContext[envelope.nativeSessionID] = total }
    }

    private func mapControlRequest(_ envelope: ClaudeCodeStreamEnvelope) -> [AgentInteractiveProviderEvent] {
        guard let request = envelope.message["request"],
              request["subtype"]?.stringValue == "can_use_tool",
              let requestID = envelope.message["request_id"]?.stringValue,
              let toolName = request["tool_name"]?.stringValue else { return [] }
        let input = request["input"] ?? .object([:])
        let isCommand = toolName == "Bash" || toolName == "Shell"
        let approval = AgentManagedApprovalRequest(
            requestToken: .string(requestID),
            requestID: requestID,
            kind: isCommand ? .command : .fileChange,
            threadID: envelope.nativeSessionID,
            turnID: envelope.turnID,
            itemID: request["tool_use_id"]?.stringValue ?? requestID,
            summary: isCommand ? "Run a command" : Self.safeToolTitle(toolName)
        )
        let key = Self.permissionKey(envelope.nativeSessionID, requestID)
        guard pendingPermissions[key] != nil || pendingPermissions.count < Self.maximumPendingPermissions else {
            // Bounded: beyond capacity a request is not projected (and so can
            // never be approved); the CLI keeps its request pending.
            return []
        }
        pendingPermissions[key] = PendingPermission(request: approval, input: input)
        return [.approvalRequested(approval)]
    }

    private func mapStreamEvent(_ envelope: ClaudeCodeStreamEnvelope) -> [AgentInteractiveProviderEvent] {
        guard envelope.message["parent_tool_use_id"]?.stringValue == nil,
              let event = envelope.message["event"],
              let eventType = event["type"]?.stringValue else { return [] }
        if eventType == "message_start",
           let messageID = event["message"]?["id"]?.stringValue {
            streamMessageIDs[envelope.nativeSessionID] = messageID
            streamBlockStarts.removeValue(forKey: envelope.nativeSessionID)
            return []
        }
        if eventType == "content_block_start",
           let messageID = streamMessageIDs[envelope.nativeSessionID],
           let index = event["index"]?.intValue {
            streamBlockStarts[envelope.nativeSessionID] = (messageID, index)
            return []
        }
        guard eventType == "content_block_delta",
              event["delta"]?["type"]?.stringValue == "text_delta",
              let text = AgentManagedTranscriptEntry.boundedText(event["delta"]?["text"]?.stringValue, preservingWhitespace: true),
              let messageID = streamMessageIDs[envelope.nativeSessionID] else {
            return []
        }
        let index = event["index"]?.intValue ?? 0
        return [.transcriptDelta(
            nativeSessionID: envelope.nativeSessionID,
            turnID: envelope.turnID,
            itemID: "\(messageID):text:\(index)",
            delta: text
        )]
    }

    private func mapAssistantMessage(_ envelope: ClaudeCodeStreamEnvelope) -> [AgentInteractiveProviderEvent] {
        guard let payload = envelope.message["message"],
              let messageID = payload["id"]?.stringValue,
              let blocks = payload["content"]?.arrayValue else { return [] }
        var mapped: [AgentInteractiveProviderEvent] = []
        let streamedIndex: Int? = blocks.count == 1
            ? streamBlockStarts[envelope.nativeSessionID].flatMap { $0.messageID == messageID ? $0.index : nil }
            : nil
        for (position, block) in blocks.enumerated() {
            let index = streamedIndex ?? position
            switch block["type"]?.stringValue {
            case "text":
                guard let text = AgentManagedTranscriptEntry.boundedText(block["text"]?.stringValue, preservingWhitespace: true) else { continue }
                mapped.append(.transcript(AgentManagedTranscriptEntry(
                    id: "\(messageID):text:\(index)",
                    nativeSessionID: envelope.nativeSessionID,
                    turnID: envelope.turnID,
                    role: .agent,
                    text: text,
                    timestamp: now()
                )))
            case "tool_use":
                guard let name = block["name"]?.stringValue else { continue }
                let isCommand = name == "Bash" || name == "Shell"
                mapped.append(.transcript(AgentManagedTranscriptEntry(
                    id: block["id"]?.stringValue ?? "\(messageID):tool:\(index)",
                    nativeSessionID: envelope.nativeSessionID,
                    turnID: envelope.turnID,
                    role: isCommand ? .command : .tool,
                    text: isCommand ? "Run command" : Self.safeToolTitle(name),
                    timestamp: now()
                )))
            default:
                // Thinking/redacted thinking are never projected.
                continue
            }
        }
        return mapped
    }

    // MARK: Helpers

    private func remember(_ descriptor: AgentManagedSessionDescriptor, state: AgentDiscoveredSessionRuntimeState) {
        knownSessions[descriptor.nativeSessionID] = AgentDiscoveredSessionDescriptor(
            session: descriptor,
            runtimeState: state,
            updatedAt: now()
        )
        pruneKnownSessions()
    }

    private func markIdle(_ nativeSessionID: String) {
        guard let current = knownSessions[nativeSessionID] else { return }
        knownSessions[nativeSessionID] = AgentDiscoveredSessionDescriptor(
            session: current.session,
            runtimeState: .idle,
            updatedAt: now()
        )
    }

    private func dropPermissions(for nativeSessionID: String) {
        pendingPermissions = pendingPermissions.filter { $0.value.request.threadID != nativeSessionID }
        answeredPermissions = answeredPermissions.filter { !$0.key.hasPrefix("\(nativeSessionID):") }
    }

    /// The CLI reports the outcome of an answered permission as the
    /// `tool_result` of that exact tool use (allowed: the tool ran; denied:
    /// an error result). Only results for answered permissions count.
    private func mapToolResultAcknowledgements(_ envelope: ClaudeCodeStreamEnvelope) -> [AgentInteractiveProviderEvent] {
        guard !answeredPermissions.isEmpty,
              let content = envelope.message["message"]?["content"]?.arrayValue else { return [] }
        return content.compactMap { block in
            guard block["type"]?.stringValue == "tool_result",
                  let toolUseID = block["tool_use_id"]?.stringValue,
                  let requestID = answeredPermissions.removeValue(
                      forKey: Self.permissionKey(envelope.nativeSessionID, toolUseID)
                  ) else { return nil }
            return .approvalAcknowledged(
                nativeSessionID: envelope.nativeSessionID,
                requestToken: .string(requestID)
            )
        }
    }

    private func pruneKnownSessions() {
        guard knownSessions.count > Self.maximumKnownSessions else { return }
        let keep = Set(
            knownSessions.values
                .sorted {
                    if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                    return $0.session.nativeSessionID < $1.session.nativeSessionID
                }
                .prefix(Self.maximumKnownSessions)
                .map { $0.session.nativeSessionID }
        )
        knownSessions = knownSessions.filter { keep.contains($0.key) }
        streamMessageIDs = streamMessageIDs.filter { keep.contains($0.key) }
        streamBlockStarts = streamBlockStarts.filter { keep.contains($0.key) }
    }

    /// Claude request ids are only unique per process; bind them to the
    /// exact session so two sessions can never answer each other's request.
    private nonisolated static func permissionKey(_ nativeSessionID: String, _ requestID: String) -> String {
        "\(nativeSessionID)\u{0}\(requestID)"
    }

    private nonisolated static func safeToolTitle(_ name: String) -> String {
        let safe = AgentPrivacyProjection.title(name, fallback: "Use tool")
        return safe == "Use tool" ? safe : "Use \(safe)"
    }
}

// MARK: - Session catalog

struct ClaudeCatalogEntry: Equatable, Sendable {
    let nativeSessionID: String
    let cwd: String?
    let updatedAt: Date
}

protocol ClaudeSessionCataloging: Sendable {
    func recentSessions(limit: Int) throws -> [ClaudeCatalogEntry]
    func session(nativeSessionID: String) throws -> ClaudeCatalogEntry?
}

/// Lists Claude Code's own session transcripts (`~/.claude/projects/*/<id>.jsonl`)
/// by modification time, reading only a bounded prefix for `cwd`. Runs on
/// the provider actor, never on the main thread.
struct ClaudeSessionCatalog: ClaudeSessionCataloging {
    var root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects", isDirectory: true)

    func recentSessions(limit: Int) throws -> [ClaudeCatalogEntry] {
        let fileManager = FileManager.default
        guard let projects = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        var candidates: [(URL, Date)] = []
        for project in projects {
            guard let files = try? fileManager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }
            for file in files where file.pathExtension == "jsonl" && Self.isSessionID(file.deletingPathExtension().lastPathComponent) {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                candidates.append((file, date))
            }
        }
        return candidates
            .sorted { $0.1 > $1.1 }
            .prefix(max(limit, 0))
            .map { ClaudeCatalogEntry(nativeSessionID: $0.0.deletingPathExtension().lastPathComponent, cwd: Self.cwd(in: $0.0), updatedAt: $0.1) }
    }

    func session(nativeSessionID: String) throws -> ClaudeCatalogEntry? {
        guard Self.isSessionID(nativeSessionID) else { return nil }
        let fileManager = FileManager.default
        guard let projects = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return nil }
        for project in projects {
            let file = project.appendingPathComponent("\(nativeSessionID).jsonl")
            if fileManager.fileExists(atPath: file.path) {
                let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return ClaudeCatalogEntry(nativeSessionID: nativeSessionID, cwd: Self.cwd(in: file), updatedAt: date)
            }
        }
        return nil
    }

    static func isSessionID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    /// Reads at most 64 KB and returns the first `cwd` value.
    static func cwd(in file: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 64 * 1024) else { return nil }
        for line in data.split(separator: 0x0A) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let cwd = object["cwd"] as? String, !cwd.isEmpty else { continue }
            return cwd
        }
        return nil
    }
}
