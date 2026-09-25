import CryptoKit
import Foundation

enum CodexRolloutRecoveryError: Error, Equatable, Sendable {
    case malformedRecord
    case unsupportedRecord
    case missingSession
    case invalidUsage
}

struct CodexRolloutRecoveryParser: Sendable {
    private(set) var sessionID: String?

    mutating func parse(
        _ record: Data,
        receivedAt: Date = Date()
    ) throws -> [AgentIngestionEvent] {
        guard !record.isEmpty,
              record.count <= AppendOnlyRecordLimits.maximumRecordBytes,
              let object = try? JSONSerialization.jsonObject(with: record) as? [String: Any],
              let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else {
            throw CodexRolloutRecoveryError.malformedRecord
        }

        let providerTimestamp = Self.parseDate(object["timestamp"] as? String)
        let sequence = Self.uint64(object["ordinal"])
        switch type {
        case "session_meta":
            return try parseSessionMeta(
                payload,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence
            )

        case "turn_context":
            return try parseTurnContext(
                payload,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence
            )

        case "token_usage_record":
            return try parseTokenUsageRecord(
                payload,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence
            )

        case "event_msg":
            return try parseEventMessage(
                payload,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence
            )

        default:
            throw CodexRolloutRecoveryError.unsupportedRecord
        }
    }

    private mutating func parseSessionMeta(
        _ payload: [String: Any],
        providerTimestamp: Date?,
        receivedAt: Date,
        sequence: UInt64?
    ) throws -> [AgentIngestionEvent] {
        guard let nativeID = Self.boundedString(
            payload["session_id"] ?? payload["id"],
            maximumBytes: AgentDomainLimits.identifierLength
        ) else {
            throw CodexRolloutRecoveryError.malformedRecord
        }
        sessionID = nativeID

        let cwd = Self.boundedString(payload["cwd"], maximumBytes: AgentDomainLimits.pathLength)
        let displayName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap {
            Self.boundedString($0, maximumBytes: AgentDomainLimits.titleLength)
        }
        let git = payload["git"] as? [String: Any]
        let branch = Self.boundedString(git?["branch"], maximumBytes: AgentDomainLimits.summaryLength)
        let commit = Self.boundedString(git?["commit_hash"], maximumBytes: AgentDomainLimits.identifierLength)
        let context = AgentProjectContext(
            displayName: displayName,
            workingDirectory: cwd,
            repositoryIdentity: nil,
            gitBranch: branch,
            gitCommit: commit,
            model: nil,
            sourceApplication: nil
        )
        let start = event(
            nativeID: nativeID,
            type: .sessionStarted,
            providerTimestamp: providerTimestamp,
            receivedAt: receivedAt,
            sequence: sequence,
            correlationID: nil,
            payload: .sessionMetadata(AgentSessionMetadata(project: context)),
            discriminator: "session-meta"
        )
        let capabilities = AgentCapabilities(evidence: [
            .sessionLifecycle: AgentCapabilityEvidence(
                authority: .localStructuredRecord,
                source: "codex-rollout",
                observedAt: providerTimestamp ?? receivedAt
            ),
            .taskLifecycle: AgentCapabilityEvidence(
                authority: .localStructuredRecord,
                source: "codex-rollout",
                observedAt: providerTimestamp ?? receivedAt
            ),
            .tokenUsage: AgentCapabilityEvidence(
                authority: .localStructuredRecord,
                source: "codex-rollout",
                observedAt: providerTimestamp ?? receivedAt
            ),
            .contextUsage: AgentCapabilityEvidence(
                authority: .localStructuredRecord,
                source: "codex-rollout",
                observedAt: providerTimestamp ?? receivedAt
            ),
            .modelMetadata: AgentCapabilityEvidence(
                authority: .localStructuredRecord,
                source: "codex-rollout",
                observedAt: providerTimestamp ?? receivedAt
            ),
            .projectContext: AgentCapabilityEvidence(
                authority: .localStructuredRecord,
                source: "codex-rollout",
                observedAt: providerTimestamp ?? receivedAt
            ),
            .gitMetadata: AgentCapabilityEvidence(
                authority: .localStructuredRecord,
                source: "codex-rollout",
                observedAt: providerTimestamp ?? receivedAt
            )
        ])
        let caps = event(
            nativeID: nativeID,
            type: .capabilitiesUpdated,
            providerTimestamp: providerTimestamp,
            receivedAt: receivedAt,
            sequence: sequence,
            correlationID: nil,
            payload: .capabilities(capabilities),
            discriminator: "capabilities"
        )
        return [start, caps]
    }

    private func parseTurnContext(
        _ payload: [String: Any],
        providerTimestamp: Date?,
        receivedAt: Date,
        sequence: UInt64?
    ) throws -> [AgentIngestionEvent] {
        guard let nativeID = sessionID else { throw CodexRolloutRecoveryError.missingSession }
        let cwd = Self.boundedString(payload["cwd"], maximumBytes: AgentDomainLimits.pathLength)
        let model = Self.boundedString(payload["model"], maximumBytes: AgentDomainLimits.summaryLength)
        let displayName = cwd.map { URL(fileURLWithPath: $0).lastPathComponent }.flatMap {
            Self.boundedString($0, maximumBytes: AgentDomainLimits.titleLength)
        }
        let context = AgentProjectContext(
            displayName: displayName,
            workingDirectory: cwd,
            repositoryIdentity: nil,
            gitBranch: nil,
            gitCommit: nil,
            model: model,
            sourceApplication: nil
        )
        let turn = Self.boundedString(payload["turn_id"], maximumBytes: AgentDomainLimits.identifierLength)
        return [event(
            nativeID: nativeID,
            type: .sessionMetadataUpdated,
            providerTimestamp: providerTimestamp,
            receivedAt: receivedAt,
            sequence: sequence,
            correlationID: turn.map(AgentCorrelationID.init(rawValue:)),
            payload: .sessionMetadata(AgentSessionMetadata(project: context)),
            discriminator: "turn-context-\(turn ?? "")"
        )]
    }

    private func parseTokenUsageRecord(
        _ payload: [String: Any],
        providerTimestamp: Date?,
        receivedAt: Date,
        sequence: UInt64?
    ) throws -> [AgentIngestionEvent] {
        let nativeID = Self.boundedString(
            payload["session_id"],
            maximumBytes: AgentDomainLimits.identifierLength
        ) ?? sessionID
        guard let nativeID else { throw CodexRolloutRecoveryError.missingSession }
        let usageObject = (payload["thread_token_usage"] as? [String: Any])
            ?? (payload["usage"] as? [String: Any])
        guard let usageObject else { throw CodexRolloutRecoveryError.invalidUsage }
        let usage = try Self.usage(
            total: usageObject,
            contextLimit: nil,
            observedAt: providerTimestamp ?? receivedAt
        )
        let correlation = Self.boundedString(payload["turn_id"], maximumBytes: AgentDomainLimits.identifierLength)
        return [event(
            nativeID: nativeID,
            type: .usageUpdated,
            providerTimestamp: providerTimestamp,
            receivedAt: receivedAt,
            sequence: sequence,
            correlationID: correlation.map(AgentCorrelationID.init(rawValue:)),
            payload: .usage(usage),
            discriminator: "token-usage-record"
        )]
    }

    private func parseEventMessage(
        _ payload: [String: Any],
        providerTimestamp: Date?,
        receivedAt: Date,
        sequence: UInt64?
    ) throws -> [AgentIngestionEvent] {
        guard let nativeID = sessionID else { throw CodexRolloutRecoveryError.missingSession }
        guard let eventType = Self.boundedString(payload["type"], maximumBytes: 96) else {
            throw CodexRolloutRecoveryError.malformedRecord
        }

        switch eventType {
        case "token_count":
            guard let info = payload["info"] as? [String: Any],
                  let total = info["total_token_usage"] as? [String: Any] else {
                throw CodexRolloutRecoveryError.invalidUsage
            }
            let contextLimit = Self.double(info["model_context_window"])
            let usage = try Self.usage(
                total: total,
                contextLimit: contextLimit,
                observedAt: providerTimestamp ?? receivedAt
            )
            return [event(
                nativeID: nativeID,
                type: .usageUpdated,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence,
                correlationID: nil,
                payload: .usage(usage),
                discriminator: "token-count"
            )]

        case "task_started", "turn_started":
            let turn = Self.boundedString(payload["turn_id"], maximumBytes: AgentDomainLimits.identifierLength)
            return [event(
                nativeID: nativeID,
                type: .agentWorking,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence,
                correlationID: turn.map(AgentCorrelationID.init(rawValue:)),
                payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil)),
                discriminator: eventType
            )]

        case "task_complete", "turn_complete":
            let turn = Self.boundedString(payload["turn_id"], maximumBytes: AgentDomainLimits.identifierLength)
            return [event(
                nativeID: nativeID,
                type: .taskCompleted,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence,
                correlationID: turn.map(AgentCorrelationID.init(rawValue:)),
                payload: .terminal(AgentTerminalEvent(summary: "Codex turn completed")),
                discriminator: eventType
            )]

        case "turn_aborted":
            let turn = Self.boundedString(payload["turn_id"], maximumBytes: AgentDomainLimits.identifierLength)
            return [event(
                nativeID: nativeID,
                type: .interrupted,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence,
                correlationID: turn.map(AgentCorrelationID.init(rawValue:)),
                payload: .terminal(AgentTerminalEvent(summary: "Codex turn interrupted")),
                discriminator: eventType
            )]

        default:
            throw CodexRolloutRecoveryError.unsupportedRecord
        }
    }

    private func event(
        nativeID: String,
        type: AgentEventType,
        providerTimestamp: Date?,
        receivedAt: Date,
        sequence: UInt64?,
        correlationID: AgentCorrelationID?,
        payload: AgentEventPayload,
        discriminator: String
    ) -> AgentIngestionEvent {
        let eventIdentity = [
            nativeID,
            String(sequence ?? 0),
            type.stableName,
            correlationID?.rawValue ?? "",
            discriminator
        ].joined(separator: "|")
        return AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: AgentEventID(rawValue: "codex-rollout-" + Self.digest(eventIdentity)),
            provider: .codex,
            source: .unknown,
            nativeSessionID: nativeID,
            assertedGeneration: nil,
            type: type,
            providerTimestamp: providerTimestamp,
            receivedTimestamp: receivedAt,
            correlationID: correlationID,
            sequence: sequence,
            authority: .localStructuredRecord,
            payload: payload,
            continuity: AgentSessionContinuity(immutableIdentity: nativeID)
        )
    }

    private static func usage(
        total: [String: Any],
        contextLimit: Double?,
        observedAt: Date
    ) throws -> AgentUsage {
        let values: [(AgentUsageMetric, String, Double?)] = [
            (.inputTokens, "input", double(total["input_tokens"])),
            (.cachedInputTokens, "cached-input", double(total["cached_input_tokens"])),
            (.outputTokens, "output", double(total["output_tokens"])),
            (.reasoningTokens, "reasoning", double(total["reasoning_output_tokens"])),
            (.contextUsed, "context-used", double(total["total_tokens"]))
        ]
        var samples: [AgentUsageMetric: AgentUsageSample] = [:]
        for (metric, scope, value) in values {
            guard let value, value.isFinite, value >= 0 else { continue }
            samples[metric] = AgentUsageSample(
                value: value,
                limit: metric == .contextUsed ? contextLimit : nil,
                unit: .tokens,
                scope: scope,
                source: "codex-rollout",
                observedAt: observedAt
            )
        }
        if let contextLimit, contextLimit.isFinite, contextLimit >= 0 {
            samples[.contextLimit] = AgentUsageSample(
                value: contextLimit,
                limit: nil,
                unit: .tokens,
                scope: "context-limit",
                source: "codex-rollout",
                observedAt: observedAt
            )
        }
        guard !samples.isEmpty else { throw CodexRolloutRecoveryError.invalidUsage }
        return AgentUsage(samples: samples)
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

    private static func uint64(_ value: Any?) -> UInt64? {
        switch value {
        case let number as NSNumber:
            let signed = number.int64Value
            return signed >= 0 ? UInt64(signed) : nil
        case let value as UInt64:
            return value
        case let value as Int where value >= 0:
            return UInt64(value)
        default:
            return nil
        }
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func digest(_ value: String) -> String {
        String(SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined().prefix(40))
    }
}

actor CodexRolloutRecoveryAdapter {
    private let coordinator: AgentIngestionCoordinator
    private var producer: AgentProducerHandle?
    private var tailers: [URL: AppendOnlyRecordTailer] = [:]
    private var parsers: [URL: CodexRolloutRecoveryParser] = [:]

    init(coordinator: AgentIngestionCoordinator) {
        self.coordinator = coordinator
    }

    func start() async -> Bool {
        if producer != nil { return true }
        let descriptor = AgentProducerDescriptor(
            sourceInstanceID: AgentSourceInstanceID(rawValue: "dynamic-island.codex-rollout-recovery"),
            sourceKind: .structuredRecovery,
            runtimeVersion: "codex-rollout-current"
        )
        switch await coordinator.registerProducer(
            descriptor: descriptor,
            policy: .codexStructuredRecovery
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
        parsers[fileURL] = CodexRolloutRecoveryParser()
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
        let currentTailers = Array(tailers.values)
        for tailer in currentTailers {
            await tailer.reconcile()
        }
    }

    func stop() async {
        let currentTailers = Array(tailers.values)
        tailers.removeAll()
        for tailer in currentTailers {
            await tailer.stop()
        }
        parsers.removeAll()
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
        } catch CodexRolloutRecoveryError.unsupportedRecord {
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
