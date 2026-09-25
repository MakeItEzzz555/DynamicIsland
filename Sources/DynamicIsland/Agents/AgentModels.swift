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


struct AgentAttentionGeneration: RawRepresentable, Hashable, Comparable, Sendable {
    let rawValue: UInt64

    init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum AgentAttentionStyle: String, Equatable, Sendable {
    case informational
    case success
    case actionRequired
    case failure
}

struct AgentAttentionPresentation: Equatable, Sendable {
    let generation: AgentAttentionGeneration
    let items: [AgentAttentionEvent]
    let overflowCount: Int
    let style: AgentAttentionStyle
    let createdAt: Date
    let updatedAt: Date
    let retractAt: Date

    var primary: AgentAttentionEvent? {
        items.max {
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.timestamp < $1.timestamp
        }
    }

    var totalCount: Int {
        items.count + overflowCount
    }
}

struct AgentAttentionBadge: Equatable, Sendable {
    let session: AgentSessionInstanceID
    let reason: AgentAttentionReason
    let priority: AgentAttentionPriority
    let eventID: AgentEventID
    let summary: String
    let createdAt: Date
}

struct AgentAttentionSoundIntent: Equatable, Sendable {
    let generation: AgentAttentionGeneration
    let eventID: AgentEventID
    let reason: AgentAttentionReason
}

struct AgentAttentionPolicyOptions: Equatable, Sendable {
    var peekDuration: TimeInterval = 5.0
    var coalescingWindow: TimeInterval = 0.75
    var soundThrottle: TimeInterval = 1.5
    var maximumPresentedItems = 3
    var maximumRememberedEvents = 256
    var completionAlertsEnabled = true
    var approvalAlertsEnabled = true
    var soundsEnabled = true
}

struct AgentAttentionPolicyState: Equatable, Sendable {
    var generation = AgentAttentionGeneration(rawValue: 0)
    var presentation: AgentAttentionPresentation?
    var badges: [AgentSessionInstanceID: AgentAttentionBadge] = [:]
    var rememberedEventOrder: [AgentAttentionEventID] = []
    var rememberedEventIDs: Set<AgentAttentionEventID> = []
    var soundedEventOrder: [AgentAttentionEventID] = []
    var soundedEventIDs: Set<AgentAttentionEventID> = []
    var lastSoundAt: Date?
}

struct AgentAttentionPolicyResult: Equatable, Sendable {
    let state: AgentAttentionPolicyState
    let soundIntent: AgentAttentionSoundIntent?
}

/// Pure attention policy. Delayed execution belongs to AgentAttentionCoordinator;
/// this reducer is deterministic and contains no sleeps or UI behavior.
enum AgentAttentionPolicyEngine {
    static func apply(
        events: [AgentAttentionEvent],
        sessions: [AgentSession],
        now: Date,
        state initialState: AgentAttentionPolicyState,
        options: AgentAttentionPolicyOptions
    ) -> AgentAttentionPolicyResult {
        var state = initialState
        var soundIntent: AgentAttentionSoundIntent?

        reconcileBadges(with: sessions, state: &state)

        for event in events.sorted(by: eventOrder) {
            guard !state.rememberedEventIDs.contains(event.id) else { continue }
            remember(event.id, order: &state.rememberedEventOrder, set: &state.rememberedEventIDs, limit: options.maximumRememberedEvents)

            if shouldPersist(event.reason) {
                state.badges[event.session] = AgentAttentionBadge(
                    session: event.session,
                    reason: event.reason,
                    priority: event.priority,
                    eventID: event.eventID,
                    summary: event.displaySummary,
                    createdAt: event.timestamp
                )
            } else if event.reason == .completed {
                state.badges.removeValue(forKey: event.session)
            }

            guard shouldPresent(event, options: options) else { continue }

            let nextGeneration = AgentAttentionGeneration(rawValue: state.generation.rawValue &+ 1)
            state.generation = nextGeneration
            let previous = state.presentation
            let presentation = mergedPresentation(
                previous,
                event: event,
                generation: nextGeneration,
                now: now,
                options: options
            )
            state.presentation = presentation

            if soundIntent == nil,
               shouldSound(event, options: options),
               !state.soundedEventIDs.contains(event.id),
               soundThrottleAllows(now: now, state: state, options: options) {
                remember(event.id, order: &state.soundedEventOrder, set: &state.soundedEventIDs, limit: options.maximumRememberedEvents)
                state.lastSoundAt = now
                soundIntent = AgentAttentionSoundIntent(
                    generation: nextGeneration,
                    eventID: event.eventID,
                    reason: event.reason
                )
            }
        }

        return AgentAttentionPolicyResult(state: state, soundIntent: soundIntent)
    }

    static func expire(
        generation: AgentAttentionGeneration,
        now: Date,
        state initialState: AgentAttentionPolicyState
    ) -> AgentAttentionPolicyState {
        var state = initialState
        guard let presentation = state.presentation,
              presentation.generation == generation,
              now >= presentation.retractAt else {
            return state
        }
        state.presentation = nil
        return state
    }

    static func dismissPresentation(
        state initialState: AgentAttentionPolicyState
    ) -> AgentAttentionPolicyState {
        var state = initialState
        state.generation = AgentAttentionGeneration(rawValue: state.generation.rawValue &+ 1)
        state.presentation = nil
        return state
    }

    static func markViewed(
        session: AgentSessionInstanceID,
        state initialState: AgentAttentionPolicyState
    ) -> AgentAttentionPolicyState {
        var state = initialState
        state.badges.removeValue(forKey: session)
        return state
    }

    private static func mergedPresentation(
        _ previous: AgentAttentionPresentation?,
        event: AgentAttentionEvent,
        generation: AgentAttentionGeneration,
        now: Date,
        options: AgentAttentionPolicyOptions
    ) -> AgentAttentionPresentation {
        var items: [AgentAttentionEvent] = []
        var overflow = 0
        var createdAt = now

        if let previous {
            items = previous.items
            overflow = previous.overflowCount
            createdAt = previous.createdAt

            if let index = items.firstIndex(where: { $0.session == event.session }) {
                let current = items[index]
                if event.priority >= current.priority || event.timestamp >= current.timestamp {
                    items[index] = event
                }
            } else if items.count < max(1, options.maximumPresentedItems) {
                items.append(event)
            } else {
                overflow += 1
            }
        } else {
            items = [event]
        }

        let style = items.map { style(for: $0.reason) }.max(by: styleRank) ?? style(for: event.reason)
        return AgentAttentionPresentation(
            generation: generation,
            items: items,
            overflowCount: overflow,
            style: style,
            createdAt: createdAt,
            updatedAt: now,
            retractAt: now.addingTimeInterval(max(0.1, options.peekDuration))
        )
    }

    private static func reconcileBadges(
        with sessions: [AgentSession],
        state: inout AgentAttentionPolicyState
    ) {
        let sessionsByID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })
        state.badges = state.badges.filter { instanceID, badge in
            guard let session = sessionsByID[instanceID] else { return false }
            switch badge.reason {
            case .approvalRequired:
                return session.state == .waitingForApproval
            case .userInputRequired:
                return session.state == .waitingForUser
            case .failed:
                return session.state == .failed
            case .planReady:
                return session.state == .planReady
            case .completed, .interrupted:
                return false
            }
        }
    }

    private static func shouldPersist(_ reason: AgentAttentionReason) -> Bool {
        switch reason {
        case .approvalRequired, .userInputRequired, .failed:
            true
        case .planReady, .completed, .interrupted:
            false
        }
    }

    private static func shouldPresent(
        _ event: AgentAttentionEvent,
        options: AgentAttentionPolicyOptions
    ) -> Bool {
        switch event.reason {
        case .approvalRequired, .userInputRequired:
            return options.approvalAlertsEnabled
        case .completed, .planReady, .failed:
            return options.completionAlertsEnabled
        case .interrupted:
            return options.completionAlertsEnabled
        }
    }

    private static func shouldSound(
        _ event: AgentAttentionEvent,
        options: AgentAttentionPolicyOptions
    ) -> Bool {
        guard options.soundsEnabled else { return false }
        switch event.reason {
        case .planReady, .completed, .approvalRequired, .userInputRequired, .failed:
            true
        case .interrupted:
            false
        }
    }

    private static func soundThrottleAllows(
        now: Date,
        state: AgentAttentionPolicyState,
        options: AgentAttentionPolicyOptions
    ) -> Bool {
        guard let lastSoundAt = state.lastSoundAt else { return true }
        return now.timeIntervalSince(lastSoundAt) >= max(0, options.soundThrottle)
    }

    private static func style(for reason: AgentAttentionReason) -> AgentAttentionStyle {
        switch reason {
        case .planReady, .interrupted:
            .informational
        case .completed:
            .success
        case .approvalRequired, .userInputRequired:
            .actionRequired
        case .failed:
            .failure
        }
    }

    private static func styleRank(_ lhs: AgentAttentionStyle, _ rhs: AgentAttentionStyle) -> Bool {
        rank(lhs) < rank(rhs)
    }

    private static func rank(_ style: AgentAttentionStyle) -> Int {
        switch style {
        case .informational: 0
        case .success: 1
        case .actionRequired: 2
        case .failure: 3
        }
    }

    private static func eventOrder(_ lhs: AgentAttentionEvent, _ rhs: AgentAttentionEvent) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
        return lhs.eventID.rawValue < rhs.eventID.rawValue
    }

    private static func remember<T: Hashable>(
        _ value: T,
        order: inout [T],
        set: inout Set<T>,
        limit: Int
    ) {
        set.insert(value)
        order.append(value)
        let safeLimit = max(1, limit)
        if order.count > safeLimit {
            let removed = order.removeFirst(order.count - safeLimit)
            for item in removed { set.remove(item) }
        }
    }
}
