import Combine
import Foundation

struct AgentWorkspaceFeedItemID: Hashable, Sendable {
    let session: AgentSessionInstanceID
    let eventID: AgentEventID
}

enum AgentWorkspaceFeedKind: String, Equatable, Sendable {
    case session, processing, command, tool, approval, userInput, plan, subagent
    case completion, failure, interruption
}

/// A read-only presentation of existing request truth. Delivery is queried from
/// AgentApprovalController; only normalized provider acknowledgement resolves it.
enum AgentWorkspaceFeedApprovalPresentation: Equatable, Sendable {
    case pending, submitting, approved, denied, withdrawn, failed

    var label: String {
        switch self {
        case .pending: "Approval required"
        case .submitting: "Waiting for provider acknowledgement"
        case .approved: "Approved"
        case .denied: "Denied"
        case .withdrawn: "Request withdrawn"
        case .failed: "Decision not confirmed"
        }
    }
}

struct AgentWorkspaceFeedItem: Identifiable, Equatable, Sendable {
    let id: AgentWorkspaceFeedItemID
    let kind: AgentWorkspaceFeedKind
    let correlationID: AgentCorrelationID?
    let timestamp: Date
    var updatedAt: Date
    var title: String
    var status: AgentOperationStatus
    var processingKind: AgentProcessingKind?
    var approvalState: AgentApprovalState?
    /// Only an allowlisted executable/tool label, never provider arguments.
    var operationLabel: String? = nil
    var exitCode: Int? = nil

    var sessionID: AgentSessionInstanceID { id.session }
    var provider: AgentProvider { sessionID.sessionID.provider }
    var approvalKey: AgentApprovalControlKey? {
        guard kind == .approval, let correlationID else { return nil }
        return AgentApprovalControlKey(session: sessionID, requestID: correlationID)
    }

    func approvalPresentation(delivery: AgentApprovalDeliveryState?) -> AgentWorkspaceFeedApprovalPresentation? {
        guard kind == .approval else { return nil }
        // Provider truth wins, including a late exact acknowledgement.
        switch approvalState {
        case .approved: return .approved
        case .denied: return .denied
        case .cancelled, .expired: return .withdrawn
        case .unknown: return .failed
        case .pending, nil:
            switch delivery {
            case .submitting: return .submitting
            case .failed: return .failed
            case .awaitingDecision, nil: return .pending
            }
        }
    }

    /// Historical rows never independently decide whether an agent is working.
    /// Exact live operation ownership comes from the canonical session snapshot.
    func isCurrentActivity(in session: AgentSession?) -> Bool {
        guard let session, session.id == sessionID, !session.state.isTerminal,
              session.state != .idle,
              session.state != .waitingForApproval, session.state != .waitingForUser,
              session.state != .planReady else { return false }
        switch kind {
        case .command: return correlationID.flatMap { session.commands[$0]?.status } == .active
        case .tool: return correlationID.flatMap { session.tools[$0]?.status } == .active
        case .subagent: return correlationID.flatMap { session.subagents[$0]?.status } == .active
        case .processing:
            guard status == .active else { return false }
            if let correlationID {
                return session.processingActivities[correlationID] != nil && session.currentProcessingKind == processingKind
            }
            // Legacy normalized reasoning/planning events (notably recovered
            // Claude thinking blocks) have concrete event semantics but no item
            // correlation. Canonical precedence still controls animation.
            return (processingKind == .reasoning && session.state == .thinking) ||
                (processingKind == .planning && session.state == .planning)
        default: return false
        }
    }
}

/// Bounded, in-memory operational presentation, separate from transcript and
/// Record Activities. It retains IDs and fixed semantic labels only, never
/// provider prose, prompt text, command arguments, paths or tool payloads.
enum AgentWorkspaceFeedProjection {
    /// Selection is a complete session instance, not a project/provider filter.
    /// No selection means no owned operational feed, including approvals.
    static func items(
        _ history: [AgentWorkspaceFeedItem],
        selectedSessionID: AgentSessionInstanceID?,
        session: AgentSession? = nil
    ) -> [AgentWorkspaceFeedItem] {
        guard let selectedSessionID else { return [] }
        var selected = history.filter { $0.sessionID == selectedSessionID }
        if let session, session.id == selectedSessionID {
            for index in selected.indices {
                guard let requestID = selected[index].approvalKey?.requestID,
                      let request = session.approvals[requestID],
                      selected[index].approvalState != request.state else { continue }
                selected[index].approvalState = request.state
                selected[index].status = request.state == .pending ? .pending : request.state == .unknown ? .failed : .resolved
                selected[index].updatedAt = request.resolvedAt ?? request.requestedAt
            }
            // A global history cap must not hide the selected owner's current
            // canonical request. This temporary projection remains bounded by
            // the domain's per-session operation limits; no new store is kept.
            for request in session.approvals.values where request.state == .pending || request.state == .unknown {
                guard !selected.contains(where: { $0.approvalKey?.requestID == request.requestID }) else { continue }
                selected.append(AgentWorkspaceFeedItem(
                    id: .init(session: session.id, eventID: .init(rawValue: "restored-approval:\(request.requestID.rawValue)")),
                    kind: .approval, correlationID: request.requestID,
                    timestamp: request.requestedAt, updatedAt: request.resolvedAt ?? request.requestedAt,
                    title: "Approval request", status: request.state == .pending ? .pending : .failed,
                    processingKind: nil, approvalState: request.state
                ))
            }
        }
        return selected.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.eventID.rawValue < $1.id.eventID.rawValue
        }
    }
}

/// Feed density per semantic widget size. Presentation only: the store keeps
/// its full bounded history at every size.
enum AgentWorkspaceFeedDensity {
    static let standardLimit = 12

    /// Compact shows one row, preferring a pending approval over the latest
    /// event so an actionable request is never hidden. `hidden` counts what
    /// the size leaves out.
    static func visible(_ items: [AgentWorkspaceFeedItem], size: WidgetPresentationSize?) -> (items: [AgentWorkspaceFeedItem], hidden: Int) {
        switch size {
        case .compact?:
            guard let first = items.first(where: { $0.status == .pending }) ?? items.first else { return ([], 0) }
            return ([first], items.count - 1)
        case .standard?:
            return (Array(items.prefix(standardLimit)), max(0, items.count - standardLimit))
        case .large?, nil:
            return (items, 0)
        }
    }
}

@MainActor
final class AgentWorkspaceFeedStore: ObservableObject {
    @Published private(set) var items: [AgentWorkspaceFeedItem] = []
    let maximumItems: Int
    private var observedOrder: [AgentWorkspaceFeedItemID] = []
    private var observed: Set<AgentWorkspaceFeedItemID> = []

    init(maximumItems: Int = 256) {
        self.maximumItems = min(1_024, max(16, maximumItems))
    }

    func items(for selectedSessionID: AgentSessionInstanceID?, session: AgentSession? = nil) -> [AgentWorkspaceFeedItem] {
        AgentWorkspaceFeedProjection.items(items, selectedSessionID: selectedSessionID, session: session)
    }

    /// Existing canonical requests may predate a newly mounted workspace. This
    /// recovers their presentation without inventing provider events or decisions.
    /// Call from the Feed surface when its canonical session snapshot changes.
    func reconcileApprovals(sessions: [AgentSession]) {
        var next = items
        for session in sessions {
            for request in session.approvals.values {
                if let index = next.firstIndex(where: {
                    $0.approvalKey == AgentApprovalControlKey(session: session.id, requestID: request.requestID)
                }) {
                    guard next[index].approvalState != request.state else { continue }
                    next[index].approvalState = request.state
                    next[index].status = Self.approvalStatus(request.state)
                    next[index].updatedAt = request.resolvedAt ?? request.requestedAt
                } else if request.state == .pending || request.state == .unknown {
                    // Do not rebuild a page of resolved approvals on each mount.
                    next.append(AgentWorkspaceFeedItem(
                        id: .init(session: session.id, eventID: .init(rawValue: "restored-approval:\(request.requestID.rawValue)")),
                        kind: .approval, correlationID: request.requestID,
                        timestamp: request.requestedAt, updatedAt: request.resolvedAt ?? request.requestedAt,
                        title: "Approval request", status: Self.approvalStatus(request.state),
                        processingKind: nil, approvalState: request.state
                    ))
                }
            }
        }
        publish(next)
    }

    /// Call beside the existing recorder in AgentEventStore.appliedEventObserver.
    /// Rejected, stale, weaker and duplicate provider events never reach here.
    func handleApplied(_ event: AgentEvent, session: AgentSession) {
        guard event.instanceID == session.id else { return }
        let eventIdentity = AgentWorkspaceFeedItemID(session: event.instanceID, eventID: event.eventID)
        guard observed.insert(eventIdentity).inserted else { return }
        observedOrder.append(eventIdentity)
        if observedOrder.count > maximumItems * 4 {
            observed.remove(observedOrder.removeFirst())
        }
        guard var item = Self.project(event, session: session) else { return }
        var next = items
        // Pair one exact operation/request across starts, delivery and endings.
        let operationIndex: Int? = if let correlation = item.correlationID {
            next.lastIndex {
                $0.sessionID == item.sessionID && $0.kind == item.kind && $0.correlationID == correlation
            }
        } else if event.type == .thinkingEnded {
            // Resolve the current uncorrelated reasoning episode, rather than
            // leaving an active historical row beside a disconnected ending.
            next.firstIndex {
                $0.sessionID == item.sessionID && $0.kind == .processing &&
                    $0.correlationID == nil && $0.processingKind == .reasoning && $0.status == .active
            }
        } else { nil }
        if let index = operationIndex {
            let prior = next[index]
            item = AgentWorkspaceFeedItem(
                id: prior.id, kind: item.kind, correlationID: item.correlationID,
                timestamp: prior.timestamp, updatedAt: item.updatedAt,
                title: item.title, status: item.status,
                processingKind: item.processingKind ?? prior.processingKind,
                approvalState: item.approvalState,
                operationLabel: item.operationLabel ?? prior.operationLabel,
                exitCode: item.exitCode
            )
            if item.kind == .command || item.kind == .tool {
                item.title = Self.operationTitle(item)
            }
            // Repeated live-state publications are not new history traffic.
            if prior.kind == .processing, prior.status == item.status,
               prior.processingKind == item.processingKind, prior.title == item.title,
               next.firstIndex(where: { $0.sessionID == item.sessionID }) == index {
                return
            }
            next[index] = item
        } else if item.kind == .processing,
                  let index = next.firstIndex(where: { $0.sessionID == item.sessionID }),
                  next[index].kind == .processing,
                  next[index].processingKind == item.processingKind,
                  next[index].status == item.status {
            // Preserve one row for a consecutive semantic state even when the
            // provider emits several concrete reasoning items. Keep the newest
            // correlation so live avatar ownership still uses canonical truth.
            let prior = next[index]
            item = AgentWorkspaceFeedItem(
                id: prior.id, kind: item.kind, correlationID: item.correlationID,
                timestamp: prior.timestamp, updatedAt: prior.updatedAt,
                title: item.title, status: item.status,
                processingKind: item.processingKind, approvalState: nil
            )
            next[index] = item
        } else {
            next.append(item)
        }
        for index in next.indices where next[index].sessionID == session.id {
            if let requestID = next[index].approvalKey?.requestID,
               let request = session.approvals[requestID],
               next[index].approvalState != request.state {
                // Terminal reducer cleanup can withdraw a request without a
                // separate approvalResolved event. Copy that canonical truth.
                next[index].approvalState = request.state
                next[index].status = Self.approvalStatus(request.state)
                next[index].updatedAt = request.resolvedAt ?? next[index].updatedAt
            }
            if session.state.isTerminal, next[index].status == .active {
                next[index].status = switch session.state {
                case .completed: .completed
                case .failed: .failed
                default: .cancelled
                }
                next[index].updatedAt = event.effectiveTimestamp
                if next[index].kind == .tool || next[index].kind == .command {
                    let operation = next[index].kind == .tool ? "Tool" : "Command"
                    next[index].title = switch session.state {
                    case .completed: "\(operation) completed"
                    case .failed: "\(operation) failed"
                    default: "\(operation) interrupted"
                    }
                }
            }
        }
        publish(next)
    }

    private func publish(_ proposed: [AgentWorkspaceFeedItem]) {
        var next = proposed
        next.sort {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            if $0.provider.deterministicSortKey != $1.provider.deterministicSortKey {
                return $0.provider.deterministicSortKey < $1.provider.deterministicSortKey
            }
            if $0.sessionID.sessionID.nativeID != $1.sessionID.sessionID.nativeID {
                return $0.sessionID.sessionID.nativeID < $1.sessionID.sessionID.nativeID
            }
            if $0.sessionID.generation != $1.sessionID.generation {
                return $0.sessionID.generation > $1.sessionID.generation
            }
            return $0.id.eventID.rawValue < $1.id.eventID.rawValue
        }
        if next.count > maximumItems {
            // Unresolved requests remain actionable while older resolved history
            // yields its slots. Storage remains bounded even under event floods.
            let pinned = next.filter { $0.kind == .approval && ($0.approvalState == .pending || $0.approvalState == .unknown) }
            let history = next.filter { $0.kind != .approval || ($0.approvalState != .pending && $0.approvalState != .unknown) }
            let retained = Set((Array(pinned.prefix(maximumItems)) + Array(history.prefix(max(0, maximumItems - pinned.count)))).map(\.id))
            next.removeAll { !retained.contains($0.id) }
        }
        if next != items { items = next }
    }

    private static func approvalStatus(_ state: AgentApprovalState) -> AgentOperationStatus {
        state == .pending ? .pending : state == .unknown ? .failed : .resolved
    }

    private static func project(_ event: AgentEvent, session: AgentSession) -> AgentWorkspaceFeedItem? {
        var kind: AgentWorkspaceFeedKind
        var title: String
        var status: AgentOperationStatus = .completed
        var processing: AgentProcessingKind?
        var approval: AgentApprovalState?
        var operationLabel: String?
        var exitCode: Int?
        switch event.type {
        case .sessionStarted:
            // Catch-up/discovery is not live traffic; do not flood Feed on launch.
            guard event.origin == .live else { return nil }
            kind = .session; title = "Session connected"
        case .sessionResumed: kind = .session; title = "Session resumed"
        case .sessionEnded: kind = .session; title = "Session disconnected"
        case .thinkingEnded:
            kind = .processing; processing = .reasoning; status = .completed; title = "Reasoning"
        case .agentWorking, .thinkingStarted, .planningStarted:
            let descriptor: AgentActivityDescriptor? = if case .activity(let value) = event.payload { value } else { nil }
            let eventKind: AgentProcessingKind? = switch event.type {
            case .thinkingStarted: .reasoning
            case .planningStarted: .planning
            default: nil
            }
            guard let typed = descriptor?.processingKind ?? eventKind else { return nil }
            kind = .processing; processing = typed
            status = descriptor?.processingStatus ?? .active
            switch typed {
            case .reasoning: title = "Reasoning"
            case .planning: title = "Planning"
            case .searching: title = "Searching"
            case .executing: title = "Processing"
            case .connecting: title = "Connecting"
            case .listening: title = "Reading external input"
            case .composing: title = "Composing response"
            case .synthesizing: title = "Combining results"
            case .background: title = "Background processing"
            }
        case .toolStarted, .toolCompleted:
            kind = .tool
            status = event.type == .toolStarted ? .active : .completed
            if case .tool(let tool) = event.payload {
                processing = tool.processingKind
                operationLabel = safeToolLabel(tool.name, category: tool.category)
                if event.type == .toolCompleted, tool.success == false { status = .failed }
            }
            title = status == .active ? "Tool started" : status == .failed ? "Tool failed" : "Tool completed"
        case .commandStarted, .commandCompleted:
            kind = .command
            status = event.type == .commandStarted ? .active : .completed
            if case .command(let command) = event.payload {
                processing = command.processingKind
                operationLabel = safeExecutableLabel(command.executable)
                exitCode = command.exitCode
                if event.type == .commandCompleted, command.success == false { status = .failed }
            }
            title = status == .active ? "Command started" : status == .failed ? "Command failed" : "Command completed"
        case .approvalRequested, .approvalResolved:
            guard let correlation = event.correlationID,
                  let request = session.approvals[correlation] else { return nil }
            kind = .approval; approval = request.state
            status = Self.approvalStatus(request.state)
            title = "Approval request"
        case .waitingForUser: kind = .userInput; title = "User input required"; status = .pending
        case .userInputResolved: kind = .userInput; title = "User input received"
        case .planReady: kind = .plan; title = "Plan ready"
        case .subagentStarted: kind = .subagent; title = "Subagent started"; status = .active
        case .subagentEnded: kind = .subagent; title = "Subagent completed"
        case .taskCompleted: kind = .completion; title = "Work completed"
        case .taskFailed: kind = .failure; title = "Work failed"; status = .failed
        case .interrupted: kind = .interruption; title = "Work interrupted"; status = .cancelled
        case .sessionMetadataUpdated, .planUpdated, .usageUpdated, .capabilitiesUpdated,
             .projectContextUpdated, .heartbeat, .unsupported: return nil
        }
        var item = AgentWorkspaceFeedItem(
            id: .init(session: event.instanceID, eventID: event.eventID),
            kind: kind, correlationID: event.correlationID,
            timestamp: event.effectiveTimestamp, updatedAt: event.effectiveTimestamp,
            title: title, status: status, processingKind: processing, approvalState: approval,
            operationLabel: operationLabel, exitCode: exitCode
        )
        if kind == .command || kind == .tool { item.title = operationTitle(item) }
        return item
    }

    private static func operationTitle(_ item: AgentWorkspaceFeedItem) -> String {
        let operation = item.kind == .command ? "Command" : "Tool"
        var title = switch item.status {
        case .active: operation
        case .failed: "\(operation) failed"
        case .cancelled: "\(operation) interrupted"
        default: "\(operation) completed"
        }
        if let label = item.operationLabel { title += item.status == .active ? ": \(label)" : " · \(label)" }
        if let exitCode = item.exitCode { title += " · exit \(exitCode)" }
        return title
    }

    private static func safeExecutableLabel(_ executable: String?) -> String? {
        guard let executable else { return nil }
        // Provider data can be malformed or sensitive; never retain arbitrary
        // strings, even if the normal adapter promises an executable only.
        let allowed = Set(["swift", "git", "rg", "grep", "find", "ls", "pwd", "cat", "sed", "head", "tail", "echo", "printf", "xcodebuild", "make", "cmake", "cargo", "go", "python", "python3", "ruby", "bash", "zsh", "sh"])
        return allowed.contains(executable) ? executable : nil
    }

    private static func safeToolLabel(_ name: String?, category: String?) -> String? {
        let known = ["read_file": "Read file", "read": "Read file", "search": "Search", "web_search": "Web search", "apply_patch": "Apply patch", "edit": "Edit", "exec_command": "Execute command", "shell": "Shell", "mcp": "MCP"]
        if let name, let label = known[name.lowercased()] { return label }
        if let category, let label = known[category.lowercased()] { return label }
        return nil
    }
}
