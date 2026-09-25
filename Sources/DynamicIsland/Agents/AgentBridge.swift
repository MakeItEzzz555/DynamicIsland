import AgentBridgeShared
import Combine
import CoreFoundation
import Darwin
import Foundation

final class AgentBridgeIngress: Sendable {
    private let coordinator: AgentIngestionCoordinator

    init(coordinator: AgentIngestionCoordinator) {
        self.coordinator = coordinator
    }

    func ingest(
        request: AgentBridgeWireRequest,
        producer: AgentProducerHandle,
        receivedAt: Date
    ) async -> Result<AgentBridgeIngestionResult, AgentBridgeEnvelopeError> {
        guard request.protocolVersion == AgentBridgeLimits.protocolVersion else {
            return .failure(.unsupportedProtocol)
        }
        guard request.producerID == producer.authenticatedProducerID,
              Self.validProducerID(producer.authenticatedProducerID),
              let batch = request.eventBatch,
              !batch.isEmpty,
              batch.count <= AgentBridgeLimits.maximumBatchEvents else {
            return .failure(request.eventBatch?.isEmpty == true ? .emptyBatch : .invalidProducer)
        }

        var normalized: [AgentIngestionEvent] = []
        normalized.reserveCapacity(batch.count)
        do {
            for wire in batch {
                normalized.append(try normalize(wire, receivedAt: receivedAt))
            }
        } catch let error as AgentBridgeEnvelopeError {
            return .failure(error)
        } catch {
            return .failure(.malformedEnvelope)
        }

        switch await coordinator.ingestAtomically(normalized, from: producer) {
        case .success(let result):
            return .success(AgentBridgeIngestionResult(
                acceptedEvents: result.acceptedEvents,
                applications: result.applications
            ))
        case .failure(let error):
            return .failure(Self.bridgeError(error))
        }
    }

    private func normalize(
        _ wire: AgentBridgeWireEvent,
        receivedAt: Date
    ) throws -> AgentIngestionEvent {
        let provider = try Self.provider(wire.provider)
        guard let source = AgentSource(rawValue: wire.source) else { throw AgentBridgeEnvelopeError.invalidSource }
        let type = try Self.eventType(wire.eventType)
        let authority = try Self.authority(wire.authority)
        let providerTimestamp: Date?
        if let timestamp = wire.providerTimestamp {
            guard let parsed = Self.date(timestamp) else { throw AgentBridgeEnvelopeError.invalidTimestamp }
            providerTimestamp = parsed
        } else {
            providerTimestamp = nil
        }
        let payload = try Self.payload(wire.payload, for: type, eventAuthority: authority)
        return AgentIngestionEvent(
            schemaVersion: wire.schemaVersion,
            eventID: AgentEventID(rawValue: wire.eventID),
            provider: provider,
            source: source,
            nativeSessionID: wire.nativeSessionID,
            assertedGeneration: wire.sessionGeneration.map(AgentSessionGeneration.init(rawValue:)),
            type: type,
            providerTimestamp: providerTimestamp,
            receivedTimestamp: receivedAt,
            correlationID: wire.correlationID.map(AgentCorrelationID.init(rawValue:)),
            sequence: wire.sequence,
            authority: authority,
            payload: payload,
            continuity: wire.continuityIdentity.map(AgentSessionContinuity.init(immutableIdentity:))
        )
    }

    private static func bridgeError(_ error: AgentIngestionError) -> AgentBridgeEnvelopeError {
        switch error {
        case .unsupportedSchema: .semanticValidation
        case .generationConflict, .identityConflict: .generationConflict
        case .policyViolation: .policyViolation
        case .invalidProducer, .staleProducer: .invalidProducer
        case .invalidEvent: .semanticValidation
        default: .storeRejected
        }
    }

    private static func provider(_ value: String) throws -> AgentProvider {
        switch value {
        case "codex": return .codex
        case "claude": return .claude
        default:
            guard validToken(value) else { throw AgentBridgeEnvelopeError.invalidProvider }
            return .other(value)
        }
    }

    private static func eventType(_ value: String) throws -> AgentEventType {
        let mapped: AgentEventType? = switch value {
        case "sessionStarted": .sessionStarted
        case "sessionResumed": .sessionResumed
        case "sessionMetadataUpdated": .sessionMetadataUpdated
        case "sessionEnded": .sessionEnded
        case "agentWorking": .agentWorking
        case "thinkingStarted": .thinkingStarted
        case "thinkingEnded": .thinkingEnded
        case "planningStarted": .planningStarted
        case "planUpdated": .planUpdated
        case "planReady": .planReady
        case "toolStarted": .toolStarted
        case "toolCompleted": .toolCompleted
        case "commandStarted": .commandStarted
        case "commandCompleted": .commandCompleted
        case "approvalRequested": .approvalRequested
        case "approvalResolved": .approvalResolved
        case "waitingForUser": .waitingForUser
        case "userInputResolved": .userInputResolved
        case "usageUpdated": .usageUpdated
        case "capabilitiesUpdated": .capabilitiesUpdated
        case "projectContextUpdated": .projectContextUpdated
        case "taskCompleted": .taskCompleted
        case "taskFailed": .taskFailed
        case "interrupted": .interrupted
        case "subagentStarted": .subagentStarted
        case "subagentEnded": .subagentEnded
        case "heartbeat": .heartbeat
        default: nil
        }
        guard let mapped else { throw AgentBridgeEnvelopeError.invalidEventType }
        return mapped
    }

    private static func authority(_ value: String) throws -> AgentEvidenceAuthority {
        guard let result = [
            "heuristic": AgentEvidenceAuthority.heuristic,
            "processObservation": .processObservation,
            "localStructuredRecord": .localStructuredRecord,
            "structuredTelemetry": .structuredTelemetry,
            "lifecycle": .lifecycle
        ][value] else {
            throw AgentBridgeEnvelopeError.invalidAuthority
        }
        return result
    }

    private static func payload(
        _ wire: AgentBridgeWirePayload?,
        for type: AgentEventType,
        eventAuthority: AgentEvidenceAuthority
    ) throws -> AgentEventPayload {
        let count = wire?.populatedFieldCount ?? 0
        switch type {
        case .sessionStarted, .sessionMetadataUpdated:
            guard count == 1, let value = wire?.sessionMetadata else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .sessionMetadata(value)
        case .sessionResumed:
            if count == 0 { return .none }
            guard count == 1, let value = wire?.sessionMetadata else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .sessionMetadata(value)
        case .sessionEnded, .thinkingEnded, .userInputResolved, .heartbeat:
            guard count == 0 else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .none
        case .agentWorking, .thinkingStarted, .planningStarted:
            if count == 0 { return .none }
            guard count == 1, let value = wire?.activity else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .activity(value)
        case .planUpdated, .planReady:
            guard count == 1, let value = wire?.plan else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .plan(value)
        case .toolStarted, .toolCompleted:
            guard count == 1, let value = wire?.tool else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .tool(value)
        case .commandStarted, .commandCompleted:
            guard count == 1, let value = wire?.command else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .command(value)
        case .approvalRequested:
            guard count == 1, let value = wire?.approvalRequest else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .approvalRequest(value)
        case .approvalResolved:
            guard count == 1, let value = wire?.approvalResolution else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .approvalResolution(value)
        case .waitingForUser:
            guard count == 1, let value = wire?.userInput else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .userInput(value)
        case .usageUpdated:
            guard count == 1, let samples = wire?.usage else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .usage(try usage(samples))
        case .capabilitiesUpdated:
            guard count == 1, let values = wire?.capabilities else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .capabilities(try capabilities(values, eventAuthority: eventAuthority))
        case .projectContextUpdated:
            guard count == 1, let value = wire?.projectContext else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .projectContext(value)
        case .taskCompleted, .taskFailed, .interrupted:
            guard count == 1, let value = wire?.terminal else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .terminal(value)
        case .subagentStarted, .subagentEnded:
            guard count == 1, let value = wire?.subagent else { throw AgentBridgeEnvelopeError.invalidPayload }
            return .subagent(value)
        case .unsupported:
            throw AgentBridgeEnvelopeError.invalidEventType
        }
    }

    private static func usage(_ values: [AgentBridgeWireUsageSample]) throws -> AgentUsage {
        var samples: [AgentUsageMetric: AgentUsageSample] = [:]
        for value in values {
            guard let metric = AgentUsageMetric(rawValue: value.metric),
                  let unit = AgentUsageUnit(rawValue: value.unit),
                  let observedAt = date(value.observedAt),
                  samples[metric] == nil else {
                throw AgentBridgeEnvelopeError.invalidUsage
            }
            samples[metric] = AgentUsageSample(
                value: value.value,
                limit: value.limit,
                unit: unit,
                scope: value.scope,
                source: value.source,
                observedAt: observedAt
            )
        }
        return AgentUsage(samples: samples)
    }

    private static func capabilities(
        _ values: [AgentBridgeWireCapability],
        eventAuthority: AgentEvidenceAuthority
    ) throws -> AgentCapabilities {
        var evidence: [AgentCapability: AgentCapabilityEvidence] = [:]
        for value in values {
            guard let capability = AgentCapability(rawValue: value.name),
                  capability != .approvalControl,
                  let capabilityAuthority = try? authority(value.authority),
                  capabilityAuthority <= eventAuthority,
                  let observedAt = date(value.observedAt),
                  evidence[capability] == nil else {
                throw AgentBridgeEnvelopeError.invalidCapability
            }
            evidence[capability] = AgentCapabilityEvidence(
                authority: capabilityAuthority,
                source: value.source,
                observedAt: observedAt
            )
        }
        return AgentCapabilities(evidence: evidence)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func validProducerID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AgentDomainLimits.identifierLength &&
            value.unicodeScalars.allSatisfy { !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0) }
    }

    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AgentDomainLimits.tokenLength && value.unicodeScalars.allSatisfy {
            $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0))
        }
    }
}

actor AgentBridgeRequestProcessor {
    private let authenticator: AgentBridgeAuthenticator
    private let ingress: AgentBridgeIngress
    private let producer: AgentProducerHandle
    private let eventsRoute: String
    private let allowsHealth: Bool
    private let now: @Sendable () -> Date

    init(
        authenticator: AgentBridgeAuthenticator,
        ingress: AgentBridgeIngress,
        producer: AgentProducerHandle,
        eventsRoute: String = AgentBridgeProtocol.eventsRoute,
        allowsHealth: Bool = true,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authenticator = authenticator
        self.ingress = ingress
        self.producer = producer
        self.eventsRoute = eventsRoute
        self.allowsHealth = allowsHealth
        self.now = now
    }

    func handle(_ request: AgentBridgeHTTPRequest) async -> AgentBridgeHTTPResponse {
        // Authenticate the exact method and route before dispatch so mutations of
        // either canonical field cannot be reinterpreted as a different request.
        if let authenticationError = await authenticator.authenticate(request) {
            let status: AgentBridgeHTTPStatus = switch authenticationError {
            case .replay: .conflict
            case .replayCacheFull: .tooManyRequests
            default: .unauthorized
            }
            return AgentBridgeHTTPResponse(status: status, code: "authentication")
        }
        guard request.route == eventsRoute ||
                (allowsHealth && request.route == AgentBridgeProtocol.healthRoute) else {
            return AgentBridgeHTTPResponse(status: .notFound, code: "unknown-route")
        }
        if request.route == eventsRoute, request.method != "POST" {
            return AgentBridgeHTTPResponse(status: .methodNotAllowed, code: "method-not-allowed")
        }
        if request.route == AgentBridgeProtocol.healthRoute, request.method != "GET" {
            return AgentBridgeHTTPResponse(status: .methodNotAllowed, code: "method-not-allowed")
        }
        if request.route == eventsRoute {
            guard let contentType = request.headers["content-type"],
                  contentType.lowercased().split(separator: ";", maxSplits: 1).first == "application/json" else {
                return AgentBridgeHTTPResponse(status: .unsupportedMediaType, code: "content-type")
            }
        }
        if request.route == AgentBridgeProtocol.healthRoute {
            guard request.body.isEmpty else {
                return AgentBridgeHTTPResponse(status: .badRequest, code: "health-body")
            }
            return AgentBridgeHTTPResponse(status: .ok, code: "healthy")
        }

        do {
            let wire = try AgentBridgeEnvelopeDecoder.decode(request.body)
            let result = await ingress.ingest(
                request: wire,
                producer: producer,
                receivedAt: now()
            )
            switch result {
            case .success:
                return AgentBridgeHTTPResponse(status: .accepted, code: "accepted")
            case .failure(let error):
                let status: AgentBridgeHTTPStatus = error == .unsupportedProtocol ? .badRequest : .unprocessableContent
                return AgentBridgeHTTPResponse(status: status, code: error.rawValue)
            }
        } catch let error as AgentBridgeEnvelopeError {
            let status: AgentBridgeHTTPStatus = switch error {
            case .eventTooLarge: .payloadTooLarge
            case .tooManyEvents: .payloadTooLarge
            case .unsupportedProtocol: .badRequest
            default: .badRequest
            }
            return AgentBridgeHTTPResponse(status: status, code: error.rawValue)
        } catch {
            return AgentBridgeHTTPResponse(status: .badRequest, code: "malformed-envelope")
        }
    }
}

typealias AgentBridgeServerFactory = @Sendable (
    @escaping AgentBridgeNetworkServer.RequestHandler
) -> any AgentBridgeServing

enum AgentBridgeEnvelopeDecoder {
    static func decode(_ data: Data) throws -> AgentBridgeWireRequest {
        guard !data.isEmpty else { throw AgentBridgeEnvelopeError.malformedEnvelope }
        guard data.count <= AgentBridgeLimits.maximumRequestBodyBytes else {
            throw AgentBridgeEnvelopeError.eventTooLarge
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw AgentBridgeEnvelopeError.malformedEnvelope
        }
        let object = try JSONSerialization.jsonObject(with: data)
        try validateJSON(object, depth: 1)
        guard let root = object as? [String: Any] else { throw AgentBridgeEnvelopeError.malformedEnvelope }
        guard let protocolNumber = root["protocolVersion"] as? NSNumber,
              CFGetTypeID(protocolNumber) != CFBooleanGetTypeID(),
              protocolNumber.intValue == AgentBridgeLimits.protocolVersion else {
            throw AgentBridgeEnvelopeError.unsupportedProtocol
        }
        let rawEvents: [Any]
        if let event = root["event"], root["events"] == nil {
            guard data.count <= AgentBridgeLimits.maximumSingleEventBodyBytes else {
                throw AgentBridgeEnvelopeError.eventTooLarge
            }
            rawEvents = [event]
        } else if let events = root["events"] as? [Any], root["event"] == nil {
            guard !events.isEmpty else { throw AgentBridgeEnvelopeError.emptyBatch }
            guard events.count <= AgentBridgeLimits.maximumBatchEvents else {
                throw AgentBridgeEnvelopeError.tooManyEvents
            }
            rawEvents = events
        } else {
            throw AgentBridgeEnvelopeError.malformedEnvelope
        }
        for event in rawEvents {
            let encoded = try JSONSerialization.data(withJSONObject: event)
            guard encoded.count <= AgentBridgeLimits.maximumSingleEventBodyBytes else {
                throw AgentBridgeEnvelopeError.eventTooLarge
            }
        }
        do {
            return try JSONDecoder().decode(AgentBridgeWireRequest.self, from: data)
        } catch {
            throw AgentBridgeEnvelopeError.malformedEnvelope
        }
    }

    private static func validateJSON(_ value: Any, depth: Int) throws {
        guard depth <= AgentBridgeLimits.maximumJSONDepth else {
            throw AgentBridgeEnvelopeError.malformedEnvelope
        }
        if let object = value as? [String: Any] {
            guard object.count <= 128 else { throw AgentBridgeEnvelopeError.malformedEnvelope }
            for child in object.values { try validateJSON(child, depth: depth + 1) }
        } else if let array = value as? [Any] {
            guard array.count <= 256 else { throw AgentBridgeEnvelopeError.malformedEnvelope }
            for child in array { try validateJSON(child, depth: depth + 1) }
        }
    }
}

@MainActor
final class AgentBridge: ObservableObject {
    @Published private(set) var health = AgentBridgeHealth()

    private let credentialStore: any AgentBridgeCredentialStore
    private let discoveryPublisher: (any AgentBridgeDiscoveryPublishing)?
    private let codexDiscoveryPublisher: (any AgentBridgeDiscoveryPublishing)?
    private let claudeDiscoveryPublisher: (any AgentBridgeDiscoveryPublishing)?
    private let coordinator: AgentIngestionCoordinator
    private let ingress: AgentBridgeIngress
    private let serverFactory: AgentBridgeServerFactory
    private var runtime: Runtime?
    private var startAttemptID: UUID?

    private struct ProducerRuntime {
        let launchID: String
        let producer: AgentProducerHandle
        let authenticator: AgentBridgeAuthenticator
    }

    private struct Runtime {
        let generic: ProducerRuntime
        let codex: ProducerRuntime
        let claude: ProducerRuntime
        let server: any AgentBridgeServing
    }

    private struct LaunchMaterial: Sendable {
        let genericLaunchID: String
        let genericKey: Data
        let codexLaunchID: String
        let codexKey: Data
        let claudeLaunchID: String
        let claudeKey: Data
    }

    init(
        coordinator: AgentIngestionCoordinator,
        credentialStore: any AgentBridgeCredentialStore = SystemAgentBridgeCredentialStore(),
        discoveryPublisher: (any AgentBridgeDiscoveryPublishing)? = nil,
        serverFactory: @escaping AgentBridgeServerFactory = {
            AgentBridgeNetworkServer(requestHandler: $0)
        }
    ) {
        self.credentialStore = credentialStore
        let resolvedDiscovery: (any AgentBridgeDiscoveryPublishing)?
        if let discoveryPublisher {
            resolvedDiscovery = discoveryPublisher
        } else {
            resolvedDiscovery = try? AgentBridgeDiscoveryPublisher()
        }
        self.discoveryPublisher = resolvedDiscovery
        if let baseURL = resolvedDiscovery?.recordURL.deletingLastPathComponent() {
            self.codexDiscoveryPublisher = try? AgentBridgeDiscoveryPublisher(
                recordURL: baseURL.appendingPathComponent("codex-hook-v1.json")
            )
            self.claudeDiscoveryPublisher = try? AgentBridgeDiscoveryPublisher(
                recordURL: baseURL.appendingPathComponent("claude-hook-v1.json")
            )
        } else {
            self.codexDiscoveryPublisher = nil
            self.claudeDiscoveryPublisher = nil
        }
        self.coordinator = coordinator
        ingress = AgentBridgeIngress(coordinator: coordinator)
        self.serverFactory = serverFactory
    }

    convenience init(
        eventStore: AgentEventStore,
        credentialStore: any AgentBridgeCredentialStore = SystemAgentBridgeCredentialStore(),
        discoveryPublisher: (any AgentBridgeDiscoveryPublishing)? = nil,
        serverFactory: @escaping AgentBridgeServerFactory = {
            AgentBridgeNetworkServer(requestHandler: $0)
        }
    ) {
        self.init(
            coordinator: AgentIngestionCoordinator(eventStore: eventStore),
            credentialStore: credentialStore,
            discoveryPublisher: discoveryPublisher,
            serverFactory: serverFactory
        )
    }

    func start() async {
        guard runtime == nil, startAttemptID == nil,
              health.state == .stopped || health.state == .failed else { return }
        let attemptID = UUID()
        startAttemptID = attemptID
        health.state = .starting
        health.lastSafeError = nil

        do {
            guard let discoveryPublisher, let codexDiscoveryPublisher, let claudeDiscoveryPublisher else {
                throw AgentBridgeDiscoveryError.unavailableDirectory
            }
            let credentialStore = credentialStore
            let material = try await Task.detached(priority: .utility) {
                let installationSecret = try credentialStore.installationSecret()
                guard installationSecret.count == AgentBridgeLimits.installationSecretBytes else {
                    throw AgentBridgeCredentialError.invalidStoredSecret
                }
                let genericLaunchID = UUID().uuidString.lowercased()
                let codexLaunchID = "codex-" + UUID().uuidString.lowercased()
                let claudeLaunchID = "claude-" + UUID().uuidString.lowercased()
                let genericNonce = try AgentBridgeCrypto.randomBytes(count: AgentBridgeLimits.launchKeyBytes)
                let codexNonce = try AgentBridgeCrypto.randomBytes(count: AgentBridgeLimits.launchKeyBytes)
                let claudeNonce = try AgentBridgeCrypto.randomBytes(count: AgentBridgeLimits.launchKeyBytes)
                return LaunchMaterial(
                    genericLaunchID: genericLaunchID,
                    genericKey: AgentBridgeCrypto.launchKey(
                        installationSecret: installationSecret,
                        launchID: genericLaunchID,
                        launchNonce: genericNonce
                    ),
                    codexLaunchID: codexLaunchID,
                    codexKey: AgentBridgeCrypto.launchKey(
                        installationSecret: installationSecret,
                        launchID: codexLaunchID,
                        launchNonce: codexNonce
                    ),
                    claudeLaunchID: claudeLaunchID,
                    claudeKey: AgentBridgeCrypto.launchKey(
                        installationSecret: installationSecret,
                        launchID: claudeLaunchID,
                        launchNonce: claudeNonce
                    )
                )
            }.value
            guard startAttemptID == attemptID else { return }

            let genericRegistration = await coordinator.registerProducer(
                descriptor: AgentProducerDescriptor(
                    sourceInstanceID: AgentSourceInstanceID(rawValue: "dynamic-island.generic-bridge"),
                    sourceKind: .authenticatedBridge,
                    runtimeVersion: "bridge-v1"
                ),
                policy: .genericAuthenticatedBridge,
                authenticatedProducerID: material.genericLaunchID
            )
            guard case .success(let genericProducer) = genericRegistration else {
                throw AgentIngestionError.invalidProducer
            }

            let codexRegistration = await coordinator.registerProducer(
                descriptor: AgentProducerDescriptor(
                    sourceInstanceID: AgentSourceInstanceID(rawValue: "dynamic-island.codex-hook"),
                    sourceKind: .officialHook,
                    runtimeVersion: "codex-hooks-v1"
                ),
                policy: .codexOfficialHook,
                authenticatedProducerID: material.codexLaunchID
            )
            guard case .success(let codexProducer) = codexRegistration else {
                _ = await coordinator.unregisterProducer(genericProducer)
                throw AgentIngestionError.invalidProducer
            }

            let claudeRegistration = await coordinator.registerProducer(
                descriptor: AgentProducerDescriptor(
                    sourceInstanceID: AgentSourceInstanceID(rawValue: "dynamic-island.claude-hook"),
                    sourceKind: .officialHook,
                    runtimeVersion: "claude-hooks-v1"
                ),
                policy: .claudeOfficialHook,
                authenticatedProducerID: material.claudeLaunchID
            )
            guard case .success(let claudeProducer) = claudeRegistration else {
                _ = await coordinator.unregisterProducer(genericProducer)
                _ = await coordinator.unregisterProducer(codexProducer)
                throw AgentIngestionError.invalidProducer
            }

            let genericAuthenticator = AgentBridgeAuthenticator(keyData: material.genericKey)
            let codexAuthenticator = AgentBridgeAuthenticator(keyData: material.codexKey)
            let claudeAuthenticator = AgentBridgeAuthenticator(keyData: material.claudeKey)
            let genericProcessor = AgentBridgeRequestProcessor(
                authenticator: genericAuthenticator,
                ingress: ingress,
                producer: genericProducer
            )
            let codexProcessor = AgentBridgeRequestProcessor(
                authenticator: codexAuthenticator,
                ingress: ingress,
                producer: codexProducer,
                eventsRoute: AgentBridgeProtocol.codexHookEventsRoute,
                allowsHealth: false
            )
            let claudeProcessor = AgentBridgeRequestProcessor(
                authenticator: claudeAuthenticator,
                ingress: ingress,
                producer: claudeProducer,
                eventsRoute: AgentBridgeProtocol.claudeHookEventsRoute,
                allowsHealth: false
            )
            let server = serverFactory { [weak self] request in
                let response: AgentBridgeHTTPResponse
                switch request.route {
                case AgentBridgeProtocol.eventsRoute, AgentBridgeProtocol.healthRoute:
                    response = await genericProcessor.handle(request)
                case AgentBridgeProtocol.codexHookEventsRoute:
                    response = await codexProcessor.handle(request)
                case AgentBridgeProtocol.claudeHookEventsRoute:
                    response = await claudeProcessor.handle(request)
                default:
                    response = AgentBridgeHTTPResponse(status: .notFound, code: "unknown-route")
                }
                await self?.record(response, launchID: material.genericLaunchID)
                return response
            }

            runtime = Runtime(
                generic: ProducerRuntime(
                    launchID: material.genericLaunchID,
                    producer: genericProducer,
                    authenticator: genericAuthenticator
                ),
                codex: ProducerRuntime(
                    launchID: material.codexLaunchID,
                    producer: codexProducer,
                    authenticator: codexAuthenticator
                ),
                claude: ProducerRuntime(
                    launchID: material.claudeLaunchID,
                    producer: claudeProducer,
                    authenticator: claudeAuthenticator
                ),
                server: server
            )

            let port = try await withCheckedThrowingContinuation { continuation in
                server.start { result in continuation.resume(with: result) }
            }
            guard startAttemptID == attemptID, runtime?.generic.launchID == material.genericLaunchID else {
                return
            }

            try discoveryPublisher.publish(AgentBridgeDiscoveryRecord(
                protocolVersion: AgentBridgeLimits.protocolVersion,
                host: "127.0.0.1",
                port: port,
                launchID: material.genericLaunchID,
                producerID: material.genericLaunchID,
                authenticationToken: material.genericKey.base64EncodedString(),
                processID: getpid(),
                createdAt: Date()
            ))
            try codexDiscoveryPublisher.publish(AgentBridgeDiscoveryRecord(
                protocolVersion: AgentBridgeLimits.protocolVersion,
                host: "127.0.0.1",
                port: port,
                launchID: material.codexLaunchID,
                producerID: material.codexLaunchID,
                authenticationToken: material.codexKey.base64EncodedString(),
                eventsRoute: AgentBridgeProtocol.codexHookEventsRoute,
                processID: getpid(),
                createdAt: Date()
            ))
            try claudeDiscoveryPublisher.publish(AgentBridgeDiscoveryRecord(
                protocolVersion: AgentBridgeLimits.protocolVersion,
                host: "127.0.0.1",
                port: port,
                launchID: material.claudeLaunchID,
                producerID: material.claudeLaunchID,
                authenticationToken: material.claudeKey.base64EncodedString(),
                eventsRoute: AgentBridgeProtocol.claudeHookEventsRoute,
                processID: getpid(),
                createdAt: Date()
            ))

            guard startAttemptID == attemptID, runtime?.generic.launchID == material.genericLaunchID else {
                try? discoveryPublisher.removeIfOwned(launchID: material.genericLaunchID)
                try? codexDiscoveryPublisher.removeIfOwned(launchID: material.codexLaunchID)
                try? claudeDiscoveryPublisher.removeIfOwned(launchID: material.claudeLaunchID)
                return
            }
            startAttemptID = nil
            health.state = .running
            health.port = port
        } catch {
            guard startAttemptID == attemptID else { return }
            startAttemptID = nil
            stopRuntime()
            health.state = .failed
            health.lastSafeError = Self.safeError(error)
        }
    }

    func stop() {
        startAttemptID = nil
        stopRuntime()
        health.state = .stopped
        health.port = nil
    }

    private func stopRuntime() {
        guard let runtime else { return }
        self.runtime = nil
        runtime.server.stop()
        Task {
            _ = await coordinator.unregisterProducer(runtime.generic.producer)
            _ = await coordinator.unregisterProducer(runtime.codex.producer)
            _ = await coordinator.unregisterProducer(runtime.claude.producer)
        }
        Task {
            await runtime.generic.authenticator.invalidate()
            await runtime.codex.authenticator.invalidate()
            await runtime.claude.authenticator.invalidate()
        }
        try? discoveryPublisher?.removeIfOwned(launchID: runtime.generic.launchID)
        try? codexDiscoveryPublisher?.removeIfOwned(launchID: runtime.codex.launchID)
        try? claudeDiscoveryPublisher?.removeIfOwned(launchID: runtime.claude.launchID)
    }

    private func record(_ response: AgentBridgeHTTPResponse, launchID: String) {
        guard runtime?.generic.launchID == launchID else { return }
        if response.status.rawValue < 400 {
            health.acceptedRequestCount &+= 1
        } else {
            health.rejectedRequestCount &+= 1
            health.lastSafeError = response.code
        }
    }

    private static func safeError(_ error: Error) -> String {
        switch error {
        case is AgentBridgeCredentialError: "credential-unavailable"
        case is AgentBridgeDiscoveryError: "discovery-unavailable"
        case is AgentBridgeNetworkError: "listener-unavailable"
        default: "bridge-unavailable"
        }
    }
}
