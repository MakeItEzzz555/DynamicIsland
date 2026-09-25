import CryptoKit
import Foundation

enum ClaudeTranscriptRecoveryError: Error, Equatable, Sendable {
    case malformedRecord
    case unsupportedRecord
    case missingSession
}

struct ClaudeTranscriptRecoveryParser: Sendable {
    private enum OperationKind: Sendable {
        case tool(name: String)
        case command(executable: String)
    }

    private(set) var sessionID: String?
    private var activeOperations: [String: OperationKind] = [:]
    private var emittedSessionStart = false

    mutating func parse(
        _ record: Data,
        receivedAt: Date = Date()
    ) throws -> [AgentIngestionEvent] {
        guard !record.isEmpty,
              record.count <= AppendOnlyRecordLimits.maximumRecordBytes,
              let root = try? JSONSerialization.jsonObject(with: record) as? [String: Any] else {
            throw ClaudeTranscriptRecoveryError.malformedRecord
        }

        let nativeID = Self.boundedString(
            root["sessionId"] ?? root["session_id"],
            maximumBytes: AgentDomainLimits.identifierLength
        ) ?? sessionID
        guard let nativeID else { throw ClaudeTranscriptRecoveryError.missingSession }
        sessionID = nativeID

        let timestamp = Self.parseDate(root["timestamp"] as? String)
        let uuid = Self.boundedString(root["uuid"], maximumBytes: AgentDomainLimits.identifierLength)
        let cwd = Self.boundedString(root["cwd"], maximumBytes: AgentDomainLimits.pathLength)
        let gitBranch = Self.boundedString(root["gitBranch"], maximumBytes: AgentDomainLimits.summaryLength)
        var events: [AgentIngestionEvent] = []

        let startedSession = !emittedSessionStart
        if startedSession {
            emittedSessionStart = true
            let context = Self.projectContext(cwd: cwd, gitBranch: gitBranch, model: nil)
            events.append(event(
                nativeID: nativeID,
                type: .sessionStarted,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: nil,
                payload: .sessionMetadata(AgentSessionMetadata(project: context)),
                recordID: uuid,
                discriminator: "session-start"
            ))
            let observedAt = timestamp ?? receivedAt
            let capabilities = AgentCapabilities(evidence: [
                .sessionLifecycle: Self.evidence(observedAt),
                .explicitThinking: Self.evidence(observedAt),
                .toolLifecycle: Self.evidence(observedAt),
                .commandLifecycle: Self.evidence(observedAt),
                .taskLifecycle: Self.evidence(observedAt),
                .tokenUsage: Self.evidence(observedAt),
                .modelMetadata: Self.evidence(observedAt),
                .projectContext: Self.evidence(observedAt),
                .gitMetadata: Self.evidence(observedAt)
            ])
            events.append(event(
                nativeID: nativeID,
                type: .capabilitiesUpdated,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: nil,
                payload: .capabilities(capabilities),
                recordID: uuid,
                discriminator: "capabilities"
            ))
        } else if cwd != nil || gitBranch != nil {
            events.append(event(
                nativeID: nativeID,
                type: .projectContextUpdated,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: nil,
                payload: .projectContext(Self.projectContext(cwd: cwd, gitBranch: gitBranch, model: nil)),
                recordID: uuid,
                discriminator: "project"
            ))
        }

        guard let message = root["message"] as? [String: Any] else {
            guard !events.isEmpty else { throw ClaudeTranscriptRecoveryError.unsupportedRecord }
            return events
        }

        let role = Self.boundedString(message["role"], maximumBytes: AgentDomainLimits.tokenLength)
        let model = Self.boundedString(message["model"], maximumBytes: AgentDomainLimits.summaryLength)
        if !startedSession,
           role == "user",
           Self.isHumanPrompt(message["content"]) {
            events.append(event(
                nativeID: nativeID,
                type: .sessionResumed,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: uuid.map(AgentCorrelationID.init(rawValue:)),
                payload: .sessionMetadata(AgentSessionMetadata(
                    project: Self.projectContext(cwd: cwd, gitBranch: gitBranch, model: model)
                )),
                recordID: uuid,
                discriminator: "user-turn-resume"
            ))
        }
        if let model {
            events.append(event(
                nativeID: nativeID,
                type: .sessionMetadataUpdated,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: nil,
                payload: .sessionMetadata(AgentSessionMetadata(
                    project: Self.projectContext(cwd: cwd, gitBranch: gitBranch, model: model)
                )),
                recordID: uuid,
                discriminator: "model"
            ))
        }

        if let content = message["content"] as? [[String: Any]] {
            for (index, item) in content.enumerated() {
                guard let contentType = Self.boundedString(
                    item["type"],
                    maximumBytes: AgentDomainLimits.tokenLength
                ) else { continue }

                switch contentType {
                case "thinking":
                    events.append(event(
                        nativeID: nativeID,
                        type: .thinkingStarted,
                        timestamp: timestamp,
                        receivedAt: receivedAt,
                        correlationID: nil,
                        payload: .activity(AgentActivityDescriptor(title: "Thinking", summary: nil)),
                        recordID: uuid,
                        discriminator: "thinking-\(index)"
                    ))

                case "tool_use":
                    guard let toolID = Self.boundedString(
                        item["id"],
                        maximumBytes: AgentDomainLimits.identifierLength
                    ), let toolName = Self.boundedString(
                        item["name"],
                        maximumBytes: AgentDomainLimits.summaryLength
                    ) else { continue }
                    events.append(event(
                        nativeID: nativeID,
                        type: .thinkingEnded,
                        timestamp: timestamp,
                        receivedAt: receivedAt,
                        correlationID: nil,
                        payload: .none,
                        recordID: uuid,
                        discriminator: "thinking-end-\(toolID)"
                    ))
                    let correlation = AgentCorrelationID(rawValue: toolID)
                    if Self.isCommandTool(toolName) {
                        let executable = Self.commandExecutable(toolName)
                        activeOperations[toolID] = .command(executable: executable)
                        events.append(event(
                            nativeID: nativeID,
                            type: .commandStarted,
                            timestamp: timestamp,
                            receivedAt: receivedAt,
                            correlationID: correlation,
                            payload: .command(AgentCommandEvent(
                                executable: executable,
                                success: nil,
                                exitCode: nil
                            )),
                            recordID: uuid,
                            discriminator: "command-start"
                        ))
                    } else {
                        activeOperations[toolID] = .tool(name: toolName)
                        events.append(event(
                            nativeID: nativeID,
                            type: .toolStarted,
                            timestamp: timestamp,
                            receivedAt: receivedAt,
                            correlationID: correlation,
                            payload: .tool(AgentToolEvent(
                                name: toolName,
                                category: Self.toolCategory(toolName),
                                summary: nil,
                                success: nil
                            )),
                            recordID: uuid,
                            discriminator: "tool-start"
                        ))
                    }

                case "tool_result":
                    guard let toolID = Self.boundedString(
                        item["tool_use_id"],
                        maximumBytes: AgentDomainLimits.identifierLength
                    ), let operation = activeOperations.removeValue(forKey: toolID) else {
                        continue
                    }
                    let success = (item["is_error"] as? Bool).map { !$0 } ?? true
                    let correlation = AgentCorrelationID(rawValue: toolID)
                    switch operation {
                    case .command(let executable):
                        events.append(event(
                            nativeID: nativeID,
                            type: .commandCompleted,
                            timestamp: timestamp,
                            receivedAt: receivedAt,
                            correlationID: correlation,
                            payload: .command(AgentCommandEvent(
                                executable: executable,
                                success: success,
                                exitCode: nil
                            )),
                            recordID: uuid,
                            discriminator: "command-end"
                        ))
                    case .tool(let name):
                        events.append(event(
                            nativeID: nativeID,
                            type: .toolCompleted,
                            timestamp: timestamp,
                            receivedAt: receivedAt,
                            correlationID: correlation,
                            payload: .tool(AgentToolEvent(
                                name: name,
                                category: Self.toolCategory(name),
                                summary: nil,
                                success: success
                            )),
                            recordID: uuid,
                            discriminator: "tool-end"
                        ))
                    }

                default:
                    continue
                }
            }
        }

        if let usageObject = message["usage"] as? [String: Any],
           let usage = Self.usage(usageObject, observedAt: timestamp ?? receivedAt) {
            events.append(event(
                nativeID: nativeID,
                type: .usageUpdated,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: nil,
                payload: .usage(usage),
                recordID: uuid,
                discriminator: "usage"
            ))
        }

        if role == "assistant",
           Self.boundedString(message["stop_reason"], maximumBytes: 64) == "end_turn" {
            events.append(event(
                nativeID: nativeID,
                type: .thinkingEnded,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: nil,
                payload: .none,
                recordID: uuid,
                discriminator: "thinking-end-turn"
            ))
            events.append(event(
                nativeID: nativeID,
                type: .taskCompleted,
                timestamp: timestamp,
                receivedAt: receivedAt,
                correlationID: nil,
                payload: .terminal(AgentTerminalEvent(summary: "Claude turn completed")),
                recordID: uuid,
                discriminator: "end-turn"
            ))
        }

        guard !events.isEmpty else { throw ClaudeTranscriptRecoveryError.unsupportedRecord }
        return events
    }

    private func event(
        nativeID: String,
        type: AgentEventType,
        timestamp: Date?,
        receivedAt: Date,
        correlationID: AgentCorrelationID?,
        payload: AgentEventPayload,
        recordID: String?,
        discriminator: String
    ) -> AgentIngestionEvent {
        let identity = [
            nativeID,
            recordID ?? Self.timestampIdentity(timestamp ?? receivedAt),
            type.stableName,
            correlationID?.rawValue ?? "",
            discriminator
        ].joined(separator: "|")
        return AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: AgentEventID(rawValue: "claude-transcript-" + Self.digest(identity)),
            provider: .claude,
            source: .unknown,
            nativeSessionID: nativeID,
            assertedGeneration: nil,
            type: type,
            providerTimestamp: timestamp,
            receivedTimestamp: receivedAt,
            correlationID: correlationID,
            sequence: nil,
            authority: .localStructuredRecord,
            payload: payload,
            continuity: AgentSessionContinuity(immutableIdentity: nativeID)
        )
    }

    private static func evidence(_ date: Date) -> AgentCapabilityEvidence {
        AgentCapabilityEvidence(
            authority: .localStructuredRecord,
            source: "claude-transcript",
            observedAt: date
        )
    }

    /// Claude transcript tool results also use role=user. Only a non-empty
    /// string record is treated as an observed human turn boundary; structured
    /// result arrays are deliberately not guessed to be user prompts.
    private static func isHumanPrompt(_ content: Any?) -> Bool {
        guard let text = content as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func projectContext(
        cwd: String?,
        gitBranch: String?,
        model: String?
    ) -> AgentProjectContext {
        let displayName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap {
            boundedString($0, maximumBytes: AgentDomainLimits.titleLength)
        }
        return AgentProjectContext(
            displayName: displayName,
            workingDirectory: cwd,
            repositoryIdentity: nil,
            gitBranch: gitBranch,
            gitCommit: nil,
            model: model,
            sourceApplication: nil
        )
    }

    private static func usage(
        _ object: [String: Any],
        observedAt: Date
    ) -> AgentUsage? {
        let candidates: [(AgentUsageMetric, String, Any?)] = [
            (.inputTokens, "message-input", object["input_tokens"]),
            (.outputTokens, "message-output", object["output_tokens"]),
            (.cachedInputTokens, "message-cache-read", object["cache_read_input_tokens"])
        ]
        var samples: [AgentUsageMetric: AgentUsageSample] = [:]
        for (metric, scope, raw) in candidates {
            guard let value = double(raw), value.isFinite, value >= 0 else { continue }
            samples[metric] = AgentUsageSample(
                value: value,
                limit: nil,
                unit: .tokens,
                scope: scope,
                source: "claude-transcript",
                observedAt: observedAt
            )
        }
        return samples.isEmpty ? nil : AgentUsage(samples: samples)
    }

    private static func isCommandTool(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower == "bash" || lower == "powershell" || lower == "shell"
    }

    private static func commandExecutable(_ name: String) -> String {
        switch name.lowercased() {
        case "bash": "bash"
        case "powershell": "powershell"
        default: "shell"
        }
    }

    private static func toolCategory(_ name: String) -> String {
        let lower = name.lowercased()
        if lower == "edit" || lower == "write" || lower.contains("patch") { return "edit" }
        if lower == "read" || lower.contains("search") || lower.contains("glob") || lower.contains("grep") { return "read" }
        if lower.contains("web") || lower.contains("browser") { return "web" }
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

    private static func double(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let value as Double: value
        case let value as Int: Double(value)
        case let value as Int64: Double(value)
        default: nil
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func timestampIdentity(_ date: Date) -> String {
        String(format: "%.6f", date.timeIntervalSince1970)
    }

    private static func digest(_ value: String) -> String {
        String(SHA256.hash(data: Data(value.utf8)).map {
            String(format: "%02x", $0)
        }.joined().prefix(40))
    }
}

actor ClaudeTranscriptRecoveryAdapter {
    private let coordinator: AgentIngestionCoordinator
    private var producer: AgentProducerHandle?
    private var tailers: [URL: AppendOnlyRecordTailer] = [:]
    private var parsers: [URL: ClaudeTranscriptRecoveryParser] = [:]

    init(coordinator: AgentIngestionCoordinator) {
        self.coordinator = coordinator
    }

    func start() async -> Bool {
        if producer != nil { return true }
        let descriptor = AgentProducerDescriptor(
            sourceInstanceID: AgentSourceInstanceID(rawValue: "dynamic-island.claude-transcript-recovery"),
            sourceKind: .structuredRecovery,
            runtimeVersion: "claude-transcript-compat-v1"
        )
        switch await coordinator.registerProducer(
            descriptor: descriptor,
            policy: .claudeStructuredRecovery
        ) {
        case .success(let handle):
            producer = handle
            _ = await coordinator.updateHealth(.starting, for: handle)
            return true
        case .failure:
            return false
        }
    }

    func attach(
        fileURL: URL,
        initialPolicy: AppendOnlyRecordStartPolicy = .boundedCatchUp
    ) async -> Bool {
        guard let producer else { return false }
        if tailers[fileURL] != nil { return true }
        parsers[fileURL] = ClaudeTranscriptRecoveryParser()
        let owner = self
        let tailer = AppendOnlyRecordTailer(
            fileURL: fileURL,
            initialPolicy: initialPolicy,
            replacementPolicy: .boundedCatchUp,
            onRecord: { record in
                Task { await owner.handle(record, from: fileURL) }
            },
            onNotice: { notice in
                Task { await owner.handle(notice, producer: producer) }
            }
        )
        tailers[fileURL] = tailer
        await tailer.start()
        return true
    }

    func detach(fileURL: URL) async {
        guard let tailer = tailers.removeValue(forKey: fileURL) else { return }
        parsers.removeValue(forKey: fileURL)
        await tailer.stop()
    }

    func reconcileAll() async {
        let current = Array(tailers.values)
        for tailer in current { await tailer.reconcile() }
    }

    func stop() async {
        let current = Array(tailers.values)
        tailers.removeAll()
        parsers.removeAll()
        for tailer in current { await tailer.stop() }
        if let producer {
            _ = await coordinator.unregisterProducer(producer)
            self.producer = nil
        }
    }

    private func handle(_ record: Data, from fileURL: URL) async {
        guard let producer, var parser = parsers[fileURL] else { return }
        do {
            let events = try parser.parse(record)
            parsers[fileURL] = parser
            guard !events.isEmpty else { return }
            let result = await coordinator.ingestAtomically(events, from: producer)
            if case .failure = result {
                _ = await coordinator.updateHealth(.degraded, error: .storeRejected, for: producer)
            }
        } catch ClaudeTranscriptRecoveryError.unsupportedRecord {
            parsers[fileURL] = parser
        } catch {
            parsers[fileURL] = parser
            _ = await coordinator.updateHealth(.degraded, error: .schemaMismatch, for: producer)
        }
    }

    private func handle(
        _ notice: AppendOnlyRecordTailerNotice,
        producer: AgentProducerHandle
    ) async {
        switch notice {
        case .opened, .rotated, .truncated:
            _ = await coordinator.updateHealth(.healthy, for: producer)
        case .waitingForFile:
            _ = await coordinator.updateHealth(.stale, for: producer)
        case .oversizeRecordDropped, .reopenFailed:
            _ = await coordinator.updateHealth(.degraded, error: .producerFailure, for: producer)
        }
    }
}
