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
        let ordered = sessions.sorted(by: AgentSessionPresentation.isOrderedBefore)
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

enum AgentSessionPresentation {
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
