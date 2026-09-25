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
