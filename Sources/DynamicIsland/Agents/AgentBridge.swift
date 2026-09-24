import Combine
import CoreFoundation
import Darwin
import Foundation

private struct AgentBridgeGenerationEntry: Sendable {
    let producerID: String
    let generation: AgentSessionGeneration
}

@MainActor
final class AgentBridgeIngress {
    private let store: AgentEventStore
    private var activeLaunchID: String?
    private var generations: [AgentSessionID: AgentBridgeGenerationEntry] = [:]

    init(store: AgentEventStore) {
        self.store = store
    }

    func activate(launchID: String) {
        activeLaunchID = launchID
        generations.removeAll(keepingCapacity: false)
    }

    func deactivate(launchID: String) {
        guard activeLaunchID == launchID else { return }
        activeLaunchID = nil
        generations.removeAll(keepingCapacity: false)
    }

    func ingest(
        request: AgentBridgeWireRequest,
        launchID: String,
        receivedAt: Date
    ) -> Result<AgentBridgeIngestionResult, AgentBridgeEnvelopeError> {
        guard activeLaunchID == launchID else { return .failure(.storeRejected) }
        guard request.protocolVersion == AgentBridgeLimits.protocolVersion else {
            return .failure(.unsupportedProtocol)
        }
        guard Self.validProducerID(request.producerID),
              let batch = request.eventBatch,
              !batch.isEmpty,
              batch.count <= AgentBridgeLimits.maximumBatchEvents else {
            return .failure(request.eventBatch?.isEmpty == true ? .emptyBatch : .invalidProducer)
        }

        var proposedGenerations = generations
        var normalized: [AgentEvent] = []
        normalized.reserveCapacity(batch.count)
        do {
            for wire in batch {
                let event = try normalize(
                    wire,
                    producerID: request.producerID,
                    receivedAt: receivedAt,
                    generations: &proposedGenerations
                )
                if event.validationError() != nil { return .failure(.semanticValidation) }
                normalized.append(event)
            }
        } catch let error as AgentBridgeEnvelopeError {
            return .failure(error)
        } catch {
            return .failure(.malformedEnvelope)
        }

        switch store.ingestAtomically(normalized) {
        case .applied(let applications):
            generations = proposedGenerations
            return .success(AgentBridgeIngestionResult(
                acceptedEvents: normalized.count,
                applications: applications
            ))
        case .rejected:
            return .failure(.storeRejected)
        }
    }

    private func normalize(
        _ wire: AgentBridgeWireEvent,
        producerID: String,
        receivedAt: Date,
        generations: inout [AgentSessionID: AgentBridgeGenerationEntry]
    ) throws -> AgentEvent {
        let provider = try Self.provider(wire.provider)
        guard let source = AgentSource(rawValue: wire.source) else { throw AgentBridgeEnvelopeError.invalidSource }
        let sessionID = AgentSessionID(provider: provider, nativeID: wire.nativeSessionID)
        let type = try Self.eventType(wire.eventType)
        let authority = try Self.authority(wire.authority)
        let generation = try Self.resolveGeneration(
            sessionID: sessionID,
            producerID: producerID,
            supplied: wire.sessionGeneration,
            isStart: type == .sessionStarted,
            generations: &generations
        )
        let providerTimestamp: Date?
        if let timestamp = wire.providerTimestamp {
            guard let parsed = Self.date(timestamp) else { throw AgentBridgeEnvelopeError.invalidTimestamp }
            providerTimestamp = parsed
        } else {
            providerTimestamp = nil
        }
        let payload = try Self.payload(wire.payload, for: type, eventAuthority: authority)
        return AgentEvent(
            schemaVersion: wire.schemaVersion,
            eventID: AgentEventID(rawValue: wire.eventID),
            sessionID: sessionID,
            generation: generation,
            source: source,
            type: type,
            providerTimestamp: providerTimestamp,
            receivedTimestamp: receivedAt,
            correlationID: wire.correlationID.map(AgentCorrelationID.init(rawValue:)),
            sequence: wire.sequence,
            authority: authority,
            origin: .live,
            payload: payload
        )
    }

    private static func resolveGeneration(
        sessionID: AgentSessionID,
        producerID: String,
        supplied: UInt64?,
        isStart: Bool,
        generations: inout [AgentSessionID: AgentBridgeGenerationEntry]
    ) throws -> AgentSessionGeneration {
        let resolved: AgentSessionGeneration
        if let current = generations[sessionID] {
            if current.producerID == producerID {
                resolved = current.generation
            } else {
                guard isStart, current.generation.rawValue < UInt64.max else {
                    throw AgentBridgeEnvelopeError.generationConflict
                }
                resolved = AgentSessionGeneration(rawValue: current.generation.rawValue + 1)
                generations[sessionID] = AgentBridgeGenerationEntry(
                    producerID: producerID,
                    generation: resolved
                )
            }
        } else {
            guard isStart else { throw AgentBridgeEnvelopeError.generationConflict }
            resolved = AgentSessionGeneration(rawValue: 1)
            generations[sessionID] = AgentBridgeGenerationEntry(
                producerID: producerID,
                generation: resolved
            )
        }
        if let supplied, supplied != resolved.rawValue {
            throw AgentBridgeEnvelopeError.generationConflict
        }
        return resolved
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
    private let launchID: String
    private let now: @Sendable () -> Date

    init(
        authenticator: AgentBridgeAuthenticator,
        ingress: AgentBridgeIngress,
        launchID: String,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.authenticator = authenticator
        self.ingress = ingress
        self.launchID = launchID
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
        guard request.route == "/v1/events" || request.route == "/v1/health" else {
            return AgentBridgeHTTPResponse(status: .notFound, code: "unknown-route")
        }
        if request.route == "/v1/events", request.method != "POST" {
            return AgentBridgeHTTPResponse(status: .methodNotAllowed, code: "method-not-allowed")
        }
        if request.route == "/v1/health", request.method != "GET" {
            return AgentBridgeHTTPResponse(status: .methodNotAllowed, code: "method-not-allowed")
        }
        if request.route == "/v1/events" {
            guard let contentType = request.headers["content-type"],
                  contentType.lowercased().split(separator: ";", maxSplits: 1).first == "application/json" else {
                return AgentBridgeHTTPResponse(status: .unsupportedMediaType, code: "content-type")
            }
        }
        if request.route == "/v1/health" {
            guard request.body.isEmpty else {
                return AgentBridgeHTTPResponse(status: .badRequest, code: "health-body")
            }
            return AgentBridgeHTTPResponse(status: .ok, code: "healthy")
        }

        do {
            let wire = try AgentBridgeEnvelopeDecoder.decode(request.body)
            let result = await ingress.ingest(request: wire, launchID: launchID, receivedAt: now())
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
    private let ingress: AgentBridgeIngress
    private let serverFactory: AgentBridgeServerFactory
    private var runtime: Runtime?
    private var startAttemptID: UUID?

    private struct Runtime {
        let launchID: String
        let authenticator: AgentBridgeAuthenticator
        let server: any AgentBridgeServing
    }

    init(
        eventStore: AgentEventStore,
        credentialStore: any AgentBridgeCredentialStore = SystemAgentBridgeCredentialStore(),
        discoveryPublisher: (any AgentBridgeDiscoveryPublishing)? = nil,
        serverFactory: @escaping AgentBridgeServerFactory = {
            AgentBridgeNetworkServer(requestHandler: $0)
        }
    ) {
        self.credentialStore = credentialStore
        if let discoveryPublisher {
            self.discoveryPublisher = discoveryPublisher
        } else {
            self.discoveryPublisher = try? AgentBridgeDiscoveryPublisher()
        }
        ingress = AgentBridgeIngress(store: eventStore)
        self.serverFactory = serverFactory
    }

    func start() async {
        guard runtime == nil, startAttemptID == nil,
              health.state == .stopped || health.state == .failed else { return }
        let attemptID = UUID()
        startAttemptID = attemptID
        health.state = .starting
        health.lastSafeError = nil
        do {
            guard let discoveryPublisher else {
                throw AgentBridgeDiscoveryError.unavailableDirectory
            }
            let credentialStore = credentialStore
            let material = try await Task.detached(priority: .utility) {
                let installationSecret = try credentialStore.installationSecret()
                guard installationSecret.count == AgentBridgeLimits.installationSecretBytes else {
                    throw AgentBridgeCredentialError.invalidStoredSecret
                }
                let launchID = UUID().uuidString.lowercased()
                let nonce = try AgentBridgeCrypto.randomBytes(count: AgentBridgeLimits.launchKeyBytes)
                let key = AgentBridgeCrypto.launchKey(
                    installationSecret: installationSecret,
                    launchID: launchID,
                    launchNonce: nonce
                )
                return (launchID, key)
            }.value
            guard startAttemptID == attemptID else { return }

            let launchID = material.0
            let authenticator = AgentBridgeAuthenticator(keyData: material.1)
            ingress.activate(launchID: launchID)
            let processor = AgentBridgeRequestProcessor(
                authenticator: authenticator,
                ingress: ingress,
                launchID: launchID
            )
            let server = serverFactory { [weak self] request in
                let response = await processor.handle(request)
                await self?.record(response, launchID: launchID)
                return response
            }
            runtime = Runtime(launchID: launchID, authenticator: authenticator, server: server)
            let port = try await withCheckedThrowingContinuation { continuation in
                server.start { result in continuation.resume(with: result) }
            }
            guard startAttemptID == attemptID, runtime?.launchID == launchID else { return }
            let record = AgentBridgeDiscoveryRecord(
                protocolVersion: AgentBridgeLimits.protocolVersion,
                host: "127.0.0.1",
                port: port,
                launchID: launchID,
                authenticationToken: material.1.base64EncodedString(),
                processID: getpid(),
                createdAt: Date()
            )
            try discoveryPublisher.publish(record)
            guard startAttemptID == attemptID, runtime?.launchID == launchID else {
                try? discoveryPublisher.removeIfOwned(launchID: launchID)
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
        ingress.deactivate(launchID: runtime.launchID)
        Task { await runtime.authenticator.invalidate() }
        try? discoveryPublisher?.removeIfOwned(launchID: runtime.launchID)
    }

    private func record(_ response: AgentBridgeHTTPResponse, launchID: String) {
        guard runtime?.launchID == launchID else { return }
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
