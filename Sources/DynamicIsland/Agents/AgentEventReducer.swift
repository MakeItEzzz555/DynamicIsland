import Foundation

struct AgentEventStoreLimits: Equatable, Sendable {
    var maximumSessions: Int
    var maximumActivityPerSession: Int
    var maximumGlobalActivity: Int
    var maximumRememberedEventIDs: Int
    var maximumPendingOperations: Int
    var maximumTrackedOperations: Int
    var maximumAttentionEvents: Int
    var completedSessionRetention: TimeInterval

    static let standard = AgentEventStoreLimits(
        maximumSessions: 32,
        maximumActivityPerSession: 200,
        maximumGlobalActivity: 2_000,
        maximumRememberedEventIDs: 512,
        maximumPendingOperations: 64,
        maximumTrackedOperations: 64,
        maximumAttentionEvents: 128,
        completedSessionRetention: 24 * 60 * 60
    )

    var normalized: AgentEventStoreLimits {
        AgentEventStoreLimits(
            maximumSessions: max(1, maximumSessions),
            maximumActivityPerSession: max(1, maximumActivityPerSession),
            maximumGlobalActivity: max(1, maximumGlobalActivity),
            maximumRememberedEventIDs: max(1, maximumRememberedEventIDs),
            maximumPendingOperations: max(1, maximumPendingOperations),
            maximumTrackedOperations: max(1, maximumTrackedOperations),
            maximumAttentionEvents: max(1, maximumAttentionEvents),
            completedSessionRetention: max(0, completedSessionRetention)
        )
    }
}

enum AgentEventRejection: Equatable, Sendable {
    case validation(AgentEventValidationError)
    case missingSession
    case generationMismatch
    case conflictingDuplicate
    case missingCorrelation
    case operationCapacity
    case sessionCapacity
}

enum AgentEventApplication: Equatable, Sendable {
    case applied
    case duplicate
    case ignoredAfterTerminal
    case ignoredWeakerEvidence
    case staleGeneration
    case rejected(AgentEventRejection)
}

enum AgentEventBatchApplication: Equatable, Sendable {
    case applied([AgentEventApplication])
    case rejected(index: Int, application: AgentEventApplication)
}

struct AgentReductionResult: Equatable, Sendable {
    let session: AgentSession?
    let application: AgentEventApplication
    let attention: AgentAttentionEvent?
}

enum AgentEventReducer {
    static func reduce(
        session existingSession: AgentSession?,
        event: AgentEvent,
        limits rawLimits: AgentEventStoreLimits = .standard
    ) -> AgentReductionResult {
        let limits = rawLimits.normalized
        if let error = event.validationError() {
            return AgentReductionResult(
                session: existingSession,
                application: .rejected(.validation(error)),
                attention: nil
            )
        }

        var session: AgentSession
        if let existingSession {
            guard existingSession.id == event.instanceID else {
                return AgentReductionResult(
                    session: existingSession,
                    application: .staleGeneration,
                    attention: nil
                )
            }
            session = existingSession
        } else {
            guard event.type == .sessionStarted else {
                return AgentReductionResult(
                    session: nil,
                    application: .rejected(.missingSession),
                    attention: nil
                )
            }
            session = makeSession(for: event)
        }

        if let existingFingerprint = session.eventFingerprints[event.eventID] {
            return AgentReductionResult(
                session: session,
                application: existingFingerprint == event.fingerprint
                    ? .duplicate
                    : .rejected(.conflictingDuplicate),
                attention: nil
            )
        }

        if event.source != .unknown,
           event.authority >= session.sourceAuthority {
            session.source = event.source
            session.sourceAuthority = event.authority
        }

        if isTerminalTransition(event.type),
           event.authority < session.terminalAuthority {
            remember(event, in: &session, limits: limits)
            return AgentReductionResult(
                session: session,
                application: .ignoredWeakerEvidence,
                attention: nil
            )
        }

        if session.state.isTerminal && !isAllowedAfterTerminal(event.type) {
            remember(event, in: &session, limits: limits)
            return AgentReductionResult(
                session: session,
                application: .ignoredAfterTerminal,
                attention: nil
            )
        }

        if session.state.isTerminal,
           event.type == .sessionResumed,
           event.authority < session.terminalAuthority {
            remember(event, in: &session, limits: limits)
            return AgentReductionResult(
                session: session,
                application: .ignoredWeakerEvidence,
                attention: nil
            )
        }

        let semanticResult = apply(event, to: &session, limits: limits)
        switch semanticResult {
        case .rejected(let reason):
            return AgentReductionResult(
                session: existingSession,
                application: .rejected(reason),
                attention: nil
            )
        case .applied(let attention):
            remember(event, in: &session, limits: limits)
            session.lastUpdatedAt = max(session.lastUpdatedAt, event.receivedTimestamp)
            if !session.state.isTerminal {
                session.state = primaryState(for: session)
            }
            return AgentReductionResult(
                session: session,
                application: .applied,
                attention: attention
            )
        }
    }

    private enum SemanticResult {
        case applied(AgentAttentionEvent?)
        case rejected(AgentEventRejection)
    }

    private static func makeSession(for event: AgentEvent) -> AgentSession {
        let project: AgentProjectContext
        let availability: AgentSessionAvailability?
        if case .sessionMetadata(let metadata) = event.payload {
            project = AgentPrivacyProjection.project(metadata.project ?? AgentProjectContext())
            availability = metadata.availability
        } else {
            project = AgentProjectContext()
            availability = nil
        }
        var session = AgentSession(
            id: event.instanceID,
            source: event.source,
            state: .idle,
            project: project,
            capabilities: AgentCapabilities(),
            usage: AgentUsage(),
            tools: [:],
            commands: [:],
            approvals: [:],
            subagents: [:],
            recentActivity: [],
            startedAt: event.effectiveTimestamp,
            endedAt: nil,
            lastUpdatedAt: event.receivedTimestamp,
            availability: availability,
            sourceAuthority: event.authority
        )
        session.terminalAuthority = event.authority
        return session
    }

    private static func apply(
        _ event: AgentEvent,
        to session: inout AgentSession,
        limits: AgentEventStoreLimits
    ) -> SemanticResult {
        expireApprovals(in: &session, at: event.receivedTimestamp)
        switch event.type {
        case .sessionStarted:
            session.terminalAuthority = max(session.terminalAuthority, event.authority)
            mergeSessionMetadata(event.payload, into: &session)
            appendActivity(
                event: event,
                kind: .session,
                title: event.origin == .localRecovery ? "Session recovered" : "Session started",
                summary: session.project.displayName,
                status: .completed,
                to: &session,
                limits: limits
            )

        case .sessionResumed:
            session.terminalAuthority = max(session.terminalAuthority, event.authority)
            session.endedAt = nil
            session.state = .working
            session.isWorking = true
            session.isPlanReady = false
            session.planReadyAuthority = .heuristic
            mergeSessionMetadata(event.payload, into: &session)
            appendActivity(
                event: event,
                kind: .session,
                title: "Session resumed",
                status: .completed,
                to: &session,
                limits: limits
            )

        case .sessionMetadataUpdated:
            mergeSessionMetadata(event.payload, into: &session)

        case .sessionEnded:
            session.endedAt = event.effectiveTimestamp
            if !session.state.isTerminal {
                finishOperations(in: &session, terminalState: .interrupted, at: event.effectiveTimestamp)
                session.state = .interrupted
                session.terminalAuthority = event.authority
            }

        case .agentWorking:
            session.isWorking = true
            if event.authority >= session.planReadyAuthority {
                session.isPlanReady = false
                session.planReadyAuthority = .heuristic
            }
            session.waitingForUserID = nil
            if case .activity(let descriptor) = event.payload {
                appendActivity(
                    event: event,
                    kind: .session,
                    title: AgentPrivacyProjection.title(descriptor.title, fallback: "Working"),
                    summary: descriptor.summary,
                    status: .active,
                    to: &session,
                    limits: limits
                )
            }

        case .thinkingStarted:
            session.isThinking = true
            if case .activity(let descriptor) = event.payload {
                appendActivity(
                    event: event,
                    kind: .thinking,
                    title: AgentPrivacyProjection.title(descriptor.title, fallback: "Thinking"),
                    summary: descriptor.summary,
                    status: .active,
                    to: &session,
                    limits: limits
                )
            }

        case .thinkingEnded:
            session.isThinking = false

        case .planningStarted:
            session.isPlanning = true
            if event.authority >= session.planReadyAuthority {
                session.isPlanReady = false
                session.planReadyAuthority = .heuristic
            }
            if case .activity(let descriptor) = event.payload {
                appendActivity(
                    event: event,
                    kind: .plan,
                    title: AgentPrivacyProjection.title(descriptor.title, fallback: "Planning"),
                    summary: descriptor.summary,
                    status: .active,
                    to: &session,
                    limits: limits
                )
            }

        case .planUpdated:
            session.isPlanning = true
            if case .plan(let plan) = event.payload {
                appendActivity(
                    event: event,
                    kind: .plan,
                    title: "Plan updated",
                    summary: plan.summary,
                    status: .active,
                    to: &session,
                    limits: limits
                )
            }

        case .planReady:
            session.isPlanning = false
            session.isPlanReady = true
            session.planReadyAuthority = event.authority
            let summary = planSummary(from: event.payload)
            appendActivity(
                event: event,
                kind: .plan,
                title: "Plan ready",
                summary: summary,
                status: .completed,
                to: &session,
                limits: limits
            )
            return .applied(attention(for: event, reason: .planReady, summary: summary ?? "Plan ready"))

        case .toolStarted:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .tool(let toolEvent) = event.payload else { preconditionFailure() }
            guard prepareCapacity(
                for: correlationID,
                in: &session.tools,
                maximum: limits.maximumTrackedOperations,
                timestamp: { $0.completedAt ?? $0.startedAt },
                isActive: { $0.status == .active }
            ) else {
                return .rejected(.operationCapacity)
            }
            if session.tools[correlationID] == nil {
                var tool = AgentTool(
                    correlationID: correlationID,
                    name: AgentPrivacyProjection.toolName(toolEvent.name),
                    category: AgentPrivacyProjection.summary(toolEvent.category),
                    summary: AgentPrivacyProjection.summary(toolEvent.summary),
                    status: .active,
                    startedAt: event.effectiveTimestamp,
                    completedAt: nil,
                    success: nil
                )
                let pendingKey = AgentPendingOperationKey(kind: .tool, correlationID: correlationID)
                if case .tool(let pending, let completedAt)? = session.pendingOperations.removeValue(forKey: pendingKey) {
                    complete(&tool, with: pending, at: completedAt)
                    session.pendingOperationOrder.removeAll { $0 == pendingKey }
                }
                session.tools[correlationID] = tool
                resolveMatchingPendingApproval(
                    operationName: tool.name,
                    at: event.effectiveTimestamp,
                    in: &session
                )
                appendActivity(
                    event: event,
                    kind: .tool,
                    title: tool.name,
                    summary: tool.summary,
                    status: tool.status,
                    correlationID: correlationID,
                    to: &session,
                    limits: limits
                )
            }

        case .toolCompleted:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .tool(let toolEvent) = event.payload else { preconditionFailure() }
            if var tool = session.tools[correlationID] {
                guard tool.status == .active else { return .applied(nil) }
                complete(&tool, with: toolEvent, at: event.effectiveTimestamp)
                session.tools[correlationID] = tool
                appendActivity(
                    event: event,
                    kind: .tool,
                    title: tool.name,
                    summary: tool.summary,
                    status: tool.status,
                    correlationID: correlationID,
                    to: &session,
                    limits: limits
                )
            } else {
                storePending(
                    .tool(sanitized(toolEvent), completedAt: event.effectiveTimestamp),
                    kind: .tool,
                    correlationID: correlationID,
                    in: &session,
                    limits: limits
                )
            }

        case .commandStarted:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .command(let commandEvent) = event.payload else { preconditionFailure() }
            guard prepareCapacity(
                for: correlationID,
                in: &session.commands,
                maximum: limits.maximumTrackedOperations,
                timestamp: { $0.completedAt ?? $0.startedAt },
                isActive: { $0.status == .active }
            ) else {
                return .rejected(.operationCapacity)
            }
            if session.commands[correlationID] == nil {
                var command = AgentCommand(
                    correlationID: correlationID,
                    displaySummary: AgentPrivacyProjection.commandSummary(executable: commandEvent.executable),
                    status: .active,
                    startedAt: event.effectiveTimestamp,
                    completedAt: nil,
                    exitCode: nil,
                    success: nil
                )
                let pendingKey = AgentPendingOperationKey(kind: .command, correlationID: correlationID)
                if case .command(let pending, let completedAt)? = session.pendingOperations.removeValue(forKey: pendingKey) {
                    complete(&command, with: pending, at: completedAt)
                    session.pendingOperationOrder.removeAll { $0 == pendingKey }
                }
                session.commands[correlationID] = command
                resolveMatchingPendingApproval(
                    operationName: command.displaySummary,
                    at: event.effectiveTimestamp,
                    in: &session
                )
                appendActivity(
                    event: event,
                    kind: .command,
                    title: command.displaySummary,
                    status: command.status,
                    correlationID: correlationID,
                    to: &session,
                    limits: limits
                )
            }

        case .commandCompleted:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .command(let commandEvent) = event.payload else { preconditionFailure() }
            if var command = session.commands[correlationID] {
                guard command.status == .active else { return .applied(nil) }
                complete(&command, with: commandEvent, at: event.effectiveTimestamp)
                session.commands[correlationID] = command
                appendActivity(
                    event: event,
                    kind: .command,
                    title: command.displaySummary,
                    status: command.status,
                    correlationID: correlationID,
                    to: &session,
                    limits: limits
                )
            } else {
                storePending(
                    .command(sanitized(commandEvent), completedAt: event.effectiveTimestamp),
                    kind: .command,
                    correlationID: correlationID,
                    in: &session,
                    limits: limits
                )
            }

        case .approvalRequested:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .approvalRequest(let request) = event.payload else { preconditionFailure() }
            guard prepareCapacity(
                for: correlationID,
                in: &session.approvals,
                maximum: limits.maximumTrackedOperations,
                timestamp: { $0.resolvedAt ?? $0.requestedAt },
                isActive: { !$0.state.isResolved }
            ) else {
                return .rejected(.operationCapacity)
            }
            if let existing = session.approvals[correlationID],
               existing.state == .pending {
                return .applied(nil)
            }
            var approval = AgentApproval(
                requestID: correlationID,
                summary: AgentPrivacyProjection.title(request.summary, fallback: "Approval required"),
                operationCorrelationID: request.operationCorrelationID,
                requestedAt: event.effectiveTimestamp,
                resolvedAt: nil,
                expiresAt: request.expiresAt,
                state: .pending
            )
            let pendingKey = AgentPendingOperationKey(kind: .approval, correlationID: correlationID)
            if case .approval(let pending, let resolvedAt)? = session.pendingOperations.removeValue(forKey: pendingKey) {
                approval.state = pending.state
                approval.resolvedAt = max(event.effectiveTimestamp, resolvedAt)
                session.pendingOperationOrder.removeAll { $0 == pendingKey }
            } else if let expiresAt = approval.expiresAt, expiresAt <= event.receivedTimestamp {
                approval.state = .expired
                approval.resolvedAt = event.receivedTimestamp
            }
            session.approvals[correlationID] = approval
            appendActivity(
                event: event,
                kind: .approval,
                title: approval.summary,
                status: approval.state == .pending ? .pending : .resolved,
                correlationID: correlationID,
                to: &session,
                limits: limits
            )
            if approval.state == .pending {
                return .applied(attention(
                    for: event,
                    reason: .approvalRequired,
                    summary: approval.summary
                ))
            }

        case .approvalResolved:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .approvalResolution(let resolution) = event.payload else { preconditionFailure() }
            if var approval = session.approvals[correlationID] {
                guard approval.state == .pending else { return .applied(nil) }
                approval.state = resolution.state
                approval.resolvedAt = event.effectiveTimestamp
                session.approvals[correlationID] = approval
                appendActivity(
                    event: event,
                    kind: .approval,
                    title: approval.summary,
                    status: .resolved,
                    correlationID: correlationID,
                    to: &session,
                    limits: limits
                )
            } else {
                storePending(
                    .approval(resolution, resolvedAt: event.effectiveTimestamp),
                    kind: .approval,
                    correlationID: correlationID,
                    in: &session,
                    limits: limits
                )
            }

        case .waitingForUser:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .userInput(let input) = event.payload else { preconditionFailure() }
            session.waitingForUserID = correlationID
            let summary = AgentPrivacyProjection.title(input.summary, fallback: "Input required")
            appendActivity(
                event: event,
                kind: .userInput,
                title: summary,
                status: .pending,
                correlationID: correlationID,
                to: &session,
                limits: limits
            )
            return .applied(attention(for: event, reason: .userInputRequired, summary: summary))

        case .userInputResolved:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            if session.waitingForUserID == correlationID {
                session.waitingForUserID = nil
            }

        case .usageUpdated:
            guard case .usage(let usage) = event.payload else { preconditionFailure() }
            session.usage.merge(AgentPrivacyProjection.usage(usage))

        case .capabilitiesUpdated:
            guard case .capabilities(let capabilities) = event.payload else { preconditionFailure() }
            let sanitized = sanitizedCapabilities(capabilities, maximumAuthority: event.authority)
            if event.authority >= session.capabilitySnapshotAuthority {
                session.capabilities = sanitized
                session.capabilitySnapshotAuthority = event.authority
            } else {
                session.capabilities = session.capabilities.mergingStrongerEvidence(from: sanitized)
            }

        case .projectContextUpdated:
            guard case .projectContext(let project) = event.payload else { preconditionFailure() }
            mergeProject(AgentPrivacyProjection.project(project), into: &session.project)

        case .taskCompleted:
            guard case .terminal(let terminal) = event.payload else { preconditionFailure() }
            let summary = AgentPrivacyProjection.title(terminal.summary, fallback: "Task completed")
            finishOperations(in: &session, terminalState: .completed, at: event.effectiveTimestamp)
            session.state = .completed
            session.terminalAuthority = event.authority
            // Task completion ends the turn, not the provider session/thread.
            // Only sessionEnded closes the session itself.
            session.endedAt = nil
            appendActivity(
                event: event,
                kind: .completion,
                title: summary,
                status: .completed,
                to: &session,
                limits: limits
            )
            return .applied(attention(for: event, reason: .completed, summary: summary))

        case .taskFailed:
            guard case .terminal(let terminal) = event.payload else { preconditionFailure() }
            let summary = AgentPrivacyProjection.title(terminal.summary, fallback: "Task failed")
            finishOperations(in: &session, terminalState: .failed, at: event.effectiveTimestamp)
            session.state = .failed
            session.terminalAuthority = event.authority
            session.endedAt = nil
            appendActivity(
                event: event,
                kind: .failure,
                title: summary,
                status: .failed,
                to: &session,
                limits: limits
            )
            return .applied(attention(for: event, reason: .failed, summary: summary))

        case .interrupted:
            guard case .terminal(let terminal) = event.payload else { preconditionFailure() }
            let summary = AgentPrivacyProjection.title(terminal.summary, fallback: "Task interrupted")
            finishOperations(in: &session, terminalState: .interrupted, at: event.effectiveTimestamp)
            session.state = .interrupted
            session.terminalAuthority = event.authority
            session.endedAt = nil
            appendActivity(
                event: event,
                kind: .interruption,
                title: summary,
                status: .cancelled,
                to: &session,
                limits: limits
            )
            return .applied(attention(for: event, reason: .interrupted, summary: summary))

        case .subagentStarted:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .subagent(let subagentEvent) = event.payload else { preconditionFailure() }
            if session.subagents.values.contains(where: { $0.nativeID == subagentEvent.nativeID }) {
                return .applied(nil)
            }
            guard prepareCapacity(
                for: correlationID,
                in: &session.subagents,
                maximum: limits.maximumTrackedOperations,
                timestamp: { $0.endedAt ?? $0.startedAt },
                isActive: { $0.status == .active }
            ) else {
                return .rejected(.operationCapacity)
            }
            if session.subagents[correlationID] == nil {
                let subagent = AgentSubagent(
                    nativeID: subagentEvent.nativeID,
                    correlationID: correlationID,
                    displayName: AgentPrivacyProjection.summary(subagentEvent.displayName),
                    status: .active,
                    startedAt: event.effectiveTimestamp,
                    endedAt: nil
                )
                session.subagents[correlationID] = subagent
                appendActivity(
                    event: event,
                    kind: .subagent,
                    title: subagent.displayName ?? "Subagent started",
                    status: .active,
                    correlationID: correlationID,
                    to: &session,
                    limits: limits
                )
            }

        case .subagentEnded:
            guard let correlationID = event.correlationID else { return .rejected(.missingCorrelation) }
            guard case .subagent(let subagentEvent) = event.payload else { preconditionFailure() }
            if var subagent = session.subagents[correlationID], subagent.status == .active {
                guard subagent.nativeID == subagentEvent.nativeID else {
                    return .rejected(.missingCorrelation)
                }
                subagent.status = .completed
                subagent.endedAt = event.effectiveTimestamp
                session.subagents[correlationID] = subagent
                appendActivity(
                    event: event,
                    kind: .subagent,
                    title: subagent.displayName ?? "Subagent finished",
                    status: .completed,
                    correlationID: correlationID,
                    to: &session,
                    limits: limits
                )
            }

        case .heartbeat:
            break

        case .unsupported:
            preconditionFailure("Unsupported events are rejected during validation")
        }

        return .applied(nil)
    }

    private static func isTerminalTransition(_ type: AgentEventType) -> Bool {
        switch type {
        case .sessionEnded, .taskCompleted, .taskFailed, .interrupted:
            true
        default:
            false
        }
    }

    private static func isAllowedAfterTerminal(_ type: AgentEventType) -> Bool {
        switch type {
        case .sessionResumed, .sessionEnded, .sessionMetadataUpdated, .usageUpdated,
             .capabilitiesUpdated, .projectContextUpdated, .heartbeat:
            true
        default:
            false
        }
    }

    private static func primaryState(for session: AgentSession) -> AgentState {
        if session.approvals.values.contains(where: { $0.state == .pending }) {
            return .waitingForApproval
        }
        if session.waitingForUserID != nil { return .waitingForUser }
        if session.isPlanReady { return .planReady }
        if session.commands.values.contains(where: { $0.status == .active }) {
            return .runningCommand
        }
        if session.tools.values.contains(where: { $0.status == .active }) {
            return .runningTool
        }
        if session.isThinking { return .thinking }
        if session.isPlanning { return .planning }
        if session.isWorking { return .working }
        return .idle
    }

    private static func mergeSessionMetadata(
        _ payload: AgentEventPayload,
        into session: inout AgentSession
    ) {
        guard case .sessionMetadata(let metadata) = payload else { return }
        if let project = metadata.project {
            mergeProject(AgentPrivacyProjection.project(project), into: &session.project)
        }
        if let availability = metadata.availability {
            session.availability = availability
        }
    }

    private static func mergeProject(
        _ update: AgentProjectContext,
        into project: inout AgentProjectContext
    ) {
        if let value = update.displayName { project.displayName = value }
        if let value = update.workingDirectory { project.workingDirectory = value }
        if let value = update.repositoryIdentity { project.repositoryIdentity = value }
        if let value = update.gitBranch { project.gitBranch = value }
        if let value = update.gitCommit { project.gitCommit = value }
        if let value = update.model { project.model = value }
        if let value = update.sourceApplication { project.sourceApplication = value }
    }

    private static func sanitizedCapabilities(
        _ capabilities: AgentCapabilities,
        maximumAuthority: AgentEvidenceAuthority
    ) -> AgentCapabilities {
        AgentCapabilities(evidence: capabilities.evidence.mapValues { evidence in
            let sanitized = AgentPrivacyProjection.capabilityEvidence(evidence)
            return AgentCapabilityEvidence(
                authority: min(sanitized.authority, maximumAuthority),
                source: sanitized.source,
                observedAt: sanitized.observedAt
            )
        })
    }

    private static func appendActivity(
        event: AgentEvent,
        kind: AgentActivityKind,
        title: String,
        summary: String? = nil,
        status: AgentOperationStatus,
        correlationID: AgentCorrelationID? = nil,
        to session: inout AgentSession,
        limits: AgentEventStoreLimits
    ) {
        session.recentActivity.append(AgentActivity(
            id: event.eventID,
            kind: kind,
            title: AgentPrivacyProjection.title(title, fallback: "Activity"),
            summary: AgentPrivacyProjection.summary(summary),
            status: status,
            correlationID: correlationID,
            timestamp: event.effectiveTimestamp
        ))
        if session.recentActivity.count > limits.maximumActivityPerSession {
            session.recentActivity.removeFirst(
                session.recentActivity.count - limits.maximumActivityPerSession
            )
        }
    }

    private static func remember(
        _ event: AgentEvent,
        in session: inout AgentSession,
        limits: AgentEventStoreLimits
    ) {
        session.eventFingerprints[event.eventID] = event.fingerprint
        session.recentEventOrder.append(event.eventID)
        while session.recentEventOrder.count > limits.maximumRememberedEventIDs {
            let expired = session.recentEventOrder.removeFirst()
            session.eventFingerprints.removeValue(forKey: expired)
        }
    }

    private static func resolveMatchingPendingApproval(
        operationName: String,
        at date: Date,
        in session: inout AgentSession
    ) {
        guard let normalized = AgentPrivacyProjection.normalized(operationName)?.lowercased() else {
            return
        }
        let hint = AgentCorrelationID(rawValue: "operation-" + normalized)
        let matches = session.approvals.compactMap { key, approval -> AgentCorrelationID? in
            approval.state == .pending && approval.operationCorrelationID == hint ? key : nil
        }
        guard matches.count == 1, let requestID = matches.first,
              var approval = session.approvals[requestID] else {
            return
        }
        approval.state = .approved
        approval.resolvedAt = max(approval.requestedAt, date)
        session.approvals[requestID] = approval
    }

    private static func storePending(
        _ operation: AgentPendingOperation,
        kind: AgentPendingOperationKind,
        correlationID: AgentCorrelationID,
        in session: inout AgentSession,
        limits: AgentEventStoreLimits
    ) {
        let key = AgentPendingOperationKey(kind: kind, correlationID: correlationID)
        if session.pendingOperations[key] == nil {
            session.pendingOperationOrder.append(key)
        }
        session.pendingOperations[key] = operation
        while session.pendingOperationOrder.count > limits.maximumPendingOperations {
            let expired = session.pendingOperationOrder.removeFirst()
            session.pendingOperations.removeValue(forKey: expired)
        }
    }

    private static func prepareCapacity<Value>(
        for key: AgentCorrelationID,
        in values: inout [AgentCorrelationID: Value],
        maximum: Int,
        timestamp: (Value) -> Date,
        isActive: (Value) -> Bool
    ) -> Bool {
        guard values[key] == nil else { return true }
        guard values.count >= maximum else { return true }
        guard let removable = values
            .filter({ !isActive($0.value) })
            .min(by: { lhs, rhs in
                let lhsDate = timestamp(lhs.value)
                let rhsDate = timestamp(rhs.value)
                if lhsDate != rhsDate { return lhsDate < rhsDate }
                return lhs.key.rawValue < rhs.key.rawValue
            })?.key else {
            return false
        }
        values.removeValue(forKey: removable)
        return true
    }

    private static func complete(_ tool: inout AgentTool, with event: AgentToolEvent, at date: Date) {
        tool.summary = AgentPrivacyProjection.summary(event.summary) ?? tool.summary
        tool.success = event.success
        tool.status = event.success == false ? .failed : .completed
        tool.completedAt = max(tool.startedAt, date)
    }

    private static func sanitized(_ event: AgentToolEvent) -> AgentToolEvent {
        AgentToolEvent(
            name: event.name.map { AgentPrivacyProjection.toolName($0) },
            category: AgentPrivacyProjection.summary(event.category),
            summary: AgentPrivacyProjection.summary(event.summary),
            success: event.success
        )
    }

    private static func sanitized(_ event: AgentCommandEvent) -> AgentCommandEvent {
        AgentCommandEvent(
            executable: event.executable.map { AgentPrivacyProjection.commandSummary(executable: $0) },
            success: event.success,
            exitCode: event.exitCode
        )
    }

    private static func complete(
        _ command: inout AgentCommand,
        with event: AgentCommandEvent,
        at date: Date
    ) {
        command.success = event.success
        command.exitCode = event.exitCode
        command.status = event.success == false ? .failed : .completed
        command.completedAt = max(command.startedAt, date)
    }

    private static func finishOperations(
        in session: inout AgentSession,
        terminalState: AgentState,
        at date: Date
    ) {
        let status: AgentOperationStatus = switch terminalState {
        case .completed: .completed
        case .failed: .failed
        default: .cancelled
        }
        for key in session.tools.keys where session.tools[key]?.status == .active {
            session.tools[key]?.status = status
            session.tools[key]?.completedAt = date
        }
        for key in session.commands.keys where session.commands[key]?.status == .active {
            session.commands[key]?.status = status
            session.commands[key]?.completedAt = date
        }
        for key in session.subagents.keys where session.subagents[key]?.status == .active {
            session.subagents[key]?.status = status
            session.subagents[key]?.endedAt = date
        }
        for key in session.approvals.keys where session.approvals[key]?.state == .pending {
            session.approvals[key]?.state = .cancelled
            session.approvals[key]?.resolvedAt = date
        }
        session.isThinking = false
        session.isPlanning = false
        session.isWorking = false
        session.isPlanReady = false
        session.planReadyAuthority = .heuristic
        session.waitingForUserID = nil
        session.pendingOperations.removeAll(keepingCapacity: false)
        session.pendingOperationOrder.removeAll(keepingCapacity: false)
    }

    private static func expireApprovals(in session: inout AgentSession, at date: Date) {
        for key in session.approvals.keys {
            guard var approval = session.approvals[key],
                  approval.state == .pending,
                  let expiresAt = approval.expiresAt,
                  expiresAt <= date else {
                continue
            }
            approval.state = .expired
            approval.resolvedAt = date
            session.approvals[key] = approval
        }
    }

    private static func planSummary(from payload: AgentEventPayload) -> String? {
        guard case .plan(let plan) = payload else { return nil }
        return AgentPrivacyProjection.summary(plan.summary)
    }

    private static func attention(
        for event: AgentEvent,
        reason: AgentAttentionReason,
        summary: String
    ) -> AgentAttentionEvent {
        let priority: AgentAttentionPriority = switch reason {
        case .failed: .failure
        case .approvalRequired: .approvalRequired
        case .userInputRequired: .userInputRequired
        case .planReady: .planReady
        case .completed: .completed
        case .interrupted: .interrupted
        }
        return AgentAttentionEvent(
            eventID: event.eventID,
            session: event.instanceID,
            source: event.source,
            reason: reason,
            priority: priority,
            timestamp: event.effectiveTimestamp,
            displaySummary: AgentPrivacyProjection.title(summary, fallback: "Agent activity")
        )
    }
}
