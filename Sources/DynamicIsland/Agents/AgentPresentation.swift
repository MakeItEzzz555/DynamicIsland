import Combine
import Foundation

enum AgentPresentationPriority: Int, Comparable, Sendable {
    case actionRequired
    case failure
    case working
    case thinking
    case idle
    case recent

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
            .filter {
                $0.isActive && AgentSessionPresentation.priority(for: $0) != .idle
            }
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
            if let active = AgentRecentActivityPresentation.active(for: session) {
                return "\(session.id.sessionID.provider.stableName.capitalized) · \(active.title)"
            }
            let state = session.isOpen && session.state == .completed
                ? "idle"
                : AgentSessionPresentation.shortStateLabel(session.state).lowercased()
            return "\(session.id.sessionID.provider.stableName.capitalized) \(state)"
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
        if session.isOpen && session.state == .completed {
            return .idle
        }
        switch session.state {
        case .waitingForApproval, .waitingForUser:
            return .actionRequired
        case .failed, .interrupted:
            return .failure
        case .working, .runningTool, .runningCommand:
            return .working
        case .thinking, .planning, .planReady:
            return .thinking
        case .completed:
            return .recent
        case .idle:
            return .idle
        }
    }

    static func isOrderedBefore(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsPriority = priority(for: lhs)
        let rhsPriority = priority(for: rhs)
        if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
        if lhs.isOpen != rhs.isOpen { return lhs.isOpen && !rhs.isOpen }
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

    static let activeSignalFreshnessInterval: TimeInterval = 60

    static func hasStaleActiveSignal(_ session: AgentSession, at date: Date) -> Bool {
        guard session.isActive else { return false }
        if session.capabilities.evidence(for: .sessionLifecycle)?.source == "codex-app-server-v2" {
            // Managed sessions receive authoritative turn completion/error
            // events; elapsed silence must not override that lifecycle.
            return false
        }
        switch session.state {
        case .thinking, .planning, .working, .runningTool, .runningCommand:
            return date.timeIntervalSince(session.lastUpdatedAt) > activeSignalFreshnessInterval
        case .waitingForApproval, .waitingForUser, .planReady,
             .idle, .completed, .failed, .interrupted:
            return false
        }
    }

    static func displayedStateLabel(for session: AgentSession, at date: Date) -> String {
        if session.availability == .resumable,
           (session.state == .idle || (session.isOpen && session.state == .completed)) {
            return "Resumable"
        }
        if session.isOpen && session.state == .completed {
            return "Idle"
        }
        return hasStaleActiveSignal(session, at: date)
            ? "Awaiting update"
            : stateLabel(session.state)
    }

    static func displayedStateSymbol(for session: AgentSession, at date: Date) -> String {
        if session.availability == .resumable,
           (session.state == .idle || (session.isOpen && session.state == .completed)) {
            return "arrow.clockwise.circle"
        }
        if session.isOpen && session.state == .completed {
            return stateSymbol(.idle)
        }
        return hasStaleActiveSignal(session, at: date)
            ? "clock.badge.questionmark"
            : stateSymbol(session.state)
    }

    static func displayedPrimaryTitle(for session: AgentSession, at date: Date) -> String {
        let title = primaryTitle(for: session)
        guard hasStaleActiveSignal(session, at: date) else { return title }
        let normalized = normalizedForComparison(title)
        let generic = Set([
            "working",
            "running tool",
            "running command",
            "thinking",
            "planning",
            "starting session",
            "session resumed"
        ])
        return generic.contains(normalized) ? "Awaiting provider update" : title
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
           activity.kind != .session,
           !activity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return activity.title
        }
        if let project = session.project.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !project.isEmpty {
            return project
        }
        if let activity = session.recentActivity.last,
           !activity.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return activity.title
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

    var primarySessions: [AgentSession] {
        sessions.filter { $0.isOpen || AgentSessionPresentation.requiresAttention($0) }
    }

    var recentSessions: [AgentSession] {
        sessions.filter { !$0.isOpen && !AgentSessionPresentation.requiresAttention($0) }
    }

    var showsRecentSection: Bool {
        !recentSessions.isEmpty
    }
}

struct AgentDashboardPresentation: Equatable, Sendable {
    let groups: [AgentProjectGroupPresentation]

    static func make(sessions: [AgentSession]) -> Self {
        make(orderedSessions: sessions.sorted(by: AgentSessionPresentation.isOrderedBefore))
    }

    static func make(orderedSessions: [AgentSession]) -> Self {
        var keys: [String] = []
        var titles: [String: String] = [:]
        var grouped: [String: [AgentSession]] = [:]

        for session in orderedSessions {
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

enum AgentWorkspaceSelection {
    static func resolve(
        current: AgentSessionInstanceID?,
        sessions: [AgentSession],
        activeManagedSessionIDs: Set<AgentSessionID> = []
    ) -> AgentSessionInstanceID? {
        if let current, sessions.contains(where: { $0.id == current }) {
            return current
        }
        return ordered(
            sessions: sessions,
            activeManagedSessionIDs: activeManagedSessionIDs
        ).first?.id
    }

    static func session(
        current: AgentSessionInstanceID?,
        sessions: [AgentSession],
        activeManagedSessionIDs: Set<AgentSessionID> = []
    ) -> AgentSession? {
        guard let selected = resolve(
            current: current,
            sessions: sessions,
            activeManagedSessionIDs: activeManagedSessionIDs
        ) else { return nil }
        return sessions.first { $0.id == selected }
    }

    static func ordered(
        sessions: [AgentSession],
        activeManagedSessionIDs: Set<AgentSessionID> = []
    ) -> [AgentSession] {
        sessions.sorted { lhs, rhs in
            isOrderedBefore(
                lhs,
                rhs,
                activeManagedSessionIDs: activeManagedSessionIDs
            )
        }
    }

    static func isActive(
        _ session: AgentSession,
        activeManagedSessionIDs: Set<AgentSessionID> = []
    ) -> Bool {
        if activeManagedSessionIDs.contains(session.id.sessionID) { return true }
        guard session.isOpen else { return false }
        switch session.state {
        case .thinking, .planning, .working, .runningTool, .runningCommand,
             .waitingForApproval, .waitingForUser, .planReady:
            return true
        case .idle, .completed, .failed, .interrupted:
            return false
        }
    }

    private static func isOrderedBefore(
        _ lhs: AgentSession,
        _ rhs: AgentSession,
        activeManagedSessionIDs: Set<AgentSessionID>
    ) -> Bool {
        let lhsRank = fallbackRank(lhs, activeManagedSessionIDs: activeManagedSessionIDs)
        let rhsRank = fallbackRank(rhs, activeManagedSessionIDs: activeManagedSessionIDs)
        if lhsRank != rhsRank { return lhsRank < rhsRank }
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt { return lhs.lastUpdatedAt > rhs.lastUpdatedAt }
        let lhsProvider = lhs.id.sessionID.provider.deterministicSortKey
        let rhsProvider = rhs.id.sessionID.provider.deterministicSortKey
        if lhsProvider != rhsProvider { return lhsProvider < rhsProvider }
        if lhs.id.sessionID.nativeID != rhs.id.sessionID.nativeID {
            return lhs.id.sessionID.nativeID < rhs.id.sessionID.nativeID
        }
        return lhs.id.generation > rhs.id.generation
    }

    private static func fallbackRank(
        _ session: AgentSession,
        activeManagedSessionIDs: Set<AgentSessionID>
    ) -> Int {
        switch AgentSessionPresentation.priority(for: session) {
        case .actionRequired, .failure:
            return 0
        case .working, .thinking:
            return activeManagedSessionIDs.contains(session.id.sessionID) ? 1 : 2
        case .idle where session.availability != .resumable:
            return activeManagedSessionIDs.contains(session.id.sessionID) ? 1 : 3
        case .idle:
            return activeManagedSessionIDs.contains(session.id.sessionID) ? 1 : 4
        case .recent:
            return activeManagedSessionIDs.contains(session.id.sessionID) ? 1 : 5
        }
    }
}

enum AgentSessionRowEmphasis: Equatable, Sendable {
    case standard
    case hovered
    case selected
    case attention
    case selectedAttention

    static func resolve(session: AgentSession, selected: Bool, hovering: Bool) -> Self {
        if AgentSessionPresentation.requiresAttention(session) {
            return selected ? .selectedAttention : .attention
        }
        if selected { return .selected }
        return hovering ? .hovered : .standard
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

struct AgentWorkspaceVerticalLayoutProjection: Equatable, Sendable {
    let sessionWorkspaceMinimumHeight: CGFloat
    let selectedDetailHeight: CGFloat
    let selectedDetailActivityLimit: Int

    static func make(availableHeight: CGFloat) -> Self {
        if availableHeight < 240 {
            return Self(
                sessionWorkspaceMinimumHeight: 96,
                selectedDetailHeight: 68,
                selectedDetailActivityLimit: 2
            )
        }
        if availableHeight < 300 {
            return Self(
                sessionWorkspaceMinimumHeight: 118,
                selectedDetailHeight: 80,
                selectedDetailActivityLimit: 3
            )
        }
        return Self(
            sessionWorkspaceMinimumHeight: 142,
            selectedDetailHeight: 94,
            selectedDetailActivityLimit: 4
        )
    }
}

#if DEBUG
/// Deterministic fixture for tests and screenshot export only. Production UI
/// has no activation path for synthetic sessions.
enum AgentDashboardPreviewFactory {
    static func sessions(now: Date = Date()) -> [AgentSession] {
        [
            approvalSession(now: now),
            workingSession(now: now),
            designSession(now: now)
        ]
    }

    private static func approvalSession(now: Date) -> AgentSession {
        let request = AgentCorrelationID(rawValue: "preview-approval")
        let read = AgentCorrelationID(rawValue: "preview-read")
        let edit = AgentCorrelationID(rawValue: "preview-edit")
        let command = AgentCorrelationID(rawValue: "preview-command")
        let subagent = AgentCorrelationID(rawValue: "preview-subagent")

        return AgentSession(
            id: instance(provider: .codex, nativeID: "preview-storefront-approval"),
            source: .terminal,
            state: .waitingForApproval,
            project: AgentProjectContext(
                displayName: "storefront",
                repositoryIdentity: "preview/storefront",
                gitBranch: "checkout",
                model: "gpt-5.6-sol"
            ),
            capabilities: capabilities([.quotaUsage, .contextUsage, .approvalObservation, .subagentLifecycle]),
            usage: usage(
                provider: "preview",
                fiveHour: 62,
                weekly: 41,
                context: 43,
                now: now
            ),
            tools: [
                read: AgentTool(
                    correlationID: read,
                    name: "read_file",
                    category: "read",
                    summary: "checkout.sql",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-34),
                    completedAt: now.addingTimeInterval(-31),
                    success: true
                ),
                edit: AgentTool(
                    correlationID: edit,
                    name: "apply_patch",
                    category: "edit",
                    summary: "checkout.sql",
                    status: .completed,
                    startedAt: now.addingTimeInterval(-24),
                    completedAt: now.addingTimeInterval(-18),
                    success: true
                )
            ],
            commands: [
                command: AgentCommand(
                    correlationID: command,
                    displaySummary: "npm run db:migrate",
                    status: .pending,
                    startedAt: now.addingTimeInterval(-4),
                    completedAt: nil,
                    exitCode: nil,
                    success: nil
                )
            ],
            approvals: [
                request: AgentApproval(
                    requestID: request,
                    summary: "$ npm run db:migrate",
                    operationCorrelationID: command,
                    requestedAt: now.addingTimeInterval(-3),
                    resolvedAt: nil,
                    expiresAt: now.addingTimeInterval(120),
                    state: .pending
                )
            ],
            subagents: [
                subagent: AgentSubagent(
                    nativeID: "preview-reviewer",
                    correlationID: subagent,
                    displayName: "Reviewer",
                    status: .active,
                    startedAt: now.addingTimeInterval(-42),
                    endedAt: nil
                )
            ],
            recentActivity: [
                AgentActivity(
                    id: AgentEventID(rawValue: "preview-plan"),
                    kind: .plan,
                    title: "Improve the checkout flow",
                    summary: "Apply the checkout schema migration",
                    status: .completed,
                    correlationID: nil,
                    timestamp: now.addingTimeInterval(-45)
                ),
                AgentActivity(
                    id: AgentEventID(rawValue: "preview-approval-event"),
                    kind: .approval,
                    title: "Improve the checkout flow",
                    summary: "Apply the checkout schema migration",
                    status: .pending,
                    correlationID: request,
                    timestamp: now.addingTimeInterval(-3)
                )
            ],
            startedAt: now.addingTimeInterval(-420),
            endedAt: nil,
            lastUpdatedAt: now.addingTimeInterval(-3)
        )
    }

    private static func workingSession(now: Date) -> AgentSession {
        let search = AgentCorrelationID(rawValue: "preview-search")
        return AgentSession(
            id: instance(provider: .codex, nativeID: "preview-storefront-search"),
            source: .terminal,
            state: .runningTool,
            project: AgentProjectContext(
                displayName: "storefront",
                repositoryIdentity: "preview/storefront",
                gitBranch: "catalog-search",
                model: "gpt-5.6-sol"
            ),
            capabilities: capabilities([.quotaUsage, .contextUsage, .toolLifecycle]),
            usage: usage(provider: "preview", fiveHour: 62, weekly: 41, context: 56, now: now),
            tools: [
                search: AgentTool(
                    correlationID: search,
                    name: "search",
                    category: "read",
                    summary: "catalog",
                    status: .active,
                    startedAt: now.addingTimeInterval(-7),
                    completedAt: nil,
                    success: nil
                )
            ],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [
                AgentActivity(
                    id: AgentEventID(rawValue: "preview-search-activity"),
                    kind: .tool,
                    title: "Add catalog search",
                    summary: "Search repository",
                    status: .active,
                    correlationID: search,
                    timestamp: now.addingTimeInterval(-7)
                )
            ],
            startedAt: now.addingTimeInterval(-180),
            endedAt: nil,
            lastUpdatedAt: now.addingTimeInterval(-7)
        )
    }

    private static func designSession(now: Date) -> AgentSession {
        let edit = AgentCorrelationID(rawValue: "preview-design-edit")
        return AgentSession(
            id: instance(provider: .claude, nativeID: "preview-design-system"),
            source: .terminal,
            state: .working,
            project: AgentProjectContext(
                displayName: "design-system",
                repositoryIdentity: "preview/design-system",
                gitBranch: "main",
                model: "claude-sonnet"
            ),
            capabilities: capabilities([.contextUsage, .toolLifecycle]),
            usage: AgentUsage(samples: [
                .contextUsed: AgentUsageSample(
                    value: 21,
                    limit: 100,
                    unit: .fraction,
                    scope: "session",
                    source: "preview",
                    observedAt: now
                )
            ]),
            tools: [
                edit: AgentTool(
                    correlationID: edit,
                    name: "edit",
                    category: "edit",
                    summary: "ComponentLibrary.swift",
                    status: .active,
                    startedAt: now.addingTimeInterval(-6),
                    completedAt: nil,
                    success: nil
                )
            ],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [
                AgentActivity(
                    id: AgentEventID(rawValue: "preview-design-activity"),
                    kind: .tool,
                    title: "Polish the component library",
                    summary: "Edit component library",
                    status: .active,
                    correlationID: edit,
                    timestamp: now.addingTimeInterval(-6)
                )
            ],
            startedAt: now.addingTimeInterval(-240),
            endedAt: nil,
            lastUpdatedAt: now.addingTimeInterval(-6)
        )
    }

    private static func instance(provider: AgentProvider, nativeID: String) -> AgentSessionInstanceID {
        AgentSessionInstanceID(
            sessionID: AgentSessionID(provider: provider, nativeID: nativeID),
            generation: AgentSessionGeneration(rawValue: 1)
        )
    }

    private static func capabilities(_ values: Set<AgentCapability>) -> AgentCapabilities {
        let observedAt = Date(timeIntervalSince1970: 1)
        return AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: values.map {
            ($0, AgentCapabilityEvidence(authority: .lifecycle, source: "preview", observedAt: observedAt))
        }))
    }

    private static func usage(
        provider: String,
        fiveHour: Double,
        weekly: Double,
        context: Double,
        now: Date
    ) -> AgentUsage {
        AgentUsage(scopedSamples: [
            AgentUsageKey(metric: .quotaUsed, scope: "5h"): AgentUsageSample(
                value: fiveHour,
                limit: 100,
                unit: .fraction,
                scope: "5h",
                source: provider,
                observedAt: now
            ),
            AgentUsageKey(metric: .quotaUsed, scope: "weekly"): AgentUsageSample(
                value: weekly,
                limit: 100,
                unit: .fraction,
                scope: "weekly",
                source: provider,
                observedAt: now
            ),
            AgentUsageKey(metric: .contextUsed, scope: "session"): AgentUsageSample(
                value: context,
                limit: 100,
                unit: .fraction,
                scope: "session",
                source: provider,
                observedAt: now
            )
        ])
    }
}
#endif

struct AgentOperationSummary: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let detail: String?
    let status: AgentOperationStatus
    let count: Int
    let date: Date
    let isCommand: Bool

    var displayTitle: String {
        count > 1 ? "\(title) ×\(count)" : title
    }
}


enum AgentRecentActivityDisplayMode: String, Equatable, Sendable {
    case recentList
    case activeDetail
}

struct AgentRecentActivityItem: Identifiable, Equatable, Sendable {
    let id: String
    let symbol: String
    let title: String
    let detail: String?
    let status: AgentOperationStatus
    let timestamp: Date
    let isCommand: Bool
}

enum AgentRecentActivityPresentation {
    static let maximumItems = 5

    static func make(
        for session: AgentSession,
        limit: Int = maximumItems
    ) -> [AgentRecentActivityItem] {
        let bounded = min(max(limit, 0), maximumItems)
        let operations = AgentOperationAggregation.make(
            for: session,
            limit: maximumItems,
            includePendingApprovals: true
        )

        struct Group {
            var operation: AgentOperationSummary
            var count: Int
        }

        var groups: [String: Group] = [:]
        var order: [String] = []
        for operation in operations {
            let canGroup = (operation.status == .active || operation.status == .pending) &&
                !operation.id.hasPrefix("approval:")
            let key = canGroup
                ? "\(operation.title)|\(operation.detail ?? "")|\(operation.status.rawValue)"
                : operation.id
            if var existing = groups[key] {
                existing.count += operation.count
                if operation.date > existing.operation.date {
                    existing.operation = operation
                }
                groups[key] = existing
            } else {
                groups[key] = Group(operation: operation, count: operation.count)
                order.append(key)
            }
        }

        let items = order.compactMap { key -> AgentRecentActivityItem? in
            guard let group = groups[key] else { return nil }
            let operation = group.operation
            return AgentRecentActivityItem(
                id: operation.id,
                symbol: operation.symbol,
                title: group.count > 1 ? "\(operation.title) ×\(group.count)" : operation.displayTitle,
                detail: operation.detail,
                status: operation.status,
                timestamp: operation.date,
                isCommand: operation.isCommand
            )
        }
        return Array(items.suffix(bounded))
    }

    static func active(
        for session: AgentSession
    ) -> AgentRecentActivityItem? {
        make(for: session, limit: maximumItems)
            .last(where: { $0.status == .active || $0.status == .pending })
    }
}

struct AgentContextPresentation: Equatable, Sendable {
    let used: Double
    let limit: Double?
    let progress: Double?
    let valueText: String
    let isStale: Bool

    static func make(for session: AgentSession, now: Date = Date()) -> Self? {
        guard session.capabilities.contains(.contextUsage),
              let sample = session.usage[.contextUsed],
              sample.isValid else { return nil }
        let limit = sample.limit ?? session.usage[.contextLimit]?.value
        let progress: Double?
        if let limit, limit.isFinite, limit > 0 {
            progress = min(max(sample.value / limit, 0), 1)
        } else {
            progress = nil
        }
        let usedText = compactCount(sample.value)
        let valueText = limit.map { usedText + " / " + compactCount($0) } ?? {
            if sample.unit == .fraction, sample.value <= 1 {
                return "\(Int((sample.value * 100).rounded()))%"
            }
            return usedText
        }()
        return Self(
            used: sample.value,
            limit: limit,
            progress: progress,
            valueText: valueText,
            isStale: now.timeIntervalSince(sample.observedAt) > 300
        )
    }

    private static func compactCount(_ value: Double) -> String {
        if value >= 1_000_000 {
            return value.formatted(.number.precision(.fractionLength(0...1)).scale(0.000001)) + "m"
        }
        if value >= 1_000 {
            return value.formatted(.number.precision(.fractionLength(0...1)).scale(0.001)) + "k"
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

enum AgentWorkspaceOwnership: String, Equatable, Sendable {
    case managed
    case observed
    case resumable
    case unavailable
}

struct AgentWorkspaceMetadataPresentation: Equatable, Sendable {
    let project: String
    let branch: String?
    let model: String?
    let threadSuffix: String
    let ownership: AgentWorkspaceOwnership
    let context: AgentContextPresentation?

    static func make(
        session: AgentSession,
        isManaged: Bool,
        canConnect: Bool
    ) -> Self {
        let project = AgentPrivacyProjection.displayProject(session.project)
        let ownership: AgentWorkspaceOwnership
        if isManaged {
            ownership = .managed
        } else if session.availability == .resumable {
            ownership = canConnect ? .resumable : .unavailable
        } else {
            ownership = .observed
        }
        return Self(
            project: project.displayName ?? session.id.sessionID.provider.stableName.capitalized,
            branch: project.gitBranch,
            model: project.model,
            threadSuffix: "…" + session.id.sessionID.nativeID.suffix(4),
            ownership: ownership,
            context: AgentContextPresentation.make(for: session)
        )
    }
}

enum AgentTurnTimingPresentation {
    static func elapsedText(startedAt: Date?, now: Date = Date()) -> String? {
        guard let startedAt, now >= startedAt else { return nil }
        let total = Int(now.timeIntervalSince(startedAt).rounded(.down))
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    static func relativeUpdateText(lastUpdatedAt: Date, now: Date = Date()) -> String {
        let seconds = max(Int(now.timeIntervalSince(lastUpdatedAt)), 0)
        if seconds < 60 { return seconds < 5 ? "Updated now" : "Updated \(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "Updated \(minutes)m ago" }
        let hours = minutes / 60
        return "Updated \(hours)h ago"
    }
}

enum AgentConsoleEntryKind: String, Hashable, Sendable {
    case user
    case agent
    case tool
    case command
    case plan
    case approval
    case status
    case error
}

/// A bounded, display-only projection of provider-authorized transcript and
/// normalized operation evidence. It deliberately carries no raw provider
/// payload, stderr, environment, or private reasoning.
struct AgentConsoleEntry: Identifiable, Equatable, Sendable {
    static let maximumEntries = 80

    let id: String
    let timestamp: Date
    let kind: AgentConsoleEntryKind
    let title: String
    let text: String?
    let status: AgentOperationStatus?
    let correlationID: String?

    static func make(
        transcript: [AgentManagedTranscriptEntry],
        operations: [AgentOperationSummary],
        provider: AgentProvider = .codex,
        limit: Int = maximumEntries
    ) -> [Self] {
        let messages = transcript.map { message in
            let presentation = transcriptPresentation(for: message.role, provider: provider)
            return Self(
                id: "message:\(message.id)",
                timestamp: message.timestamp,
                kind: presentation.kind,
                title: presentation.title,
                text: message.text,
                status: nil,
                correlationID: message.turnID
            )
        }
        let activities = operations.map { operation in
            Self(
                id: "operation:\(operation.id)",
                timestamp: operation.date,
                kind: kind(for: operation),
                title: operation.displayTitle,
                text: operation.detail,
                status: operation.status,
                correlationID: operation.id
            )
        }
        let boundedLimit = min(max(limit, 0), maximumEntries)
        return Array((messages + activities).sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.id < $1.id
        }.suffix(boundedLimit))
    }

    private static func kind(for operation: AgentOperationSummary) -> AgentConsoleEntryKind {
        if operation.isCommand { return .command }
        let title = operation.title.lowercased()
        if title.contains("approval") || title == "approved" || title == "denied" {
            return .approval
        }
        if title.contains("plan") { return .plan }
        if operation.status == .failed || title.contains("failed") { return .error }
        if title == "completed" || title == "interrupted" || title.contains("waiting") {
            return .status
        }
        return .tool
    }

    private static func transcriptPresentation(
        for role: AgentManagedTranscriptRole,
        provider: AgentProvider
    ) -> (kind: AgentConsoleEntryKind, title: String) {
        switch role {
        case .user: (.user, "You")
        case .agent: (.agent, provider.stableName.capitalized)
        case .tool: (.tool, "Tool")
        case .command: (.command, "Command")
        case .plan: (.plan, "Plan")
        case .status: (.status, "Status")
        case .error: (.error, "Error")
        }
    }
}

enum AgentOperationAggregation {
    static func make(
        for session: AgentSession,
        limit: Int = 6,
        includePendingApprovals: Bool = true
    ) -> [AgentOperationSummary] {
        var operations: [AgentOperationSummary] = []
        operations += session.approvals.values
            .filter { includePendingApprovals || $0.state != .pending }
            .map { approval in
                let presentation: (title: String, status: AgentOperationStatus) = switch approval.state {
                case .pending: ("Approval requested", .pending)
                case .approved: ("Approved", .resolved)
                case .denied: ("Denied", .resolved)
                case .cancelled: ("Approval failed", .failed)
                case .expired: ("Approval expired", .cancelled)
                case .unknown: ("Approval status unknown", .unknown)
                }
                return AgentOperationSummary(
                    id: "approval:\(approval.requestID.rawValue)",
                    symbol: "checkmark.shield",
                    title: presentation.title,
                    detail: approval.summary,
                    status: presentation.status,
                    count: 1,
                    date: approval.resolvedAt ?? approval.requestedAt,
                    isCommand: approval.summary.trimmingCharacters(in: .whitespaces).hasPrefix("$")
                )
            }
        operations += session.tools.values.map {
            AgentOperationSummary(
                id: "tool:\($0.correlationID.rawValue)",
                symbol: classification(name: $0.name, category: $0.category, summary: $0.summary).symbol,
                title: classification(name: $0.name, category: $0.category, summary: $0.summary).title,
                detail: safeDetail($0.summary),
                status: $0.status,
                count: 1,
                date: $0.completedAt ?? $0.startedAt,
                isCommand: classification(name: $0.name, category: $0.category, summary: $0.summary).isCommand
            )
        }
        operations += session.commands.values.map {
            AgentOperationSummary(
                id: "command:\($0.correlationID.rawValue)",
                symbol: "terminal",
                title: commandTitle($0.displaySummary),
                detail: safeDetail($0.displaySummary).map { "$ " + $0 } ??
                    $0.exitCode.map { "Exit \($0)" },
                status: $0.status,
                count: 1,
                date: $0.completedAt ?? $0.startedAt,
                isCommand: true
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
                date: $0.endedAt ?? $0.startedAt,
                isCommand: false
            )
        }

        operations += session.recentActivity.compactMap { activity in
            let title: String
            let symbol: String
            switch activity.kind {
            case .session: title = "Starting session"; symbol = "play.circle"
            case .thinking: title = "Thinking"; symbol = "brain.head.profile"
            case .plan: title = activity.status == .completed ? "Plan ready" : "Planning"; symbol = "list.bullet.clipboard"
            case .userInput: title = "Waiting for input"; symbol = "person.crop.circle.badge.questionmark"
            case .completion: title = "Completed"; symbol = "checkmark.circle.fill"
            case .failure: title = "Failed"; symbol = "exclamationmark.triangle.fill"
            case .interruption: title = "Interrupted"; symbol = "stop.circle.fill"
            case .tool, .command, .approval, .subagent: return nil
            }
            return AgentOperationSummary(
                id: "activity:\(activity.id.rawValue)", symbol: symbol, title: title,
                detail: nil, status: activity.status, count: 1, date: activity.timestamp,
                isCommand: false
            )
        }

        var aggregated: [String: AgentOperationSummary] = [:]
        for operation in operations.sorted(by: operationOrder) {
            let isCurrent = operation.status == .pending || operation.status == .active
            let isApproval = operation.id.hasPrefix("approval:")
            let key = (isCurrent || isApproval)
                ? operation.id
                : "\(operation.title.lowercased())|\(operation.status.rawValue)"
            if let existing = aggregated[key] {
                aggregated[key] = AgentOperationSummary(
                    id: existing.id,
                    symbol: existing.symbol,
                    title: existing.title,
                    detail: existing.detail ?? operation.detail,
                    status: existing.status,
                    count: existing.count + 1,
                    date: max(existing.date, operation.date),
                    isCommand: existing.isCommand
                )
            } else {
                aggregated[key] = operation
            }
        }
        let selected = aggregated.values.sorted(by: operationOrder).prefix(max(limit, 0))
        return selected.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
    }

    private static func operationOrder(_ lhs: AgentOperationSummary, _ rhs: AgentOperationSummary) -> Bool {
        let lhsActive = lhs.status == .pending || lhs.status == .active
        let rhsActive = rhs.status == .pending || rhs.status == .active
        if lhsActive != rhsActive { return lhsActive && !rhsActive }
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        return lhs.id < rhs.id
    }

    private static func classification(name: String, category: String?, summary: String?) -> (title: String, symbol: String, isCommand: Bool) {
        let value = [name, category, summary].compactMap { $0 }.joined(separator: " ").lowercased()
        if value.contains("apply_patch") || value.contains("edit") || value.contains("write") {
            return ("Edit file", "pencil.line", false)
        }
        if value.contains("search") || value.contains("grep") || value.contains("find") || value.contains("ripgrep") {
            return ("Search repository", "magnifyingglass", false)
        }
        if value.contains("read") || value.contains("filesystem") {
            return ("Read file", "doc.text", false)
        }
        if value.contains("browser") || value.contains("web") {
            return ("Search web", "globe", false)
        }
        if value.contains("test") { return ("Run tests", "checkmark.circle", true) }
        if value.contains("build") { return ("Build project", "hammer", true) }
        if value.contains("bash") || value.contains("shell") || value.contains("terminal") || value.contains("command") {
            return ("Run command", "terminal", true)
        }
        return ("Use tool", "wrench.and.screwdriver", false)
    }

    private static func commandTitle(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.contains("test") { return "Run tests" }
        if lower.contains("build") { return "Build project" }
        if lower.contains("git status") { return "Git status" }
        if lower.contains("git commit") { return "Commit changes" }
        if lower.contains("git push") { return "Push branch" }
        return "Run command"
    }

    private static func safeDetail(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 160, !value.contains("\n") else { return nil }
        let lower = value.lowercased()
        let sensitive = ["token", "secret", "password", "authorization", "bearer", "api_key", "api-key", "cookie"]
        guard !sensitive.contains(where: lower.contains) else { return nil }
        if value.contains("/") {
            let name = URL(fileURLWithPath: value).lastPathComponent
            return name.isEmpty ? nil : name
        }
        return value
    }
}

enum AgentApprovalPresentation {
    static func isActionable(session: AgentSession, pending: AgentApprovalControlRequest?) -> Bool {
        session.state == .waitingForApproval &&
            session.capabilities.contains(.approvalControl) &&
            pending?.key.session == session.id
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

    var isQuotaUsage: Bool {
        id.hasPrefix("quota:")
    }

    var gaugeProgress: Double? {
        guard let progress else { return nil }
        return isQuotaUsage ? min(max(1 - progress, 0), 1) : progress
    }

    var gaugeValueText: String {
        guard let gaugeProgress else {
            return sample.value.formatted(.number.precision(.fractionLength(0...1)))
        }
        let percent = Int((gaugeProgress * 100).rounded())
        return isQuotaUsage ? "\(percent)% left" : "\(percent)%"
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
        if session.capabilities.contains(.quotaUsage) {
            for used in session.usage.samples(for: .quotaUsed) {
                let limit = used.limit ?? session.usage.samples(for: .quotaLimit)
                    .first(where: { $0.scope == used.scope })?.value
                let scope = quotaScopeLabel(used.scope)
                values.append(.init(
                    id: "quota:\(used.scope.lowercased())",
                    label: scope.map { "Quota · \($0)" } ?? "Quota",
                    sample: used,
                    effectiveLimit: limit
                ))
            }
        }
        if session.capabilities.contains(.quotaUsage), let remaining = session.usage[.rateLimitRemaining] {
            values.append(.init(id: "remaining", label: "Rate remaining", sample: remaining, effectiveLimit: remaining.limit))
        }
        if session.capabilities.contains(.costUsage), let cost = session.usage[.cost] {
            values.append(.init(id: "cost", label: "Cost", sample: cost, effectiveLimit: cost.limit))
        }
        return values
    }

    static func make(providerUsage usage: AgentUsage) -> [AgentUsagePresentation] {
        var values: [AgentUsagePresentation] = []

        if let used = usage[.contextUsed] {
            let limit = used.limit ?? usage[.contextLimit]?.value
            values.append(.init(id: "context", label: "Context", sample: used, effectiveLimit: limit))
        }

        for used in usage.samples(for: .quotaUsed) {
            let limit = used.limit ?? usage.samples(for: .quotaLimit)
                .first(where: { $0.scope == used.scope })?.value
            let scope = quotaScopeLabel(used.scope)
            values.append(.init(
                id: "quota:\(used.scope.lowercased())",
                label: scope.map { "Quota · \($0)" } ?? "Quota",
                sample: used,
                effectiveLimit: limit
            ))
        }

        if let remaining = usage[.rateLimitRemaining] {
            values.append(.init(
                id: "remaining",
                label: "Rate remaining",
                sample: remaining,
                effectiveLimit: remaining.limit
            ))
        }

        return values
    }

    private static func quotaScopeLabel(_ raw: String) -> String? {
        let value = raw.lowercased().replacingOccurrences(of: "_", with: "-")
        if value.contains("5h") || value.contains("five-hour") || value.contains("5-hour") { return "5h" }
        if value.contains("week") || value == "7d" { return "Week" }
        return nil
    }
}

struct AgentGlobalUsagePresentation: Identifiable, Equatable, Sendable {
    let id: String
    let provider: AgentProvider
    let metric: AgentUsagePresentation

    static func makeForSelectedSession(
        provider: AgentProvider,
        accountUsage: AgentUsage,
        selectedSession: AgentSession?,
        limit: Int
    ) -> [Self] {
        var values: [Self] = []

        for metric in AgentUsagePresentation.make(providerUsage: accountUsage)
            where metric.id != "context" {
            values.append(Self(
                id: "\(provider.deterministicSortKey):\(metric.id)",
                provider: provider,
                metric: metric
            ))
        }

        if let selectedSession,
           selectedSession.id.sessionID.provider == provider,
           let context = AgentUsagePresentation.make(for: selectedSession)
                .first(where: { $0.id == "context" }) {
            values.append(Self(
                id: "\(provider.deterministicSortKey):context",
                provider: provider,
                metric: context
            ))
        }

        return Array(values.sorted {
            let lhsRank = canonicalRank($0.metric)
            let rhsRank = canonicalRank($1.metric)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            return $0.id < $1.id
        }.prefix(max(limit, 0)))
    }

    static func make(
        sessions: [AgentSession],
        providerUsage: [AgentProvider: AgentUsage] = [:],
        limit: Int
    ) -> [Self] {
        var selected: [String: Self] = [:]

        func consider(provider: AgentProvider, metric: AgentUsagePresentation) {
            let key = "\(provider.deterministicSortKey):\(metric.id)"
            let candidate = Self(id: key, provider: provider, metric: metric)
            if let existing = selected[key],
               existing.metric.sample.observedAt > metric.sample.observedAt {
                return
            }
            selected[key] = candidate
        }

        for (provider, usage) in providerUsage {
            for metric in AgentUsagePresentation.make(providerUsage: usage) {
                consider(provider: provider, metric: metric)
            }
        }

        for session in sessions.sorted(by: AgentSessionPresentation.isOrderedBefore) {
            for metric in AgentUsagePresentation.make(for: session) {
                consider(provider: session.id.sessionID.provider, metric: metric)
            }
        }

        let ordered = selected.values.sorted { lhs, rhs in
            let lhsRank = canonicalRank(lhs.metric)
            let rhsRank = canonicalRank(rhs.metric)
            if lhsRank != rhsRank { return lhsRank < rhsRank }
            if lhs.provider.deterministicSortKey != rhs.provider.deterministicSortKey {
                return lhs.provider.deterministicSortKey < rhs.provider.deterministicSortKey
            }
            return lhs.id < rhs.id
        }
        return Array(ordered.prefix(max(limit, 0)))
    }

    private static func canonicalRank(_ metric: AgentUsagePresentation) -> Int {
        let label = metric.label.lowercased()
        if label.contains("5h") { return 0 }
        if label.contains("week") { return 1 }
        if label == "context" { return 2 }
        return 10
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
