import Foundation

enum AgentIntegrationPrecedence: Int, Comparable, Sendable {
    case mcpFallback = 0
    case secondaryObservation = 1
    case providerNative = 2

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum AgentMCPObservationError: Error, Equatable, Sendable {
    case invalidIdentity
    case invalidCorrelation
    case invalidPayload
    case unauthoritativeUsage
}

enum AgentMCPObservationKind: Equatable, Sendable {
    case sessionObserved(project: AgentProjectContext?)
    case activity(title: String?, summary: String?)
    case planUpdated(summary: String?)
    case planReady(summary: String?)
    case toolStarted(name: String?, category: String?, summary: String?)
    case toolCompleted(name: String?, category: String?, summary: String?, success: Bool?)
    case commandStarted(executable: String?)
    case commandCompleted(executable: String?, success: Bool?, exitCode: Int?)
    case attention(summary: String?, operationCorrelationID: AgentCorrelationID?, expiresAt: Date?)
    case project(AgentProjectContext)
    case usage(AgentUsage, authoritative: Bool)
    case heartbeat
}

struct AgentMCPObservation: Equatable, Sendable {
    let observationID: String
    let provider: AgentProvider
    let nativeSessionID: String
    let timestamp: Date
    let correlationID: AgentCorrelationID?
    let kind: AgentMCPObservationKind

    init(
        observationID: String,
        provider: AgentProvider,
        nativeSessionID: String,
        timestamp: Date = Date(),
        correlationID: AgentCorrelationID? = nil,
        kind: AgentMCPObservationKind
    ) {
        self.observationID = observationID
        self.provider = provider
        self.nativeSessionID = nativeSessionID
        self.timestamp = timestamp
        self.correlationID = correlationID
        self.kind = kind
    }
}

/// The single normalization boundary for provider-native, secondary, and MCP
/// observations. It deliberately owns no lifecycle or control state; accepted
/// events still converge through AgentIngestionCoordinator and AgentEventStore.
actor AgentIntegrationRouter {
    private struct DeduplicationKey: Hashable {
        let sessionID: AgentSessionID
        let eventType: String
        let correlation: String
        let payload: String
    }

    private struct RoutedObservation {
        var precedence: AgentIntegrationPrecedence
        let routedAt: Date
    }

    private let coordinator: AgentIngestionCoordinator
    private let deduplicationWindow: TimeInterval
    private let maximumDeduplicationEntries: Int
    private var recentObservations: [DeduplicationKey: RoutedObservation] = [:]
    private var observationOrder: [DeduplicationKey] = []

    init(
        coordinator: AgentIngestionCoordinator,
        deduplicationWindow: TimeInterval = 120,
        maximumDeduplicationEntries: Int = 2_048
    ) {
        self.coordinator = coordinator
        self.deduplicationWindow = max(1, deduplicationWindow)
        self.maximumDeduplicationEntries = max(32, maximumDeduplicationEntries)
    }

    func registerMCPSource(
        id: AgentSourceInstanceID,
        runtimeVersion: String? = nil,
        authenticatedProducerID: String = UUID().uuidString.lowercased()
    ) async -> Result<AgentProducerHandle, AgentIngestionError> {
        await coordinator.registerProducer(
            descriptor: AgentProducerDescriptor(
                sourceInstanceID: id,
                sourceKind: .mcpObservation,
                runtimeVersion: runtimeVersion
            ),
            policy: .mcpObservation,
            authenticatedProducerID: authenticatedProducerID
        )
    }

    func unregisterMCPSource(_ producer: AgentProducerHandle) async {
        _ = await coordinator.unregisterProducer(producer)
    }

    func route(
        _ event: AgentIngestionEvent,
        from producer: AgentProducerHandle,
        precedence: AgentIntegrationPrecedence
    ) async -> Result<AgentIngestionResult, AgentIngestionError> {
        await routeAtomically([event], from: producer, precedence: precedence)
    }

    func routeAtomically(
        _ events: [AgentIngestionEvent],
        from producer: AgentProducerHandle,
        precedence: AgentIntegrationPrecedence
    ) async -> Result<AgentIngestionResult, AgentIngestionError> {
        guard !events.isEmpty else { return .failure(.invalidEvent) }
        if case .failure(let error) = await coordinator.validateForRouting(events, from: producer) {
            return .failure(error)
        }
        let now = Date()
        prune(at: now)

        var forwarded: [AgentIngestionEvent] = []
        var stagedKeys: [DeduplicationKey] = []
        for event in events {
            guard Self.isDeduplicatedObservation(event.type) else {
                forwarded.append(event)
                continue
            }
            let key = Self.deduplicationKey(for: event)
            if var previous = recentObservations[key] {
                if precedence > previous.precedence,
                   Self.canUpgradeWithoutDuplicateActivity(event.type) {
                    forwarded.append(event)
                    stagedKeys.append(key)
                    continue
                }
                // Equivalent evidence is represented once. Raising the cached
                // precedence ensures later fallbacks cannot displace knowledge
                // that a provider-native source also observed the same fact.
                previous.precedence = max(previous.precedence, precedence)
                recentObservations[key] = previous
                continue
            }
            forwarded.append(event)
            stagedKeys.append(key)
        }

        guard !forwarded.isEmpty else {
            return .success(AgentIngestionResult(
                acceptedEvents: 0,
                applications: [],
                sessionInstances: []
            ))
        }

        let result = await coordinator.ingestAtomically(forwarded, from: producer)
        guard case .success = result else { return result }
        for key in stagedKeys {
            recentObservations[key] = RoutedObservation(precedence: precedence, routedAt: now)
            observationOrder.removeAll { $0 == key }
            observationOrder.append(key)
        }
        enforceBound()
        return result
    }

    func routeMCP(
        _ observation: AgentMCPObservation,
        from producer: AgentProducerHandle
    ) async -> Result<AgentIngestionResult, AgentIngestionError> {
        do {
            let events = try Self.normalizeMCP(observation, sourceID: producer.sourceInstanceID)
            return await routeAtomically(events, from: producer, precedence: .mcpFallback)
        } catch {
            return .failure(.invalidEvent)
        }
    }

    private func prune(at now: Date) {
        while let first = observationOrder.first {
            guard let record = recentObservations[first] else {
                observationOrder.removeFirst()
                continue
            }
            guard now.timeIntervalSince(record.routedAt) > deduplicationWindow else { break }
            observationOrder.removeFirst()
            recentObservations.removeValue(forKey: first)
        }
    }

    private func enforceBound() {
        while observationOrder.count > maximumDeduplicationEntries {
            let removed = observationOrder.removeFirst()
            recentObservations.removeValue(forKey: removed)
        }
    }

    private static func deduplicationKey(for event: AgentIngestionEvent) -> DeduplicationKey {
        let payload: String
        if let correlation = event.correlationID?.rawValue {
            payload = correlation
        } else {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .millisecondsSince1970
            payload = (try? encoder.encode(event.payload).base64EncodedString()) ?? event.eventID.rawValue
        }
        return DeduplicationKey(
            sessionID: event.sessionID,
            eventType: event.type.stableName,
            correlation: event.correlationID?.rawValue ?? "",
            payload: payload
        )
    }

    private static func isDeduplicatedObservation(_ type: AgentEventType) -> Bool {
        switch type {
        case .agentWorking, .thinkingStarted, .thinkingEnded,
             .planningStarted, .planUpdated, .planReady,
             .toolStarted, .toolCompleted, .commandStarted, .commandCompleted,
             .approvalRequested, .waitingForUser,
             .usageUpdated, .sessionMetadataUpdated, .projectContextUpdated,
             .subagentStarted, .subagentEnded:
            true
        case .sessionStarted, .sessionResumed, .sessionEnded,
             .approvalResolved, .userInputResolved, .capabilitiesUpdated,
             .taskCompleted, .taskFailed, .interrupted, .heartbeat, .unsupported:
            false
        }
    }

    private static func canUpgradeWithoutDuplicateActivity(_ type: AgentEventType) -> Bool {
        switch type {
        case .toolStarted, .toolCompleted, .commandStarted, .commandCompleted,
             .usageUpdated, .sessionMetadataUpdated, .projectContextUpdated:
            true
        default:
            false
        }
    }

    private static func normalizeMCP(
        _ observation: AgentMCPObservation,
        sourceID: AgentSourceInstanceID
    ) throws -> [AgentIngestionEvent] {
        guard validIdentifier(observation.observationID),
              validIdentifier(observation.nativeSessionID),
              validProvider(observation.provider) else {
            throw AgentMCPObservationError.invalidIdentity
        }
        if let correlation = observation.correlationID,
           !validIdentifier(correlation.rawValue) {
            throw AgentMCPObservationError.invalidCorrelation
        }

        let eventID = AgentEventID(rawValue: "mcp-\(observation.observationID)")
        let common: (AgentEventType, AgentEvidenceAuthority, AgentEventPayload)
        var capabilityEvent: AgentIngestionEvent?

        switch observation.kind {
        case .sessionObserved(let project):
            let safeProject = project.map(safeProject)
            common = (
                .sessionStarted,
                .processObservation,
                .sessionMetadata(AgentSessionMetadata(project: safeProject))
            )
            let observedAt = observation.timestamp
            let capabilities = AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: [
                AgentCapability.sessionLifecycle,
                .planLifecycle,
                .toolLifecycle,
                .commandLifecycle,
                .approvalObservation,
                .tokenUsage,
                .contextUsage,
                .quotaUsage,
                .costUsage,
                .modelMetadata,
                .projectContext,
                .gitMetadata
            ].map {
                ($0, AgentCapabilityEvidence(
                    authority: .processObservation,
                    source: sourceID.rawValue,
                    observedAt: observedAt
                ))
            }))
            capabilityEvent = makeEvent(
                observation,
                eventID: AgentEventID(rawValue: "mcp-\(observation.observationID)-capabilities"),
                type: .capabilitiesUpdated,
                authority: .processObservation,
                payload: .capabilities(capabilities),
                correlationID: nil
            )
        case .activity(let title, let summary):
            common = (.agentWorking, .processObservation, .activity(AgentActivityDescriptor(
                title: safeSummary(title),
                summary: safeSummary(summary)
            )))
        case .planUpdated(let summary):
            common = (.planUpdated, .processObservation, .plan(AgentPlanEvent(
                summary: safeSummary(summary)
            )))
        case .planReady(let summary):
            common = (.planReady, .processObservation, .plan(AgentPlanEvent(
                summary: safeSummary(summary)
            )))
        case .toolStarted(let name, let category, let summary):
            try requireCorrelation(observation.correlationID)
            common = (.toolStarted, .processObservation, .tool(AgentToolEvent(
                name: safeSummary(name).map(AgentPrivacyProjection.toolName),
                category: safeSummary(category),
                summary: safeSummary(summary),
                success: nil
            )))
        case .toolCompleted(let name, let category, let summary, let success):
            try requireCorrelation(observation.correlationID)
            common = (.toolCompleted, .processObservation, .tool(AgentToolEvent(
                name: safeSummary(name).map(AgentPrivacyProjection.toolName),
                category: safeSummary(category),
                summary: safeSummary(summary),
                success: success
            )))
        case .commandStarted(let executable):
            try requireCorrelation(observation.correlationID)
            common = (.commandStarted, .processObservation, .command(AgentCommandEvent(
                executable: AgentPrivacyProjection.commandSummary(executable: executable),
                success: nil,
                exitCode: nil
            )))
        case .commandCompleted(let executable, let success, let exitCode):
            try requireCorrelation(observation.correlationID)
            common = (.commandCompleted, .processObservation, .command(AgentCommandEvent(
                executable: AgentPrivacyProjection.commandSummary(executable: executable),
                success: success,
                exitCode: exitCode
            )))
        case .attention(let summary, let operationCorrelationID, let expiresAt):
            try requireCorrelation(observation.correlationID)
            common = (.approvalRequested, .processObservation, .approvalRequest(AgentApprovalRequest(
                summary: safeSummary(summary),
                operationCorrelationID: operationCorrelationID,
                expiresAt: expiresAt
            )))
        case .project(let project):
            common = (.projectContextUpdated, .processObservation, .projectContext(safeProject(project)))
        case .usage(let usage, let authoritative):
            guard authoritative, !usage.isEmpty,
                  !usage.allSamples.contains(where: { !$0.isValid }) else {
                throw AgentMCPObservationError.unauthoritativeUsage
            }
            common = (.usageUpdated, .structuredTelemetry, .usage(AgentPrivacyProjection.usage(usage)))
        case .heartbeat:
            common = (.heartbeat, .processObservation, .none)
        }

        let event = makeEvent(
            observation,
            eventID: eventID,
            type: common.0,
            authority: common.1,
            payload: common.2,
            correlationID: observation.correlationID
        )
        return [event] + (capabilityEvent.map { [$0] } ?? [])
    }

    private static func makeEvent(
        _ observation: AgentMCPObservation,
        eventID: AgentEventID,
        type: AgentEventType,
        authority: AgentEvidenceAuthority,
        payload: AgentEventPayload,
        correlationID: AgentCorrelationID?
    ) -> AgentIngestionEvent {
        AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: eventID,
            provider: observation.provider,
            source: .mcp,
            nativeSessionID: observation.nativeSessionID,
            assertedGeneration: nil,
            type: type,
            providerTimestamp: observation.timestamp,
            receivedTimestamp: observation.timestamp,
            correlationID: correlationID,
            sequence: nil,
            authority: authority,
            payload: payload,
            continuity: AgentSessionContinuity(immutableIdentity: observation.nativeSessionID)
        )
    }

    private static func safeProject(_ project: AgentProjectContext) -> AgentProjectContext {
        let safe = AgentPrivacyProjection.project(project)
        return AgentProjectContext(
            displayName: safeSummary(safe.displayName),
            workingDirectory: nil,
            repositoryIdentity: safeSummary(safe.repositoryIdentity),
            gitBranch: safeSummary(safe.gitBranch),
            gitCommit: safeSummary(safe.gitCommit),
            model: safeSummary(safe.model),
            sourceApplication: safe.sourceApplication
        )
    }

    private static func safeSummary(_ value: String?) -> String? {
        guard let normalized = AgentPrivacyProjection.summary(value) else { return nil }
        let lower = normalized.lowercased()
        let sensitive = [
            "token=", "secret=", "password=", "authorization:", "bearer ",
            "api_key=", "api-key=", "cookie:", "session_key=", "credential="
        ]
        return sensitive.contains(where: lower.contains) ? nil : normalized
    }

    private static func requireCorrelation(_ correlation: AgentCorrelationID?) throws {
        guard let correlation, validIdentifier(correlation.rawValue) else {
            throw AgentMCPObservationError.invalidCorrelation
        }
    }

    private static func validProvider(_ provider: AgentProvider) -> Bool {
        switch provider {
        case .codex, .claude: true
        case .other(let name): validToken(name)
        }
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            value.utf8.count <= AgentDomainLimits.identifierLength &&
            value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AgentDomainLimits.tokenLength &&
            value.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII &&
                    (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
            }
    }
}
