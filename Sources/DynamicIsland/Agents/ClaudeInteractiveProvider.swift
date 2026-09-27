import Foundation

actor ClaudeInteractiveProvider: AgentInteractiveProvider {
    static let maximumKnownSessions = 20
    nonisolated let provider: AgentProvider = .claude
    nonisolated let interactiveCapabilities: Set<AgentInteractiveCapability> = [
        .resumeSession,
        .submitPrompt,
        .streamToolActivity
    ]
    nonisolated let modelSelectionScope: AgentModelSelectionScope? = nil

    private let client: ClaudeCodeStreamingClient
    private var knownSessions: [String: AgentDiscoveredSessionDescriptor] = [:]
    private var streamMessageIDs: [String: String] = [:]

    init(client: ClaudeCodeStreamingClient) {
        self.client = client
    }

    static func makeDefault() throws -> ClaudeInteractiveProvider {
        ClaudeInteractiveProvider(client: try ClaudeCodeStreamingClient())
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

    func discoverSessions() async throws -> [AgentDiscoveredSessionDescriptor] {
        Array(knownSessions.values)
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.session.nativeSessionID < $1.session.nativeSessionID
            }
            .prefix(Self.maximumKnownSessions)
            .map { $0 }
    }

    func readAccountUsage() async throws -> AgentUsage { AgentUsage() }

    func readTranscript(
        nativeSessionID: String,
        limit: Int
    ) async throws -> [AgentManagedTranscriptEntry] { [] }

    func listModels() async throws -> [AgentManagedModelDescriptor] { [] }

    func startSession(cwd: String?) async throws -> AgentManagedSessionDescriptor {
        throw ClaudeCodeStreamingError.unsupported
    }

    func resumeSession(nativeSessionID: String) async throws -> AgentManagedSessionDescriptor {
        let descriptor = AgentManagedSessionDescriptor(
            provider: .claude,
            nativeSessionID: nativeSessionID,
            cwd: nil,
            model: nil,
            acceptsDirectInput: true
        )
        knownSessions[nativeSessionID] = AgentDiscoveredSessionDescriptor(
            session: descriptor,
            runtimeState: .idle,
            updatedAt: Date()
        )
        pruneKnownSessions()
        return descriptor
    }

    func submit(
        prompt: String,
        nativeSessionID: String,
        model: String?
    ) async throws -> AgentManagedTurnDescriptor {
        guard model == nil else { throw ClaudeCodeStreamingError.unsupported }
        let turn = try await client.submit(prompt: prompt, nativeSessionID: nativeSessionID)
        if let current = knownSessions[nativeSessionID] {
            knownSessions[nativeSessionID] = AgentDiscoveredSessionDescriptor(
                session: current.session,
                runtimeState: .active,
                updatedAt: Date()
            )
        }
        return turn
    }

    func interrupt(nativeSessionID: String, turnID: String) async throws {
        throw ClaudeCodeStreamingError.unsupported
    }

    func resolveApproval(_ request: AgentManagedApprovalRequest, allow: Bool) async throws {
        throw ClaudeCodeStreamingError.unsupported
    }

    func stop() async {
        await client.stop()
    }

    private func map(_ event: ClaudeCodeStreamEvent) -> [AgentInteractiveProviderEvent] {
        switch event {
        case .transportFailed(let nativeSessionID, _):
            streamMessageIDs.removeValue(forKey: nativeSessionID)
            return [.providerFailure(
                nativeSessionID: nativeSessionID,
                summary: "Claude control transport failed"
            )]
        case .message(let envelope):
            return project(envelope)
        }
    }

    func project(_ envelope: ClaudeCodeStreamEnvelope) -> [AgentInteractiveProviderEvent] {
        let message = envelope.message
        guard let type = message["type"]?.stringValue else { return [] }
        switch type {
        case "system" where message["subtype"]?.stringValue == "init":
            let descriptor = AgentManagedSessionDescriptor(
                provider: .claude,
                nativeSessionID: envelope.nativeSessionID,
                cwd: message["cwd"]?.stringValue,
                model: message["model"]?.stringValue,
                acceptsDirectInput: true
            )
            knownSessions[envelope.nativeSessionID] = AgentDiscoveredSessionDescriptor(
                session: descriptor,
                runtimeState: .active,
                updatedAt: Date()
            )
            pruneKnownSessions()
            return [.threadAvailable(descriptor)]

        case "stream_event":
            return mapStreamEvent(envelope)

        case "assistant":
            return mapAssistantMessage(envelope)

        case "result":
            let failed = message["is_error"]?.boolValue == true ||
                message["subtype"]?.stringValue != "success"
            if let current = knownSessions[envelope.nativeSessionID] {
                knownSessions[envelope.nativeSessionID] = AgentDiscoveredSessionDescriptor(
                    session: current.session,
                    runtimeState: .idle,
                    updatedAt: Date()
                )
            }
            streamMessageIDs.removeValue(forKey: envelope.nativeSessionID)
            pruneKnownSessions()
            return [.turnCompleted(
                AgentManagedTurnDescriptor(
                    nativeSessionID: envelope.nativeSessionID,
                    turnID: envelope.turnID
                ),
                state: failed ? .failed : .completed,
                summary: failed ? "Claude turn failed" : nil
            )]

        default:
            return []
        }
    }

    private func mapStreamEvent(
        _ envelope: ClaudeCodeStreamEnvelope
    ) -> [AgentInteractiveProviderEvent] {
        guard let event = envelope.message["event"],
              let eventType = event["type"]?.stringValue else { return [] }
        if eventType == "message_start",
           let messageID = event["message"]?["id"]?.stringValue {
            streamMessageIDs[envelope.nativeSessionID] = messageID
            return []
        }
        guard eventType == "content_block_delta",
              event["delta"]?["type"]?.stringValue == "text_delta",
              let text = AgentManagedTranscriptEntry.boundedText(
                event["delta"]?["text"]?.stringValue
              ),
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

    private func mapAssistantMessage(
        _ envelope: ClaudeCodeStreamEnvelope
    ) -> [AgentInteractiveProviderEvent] {
        guard let payload = envelope.message["message"],
              let messageID = payload["id"]?.stringValue,
              let blocks = payload["content"]?.arrayValue else { return [] }
        var mapped: [AgentInteractiveProviderEvent] = []
        for (index, block) in blocks.enumerated() {
            switch block["type"]?.stringValue {
            case "text":
                guard let text = AgentManagedTranscriptEntry.boundedText(block["text"]?.stringValue) else {
                    continue
                }
                mapped.append(.transcript(AgentManagedTranscriptEntry(
                    id: "\(messageID):text:\(index)",
                    nativeSessionID: envelope.nativeSessionID,
                    turnID: envelope.turnID,
                    role: .agent,
                    text: text,
                    timestamp: Date()
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
                    timestamp: Date()
                )))
            case "thinking", "redacted_thinking":
                continue
            default:
                continue
            }
        }
        return mapped
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
    }

    private nonisolated static func safeToolTitle(_ name: String) -> String {
        let safe = AgentPrivacyProjection.title(name, fallback: "Use tool")
        return safe == "Use tool" ? safe : "Use \(safe)"
    }
}
