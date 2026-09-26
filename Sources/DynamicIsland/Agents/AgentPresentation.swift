import Combine
import Foundation

enum AgentPresentationPriority: Int, Comparable, Sendable {
    case actionRequired
    case failure
    case working
    case thinking
    case recent
    case idle

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct AgentCompactPresentation: Equatable, Sendable {
    static let maximumVisibleSessions = 3

    let sessions: [AgentSession]
    let overflowCount: Int
    let summary: String

    static func make(sessions: [AgentSession], enabled: Bool = true) -> AgentCompactPresentation? {
        guard enabled, !sessions.isEmpty else { return nil }
        let ordered = sessions
            .filter(\.isActive)
            .sorted(by: AgentSessionPresentation.isOrderedBefore)
        guard !ordered.isEmpty else { return nil }
        let visible = Array(ordered.prefix(maximumVisibleSessions))
        return AgentCompactPresentation(
            sessions: visible,
            overflowCount: max(ordered.count - visible.count, 0),
            summary: summary(for: ordered)
        )
    }

    private static func summary(for sessions: [AgentSession]) -> String {
        if sessions.count == 1, let session = sessions.first {
            return "\(session.id.sessionID.provider.stableName.capitalized) \(AgentSessionPresentation.shortStateLabel(session.state).lowercased())"
        }

        let waiting = sessions.filter { AgentSessionPresentation.priority(for: $0) == .actionRequired }.count
        let failures = sessions.filter { AgentSessionPresentation.priority(for: $0) == .failure }.count
        let working = sessions.filter { AgentSessionPresentation.priority(for: $0) == .working }.count
        let thinking = sessions.filter { AgentSessionPresentation.priority(for: $0) == .thinking }.count
        var parts: [String] = []
        if waiting > 0 { parts.append("\(waiting) waiting") }
        if failures > 0 { parts.append("\(failures) failed") }
        if working > 0 { parts.append("\(working) working") }
        if thinking > 0 { parts.append("\(thinking) thinking") }
        if parts.isEmpty { return "\(sessions.count) agent\(sessions.count == 1 ? "" : "s")" }
        return parts.prefix(2).joined(separator: " · ")
    }
}

enum AgentCollapsedShellPresentation {
    static func routine(sessions: [AgentSession], enabled: Bool) -> CollapsedPresentationProfile? {
        guard let compact = AgentCompactPresentation.make(sessions: sessions, enabled: enabled) else {
            return nil
        }
        let markerWidth = min(
            84,
            CGFloat(compact.sessions.count * 18 + (compact.overflowCount > 0 ? 22 : 0))
        )
        return .agentRoutine(
            leftContentWidth: max(markerWidth, 28),
            rightContentWidth: estimatedWidth(compact.summary, minimum: 56, maximum: 112)
        )
    }

    static func attention(
        _ presentation: AgentAttentionPresentation,
        session: AgentSession?
    ) -> CollapsedPresentationProfile {
        let provider = presentation.primary?.session.sessionID.provider.stableName.capitalized ?? "Agent"
        let project = session?.project.displayName ?? provider
        let trailing = presentation.totalCount > 1
            ? "\(presentation.totalCount) agents"
            : (presentation.primary?.displaySummary ?? "Needs attention")
        return .agentAttention(
            leftContentWidth: estimatedWidth(project, minimum: 62, maximum: 112),
            rightContentWidth: estimatedWidth(trailing, minimum: 76, maximum: 126)
        )
    }

    private static func estimatedWidth(
        _ text: String,
        minimum: CGFloat,
        maximum: CGFloat
    ) -> CGFloat {
        min(maximum, max(minimum, CGFloat(text.prefix(32).count) * 5.2 + 12))
    }
}

enum AgentSessionPresentation {
    static func requiresAttention(_ session: AgentSession) -> Bool {
        switch session.state {
        case .waitingForApproval, .waitingForUser, .planReady, .failed, .interrupted:
            true
        default:
            false
        }
    }

    static func priority(for session: AgentSession) -> AgentPresentationPriority {
        switch session.state {
        case .waitingForApproval, .waitingForUser, .planReady:
            .actionRequired
        case .failed, .interrupted:
            .failure
        case .working, .runningTool, .runningCommand:
            .working
        case .thinking, .planning:
            .thinking
        case .completed:
            .recent
        case .idle:
            .idle
        }
    }

    static func isOrderedBefore(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsPriority = priority(for: lhs)
        let rhsPriority = priority(for: rhs)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        if lhs.isActive != rhs.isActive { return lhs.isActive && !rhs.isActive }
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt { return lhs.lastUpdatedAt > rhs.lastUpdatedAt }
        let lhsProvider = lhs.id.sessionID.provider.deterministicSortKey
        let rhsProvider = rhs.id.sessionID.provider.deterministicSortKey
        if lhsProvider != rhsProvider { return lhsProvider < rhsProvider }
        if lhs.id.sessionID.nativeID != rhs.id.sessionID.nativeID {
            return lhs.id.sessionID.nativeID < rhs.id.sessionID.nativeID
        }
        return lhs.id.generation > rhs.id.generation
    }

    static func stateLabel(_ state: AgentState) -> String {
        switch state {
        case .idle: "Idle"
        case .thinking: "Thinking"
        case .planning: "Planning"
        case .working: "Working"
        case .runningTool: "Running tool"
        case .runningCommand: "Running command"
        case .waitingForApproval: "Approval requested"
        case .waitingForUser: "Waiting for input"
        case .planReady: "Plan ready"
        case .completed: "Completed"
        case .failed: "Failed"
        case .interrupted: "Interrupted"
        }
    }

    static func shortStateLabel(_ state: AgentState) -> String {
        switch state {
        case .runningTool: "Tool"
        case .runningCommand: "Command"
        case .waitingForApproval: "Approval"
        case .waitingForUser: "Waiting"
        default: stateLabel(state)
        }
    }

    static func stateSymbol(_ state: AgentState) -> String {
        switch state {
        case .idle: "circle"
        case .thinking, .planning: "brain.head.profile"
        case .working: "waveform.path.ecg"
        case .runningTool: "wrench.and.screwdriver.fill"
        case .runningCommand: "terminal.fill"
        case .waitingForApproval: "checkmark.shield.fill"
        case .waitingForUser: "person.crop.circle.badge.questionmark"
        case .planReady: "list.bullet.clipboard.fill"
        case .completed: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .interrupted: "stop.circle.fill"
        }
    }

    static func primaryTitle(for session: AgentSession) -> String {
        if session.state == .waitingForApproval,
           let activity = session.recentActivity.last {
            let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let approvalSummary = session.approvals.values
                .filter { $0.state == .pending }
                .sorted { $0.requestedAt > $1.requestedAt }
                .first?.summary
            if !title.isEmpty,
               !isGenericApprovalTitle(title),
               normalizedForComparison(title) != approvalSummary.map(normalizedForComparison) {
                return title
            }
        }

        if requiresAttention(session) {
            if let plan = session.recentActivity.reversed().first(where: {
                $0.kind == .plan && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
                return plan.title
            }
            if let project = session.project.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !project.isEmpty {
                return project
            }
        }

        if let activity = session.recentActivity.last,
           !activity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return activity.title
        }
        if let project = session.project.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            return project
        }
        return stateLabel(session.state)
    }

    private static func normalizedForComparison(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    private static func isGenericApprovalTitle(_ value: String) -> Bool {
        let normalized = normalizedForComparison(value)
        return normalized == "approval" ||
            normalized == "approval required" ||
            normalized == "approval requested" ||
            normalized.hasSuffix(" approval required") ||
            normalized.hasSuffix(" approval requested")
    }

    static func attentionDetail(for session: AgentSession) -> String {
        switch session.state {
        case .waitingForApproval:
            return session.approvals.values
                .filter { $0.state == .pending }
                .sorted { $0.requestedAt > $1.requestedAt }
                .first?.summary ?? "Waiting for approval in \(session.id.sessionID.provider.stableName.capitalized)"
        case .waitingForUser:
            return "Waiting for input in \(session.id.sessionID.provider.stableName.capitalized)"
        case .planReady:
            return session.recentActivity.reversed().first(where: { $0.kind == .plan })?.summary
                ?? "Plan ready in \(session.id.sessionID.provider.stableName.capitalized)"
        case .failed:
            return session.recentActivity.last?.summary ?? "The provider reported a failure"
        case .interrupted:
            return session.recentActivity.last?.summary ?? "The provider reported an interruption"
        default:
            return stateLabel(session.state)
        }
    }
}

struct AgentProjectGroupPresentation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let sessions: [AgentSession]

    var subagentCount: Int {
        sessions.reduce(0) { $0 + $1.subagents.count }
    }
}

struct AgentDashboardPresentation: Equatable, Sendable {
    let groups: [AgentProjectGroupPresentation]

    static func make(sessions: [AgentSession]) -> Self {
        let ordered = sessions.sorted(by: AgentSessionPresentation.isOrderedBefore)
        var keys: [String] = []
        var titles: [String: String] = [:]
        var grouped: [String: [AgentSession]] = [:]

        for session in ordered {
            let identity = projectIdentity(for: session)
            if grouped[identity.key] == nil {
                keys.append(identity.key)
                titles[identity.key] = identity.title
            }
            grouped[identity.key, default: []].append(session)
        }

        return Self(groups: keys.map { key in
            AgentProjectGroupPresentation(
                id: key,
                title: titles[key] ?? "Other",
                sessions: grouped[key] ?? []
            )
        })
    }

    private static func projectIdentity(for session: AgentSession) -> (key: String, title: String) {
        if let project = session.project.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            let repository = session.project.repositoryIdentity?.trimmingCharacters(in: .whitespacesAndNewlines)
            let discriminator = repository.flatMap { $0.isEmpty ? nil : $0.lowercased() } ?? ""
            return ("project:\(project.lowercased())|\(discriminator)", project)
        }
        if let repository = session.project.repositoryIdentity?.trimmingCharacters(in: .whitespacesAndNewlines),
           !repository.isEmpty {
            return ("repository:\(repository.lowercased())", repository)
        }
        let provider = session.id.sessionID.provider.stableName.capitalized
        return ("provider:\(session.id.sessionID.provider.deterministicSortKey)", "\(provider) sessions")
    }
}

struct AgentDashboardLayoutProjection: Equatable, Sendable {
    let isNarrow: Bool
    let maximumGaugeCount: Int
    let showsModel: Bool
    let trailingColumnWidth: CGFloat

    static func make(width: CGFloat) -> Self {
        if width < 620 {
            return Self(isNarrow: true, maximumGaugeCount: 2, showsModel: false, trailingColumnWidth: 76)
        }
        return Self(isNarrow: false, maximumGaugeCount: 5, showsModel: true, trailingColumnWidth: 126)
    }
}

struct AgentOperationSummary: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let detail: String?
    let status: AgentOperationStatus
    let count: Int
    let date: Date

    var displayTitle: String {
        count > 1 ? "\(title) ×\(count)" : title
    }
}

enum AgentOperationAggregation {
    static func make(
        for session: AgentSession,
        limit: Int = 3,
        includePendingApprovals: Bool = true
    ) -> [AgentOperationSummary] {
        var operations: [AgentOperationSummary] = []
        if includePendingApprovals {
            operations += session.approvals.values
                .filter { $0.state == .pending }
                .map {
                    AgentOperationSummary(
                        id: "approval:\($0.requestID.rawValue)",
                        symbol: "checkmark.shield",
                        title: "Approval requested",
                        detail: $0.summary,
                        status: .pending,
                        count: 1,
                        date: $0.requestedAt
                    )
                }
        }
        operations += session.tools.values.map {
            AgentOperationSummary(
                id: "tool:\($0.correlationID.rawValue)",
                symbol: symbol(for: $0.name, fallback: "wrench.and.screwdriver"),
                title: friendlyTitle($0.name),
                detail: $0.summary,
                status: $0.status,
                count: 1,
                date: $0.completedAt ?? $0.startedAt
            )
        }
        operations += session.commands.values.map {
            AgentOperationSummary(
                id: "command:\($0.correlationID.rawValue)",
                symbol: symbol(for: $0.displaySummary, fallback: "terminal"),
                title: friendlyTitle($0.displaySummary),
                detail: $0.exitCode.map { "Exit \($0)" },
                status: $0.status,
                count: 1,
                date: $0.completedAt ?? $0.startedAt
            )
        }
        operations += session.subagents.values.map {
            AgentOperationSummary(
                id: "subagent:\($0.correlationID.rawValue)",
                symbol: "person.2",
                title: $0.status == .active ? "Subagent active" : "Subagent",
                detail: $0.displayName,
                status: $0.status,
                count: 1,
                date: $0.endedAt ?? $0.startedAt
            )
        }

        var aggregated: [String: AgentOperationSummary] = [:]
        for operation in operations.sorted(by: operationOrder) {
            let key = "\(operation.title.lowercased())|\(operation.status.rawValue)"
            if let existing = aggregated[key] {
                aggregated[key] = AgentOperationSummary(
                    id: existing.id,
                    symbol: existing.symbol,
                    title: existing.title,
                    detail: existing.detail ?? operation.detail,
                    status: existing.status,
                    count: existing.count + 1,
                    date: max(existing.date, operation.date)
                )
            } else {
                aggregated[key] = operation
            }
        }
        return Array(aggregated.values.sorted(by: operationOrder).prefix(max(limit, 0)))
    }

    private static func operationOrder(_ lhs: AgentOperationSummary, _ rhs: AgentOperationSummary) -> Bool {
        let lhsActive = lhs.status == .pending || lhs.status == .active
        let rhsActive = rhs.status == .pending || rhs.status == .active
        if lhsActive != rhsActive { return lhsActive && !rhsActive }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id < rhs.id
    }

    private static func friendlyTitle(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower == "bash" || lower == "shell" || lower == "terminal" { return "Bash" }
        if lower.contains("test") { return "Run tests" }
        if lower.contains("search") || lower.contains("grep") || lower.contains("find") { return "Search repository" }
        if lower.contains("read") || lower.contains("file") { return "Read file" }
        guard let first = trimmed.first else { return "Operation" }
        return String(first).uppercased() + trimmed.dropFirst()
    }

    private static func symbol(for raw: String, fallback: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("test") { return "checkmark.circle" }
        if lower.contains("search") || lower.contains("grep") || lower.contains("find") { return "magnifyingglass" }
        if lower.contains("read") || lower.contains("file") { return "doc.text" }
        return fallback
    }
}

struct AgentUsagePresentation: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let sample: AgentUsageSample
    let effectiveLimit: Double?

    var isStale: Bool { isStale(at: Date()) }

    func isStale(at date: Date) -> Bool {
        date.timeIntervalSince(sample.observedAt) > 300
    }

    var progress: Double? {
        guard let effectiveLimit, effectiveLimit.isFinite, effectiveLimit > 0 else { return nil }
        return min(max(sample.value / effectiveLimit, 0), 1)
    }

    var valueText: String {
        let value = sample.value.formatted(.number.precision(.fractionLength(0...2)))
        guard let effectiveLimit else { return value + " " + sample.unit.rawValue }
        let limit = effectiveLimit.formatted(.number.precision(.fractionLength(0...2)))
        return value + " / " + limit + " " + sample.unit.rawValue
    }

    static func make(for session: AgentSession) -> [AgentUsagePresentation] {
        var values: [AgentUsagePresentation] = []
        if session.capabilities.contains(.contextUsage), let used = session.usage[.contextUsed] {
            let limit = used.limit ?? session.usage[.contextLimit]?.value
            values.append(.init(id: "context", label: "Context", sample: used, effectiveLimit: limit))
        }
        if session.capabilities.contains(.tokenUsage) {
            for (metric, label) in [(AgentUsageMetric.inputTokens, "Input"), (.outputTokens, "Output"), (.cachedInputTokens, "Cached"), (.reasoningTokens, "Reasoning")] {
                if let sample = session.usage[metric] {
                    values.append(.init(id: metric.rawValue, label: label, sample: sample, effectiveLimit: sample.limit))
                }
            }
        }
        if session.capabilities.contains(.quotaUsage), let used = session.usage[.quotaUsed] {
            let limit = used.limit ?? session.usage[.quotaLimit]?.value
            values.append(.init(id: "quota", label: "Quota", sample: used, effectiveLimit: limit))
        }
        if session.capabilities.contains(.quotaUsage), let remaining = session.usage[.rateLimitRemaining] {
            values.append(.init(id: "remaining", label: "Rate remaining", sample: remaining, effectiveLimit: remaining.limit))
        }
        if session.capabilities.contains(.costUsage), let cost = session.usage[.cost] {
            values.append(.init(id: "cost", label: "Cost", sample: cost, effectiveLimit: cost.limit))
        }
        return values
    }
}

struct AgentGlobalUsagePresentation: Identifiable, Equatable, Sendable {
    let id: String
    let provider: AgentProvider
    let metric: AgentUsagePresentation

    static func make(sessions: [AgentSession], limit: Int) -> [Self] {
        var order: [String] = []
        var selected: [String: Self] = [:]
        for session in sessions.sorted(by: AgentSessionPresentation.isOrderedBefore) {
            for metric in AgentUsagePresentation.make(for: session) {
                let key = "\(session.id.sessionID.provider.deterministicSortKey):\(metric.id)"
                let candidate = Self(id: key, provider: session.id.sessionID.provider, metric: metric)
                if let existing = selected[key] {
                    if metric.sample.observedAt > existing.metric.sample.observedAt {
                        selected[key] = candidate
                    }
                } else {
                    order.append(key)
                    selected[key] = candidate
                }
            }
        }
        return Array(order.compactMap { selected[$0] }.prefix(max(limit, 0)))
    }
}

enum AgentIntegrationOperationalState: Equatable, Sendable {
    case notConfigured
    case awaitingFirstEvent
    case active
    case stale
    case degraded
    case failed
    case stopped
    case repairRequired
    case unavailable
    case blocked

    var label: String {
        switch self {
        case .notConfigured: "Not configured"
        case .awaitingFirstEvent: "Configured — awaiting first event"
        case .active: "Active"
        case .stale: "Stale"
        case .degraded: "Degraded"
        case .failed: "Failed"
        case .stopped: "Stopped"
        case .repairRequired: "Repair required"
        case .unavailable: "Helper unavailable"
        case .blocked: "Needs manual setup"
        }
    }
}

struct AgentIntegrationDiagnostics: Equatable, Sendable {
    let state: AgentIntegrationOperationalState
    let lastAcceptedEventAt: Date?
    let acceptedCount: UInt64
    let rejectedCount: UInt64
    let droppedCount: UInt64
    let schemaMismatchCount: UInt64
    let lastError: AgentSourceHealthError?

    static func make(
        provider: AgentIntegrationProvider,
        setup: AgentIntegrationSetupState,
        active: [AgentSourceHealthSnapshot],
        stopped: [AgentSourceHealthSnapshot]
    ) -> AgentIntegrationDiagnostics {
        let relevantActive = active.filter { belongs($0, to: provider) }
        let relevantStopped = stopped.filter { belongs($0, to: provider) }
        let relevant = relevantActive.isEmpty ? relevantStopped : relevantActive
        let accepted = relevant.reduce(UInt64.zero) { saturatedAdd($0, $1.acceptedCount) }
        let state: AgentIntegrationOperationalState = switch setup {
        case .needsSetup: .notConfigured
        case .repairRequired: .repairRequired
        case .helperUnavailable: .unavailable
        case .blocked: .blocked
        case .configured:
            if accepted == 0 {
                .awaitingFirstEvent
            } else {
                operationalState(for: relevant)
            }
        }
        return AgentIntegrationDiagnostics(
            state: state,
            lastAcceptedEventAt: relevant.compactMap(\.lastAcceptedEventAt).max(),
            acceptedCount: accepted,
            rejectedCount: relevant.reduce(UInt64.zero) { saturatedAdd($0, $1.rejectedCount) },
            droppedCount: relevant.reduce(UInt64.zero) { saturatedAdd($0, $1.dropCount) },
            schemaMismatchCount: relevant.reduce(UInt64.zero) { saturatedAdd($0, $1.schemaMismatchCount) },
            lastError: relevant.reversed().compactMap(\.lastError).first
        )
    }

    private static func operationalState(for health: [AgentSourceHealthSnapshot]) -> AgentIntegrationOperationalState {
        if health.contains(where: { $0.state == .failed }) { return .failed }
        if health.contains(where: { $0.state == .degraded }) { return .degraded }
        if health.contains(where: { $0.state == .stale }) { return .stale }
        if health.contains(where: { $0.state == .healthy }) { return .active }
        if health.contains(where: { $0.state == .stopped }) { return .stopped }
        return .awaitingFirstEvent
    }

    private static func belongs(_ health: AgentSourceHealthSnapshot, to provider: AgentIntegrationProvider) -> Bool {
        health.sourceInstanceID.rawValue.contains(".\(provider.rawValue)-")
    }

    private static func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }
}

@MainActor
final class AgentIntegrationDiagnosticsController: ObservableObject {
    @Published private(set) var activeHealth: [AgentSourceHealthSnapshot] = []
    @Published private(set) var stoppedHealth: [AgentSourceHealthSnapshot] = []
    @Published private(set) var isRefreshing = false

    private let coordinator: AgentIngestionCoordinator
    private var cancellables: Set<AnyCancellable> = []

    init(coordinator: AgentIngestionCoordinator, eventStore: AgentEventStore) {
        self.coordinator = coordinator
        eventStore.$sessions
            .dropFirst()
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            guard let self else { return }
            async let active = coordinator.sourceHealth()
            async let stopped = coordinator.stoppedSourceHealth()
            activeHealth = await active
            stoppedHealth = await stopped
            isRefreshing = false
        }
    }
}
