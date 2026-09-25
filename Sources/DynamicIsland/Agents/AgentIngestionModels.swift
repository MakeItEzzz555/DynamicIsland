import Foundation

enum AgentIngestionLimits {
    static let maximumRegisteredProducers = 64
    static let maximumProducerHistories = 128
    static let maximumSessionLeases = 256
    static let maximumCapabilityEvidenceEntries = 512
    static let maximumIdentityConflicts = 64
    static let maximumRuntimeVersionLength = 128
}

struct AgentSourceInstanceID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct AgentProducerEpoch: RawRepresentable, Hashable, Codable, Comparable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum AgentSourceKind: String, CaseIterable, Hashable, Codable, Sendable {
    case authenticatedBridge
    case officialHook
    case officialLifecycleProtocol
    case structuredTelemetry
    case structuredRecovery
    case processEnrichment
    case heuristicFallback
}

struct AgentProducerHandle: Hashable, Sendable {
    let sourceInstanceID: AgentSourceInstanceID
    let epoch: AgentProducerEpoch
    let authenticatedProducerID: String
    let registrationToken: UUID
}

struct AgentProducerDescriptor: Equatable, Sendable {
    let sourceInstanceID: AgentSourceInstanceID
    let sourceKind: AgentSourceKind
    let runtimeVersion: String?
    let normalizedSchemaVersions: Set<Int>

    init(
        sourceInstanceID: AgentSourceInstanceID,
        sourceKind: AgentSourceKind,
        runtimeVersion: String? = nil,
        normalizedSchemaVersions: Set<Int> = [AgentEvent.normalizedSchemaVersion]
    ) {
        self.sourceInstanceID = sourceInstanceID
        self.sourceKind = sourceKind
        self.runtimeVersion = runtimeVersion
        self.normalizedSchemaVersions = normalizedSchemaVersions
    }
}

enum AgentAuthorityDomain: String, CaseIterable, Hashable, Sendable {
    case lifecycle
    case activity
    case operation
    case interaction
    case usage
    case metadata
    case capability
    case liveness

    static func domain(for type: AgentEventType) -> Self? {
        switch type {
        case .sessionStarted, .sessionResumed, .sessionEnded, .taskCompleted, .taskFailed, .interrupted:
            .lifecycle
        case .agentWorking, .thinkingStarted, .thinkingEnded, .planningStarted, .planUpdated, .planReady:
            .activity
        case .toolStarted, .toolCompleted, .commandStarted, .commandCompleted, .subagentStarted, .subagentEnded:
            .operation
        case .approvalRequested, .approvalResolved, .waitingForUser, .userInputResolved:
            .interaction
        case .usageUpdated:
            .usage
        case .sessionMetadataUpdated, .projectContextUpdated:
            .metadata
        case .capabilitiesUpdated:
            .capability
        case .heartbeat:
            .liveness
        case .unsupported:
            nil
        }
    }
}

struct AgentProducerPolicy: Equatable, Sendable {
    /// `nil` means the trusted registration permits any normalized value. It is
    /// not evidence that a payload claim has been independently verified.
    let allowedProviders: Set<AgentProvider>?
    let allowedSources: Set<AgentSource>?
    let allowedSourceKinds: Set<AgentSourceKind>
    let allowedEventTypes: Set<AgentEventType>
    let authorityCeilings: [AgentAuthorityDomain: AgentEvidenceAuthority]
    let allowedCapabilities: Set<AgentCapability>
    let allowedSchemaVersions: Set<Int>

    func permits(provider: AgentProvider) -> Bool {
        allowedProviders?.contains(provider) ?? true
    }

    func permits(source: AgentSource) -> Bool {
        allowedSources?.contains(source) ?? true
    }

    static let codexOfficialHook = AgentProducerPolicy(
        allowedProviders: [.codex],
        allowedSources: [.unknown],
        allowedSourceKinds: [.officialHook],
        allowedEventTypes: [
            .sessionStarted, .sessionResumed, .sessionMetadataUpdated, .sessionEnded,
            .agentWorking, .toolStarted, .toolCompleted, .commandStarted, .commandCompleted,
            .approvalRequested, .capabilitiesUpdated, .projectContextUpdated,
            .taskCompleted, .interrupted, .subagentStarted, .subagentEnded, .heartbeat
        ],
        authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map {
            ($0, AgentEvidenceAuthority.lifecycle)
        }),
        allowedCapabilities: [
            .sessionLifecycle, .toolLifecycle, .commandLifecycle, .approvalObservation,
            .subagentLifecycle, .taskLifecycle, .modelMetadata, .projectContext
        ],
        allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
    )

    static let codexStructuredRecovery = AgentProducerPolicy(
        allowedProviders: [.codex],
        allowedSources: [.unknown],
        allowedSourceKinds: [.structuredRecovery],
        allowedEventTypes: [
            .sessionStarted, .sessionMetadataUpdated, .agentWorking,
            .usageUpdated, .capabilitiesUpdated, .projectContextUpdated,
            .taskCompleted, .interrupted, .heartbeat
        ],
        authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map {
            ($0, AgentEvidenceAuthority.localStructuredRecord)
        }),
        allowedCapabilities: [
            .sessionLifecycle, .taskLifecycle, .tokenUsage, .contextUsage,
            .modelMetadata, .projectContext, .gitMetadata
        ],
        allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
    )

    static let claudeOfficialHook = AgentProducerPolicy(
        allowedProviders: [.claude],
        allowedSources: [.unknown],
        allowedSourceKinds: [.officialHook],
        allowedEventTypes: [
            .sessionStarted, .sessionResumed, .sessionEnded,
            .agentWorking, .toolStarted, .toolCompleted,
            .commandStarted, .commandCompleted,
            .approvalRequested, .waitingForUser, .userInputResolved,
            .capabilitiesUpdated, .projectContextUpdated,
            .taskCompleted, .taskFailed,
            .subagentStarted, .subagentEnded, .heartbeat
        ],
        authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map {
            ($0, AgentEvidenceAuthority.lifecycle)
        }),
        allowedCapabilities: [
            .sessionLifecycle, .toolLifecycle, .commandLifecycle,
            .approvalObservation, .userInputObservation,
            .subagentLifecycle, .taskLifecycle, .modelMetadata, .projectContext
        ],
        allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
    )

    static let claudeStructuredRecovery = AgentProducerPolicy(
        allowedProviders: [.claude],
        allowedSources: [.unknown],
        allowedSourceKinds: [.structuredRecovery],
        allowedEventTypes: [
            .sessionStarted, .sessionMetadataUpdated,
            .thinkingStarted, .thinkingEnded,
            .toolStarted, .toolCompleted,
            .commandStarted, .commandCompleted,
            .usageUpdated, .capabilitiesUpdated, .projectContextUpdated,
            .taskCompleted, .heartbeat
        ],
        authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map {
            ($0, AgentEvidenceAuthority.localStructuredRecord)
        }),
        allowedCapabilities: [
            .sessionLifecycle, .explicitThinking, .toolLifecycle, .commandLifecycle,
            .taskLifecycle, .tokenUsage, .modelMetadata, .projectContext, .gitMetadata
        ],
        allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
    )

    static let codexStructuredTelemetry = AgentProducerPolicy(
        allowedProviders: [.codex],
        allowedSources: nil,
        allowedSourceKinds: [.structuredTelemetry],
        allowedEventTypes: [.usageUpdated, .sessionMetadataUpdated, .capabilitiesUpdated, .heartbeat],
        authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map {
            ($0, AgentEvidenceAuthority.structuredTelemetry)
        }),
        allowedCapabilities: [.tokenUsage, .contextUsage, .quotaUsage, .costUsage, .modelMetadata],
        allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
    )

    static let claudeStructuredTelemetry = AgentProducerPolicy(
        allowedProviders: [.claude],
        allowedSources: nil,
        allowedSourceKinds: [.structuredTelemetry],
        allowedEventTypes: [.usageUpdated, .sessionMetadataUpdated, .capabilitiesUpdated, .heartbeat],
        authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map {
            ($0, AgentEvidenceAuthority.structuredTelemetry)
        }),
        allowedCapabilities: [.tokenUsage, .contextUsage, .quotaUsage, .costUsage, .modelMetadata],
        allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
    )

    static let genericAuthenticatedBridge = AgentProducerPolicy(
        allowedProviders: [.other("unverified")],
        allowedSources: [.unknown],
        allowedSourceKinds: [.authenticatedBridge],
        allowedEventTypes: [
            .sessionStarted, .sessionResumed, .sessionMetadataUpdated, .agentWorking,
            .thinkingStarted, .thinkingEnded, .planningStarted, .planUpdated, .planReady,
            .toolStarted, .toolCompleted, .commandStarted, .commandCompleted,
            .approvalRequested, .waitingForUser, .userInputResolved, .usageUpdated,
            .capabilitiesUpdated, .projectContextUpdated, .subagentStarted, .subagentEnded,
            .heartbeat
        ],
        authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map {
            ($0, AgentEvidenceAuthority.localStructuredRecord)
        }),
        allowedCapabilities: Set(AgentCapability.allCases).subtracting([
            .approvalControl, .verifiedSourceIdentity, .sourceAppOpen
        ]),
        allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
    )
}

enum AgentSourceHealthState: String, Equatable, Sendable {
    case starting
    case healthy
    case stale
    case degraded
    case failed
    case stopped
}

enum AgentSourceHealthError: String, Equatable, Sendable {
    case policyRejected
    case schemaMismatch
    case invalidEvent
    case staleProducer
    case identityConflict
    case storeRejected
    case producerFailure
}

struct AgentSourceHealthSnapshot: Equatable, Sendable {
    let sourceInstanceID: AgentSourceInstanceID
    let epoch: AgentProducerEpoch
    let sourceKind: AgentSourceKind
    var state: AgentSourceHealthState
    var lastAcceptedEventAt: Date?
    var acceptedCount: UInt64
    var rejectedCount: UInt64
    var dropCount: UInt64
    var schemaMismatchCount: UInt64
    var lastError: AgentSourceHealthError?
}

struct AgentSessionContinuity: Hashable, Sendable {
    /// A provider-owned immutable lifecycle identity. Paths, model names and
    /// foreground applications are deliberately not continuity evidence.
    let immutableIdentity: String
}

struct AgentIngestionEvent: Equatable, Sendable {
    let schemaVersion: Int
    let eventID: AgentEventID
    let provider: AgentProvider
    let source: AgentSource
    let nativeSessionID: String
    let assertedGeneration: AgentSessionGeneration?
    let type: AgentEventType
    let providerTimestamp: Date?
    let receivedTimestamp: Date
    let correlationID: AgentCorrelationID?
    let sequence: UInt64?
    let authority: AgentEvidenceAuthority
    let payload: AgentEventPayload
    let continuity: AgentSessionContinuity?

    var sessionID: AgentSessionID {
        AgentSessionID(provider: provider, nativeID: nativeSessionID)
    }
}

struct AgentEventProvenance: Equatable, Codable, Sendable {
    let sourceInstanceID: AgentSourceInstanceID
    let producerEpoch: AgentProducerEpoch
    let sourceKind: AgentSourceKind
    let claimedAuthority: AgentEvidenceAuthority
    let schemaVersion: Int
}

struct AgentSessionLease: Equatable, Sendable {
    let instanceID: AgentSessionInstanceID
    let continuity: AgentSessionContinuity?
    var owners: Set<AgentProducerHandle>
    var isTerminal: Bool
}

struct AgentIdentityConflict: Equatable, Sendable {
    let sessionID: AgentSessionID
    let currentGeneration: AgentSessionGeneration
    let sourceInstanceID: AgentSourceInstanceID
    let recordedAt: Date
}

enum AgentIngestionError: Error, Equatable, Sendable {
    case invalidProducer
    case producerCapacity
    case staleProducer
    case invalidDescriptor
    case policyViolation
    case unsupportedSchema
    case invalidEvent
    case generationConflict
    case identityConflict
    case leaseCapacity
    case capabilityCapacity
    case storeRejected
}

struct AgentIngestionResult: Equatable, Sendable {
    let acceptedEvents: Int
    let applications: [AgentEventApplication]
}


enum AgentOTLPJSONError: Error, Equatable, Sendable {
    case emptyPayload
    case payloadTooLarge
    case malformedJSON
    case excessiveDepth
    case excessiveCardinality
}

enum AgentTelemetryLimits {
    static let maximumPayloadBytes = 1_048_576
    static let maximumJSONDepth = 12
    static let maximumObjectKeys = 128
    static let maximumArrayElements = 2_048
    static let maximumObservations = 512
    static let maximumAttributeCount = 128
    static let maximumStringBytes = 1_024
}

struct AgentTelemetryObservation: Equatable, Sendable {
    let provider: AgentProvider
    let nativeSessionID: String
    let source: AgentSource
    let observedAt: Date
    let receivedAt: Date
    let usage: AgentUsage
    let model: String?

    var isEmpty: Bool {
        usage.samples.isEmpty && model == nil
    }
}

/// Bounded OTLP/HTTP JSON decoder. Log bodies are intentionally ignored.
struct AgentOTLPJSONDecoder: Sendable {
    func decode(_ data: Data, receivedAt: Date = Date()) throws -> [AgentTelemetryObservation] {
        guard !data.isEmpty else { throw AgentOTLPJSONError.emptyPayload }
        guard data.count <= AgentTelemetryLimits.maximumPayloadBytes else {
            throw AgentOTLPJSONError.payloadTooLarge
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw AgentOTLPJSONError.malformedJSON
        }
        let rootValue: Any
        do {
            rootValue = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AgentOTLPJSONError.malformedJSON
        }
        try Self.validateJSON(rootValue, depth: 1)
        guard let root = rootValue as? [String: Any] else {
            throw AgentOTLPJSONError.malformedJSON
        }

        var observations: [AgentTelemetryObservation] = []
        try decodeMetrics(root["resourceMetrics"], receivedAt: receivedAt, into: &observations)
        try decodeLogs(root["resourceLogs"], receivedAt: receivedAt, into: &observations)
        return observations
    }

    private func decodeMetrics(
        _ raw: Any?,
        receivedAt: Date,
        into observations: inout [AgentTelemetryObservation]
    ) throws {
        guard let resourceMetrics = raw as? [Any] else { return }
        for resourceMetricValue in resourceMetrics {
            guard let resourceMetric = resourceMetricValue as? [String: Any] else { continue }
            let resourceAttributes = Self.attributes(fromResource: resourceMetric["resource"])
            guard let scopeMetrics = resourceMetric["scopeMetrics"] as? [Any] else { continue }
            for scopeMetricValue in scopeMetrics {
                guard let scopeMetric = scopeMetricValue as? [String: Any],
                      let metrics = scopeMetric["metrics"] as? [Any] else { continue }
                for metricValue in metrics {
                    guard let metric = metricValue as? [String: Any],
                          let name = Self.boundedString(metric["name"]) else { continue }
                    for point in Self.dataPoints(from: metric) {
                        var attributes = resourceAttributes
                        Self.merge(Self.attributes(from: point["attributes"]), into: &attributes)
                        guard let provider = Self.provider(from: attributes, hint: name),
                              let sessionID = Self.sessionID(from: attributes),
                              let mapping = Self.metricMapping(name),
                              let value = Self.number(fromPoint: point) else { continue }

                        let observedAt = Self.timestamp(from: point["timeUnixNano"]) ?? receivedAt
                        let sample = AgentUsageSample(
                            value: max(0, value),
                            limit: nil,
                            unit: mapping.unit,
                            scope: Self.boundedString(attributes["scope"]) ?? "session",
                            source: "otlp-json:" + String(name.prefix(120)),
                            observedAt: observedAt
                        )
                        guard sample.isValid else { continue }
                        try Self.append(
                            AgentTelemetryObservation(
                                provider: provider,
                                nativeSessionID: sessionID,
                                source: Self.source(from: attributes),
                                observedAt: observedAt,
                                receivedAt: receivedAt,
                                usage: AgentUsage(samples: [mapping.metric: sample]),
                                model: Self.model(from: attributes)
                            ),
                            into: &observations
                        )
                    }
                }
            }
        }
    }

    private func decodeLogs(
        _ raw: Any?,
        receivedAt: Date,
        into observations: inout [AgentTelemetryObservation]
    ) throws {
        guard let resourceLogs = raw as? [Any] else { return }
        for resourceLogValue in resourceLogs {
            guard let resourceLog = resourceLogValue as? [String: Any] else { continue }
            let resourceAttributes = Self.attributes(fromResource: resourceLog["resource"])
            guard let scopeLogs = resourceLog["scopeLogs"] as? [Any] else { continue }
            for scopeLogValue in scopeLogs {
                guard let scopeLog = scopeLogValue as? [String: Any],
                      let logRecords = scopeLog["logRecords"] as? [Any] else { continue }
                for logValue in logRecords {
                    guard let log = logValue as? [String: Any] else { continue }
                    var attributes = resourceAttributes
                    Self.merge(Self.attributes(from: log["attributes"]), into: &attributes)
                    let eventName = Self.boundedString(attributes["event.name"])
                        ?? Self.boundedString(attributes["event_name"])
                        ?? ""
                    guard let provider = Self.provider(from: attributes, hint: eventName),
                          let sessionID = Self.sessionID(from: attributes) else { continue }

                    let observedAt = Self.timestamp(from: log["timeUnixNano"])
                        ?? Self.timestamp(from: log["observedTimeUnixNano"])
                        ?? receivedAt
                    var samples: [AgentUsageMetric: AgentUsageSample] = [:]
                    for (key, rawValue) in attributes {
                        guard let mapping = Self.metricMapping(key),
                              let value = Self.number(rawValue) else { continue }
                        let sample = AgentUsageSample(
                            value: max(0, value),
                            limit: nil,
                            unit: mapping.unit,
                            scope: Self.boundedString(attributes["scope"]) ?? "session",
                            source: "otlp-json:" + String(key.prefix(120)),
                            observedAt: observedAt
                        )
                        if sample.isValid { samples[mapping.metric] = sample }
                    }
                    let observation = AgentTelemetryObservation(
                        provider: provider,
                        nativeSessionID: sessionID,
                        source: Self.source(from: attributes),
                        observedAt: observedAt,
                        receivedAt: receivedAt,
                        usage: AgentUsage(samples: samples),
                        model: Self.model(from: attributes)
                    )
                    if !observation.isEmpty {
                        try Self.append(observation, into: &observations)
                    }
                }
            }
        }
    }

    private static func append(
        _ observation: AgentTelemetryObservation,
        into observations: inout [AgentTelemetryObservation]
    ) throws {
        guard observations.count < AgentTelemetryLimits.maximumObservations else {
            throw AgentOTLPJSONError.excessiveCardinality
        }
        observations.append(observation)
    }

    private static func dataPoints(from metric: [String: Any]) -> [[String: Any]] {
        let container = (metric["gauge"] as? [String: Any])
            ?? (metric["sum"] as? [String: Any])
        return (container?["dataPoints"] as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func attributes(fromResource raw: Any?) -> [String: Any] {
        guard let resource = raw as? [String: Any] else { return [:] }
        return attributes(from: resource["attributes"])
    }

    private static func attributes(from raw: Any?) -> [String: Any] {
        guard let values = raw as? [Any] else { return [:] }
        var result: [String: Any] = [:]
        for value in values.prefix(AgentTelemetryLimits.maximumAttributeCount) {
            guard let attribute = value as? [String: Any],
                  let key = boundedString(attribute["key"]),
                  let wrapped = attribute["value"] as? [String: Any],
                  let decoded = decodeAnyValue(wrapped) else { continue }
            result[key] = decoded
        }
        return result
    }

    private static func decodeAnyValue(_ value: [String: Any]) -> Any? {
        if let string = boundedString(value["stringValue"]) { return string }
        if let int = value["intValue"] as? NSNumber { return int.doubleValue }
        if let int = value["intValue"] as? String, let number = Double(int) { return number }
        if let double = value["doubleValue"] as? NSNumber { return double.doubleValue }
        if let bool = value["boolValue"] as? Bool { return bool }
        return nil
    }

    private static func merge(_ update: [String: Any], into base: inout [String: Any]) {
        for (key, value) in update { base[key] = value }
    }

    private static func provider(from attributes: [String: Any], hint: String) -> AgentProvider? {
        let text = [
            hint,
            boundedString(attributes["service.name"]) ?? "",
            boundedString(attributes["service_name"]) ?? "",
            boundedString(attributes["provider"]) ?? "",
            boundedString(attributes["gen_ai.system"]) ?? ""
        ].joined(separator: " ").lowercased()
        if text.contains("codex") || text.contains("openai") { return .codex }
        if text.contains("claude") || text.contains("anthropic") { return .claude }
        return nil
    }

    private static func sessionID(from attributes: [String: Any]) -> String? {
        for key in ["session.id", "session_id", "conversation.id", "conversation_id", "thread.id", "thread_id"] {
            if let value = boundedString(attributes[key]),
               value.utf8.count <= AgentDomainLimits.identifierLength {
                return value
            }
        }
        return nil
    }

    private static func model(from attributes: [String: Any]) -> String? {
        for key in ["gen_ai.request.model", "gen_ai.response.model", "model", "model.name", "model_name"] {
            if let value = boundedString(attributes[key]),
               value.utf8.count <= AgentDomainLimits.tokenLength {
                return value
            }
        }
        return nil
    }

    private static func source(from attributes: [String: Any]) -> AgentSource {
        let raw = (boundedString(attributes["source"]) ?? boundedString(attributes["client.name"]) ?? "").lowercased()
        if raw.contains("vscode") || raw.contains("cursor") { return .vscode }
        if raw.contains("jetbrains") || raw.contains("rider") || raw.contains("pycharm") { return .jetbrains }
        if raw.contains("desktop") || raw.contains("app") { return .desktopApp }
        if raw.contains("cloud") || raw.contains("web") { return .cloud }
        if raw.contains("terminal") || raw.contains("cli") || raw.contains("tui") { return .terminal }
        return .unknown
    }

    private static func metricMapping(_ name: String) -> (metric: AgentUsageMetric, unit: AgentUsageUnit)? {
        let key = name.lowercased().replacingOccurrences(of: "-", with: "_")
        if key.contains("cached") && key.contains("token") { return (.cachedInputTokens, .tokens) }
        if key.contains("reasoning") && key.contains("token") { return (.reasoningTokens, .tokens) }
        if key.contains("input") && key.contains("token") { return (.inputTokens, .tokens) }
        if key.contains("output") && key.contains("token") { return (.outputTokens, .tokens) }
        if key.contains("context") && (key.contains("limit") || key.contains("window")) { return (.contextLimit, .tokens) }
        if key.contains("context") && (key.contains("used") || key.contains("usage")) { return (.contextUsed, .tokens) }
        if key.contains("cost") { return (.cost, .currency) }
        if key.contains("quota") && key.contains("limit") { return (.quotaLimit, .count) }
        if key.contains("quota") && (key.contains("used") || key.contains("usage")) { return (.quotaUsed, .count) }
        if key.contains("rate") && key.contains("remaining") { return (.rateLimitRemaining, .count) }
        return nil
    }

    private static func number(fromPoint point: [String: Any]) -> Double? {
        for key in ["asDouble", "asInt", "doubleValue", "intValue", "value"] {
            if let value = number(point[key]) { return value }
        }
        return nil
    }

    private static func number(_ raw: Any?) -> Double? {
        if let number = raw as? NSNumber {
            let value = number.doubleValue
            return value.isFinite ? value : nil
        }
        if let string = raw as? String, let value = Double(string), value.isFinite {
            return value
        }
        return nil
    }

    private static func timestamp(from raw: Any?) -> Date? {
        guard let nanos = number(raw), nanos >= 0 else { return nil }
        return Date(timeIntervalSince1970: nanos / 1_000_000_000.0)
    }

    private static func boundedString(_ raw: Any?) -> String? {
        guard let string = raw as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.utf8.count <= AgentTelemetryLimits.maximumStringBytes,
              trimmed.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    private static func validateJSON(_ value: Any, depth: Int) throws {
        guard depth <= AgentTelemetryLimits.maximumJSONDepth else {
            throw AgentOTLPJSONError.excessiveDepth
        }
        if let object = value as? [String: Any] {
            guard object.count <= AgentTelemetryLimits.maximumObjectKeys else {
                throw AgentOTLPJSONError.excessiveCardinality
            }
            for child in object.values { try validateJSON(child, depth: depth + 1) }
        } else if let array = value as? [Any] {
            guard array.count <= AgentTelemetryLimits.maximumArrayElements else {
                throw AgentOTLPJSONError.excessiveCardinality
            }
            for child in array { try validateJSON(child, depth: depth + 1) }
        }
    }
}

enum AgentTelemetryFusionOutcome: Equatable, Sendable {
    case applied(Int)
    case deferredNoSession
    case ignoredEmpty
    case rejected(AgentIngestionError)
}

actor AgentTelemetryFusion {
    private let coordinator: AgentIngestionCoordinator
    private var producers: [AgentProvider: AgentProducerHandle] = [:]

    init(coordinator: AgentIngestionCoordinator) {
        self.coordinator = coordinator
    }

    func stop() async {
        for handle in producers.values {
            _ = await coordinator.unregisterProducer(handle)
        }
        producers.removeAll()
    }

    func ingest(_ observation: AgentTelemetryObservation) async -> AgentTelemetryFusionOutcome {
        guard !observation.isEmpty else { return .ignoredEmpty }
        let handleResult = await producer(for: observation.provider)
        guard case .success(let handle) = handleResult else {
            if case .failure(let error) = handleResult { return .rejected(error) }
            return .rejected(.invalidProducer)
        }

        let leases = await coordinator.sessionLeases()
        let sessionID = AgentSessionID(provider: observation.provider, nativeID: observation.nativeSessionID)
        guard let lease = leases.first(where: { $0.instanceID.sessionID == sessionID }),
              let continuity = lease.continuity else {
            return .deferredNoSession
        }

        var events: [AgentIngestionEvent] = []
        let stableBase = Self.stableID(
            observation.provider.stableName + "|" +
            observation.nativeSessionID + "|" +
            String(format: "%.6f", observation.observedAt.timeIntervalSince1970)
        )

        if !observation.usage.samples.isEmpty {
            events.append(AgentIngestionEvent(
                schemaVersion: AgentEvent.normalizedSchemaVersion,
                eventID: AgentEventID(rawValue: "otel-usage-" + stableBase),
                provider: observation.provider,
                source: observation.source,
                nativeSessionID: observation.nativeSessionID,
                assertedGeneration: lease.instanceID.generation,
                type: .usageUpdated,
                providerTimestamp: observation.observedAt,
                receivedTimestamp: observation.receivedAt,
                correlationID: nil,
                sequence: nil,
                authority: .structuredTelemetry,
                payload: .usage(observation.usage),
                continuity: continuity
            ))
        }

        if let model = observation.model {
            events.append(AgentIngestionEvent(
                schemaVersion: AgentEvent.normalizedSchemaVersion,
                eventID: AgentEventID(rawValue: "otel-model-" + stableBase),
                provider: observation.provider,
                source: observation.source,
                nativeSessionID: observation.nativeSessionID,
                assertedGeneration: lease.instanceID.generation,
                type: .sessionMetadataUpdated,
                providerTimestamp: observation.observedAt,
                receivedTimestamp: observation.receivedAt,
                correlationID: nil,
                sequence: nil,
                authority: .structuredTelemetry,
                payload: .sessionMetadata(AgentSessionMetadata(
                    project: AgentProjectContext(model: model)
                )),
                continuity: continuity
            ))
        }

        var evidence: [AgentCapability: AgentCapabilityEvidence] = [:]
        if observation.usage[.inputTokens] != nil || observation.usage[.outputTokens] != nil ||
            observation.usage[.cachedInputTokens] != nil || observation.usage[.reasoningTokens] != nil {
            evidence[.tokenUsage] = Self.capabilityEvidence(at: observation.observedAt)
        }
        if observation.usage[.contextUsed] != nil || observation.usage[.contextLimit] != nil {
            evidence[.contextUsage] = Self.capabilityEvidence(at: observation.observedAt)
        }
        if observation.usage[.quotaUsed] != nil || observation.usage[.quotaLimit] != nil ||
            observation.usage[.rateLimitRemaining] != nil {
            evidence[.quotaUsage] = Self.capabilityEvidence(at: observation.observedAt)
        }
        if observation.usage[.cost] != nil {
            evidence[.costUsage] = Self.capabilityEvidence(at: observation.observedAt)
        }
        if observation.model != nil {
            evidence[.modelMetadata] = Self.capabilityEvidence(at: observation.observedAt)
        }

        if !evidence.isEmpty {
            events.append(AgentIngestionEvent(
                schemaVersion: AgentEvent.normalizedSchemaVersion,
                eventID: AgentEventID(rawValue: "otel-cap-" + stableBase),
                provider: observation.provider,
                source: observation.source,
                nativeSessionID: observation.nativeSessionID,
                assertedGeneration: lease.instanceID.generation,
                type: .capabilitiesUpdated,
                providerTimestamp: observation.observedAt,
                receivedTimestamp: observation.receivedAt,
                correlationID: nil,
                sequence: nil,
                authority: .structuredTelemetry,
                payload: .capabilities(AgentCapabilities(evidence: evidence)),
                continuity: continuity
            ))
        }

        guard !events.isEmpty else { return .ignoredEmpty }
        switch await coordinator.ingestAtomically(events, from: handle) {
        case .success(let result):
            return .applied(result.acceptedEvents)
        case .failure(let error):
            return .rejected(error)
        }
    }

    private func producer(
        for provider: AgentProvider
    ) async -> Result<AgentProducerHandle, AgentIngestionError> {
        if let existing = producers[provider] { return .success(existing) }
        guard provider == .codex || provider == .claude else { return .failure(.policyViolation) }
        let descriptor = AgentProducerDescriptor(
            sourceInstanceID: AgentSourceInstanceID(
                rawValue: "dynamic-island." + provider.stableName + "-otlp-json"
            ),
            sourceKind: .structuredTelemetry,
            runtimeVersion: "otlp-json-v1"
        )
        let policy: AgentProducerPolicy = provider == .codex
            ? .codexStructuredTelemetry
            : .claudeStructuredTelemetry
        let result = await coordinator.registerProducer(
            descriptor: descriptor,
            policy: policy,
            authenticatedProducerID: "in-process-" + provider.stableName + "-telemetry"
        )
        if case .success(let handle) = result { producers[provider] = handle }
        return result
    }

    private static func capabilityEvidence(at date: Date) -> AgentCapabilityEvidence {
        AgentCapabilityEvidence(
            authority: .structuredTelemetry,
            source: "otlp-json-v1",
            observedAt: date
        )
    }

    private static func stableID(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}
