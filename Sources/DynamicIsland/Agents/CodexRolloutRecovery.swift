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
    private(set) var source: AgentSource = .unknown
    private var commandCallIDs: Set<String> = []

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

        case "response_item":
            return try parseResponseItem(
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
        let rawSource = Self.boundedString(payload["source"], maximumBytes: 96)
        let originator = Self.boundedString(payload["originator"], maximumBytes: 96)
        let sourceApplication = Self.sourceApplication(rawSource: rawSource, originator: originator)
        source = Self.agentSource(rawSource: rawSource, originator: originator)
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
            sourceApplication: sourceApplication
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
            includesCurrentContext: false,
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
                  let current = info["last_token_usage"] as? [String: Any] else {
                throw CodexRolloutRecoveryError.invalidUsage
            }
            let contextLimit = Self.double(info["model_context_window"])
            let usage = try Self.usage(
                total: current,
                contextLimit: contextLimit,
                includesCurrentContext: true,
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
            let correlation = turn.map(AgentCorrelationID.init(rawValue:))
            // Recovery observes a provider-native turn boundary. Resuming here
            // lets a later turn continue the same generation after the prior
            // turn completed without treating weaker recovery as a new session.
            return [
                event(
                    nativeID: nativeID,
                    type: .sessionResumed,
                    providerTimestamp: providerTimestamp,
                    receivedAt: receivedAt,
                    sequence: sequence,
                    correlationID: correlation,
                    payload: .sessionMetadata(AgentSessionMetadata(project: nil)),
                    discriminator: eventType + "-resume"
                ),
                event(
                    nativeID: nativeID,
                    type: .agentWorking,
                    providerTimestamp: providerTimestamp,
                    receivedAt: receivedAt,
                    sequence: sequence,
                    correlationID: correlation,
                    payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil)),
                    discriminator: eventType
                )
            ]

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


    private mutating func parseResponseItem(
        _ payload: [String: Any],
        providerTimestamp: Date?,
        receivedAt: Date,
        sequence: UInt64?
    ) throws -> [AgentIngestionEvent] {
        guard let nativeID = sessionID else { throw CodexRolloutRecoveryError.missingSession }
        guard let itemType = Self.boundedString(payload["type"], maximumBytes: 96) else {
            throw CodexRolloutRecoveryError.malformedRecord
        }
        let turnID = Self.boundedString(
            (payload["internal_chat_message_metadata_passthrough"] as? [String: Any])?["turn_id"],
            maximumBytes: AgentDomainLimits.identifierLength
        )

        switch itemType {
        case "function_call", "custom_tool_call":
            guard let callID = Self.boundedString(payload["call_id"], maximumBytes: AgentDomainLimits.identifierLength),
                  let name = Self.boundedString(payload["name"], maximumBytes: AgentDomainLimits.summaryLength) else {
                throw CodexRolloutRecoveryError.malformedRecord
            }
            let correlation = AgentCorrelationID(rawValue: callID)
            if name == "exec_command" {
                commandCallIDs.insert(callID)
                let executable = Self.commandExecutable(from: payload["arguments"])
                return [event(
                    nativeID: nativeID,
                    type: .commandStarted,
                    providerTimestamp: providerTimestamp,
                    receivedAt: receivedAt,
                    sequence: sequence,
                    correlationID: correlation,
                    payload: .command(AgentCommandEvent(
                        executable: executable ?? "command",
                        success: nil,
                        exitCode: nil
                    )),
                    discriminator: "response-command-start-\(turnID ?? "")"
                )]
            }
            return [event(
                nativeID: nativeID,
                type: .toolStarted,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence,
                correlationID: correlation,
                payload: .tool(AgentToolEvent(
                    name: name,
                    category: itemType == "custom_tool_call" ? "custom" : "tool",
                    summary: nil,
                    success: nil
                )),
                discriminator: "response-tool-start-\(turnID ?? "")"
            )]

        case "function_call_output", "custom_tool_call_output":
            guard let callID = Self.boundedString(payload["call_id"], maximumBytes: AgentDomainLimits.identifierLength) else {
                throw CodexRolloutRecoveryError.malformedRecord
            }
            let correlation = AgentCorrelationID(rawValue: callID)
            let rawOutput = payload["output"] as? String
            let outputForClassification = rawOutput.flatMap {
                $0.utf8.count <= 16_384 ? $0 : nil
            }
            let exitCode = Self.exitCode(from: outputForClassification)
            // Pair output with the exact call kind remembered from its start.
            // This avoids guessing command-vs-tool from provider output text.
            if commandCallIDs.remove(callID) != nil {
                return [event(
                    nativeID: nativeID,
                    type: .commandCompleted,
                    providerTimestamp: providerTimestamp,
                    receivedAt: receivedAt,
                    sequence: sequence,
                    correlationID: correlation,
                    payload: .command(AgentCommandEvent(
                        executable: nil,
                        success: exitCode.map { $0 == 0 },
                        exitCode: exitCode
                    )),
                    discriminator: "response-command-end-\(turnID ?? "")"
                )]
            }
            return [event(
                nativeID: nativeID,
                type: .toolCompleted,
                providerTimestamp: providerTimestamp,
                receivedAt: receivedAt,
                sequence: sequence,
                correlationID: correlation,
                payload: .tool(AgentToolEvent(
                    name: nil,
                    category: nil,
                    summary: nil,
                    success: true
                )),
                discriminator: "response-tool-end-\(turnID ?? "")"
            )]

        case "message", "reasoning":
            // Deliberately do not ingest raw message/reasoning text from local
            // recovery. Live/managed transcript content has a separate path.
            throw CodexRolloutRecoveryError.unsupportedRecord

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
            source: source,
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
        includesCurrentContext: Bool,
        observedAt: Date
    ) throws -> AgentUsage {
        var values: [(AgentUsageMetric, String, Double?)] = [
            (.inputTokens, "input", double(total["input_tokens"])),
            (.cachedInputTokens, "cached-input", double(total["cached_input_tokens"])),
            (.outputTokens, "output", double(total["output_tokens"])),
            (.reasoningTokens, "reasoning", double(total["reasoning_output_tokens"]))
        ]
        if includesCurrentContext {
            values.append((.contextUsed, "context-used", double(total["total_tokens"])))
        }
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


    private static func agentSource(rawSource: String?, originator: String?) -> AgentSource {
        let combined = [rawSource, originator].compactMap { $0?.lowercased() }.joined(separator: " ")
        if combined.contains("vscode") { return .vscode }
        if combined.contains("jetbrains") { return .jetbrains }
        if combined.contains("desktop") { return .desktopApp }
        if combined.contains("cloud") { return .cloud }
        if combined.contains("cli") || combined.contains("tui") || combined.contains("terminal") {
            return .terminal
        }
        return .unknown
    }

    private static func sourceApplication(rawSource: String?, originator: String?) -> AgentSourceApplication? {
        switch agentSource(rawSource: rawSource, originator: originator) {
        case .vscode:
            return AgentSourceApplication(
                displayName: "Visual Studio Code",
                bundleIdentifier: "com.microsoft.VSCode"
            )
        case .jetbrains:
            return AgentSourceApplication(displayName: "JetBrains", bundleIdentifier: nil)
        case .desktopApp:
            return AgentSourceApplication(displayName: "Codex Desktop", bundleIdentifier: nil)
        case .terminal:
            return AgentSourceApplication(displayName: "Terminal / Codex CLI", bundleIdentifier: nil)
        case .cloud:
            return AgentSourceApplication(displayName: "Codex Cloud", bundleIdentifier: nil)
        case .mcp:
            return AgentSourceApplication(displayName: "MCP", bundleIdentifier: nil)
        case .unknown:
            return nil
        }
    }

    private static func commandExecutable(from value: Any?) -> String? {
        guard let raw = value as? String,
              raw.utf8.count <= 16_384,
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let command = (object["cmd"] as? String) ?? (object["command"] as? String)
        guard let command else { return nil }
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let token = trimmed.split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
        return token.flatMap { boundedString($0, maximumBytes: AgentDomainLimits.summaryLength) }
    }

    private static func exitCode(from output: String?) -> Int? {
        guard let output else { return nil }
        for marker in ["Process exited with code ", "Exit code: "] {
            guard let range = output.range(of: marker) else { continue }
            let suffix = output[range.upperBound...]
            let number = suffix.prefix { $0 == "-" || $0.isNumber }
            if let value = Int(number) { return value }
        }
        return nil
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
    private let integrationRouter: AgentIntegrationRouter
    private var producer: AgentProducerHandle?
    private var tailers: [URL: AppendOnlyRecordTailer] = [:]
    private var parsers: [URL: CodexRolloutRecoveryParser] = [:]

    init(
        coordinator: AgentIngestionCoordinator,
        integrationRouter: AgentIntegrationRouter? = nil
    ) {
        self.coordinator = coordinator
        self.integrationRouter = integrationRouter ?? AgentIntegrationRouter(coordinator: coordinator)
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

        // AgentNotch discovers identity from the session_meta near the start of
        // each rollout before it tails recent activity. Do the same here so a
        // large rollout can still bind bounded catch-up records to the exact
        // native thread even when session_meta is far outside the tail window.
        var parser = CodexRolloutRecoveryParser()
        if let bootstrap = Self.bootstrapSessionMetaRecord(fileURL: fileURL) {
            do {
                let events = try parser.parse(bootstrap)
                let result = await integrationRouter.routeAtomically(
                    events,
                    from: producer,
                    precedence: .secondaryObservation
                )
                if case .failure = result { return false }
            } catch {
                _ = await coordinator.updateHealth(.degraded, error: .schemaMismatch, for: producer)
                return false
            }
        } else {
            _ = await coordinator.updateHealth(.degraded, error: .schemaMismatch, for: producer)
            return false
        }
        parsers[fileURL] = parser
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


    nonisolated static func bootstrapSessionMetaRecord(
        fileURL: URL,
        maximumBytes: Int = 16 * 1024
    ) -> Data? {
        guard maximumBytes > 0,
              let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: maximumBytes)
        guard !data.isEmpty else { return nil }
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let record = Data(line)
            guard record.count <= AppendOnlyRecordLimits.maximumRecordBytes,
                  let object = try? JSONSerialization.jsonObject(with: record) as? [String: Any],
                  object["type"] as? String == "session_meta" else { continue }
            return record
        }
        return nil
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
            let result = await integrationRouter.routeAtomically(
                events,
                from: producer,
                precedence: .secondaryObservation
            )
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
