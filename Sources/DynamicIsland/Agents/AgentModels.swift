// Continuation validation marker.
import Foundation

enum AgentDomainLimits {
    static let identifierLength = 256
    static let tokenLength = 64
    static let titleLength = 512
    static let summaryLength = 2_048
    static let pathLength = 1_024
    static let bundleIdentifierLength = 256
}

enum AgentProvider: Hashable, Codable, Sendable {
    case codex
    case claude
    case other(String)

    var stableName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .other(let name): name
        }
    }

    /// Distinguishes built-in namespaces from future providers even when a custom
    /// provider happens to use the same display spelling.
    var deterministicSortKey: String {
        switch self {
        case .codex: "0:codex"
        case .claude: "1:claude"
        case .other(let name): "2:\(name)"
        }
    }
}

enum AgentSource: String, Hashable, Codable, Sendable {
    case terminal
    case vscode
    case jetbrains
    case desktopApp
    case cloud
    case unknown
}

struct AgentSessionID: Hashable, Codable, Sendable {
    let provider: AgentProvider
    let nativeID: String

    init(provider: AgentProvider, nativeID: String) {
        self.provider = provider
        self.nativeID = nativeID
    }
}

struct AgentSessionGeneration: RawRepresentable, Hashable, Codable, Comparable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgentSessionInstanceID: Hashable, Codable, Sendable {
    let sessionID: AgentSessionID
    let generation: AgentSessionGeneration
}

struct AgentEventID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct AgentCorrelationID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum AgentState: String, Hashable, Codable, Sendable {
    case idle
    case thinking
    case planning
    case working
    case runningTool
    case runningCommand
    case waitingForApproval
    case waitingForUser
    case planReady
    case completed
    case failed
    case interrupted

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .interrupted: true
        default: false
        }
    }
}

enum AgentCapability: String, CaseIterable, Hashable, Codable, Sendable {
    case sessionLifecycle
    case explicitThinking
    case planLifecycle
    case toolLifecycle
    case commandLifecycle
    case approvalObservation
    case approvalControl
    case userInputObservation
    case subagentLifecycle
    case taskLifecycle
    case tokenUsage
    case contextUsage
    case quotaUsage
    case costUsage
    case modelMetadata
    case projectContext
    case gitMetadata
    case verifiedSourceIdentity
    case sourceAppOpen
}

enum AgentEvidenceAuthority: Int, Hashable, Codable, Comparable, Sendable {
    case heuristic = 0
    case processObservation = 1
    case localStructuredRecord = 2
    case structuredTelemetry = 3
    case lifecycle = 4

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgentCapabilityEvidence: Equatable, Codable, Sendable {
    let authority: AgentEvidenceAuthority
    let source: String
    let observedAt: Date
}

struct AgentCapabilities: Equatable, Codable, Sendable {
    private(set) var evidence: [AgentCapability: AgentCapabilityEvidence]

    init(evidence: [AgentCapability: AgentCapabilityEvidence] = [:]) {
        self.evidence = evidence
    }

    var all: Set<AgentCapability> {
        Set(evidence.keys)
    }

    func contains(_ capability: AgentCapability) -> Bool {
        evidence[capability] != nil
    }

    func evidence(for capability: AgentCapability) -> AgentCapabilityEvidence? {
        evidence[capability]
    }

    func mergingStrongerEvidence(from update: AgentCapabilities) -> AgentCapabilities {
        var merged = evidence
        for (capability, candidate) in update.evidence {
            if let current = merged[capability], current.authority > candidate.authority {
                continue
            }
            merged[capability] = candidate
        }
        return AgentCapabilities(evidence: merged)
    }
}

struct AgentSourceApplication: Equatable, Codable, Sendable {
    let displayName: String
    let bundleIdentifier: String?
}

/// Full paths are optional, memory-only correlation metadata. UI-facing projections omit them.
struct AgentProjectContext: Equatable, Codable, Sendable {
    var displayName: String?
    var workingDirectory: String?
    var repositoryIdentity: String?
    var gitBranch: String?
    var gitCommit: String?
    var model: String?
    var sourceApplication: AgentSourceApplication?

    init(
        displayName: String? = nil,
        workingDirectory: String? = nil,
        repositoryIdentity: String? = nil,
        gitBranch: String? = nil,
        gitCommit: String? = nil,
        model: String? = nil,
        sourceApplication: AgentSourceApplication? = nil
    ) {
        self.displayName = displayName
        self.workingDirectory = workingDirectory
        self.repositoryIdentity = repositoryIdentity
        self.gitBranch = gitBranch
        self.gitCommit = gitCommit
        self.model = model
        self.sourceApplication = sourceApplication
    }
}

struct AgentProjectDisplayContext: Equatable, Sendable {
    let displayName: String?
    let gitBranch: String?
    let model: String?
    let sourceApplicationName: String?
}

enum AgentUsageMetric: String, Hashable, Codable, Sendable {
    case inputTokens
    case outputTokens
    case cachedInputTokens
    case reasoningTokens
    case contextUsed
    case contextLimit
    case cost
    case quotaUsed
    case quotaLimit
    case rateLimitRemaining
}

enum AgentUsageUnit: String, Hashable, Codable, Sendable {
    case tokens
    case currency
    case requests
    case fraction
    case count
}

struct AgentUsageSample: Equatable, Codable, Sendable {
    let value: Double
    let limit: Double?
    let unit: AgentUsageUnit
    let scope: String
    let source: String
    let observedAt: Date

    var isValid: Bool {
        value.isFinite && value >= 0 && (limit.map { $0.isFinite && $0 >= 0 } ?? true)
    }
}

struct AgentUsage: Equatable, Codable, Sendable {
    private(set) var samples: [AgentUsageMetric: AgentUsageSample]

    init(samples: [AgentUsageMetric: AgentUsageSample] = [:]) {
        self.samples = samples
    }

    subscript(metric: AgentUsageMetric) -> AgentUsageSample? {
        samples[metric]
    }

    mutating func merge(_ update: AgentUsage) {
        for (metric, sample) in update.samples where sample.isValid {
            if let current = samples[metric], current.observedAt > sample.observedAt {
                continue
            }
            samples[metric] = sample
        }
    }
}

enum AgentOperationStatus: String, Hashable, Codable, Sendable {
    case active
    case pending
    case resolved
    case completed
    case failed
    case cancelled
    case unknown
}

enum AgentActivityKind: String, Hashable, Codable, Sendable {
    case session
    case thinking
    case plan
    case tool
    case command
    case approval
    case userInput
    case completion
    case failure
    case interruption
    case subagent
}

struct AgentActivity: Identifiable, Equatable, Codable, Sendable {
    let id: AgentEventID
    let kind: AgentActivityKind
    let title: String
    let summary: String?
    let status: AgentOperationStatus
    let correlationID: AgentCorrelationID?
    let timestamp: Date
}

struct AgentTool: Equatable, Codable, Sendable {
    let correlationID: AgentCorrelationID
    var name: String
    var category: String?
    var summary: String?
    var status: AgentOperationStatus
    let startedAt: Date
    var completedAt: Date?
    var success: Bool?
}

struct AgentCommand: Equatable, Codable, Sendable {
    let correlationID: AgentCorrelationID
    var displaySummary: String
    var status: AgentOperationStatus
    let startedAt: Date
    var completedAt: Date?
    var exitCode: Int?
    var success: Bool?
}

enum AgentApprovalState: String, Hashable, Codable, Sendable {
    case pending
    case approved
    case denied
    case cancelled
    case expired
    case unknown

    var isResolved: Bool { self != .pending }
}

struct AgentApproval: Equatable, Codable, Sendable {
    let requestID: AgentCorrelationID
    var summary: String
    var operationCorrelationID: AgentCorrelationID?
    let requestedAt: Date
    var resolvedAt: Date?
    var expiresAt: Date?
    var state: AgentApprovalState
}

struct AgentSubagent: Equatable, Codable, Sendable {
    let nativeID: String
    let correlationID: AgentCorrelationID
    var displayName: String?
    var status: AgentOperationStatus
    let startedAt: Date
    var endedAt: Date?
}

enum AgentAttentionReason: String, Hashable, Codable, Sendable {
    case planReady
    case completed
    case approvalRequired
    case userInputRequired
    case failed
    case interrupted
}

enum AgentAttentionPriority: Int, Hashable, Codable, Comparable, Sendable {
    case interrupted = 10
    case completed = 20
    case planReady = 30
    case userInputRequired = 40
    case approvalRequired = 50
    case failure = 60

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgentAttentionEventID: Hashable, Codable, Sendable {
    let session: AgentSessionInstanceID
    let eventID: AgentEventID
}

struct AgentAttentionEvent: Identifiable, Equatable, Codable, Sendable {
    let eventID: AgentEventID
    let session: AgentSessionInstanceID
    let source: AgentSource
    let reason: AgentAttentionReason
    let priority: AgentAttentionPriority
    let timestamp: Date
    let displaySummary: String

    var id: AgentAttentionEventID {
        AgentAttentionEventID(session: session, eventID: eventID)
    }
}

struct AgentEventFingerprint: Equatable, Sendable {
    let eventType: AgentEventType
    let correlationID: AgentCorrelationID?
    let authority: AgentEvidenceAuthority
    let semanticValue: String
}

enum AgentPendingOperation: Equatable, Sendable {
    case tool(AgentToolEvent, completedAt: Date)
    case command(AgentCommandEvent, completedAt: Date)
    case approval(AgentApprovalResolution, resolvedAt: Date)
}

enum AgentPendingOperationKind: Hashable, Sendable {
    case tool
    case command
    case approval
}

struct AgentPendingOperationKey: Hashable, Sendable {
    let kind: AgentPendingOperationKind
    let correlationID: AgentCorrelationID
}

struct AgentSession: Identifiable, Equatable, Sendable {
    let id: AgentSessionInstanceID
    var source: AgentSource
    var state: AgentState
    var project: AgentProjectContext
    var capabilities: AgentCapabilities
    var usage: AgentUsage
    var tools: [AgentCorrelationID: AgentTool]
    var commands: [AgentCorrelationID: AgentCommand]
    var approvals: [AgentCorrelationID: AgentApproval]
    var subagents: [AgentCorrelationID: AgentSubagent]
    var recentActivity: [AgentActivity]
    let startedAt: Date
    var endedAt: Date?
    var lastUpdatedAt: Date

    var isThinking = false
    var isPlanning = false
    var isWorking = false
    var isPlanReady = false
    var planReadyAuthority: AgentEvidenceAuthority = .heuristic
    var terminalAuthority: AgentEvidenceAuthority = .heuristic
    var capabilitySnapshotAuthority: AgentEvidenceAuthority = .heuristic
    var waitingForUserID: AgentCorrelationID?
    var pendingOperations: [AgentPendingOperationKey: AgentPendingOperation] = [:]
    var pendingOperationOrder: [AgentPendingOperationKey] = []
    var recentEventOrder: [AgentEventID] = []
    var eventFingerprints: [AgentEventID: AgentEventFingerprint] = [:]

    var isActive: Bool {
        endedAt == nil && !state.isTerminal
    }
}
