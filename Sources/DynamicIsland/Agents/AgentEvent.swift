import Foundation

enum AgentEventOrigin: String, Hashable, Codable, Sendable {
    case live
    case replay
    /// A local session shell created after DynamicIsland restarts while a
    /// trusted provider session is already active. This is never presented as
    /// a provider-emitted SessionStart.
    case localRecovery
}

enum AgentEventType: Hashable, Codable, Sendable {
    case sessionStarted
    case sessionResumed
    case sessionMetadataUpdated
    case sessionEnded
    case agentWorking
    case thinkingStarted
    case thinkingEnded
    case planningStarted
    case planUpdated
    case planReady
    case toolStarted
    case toolCompleted
    case commandStarted
    case commandCompleted
    case approvalRequested
    case approvalResolved
    case waitingForUser
    case userInputResolved
    case usageUpdated
    case capabilitiesUpdated
    case projectContextUpdated
    case taskCompleted
    case taskFailed
    case interrupted
    case subagentStarted
    case subagentEnded
    case heartbeat
    case unsupported(String)

    /// Stable privacy-safe token for deterministic IDs and diagnostics.
    var stableName: String {
        switch self {
        case .sessionStarted: "sessionStarted"
        case .sessionResumed: "sessionResumed"
        case .sessionMetadataUpdated: "sessionMetadataUpdated"
        case .sessionEnded: "sessionEnded"
        case .agentWorking: "agentWorking"
        case .thinkingStarted: "thinkingStarted"
        case .thinkingEnded: "thinkingEnded"
        case .planningStarted: "planningStarted"
        case .planUpdated: "planUpdated"
        case .planReady: "planReady"
        case .toolStarted: "toolStarted"
        case .toolCompleted: "toolCompleted"
        case .commandStarted: "commandStarted"
        case .commandCompleted: "commandCompleted"
        case .approvalRequested: "approvalRequested"
        case .approvalResolved: "approvalResolved"
        case .waitingForUser: "waitingForUser"
        case .userInputResolved: "userInputResolved"
        case .usageUpdated: "usageUpdated"
        case .capabilitiesUpdated: "capabilitiesUpdated"
        case .projectContextUpdated: "projectContextUpdated"
        case .taskCompleted: "taskCompleted"
        case .taskFailed: "taskFailed"
        case .interrupted: "interrupted"
        case .subagentStarted: "subagentStarted"
        case .subagentEnded: "subagentEnded"
        case .heartbeat: "heartbeat"
        case .unsupported: "unsupported"
        }
    }
}

struct AgentSessionMetadata: Equatable, Codable, Sendable {
    let project: AgentProjectContext?
    let availability: AgentSessionAvailability?

    init(
        project: AgentProjectContext?,
        availability: AgentSessionAvailability? = nil
    ) {
        self.project = project
        self.availability = availability
    }
}

struct AgentActivityDescriptor: Equatable, Codable, Sendable {
    let title: String?
    let summary: String?
}

struct AgentPlanEvent: Equatable, Codable, Sendable {
    let summary: String?
}

struct AgentToolEvent: Equatable, Codable, Sendable {
    let name: String?
    let category: String?
    let summary: String?
    let success: Bool?
}

struct AgentCommandEvent: Equatable, Codable, Sendable {
    /// Provider adapters must pass an executable/name, not a complete command line.
    let executable: String?
    let success: Bool?
    let exitCode: Int?
}

struct AgentApprovalRequest: Equatable, Codable, Sendable {
    let summary: String?
    let operationCorrelationID: AgentCorrelationID?
    let expiresAt: Date?
}

struct AgentApprovalResolution: Equatable, Codable, Sendable {
    let state: AgentApprovalState
}

struct AgentUserInputEvent: Equatable, Codable, Sendable {
    let summary: String?
}

struct AgentTerminalEvent: Equatable, Codable, Sendable {
    let summary: String?
}

struct AgentSubagentEvent: Equatable, Codable, Sendable {
    let nativeID: String
    let displayName: String?
}

enum AgentEventPayload: Equatable, Codable, Sendable {
    case none
    case sessionMetadata(AgentSessionMetadata)
    case activity(AgentActivityDescriptor)
    case plan(AgentPlanEvent)
    case tool(AgentToolEvent)
    case command(AgentCommandEvent)
    case approvalRequest(AgentApprovalRequest)
    case approvalResolution(AgentApprovalResolution)
    case userInput(AgentUserInputEvent)
    case usage(AgentUsage)
    case capabilities(AgentCapabilities)
    case projectContext(AgentProjectContext)
    case terminal(AgentTerminalEvent)
    case subagent(AgentSubagentEvent)
    case unsupported(String)
}

struct AgentEvent: Equatable, Codable, Sendable {
    static let normalizedSchemaVersion = 1

    let schemaVersion: Int
    let eventID: AgentEventID
    let sessionID: AgentSessionID
    let generation: AgentSessionGeneration
    let source: AgentSource
    let type: AgentEventType
    let providerTimestamp: Date?
    let receivedTimestamp: Date
    let correlationID: AgentCorrelationID?
    let sequence: UInt64?
    let authority: AgentEvidenceAuthority
    let origin: AgentEventOrigin
    let payload: AgentEventPayload
    let provenance: AgentEventProvenance?

    init(
        schemaVersion: Int = AgentEvent.normalizedSchemaVersion,
        eventID: AgentEventID,
        sessionID: AgentSessionID,
        generation: AgentSessionGeneration,
        source: AgentSource,
        type: AgentEventType,
        providerTimestamp: Date? = nil,
        receivedTimestamp: Date,
        correlationID: AgentCorrelationID? = nil,
        sequence: UInt64? = nil,
        authority: AgentEvidenceAuthority = .lifecycle,
        origin: AgentEventOrigin = .live,
        payload: AgentEventPayload = .none,
        provenance: AgentEventProvenance? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.sessionID = sessionID
        self.generation = generation
        self.source = source
        self.type = type
        self.providerTimestamp = providerTimestamp
        self.receivedTimestamp = receivedTimestamp
        self.correlationID = correlationID
        self.sequence = sequence
        self.authority = authority
        self.origin = origin
        self.payload = payload
        self.provenance = provenance
    }

    var instanceID: AgentSessionInstanceID {
        AgentSessionInstanceID(sessionID: sessionID, generation: generation)
    }

    var effectiveTimestamp: Date {
        guard let providerTimestamp,
              providerTimestamp <= receivedTimestamp.addingTimeInterval(300) else {
            return receivedTimestamp
        }
        return providerTimestamp
    }

    var fingerprint: AgentEventFingerprint {
        AgentEventFingerprint(
            eventType: type,
            correlationID: correlationID,
            authority: authority,
            semanticValue: Self.stablePayloadFingerprint(payload)
        )
    }

    func validationError() -> AgentEventValidationError? {
        guard schemaVersion == Self.normalizedSchemaVersion else { return .unsupportedSchema }
        guard generation.rawValue > 0 else { return .invalidGeneration }
        guard Self.validIdentifier(eventID.rawValue) else { return .invalidEventID }
        guard Self.validIdentifier(sessionID.nativeID) else { return .invalidSessionID }
        if case .other(let name) = sessionID.provider,
           !Self.validToken(name) {
            return .invalidProvider
        }
        if let correlationID, !Self.validIdentifier(correlationID.rawValue) {
            return .invalidCorrelationID
        }
        if case .approvalRequest(let request) = payload,
           let operationCorrelationID = request.operationCorrelationID,
           !Self.validIdentifier(operationCorrelationID.rawValue) {
            return .invalidCorrelationID
        }
        if case .unsupported = type { return .unsupportedEventType }
        if case .unsupported = payload { return .unsupportedPayload }
        guard payloadIsCompatible else { return .payloadMismatch }
        if case .usage(let usage) = payload,
           usage.allSamples.contains(where: { !$0.isValid }) {
            return .invalidUsage
        }
        if case .approvalResolution(let resolution) = payload,
           resolution.state == .pending {
            return .invalidApprovalResolution
        }
        if case .subagent(let subagent) = payload,
           !Self.validIdentifier(subagent.nativeID) {
            return .invalidSubagentID
        }
        return nil
    }

    private var payloadIsCompatible: Bool {
        switch type {
        case .sessionStarted, .sessionMetadataUpdated:
            if case .sessionMetadata = payload { return true }
            return false
        case .sessionResumed:
            if case .sessionMetadata = payload { return true }
            if case .none = payload { return true }
            return false
        case .sessionEnded, .thinkingEnded, .userInputResolved, .heartbeat:
            if case .none = payload { return true }
            return false
        case .agentWorking, .thinkingStarted, .planningStarted:
            if case .activity = payload { return true }
            if case .none = payload { return true }
            return false
        case .planUpdated, .planReady:
            if case .plan = payload { return true }
            return false
        case .toolStarted, .toolCompleted:
            if case .tool = payload { return true }
            return false
        case .commandStarted, .commandCompleted:
            if case .command = payload { return true }
            return false
        case .approvalRequested:
            if case .approvalRequest = payload { return true }
            return false
        case .approvalResolved:
            if case .approvalResolution = payload { return true }
            return false
        case .waitingForUser:
            if case .userInput = payload { return true }
            return false
        case .usageUpdated:
            if case .usage = payload { return true }
            return false
        case .capabilitiesUpdated:
            if case .capabilities = payload { return true }
            return false
        case .projectContextUpdated:
            if case .projectContext = payload { return true }
            return false
        case .taskCompleted, .taskFailed, .interrupted:
            if case .terminal = payload { return true }
            return false
        case .subagentStarted, .subagentEnded:
            if case .subagent = payload { return true }
            return false
        case .unsupported:
            return false
        }
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            value.utf8.count <= AgentDomainLimits.identifierLength &&
            value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func validToken(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= AgentDomainLimits.tokenLength else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    private static func stablePayloadFingerprint(_ payload: AgentEventPayload) -> String {
        let data: Data
        switch payload {
        case .capabilities(let capabilities):
            let value = capabilities.evidence
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .map { capability, evidence in
                    [
                        capability.rawValue,
                        String(evidence.authority.rawValue),
                        evidence.source,
                        String(evidence.observedAt.timeIntervalSince1970.bitPattern)
                    ].joined(separator: "|")
                }
                .joined(separator: "\n")
            data = Data(value.utf8)
        case .usage(let usage):
            let value = usage.scopedEntries
                .sorted {
                    if $0.key.metric.rawValue != $1.key.metric.rawValue {
                        return $0.key.metric.rawValue < $1.key.metric.rawValue
                    }
                    return $0.key.scope < $1.key.scope
                }
                .map { key, sample in
                    [
                        key.metric.rawValue,
                        String(sample.value.bitPattern),
                        sample.limit.map { String($0.bitPattern) } ?? "nil",
                        sample.unit.rawValue,
                        sample.scope,
                        sample.source,
                        String(sample.observedAt.timeIntervalSince1970.bitPattern)
                    ].joined(separator: "|")
                }
                .joined(separator: "\n")
            data = Data(value.utf8)
        default:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            guard let encoded = try? encoder.encode(payload) else { return "encoding-failed" }
            data = encoded
        }

        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

enum AgentEventValidationError: String, Equatable, Sendable {
    case unsupportedSchema
    case invalidGeneration
    case invalidEventID
    case invalidSessionID
    case invalidProvider
    case invalidCorrelationID
    case unsupportedEventType
    case unsupportedPayload
    case payloadMismatch
    case invalidUsage
    case invalidApprovalResolution
    case invalidSubagentID
}
