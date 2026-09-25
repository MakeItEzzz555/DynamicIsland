import Foundation
import XCTest
@testable import DynamicIsland

enum AgentIngestionTestSupport {
    static let now = Date(timeIntervalSince1970: 2_100_000_000)

    static func policy(
        providers: Set<AgentProvider>? = nil,
        sources: Set<AgentSource>? = nil,
        kinds: Set<AgentSourceKind>,
        allowedTypes: Set<AgentEventType> = allEventTypes,
        ceiling: AgentEvidenceAuthority = .lifecycle,
        capabilities: Set<AgentCapability> = Set(AgentCapability.allCases).subtracting([.approvalControl])
    ) -> AgentProducerPolicy {
        AgentProducerPolicy(
            allowedProviders: providers,
            allowedSources: sources,
            allowedSourceKinds: kinds,
            allowedEventTypes: allowedTypes,
            authorityCeilings: Dictionary(uniqueKeysWithValues: AgentAuthorityDomain.allCases.map { ($0, ceiling) }),
            allowedCapabilities: capabilities,
            allowedSchemaVersions: [AgentEvent.normalizedSchemaVersion]
        )
    }

    static let allEventTypes: Set<AgentEventType> = [
        .sessionStarted, .sessionResumed, .sessionMetadataUpdated, .sessionEnded,
        .agentWorking, .thinkingStarted, .thinkingEnded, .planningStarted, .planUpdated, .planReady,
        .toolStarted, .toolCompleted, .commandStarted, .commandCompleted,
        .approvalRequested, .approvalResolved, .waitingForUser, .userInputResolved,
        .usageUpdated, .capabilitiesUpdated, .projectContextUpdated,
        .taskCompleted, .taskFailed, .interrupted, .subagentStarted, .subagentEnded, .heartbeat
    ]

    static func descriptor(
        _ id: String,
        kind: AgentSourceKind = .officialLifecycleProtocol
    ) -> AgentProducerDescriptor {
        AgentProducerDescriptor(
            sourceInstanceID: AgentSourceInstanceID(rawValue: id),
            sourceKind: kind,
            runtimeVersion: "test-1"
        )
    }

    static func event(
        _ id: String,
        provider: AgentProvider = .codex,
        source: AgentSource = .terminal,
        nativeID: String = "session",
        generation: UInt64? = nil,
        type: AgentEventType = .sessionStarted,
        authority: AgentEvidenceAuthority = .lifecycle,
        payload: AgentEventPayload? = nil,
        continuity: String? = nil,
        offset: TimeInterval = 0
    ) -> AgentIngestionEvent {
        AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: AgentEventID(rawValue: id),
            provider: provider,
            source: source,
            nativeSessionID: nativeID,
            assertedGeneration: generation.map(AgentSessionGeneration.init(rawValue:)),
            type: type,
            providerTimestamp: nil,
            receivedTimestamp: now.addingTimeInterval(offset),
            correlationID: correlation(for: type),
            sequence: nil,
            authority: authority,
            payload: payload ?? defaultPayload(for: type),
            continuity: continuity.map(AgentSessionContinuity.init(immutableIdentity:))
        )
    }

    static func registered(
        coordinator: AgentIngestionCoordinator,
        id: String,
        kind: AgentSourceKind = .officialLifecycleProtocol,
        policy: AgentProducerPolicy? = nil
    ) async throws -> AgentProducerHandle {
        let result = await coordinator.registerProducer(
            descriptor: descriptor(id, kind: kind),
            policy: policy ?? self.policy(kinds: [kind]),
            authenticatedProducerID: "auth-\(id)"
        )
        switch result {
        case .success(let handle): return handle
        case .failure(let error): throw error
        }
    }

    static func capabilities(
        _ values: Set<AgentCapability>,
        authority: AgentEvidenceAuthority = .lifecycle,
        source: String = "test"
    ) -> AgentCapabilities {
        AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: values.map {
            ($0, AgentCapabilityEvidence(authority: authority, source: source, observedAt: now))
        }))
    }

    private static func correlation(for type: AgentEventType) -> AgentCorrelationID? {
        switch type {
        case .toolStarted, .toolCompleted, .commandStarted, .commandCompleted,
             .approvalRequested, .approvalResolved, .waitingForUser, .userInputResolved:
            AgentCorrelationID(rawValue: "correlation")
        default:
            nil
        }
    }

    private static func defaultPayload(for type: AgentEventType) -> AgentEventPayload {
        switch type {
        case .sessionStarted, .sessionMetadataUpdated:
            .sessionMetadata(AgentSessionMetadata(project: nil))
        case .sessionResumed, .sessionEnded, .thinkingEnded, .userInputResolved, .heartbeat:
            .none
        case .agentWorking, .thinkingStarted, .planningStarted:
            .activity(AgentActivityDescriptor(title: nil, summary: nil))
        case .planUpdated, .planReady:
            .plan(AgentPlanEvent(summary: "plan"))
        case .toolStarted, .toolCompleted:
            .tool(AgentToolEvent(name: "tool", category: nil, summary: nil, success: type == .toolCompleted))
        case .commandStarted, .commandCompleted:
            .command(AgentCommandEvent(executable: "swift", success: type == .commandCompleted, exitCode: nil))
        case .approvalRequested:
            .approvalRequest(AgentApprovalRequest(summary: "approval", operationCorrelationID: nil, expiresAt: nil))
        case .approvalResolved:
            .approvalResolution(AgentApprovalResolution(state: .approved))
        case .waitingForUser:
            .userInput(AgentUserInputEvent(summary: "input"))
        case .usageUpdated:
            .usage(AgentUsage())
        case .capabilitiesUpdated:
            .capabilities(AgentCapabilities())
        case .projectContextUpdated:
            .projectContext(AgentProjectContext(displayName: "Project"))
        case .taskCompleted, .taskFailed, .interrupted:
            .terminal(AgentTerminalEvent(summary: "terminal"))
        case .subagentStarted, .subagentEnded:
            .subagent(AgentSubagentEvent(nativeID: "subagent", displayName: nil))
        case .unsupported:
            .unsupported("unsupported")
        }
    }
}
