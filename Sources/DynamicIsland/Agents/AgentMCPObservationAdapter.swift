import Foundation

enum AgentMCPAdapterLimits {
    static let maximumSources = 16
    static let maximumInitialObservations = 256
    static let maximumObservationBytes = 65_536
    static let maximumJSONDepth = 10
    static let maximumJSONContainers = 256
}

struct AgentMCPSourceDescriptor: Hashable, Sendable {
    let sourceInstanceID: AgentSourceInstanceID
    let displayName: String
    let runtimeVersion: String?
}

struct AgentMCPSourceConnection: Sendable {
    let initialObservations: [Data]
    let observations: AsyncStream<Data>
    let disconnect: @Sendable () async -> Void

    init(
        initialObservations: [Data] = [],
        observations: AsyncStream<Data>,
        disconnect: @escaping @Sendable () async -> Void
    ) {
        self.initialObservations = initialObservations
        self.observations = observations
        self.disconnect = disconnect
    }
}

protocol AgentMCPSourceDiscovering: Sendable {
    func discoverSources() async throws -> [AgentMCPSourceDescriptor]
}

protocol AgentMCPSourceConnecting: Sendable {
    /// Connections expose only observation resources/notifications. Adapters
    /// must not invoke MCP tools, prompts, sampling, elicitation, or mutation APIs.
    func connect(to source: AgentMCPSourceDescriptor) async throws -> AgentMCPSourceConnection
}

struct AgentMCPAdapterRefreshResult: Equatable, Sendable {
    let discovered: Int
    let connected: Int
    let rejectedSources: Int
    let rejectedObservations: Int
}

enum AgentMCPAdapterError: Error, Equatable, Sendable {
    case payloadTooLarge
    case malformedJSON
    case invalidSchema
    case unsupportedObservation
    case invalidIdentity
    case invalidUsage
}

/// Owns MCP observation-source discovery and connection lifecycle. Raw MCP
/// resource data stops here; only typed, privacy-reduced observations cross the
/// AgentIntegrationRouter boundary.
actor AgentMCPObservationAdapter {
    private struct Runtime {
        let producer: AgentProducerHandle
        let task: Task<Void, Never>
        let disconnect: @Sendable () async -> Void
    }

    private let discovery: any AgentMCPSourceDiscovering
    private let connector: any AgentMCPSourceConnecting
    private let router: AgentIntegrationRouter
    private var runtimes: [AgentSourceInstanceID: Runtime] = [:]
    private var started = false

    init(
        discovery: any AgentMCPSourceDiscovering,
        connector: any AgentMCPSourceConnecting,
        router: AgentIntegrationRouter
    ) {
        self.discovery = discovery
        self.connector = connector
        self.router = router
    }

    func start() async -> AgentMCPAdapterRefreshResult {
        guard !started else {
            return AgentMCPAdapterRefreshResult(
                discovered: runtimes.count,
                connected: 0,
                rejectedSources: 0,
                rejectedObservations: 0
            )
        }
        started = true
        return await refreshSources()
    }

    func refreshSources() async -> AgentMCPAdapterRefreshResult {
        guard started else {
            return AgentMCPAdapterRefreshResult(
                discovered: 0,
                connected: 0,
                rejectedSources: 0,
                rejectedObservations: 0
            )
        }

        let discovered: [AgentMCPSourceDescriptor]
        do {
            discovered = try await discovery.discoverSources()
        } catch {
            return AgentMCPAdapterRefreshResult(
                discovered: 0,
                connected: 0,
                rejectedSources: 1,
                rejectedObservations: 0
            )
        }

        let bounded = Array(discovered
            .sorted { $0.sourceInstanceID.rawValue < $1.sourceInstanceID.rawValue }
            .prefix(AgentMCPAdapterLimits.maximumSources))
        let duplicateCount = bounded.count - Set(bounded.map(\.sourceInstanceID)).count
        var connected = 0
        var rejectedSources = duplicateCount + max(0, discovered.count - bounded.count)
        var rejectedObservations = 0
        var seen: Set<AgentSourceInstanceID> = []

        for descriptor in bounded {
            guard seen.insert(descriptor.sourceInstanceID).inserted,
                  Self.valid(descriptor),
                  runtimes[descriptor.sourceInstanceID] == nil else {
                if !seen.contains(descriptor.sourceInstanceID) || !Self.valid(descriptor) {
                    rejectedSources += 1
                }
                continue
            }

            let connection: AgentMCPSourceConnection
            do {
                connection = try await connector.connect(to: descriptor)
            } catch {
                rejectedSources += 1
                continue
            }
            guard connection.initialObservations.count <= AgentMCPAdapterLimits.maximumInitialObservations else {
                rejectedSources += 1
                await connection.disconnect()
                continue
            }

            let registration = await router.registerMCPSource(
                id: descriptor.sourceInstanceID,
                runtimeVersion: descriptor.runtimeVersion,
                authenticatedProducerID: "mcp-observer-\(descriptor.sourceInstanceID.rawValue)"
            )
            guard case .success(let producer) = registration else {
                rejectedSources += 1
                await connection.disconnect()
                continue
            }

            for payload in connection.initialObservations {
                if !(await route(payload, producer: producer)) { rejectedObservations += 1 }
            }

            let sourceID = descriptor.sourceInstanceID
            let task = Task { [weak self, stream = connection.observations] in
                for await payload in stream {
                    guard !Task.isCancelled else { break }
                    await self?.consume(payload, sourceID: sourceID, producer: producer)
                }
                await self?.connectionEnded(sourceID: sourceID, producer: producer)
            }
            runtimes[sourceID] = Runtime(
                producer: producer,
                task: task,
                disconnect: connection.disconnect
            )
            connected += 1
        }

        return AgentMCPAdapterRefreshResult(
            discovered: discovered.count,
            connected: connected,
            rejectedSources: rejectedSources,
            rejectedObservations: rejectedObservations
        )
    }

    func stop() async {
        started = false
        let active = runtimes
        runtimes.removeAll(keepingCapacity: false)
        for runtime in active.values {
            runtime.task.cancel()
            await runtime.disconnect()
            await router.unregisterMCPSource(runtime.producer)
        }
    }

    func connectedSourceIDs() -> Set<AgentSourceInstanceID> {
        Set(runtimes.keys)
    }

    private func consume(
        _ payload: Data,
        sourceID: AgentSourceInstanceID,
        producer: AgentProducerHandle
    ) async {
        guard runtimes[sourceID]?.producer == producer else { return }
        _ = await route(payload, producer: producer)
    }

    private func route(_ payload: Data, producer: AgentProducerHandle) async -> Bool {
        do {
            let observation = try AgentMCPObservationDecoder.decode(payload)
            guard case .success = await router.routeMCP(observation, from: producer) else { return false }
            return true
        } catch {
            return false
        }
    }

    private func connectionEnded(
        sourceID: AgentSourceInstanceID,
        producer: AgentProducerHandle
    ) async {
        guard let runtime = runtimes[sourceID], runtime.producer == producer else { return }
        runtimes.removeValue(forKey: sourceID)
        await runtime.disconnect()
        await router.unregisterMCPSource(producer)
    }

    private static func valid(_ descriptor: AgentMCPSourceDescriptor) -> Bool {
        let id = descriptor.sourceInstanceID.rawValue
        let name = descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !id.isEmpty && id.utf8.count <= AgentDomainLimits.identifierLength &&
            id.unicodeScalars.allSatisfy {
                !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
            } &&
            !name.isEmpty && name.utf8.count <= AgentDomainLimits.titleLength &&
            (descriptor.runtimeVersion?.utf8.count ?? 0) <= AgentIngestionLimits.maximumRuntimeVersionLength
    }
}

enum AgentMCPObservationDecoder {
    private struct WireProject: Decodable {
        let displayName: String?
        let repositoryIdentity: String?
        let gitBranch: String?
        let gitCommit: String?
        let model: String?
    }

    private struct WireUsage: Decodable {
        let authoritative: Bool
        let samples: [WireUsageSample]
    }

    private struct WireUsageSample: Decodable {
        let metric: String
        let value: Double
        let limit: Double?
        let unit: String
        let scope: String
        let source: String
        let observedAt: Double
    }

    private struct WireObservation: Decodable {
        let schemaVersion: Int
        let observationID: String
        let provider: String
        let nativeSessionID: String
        let timestamp: Double
        let type: String
        let correlationID: String?
        let title: String?
        let summary: String?
        let name: String?
        let category: String?
        let executable: String?
        let success: Bool?
        let exitCode: Int?
        let operationCorrelationID: String?
        let expiresAt: Double?
        let project: WireProject?
        let usage: WireUsage?
    }

    private static let rootKeys: Set<String> = [
        "schemaVersion", "observationID", "provider", "nativeSessionID", "timestamp", "type",
        "correlationID", "title", "summary", "name", "category", "executable", "success",
        "exitCode", "operationCorrelationID", "expiresAt", "project", "usage"
    ]
    private static let projectKeys: Set<String> = [
        "displayName", "repositoryIdentity", "gitBranch", "gitCommit", "model"
    ]
    private static let usageKeys: Set<String> = ["authoritative", "samples"]
    private static let sampleKeys: Set<String> = [
        "metric", "value", "limit", "unit", "scope", "source", "observedAt"
    ]

    static func decode(_ data: Data) throws -> AgentMCPObservation {
        guard !data.isEmpty, data.count <= AgentMCPAdapterLimits.maximumObservationBytes else {
            throw AgentMCPAdapterError.payloadTooLarge
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw AgentMCPAdapterError.malformedJSON
        }
        var containers = 0
        guard validateShape(object, depth: 0, containers: &containers),
              let root = object as? [String: Any],
              Set(root.keys).isSubset(of: rootKeys),
              strictNestedKeys(root) else {
            throw AgentMCPAdapterError.invalidSchema
        }

        let wire: WireObservation
        do {
            wire = try JSONDecoder().decode(WireObservation.self, from: data)
        } catch {
            throw AgentMCPAdapterError.invalidSchema
        }
        guard wire.schemaVersion == 1,
              wire.timestamp.isFinite else {
            throw AgentMCPAdapterError.invalidSchema
        }

        let provider = try provider(wire.provider)
        let correlation = wire.correlationID.map(AgentCorrelationID.init(rawValue:))
        let project = wire.project.map(project)
        let kind: AgentMCPObservationKind

        switch wire.type {
        case "sessionObserved":
            kind = .sessionObserved(project: project)
        case "task", "activity":
            kind = .activity(title: wire.title, summary: wire.summary)
        case "planUpdated":
            kind = .planUpdated(summary: wire.summary)
        case "planReady":
            kind = .planReady(summary: wire.summary)
        case "toolStarted":
            kind = .toolStarted(name: wire.name, category: wire.category, summary: wire.summary)
        case "toolCompleted":
            kind = .toolCompleted(
                name: wire.name,
                category: wire.category,
                summary: wire.summary,
                success: wire.success
            )
        case "commandStarted":
            kind = .commandStarted(executable: wire.executable)
        case "commandCompleted":
            kind = .commandCompleted(
                executable: wire.executable,
                success: wire.success,
                exitCode: wire.exitCode
            )
        case "attention", "permissionRequired":
            kind = .attention(
                summary: wire.summary,
                operationCorrelationID: wire.operationCorrelationID.map(AgentCorrelationID.init(rawValue:)),
                expiresAt: wire.expiresAt.map { Date(timeIntervalSince1970: $0) }
            )
        case "project":
            guard let project else { throw AgentMCPAdapterError.invalidSchema }
            kind = .project(project)
        case "usage":
            guard let wireUsage = wire.usage else { throw AgentMCPAdapterError.invalidUsage }
            kind = .usage(try usage(wireUsage), authoritative: wireUsage.authoritative)
        case "heartbeat":
            kind = .heartbeat
        default:
            throw AgentMCPAdapterError.unsupportedObservation
        }

        return AgentMCPObservation(
            observationID: wire.observationID,
            provider: provider,
            nativeSessionID: wire.nativeSessionID,
            timestamp: Date(timeIntervalSince1970: wire.timestamp),
            correlationID: correlation,
            kind: kind
        )
    }

    private static func provider(_ raw: String) throws -> AgentProvider {
        switch raw {
        case "codex": return .codex
        case "claude": return .claude
        default:
            guard validToken(raw) else { throw AgentMCPAdapterError.invalidIdentity }
            return .other(raw)
        }
    }

    private static func project(_ wire: WireProject) -> AgentProjectContext {
        AgentProjectContext(
            displayName: wire.displayName,
            repositoryIdentity: wire.repositoryIdentity,
            gitBranch: wire.gitBranch,
            gitCommit: wire.gitCommit,
            model: wire.model
        )
    }

    private static func usage(_ wire: WireUsage) throws -> AgentUsage {
        guard wire.authoritative, !wire.samples.isEmpty, wire.samples.count <= 32 else {
            throw AgentMCPAdapterError.invalidUsage
        }
        var entries: [AgentUsageKey: AgentUsageSample] = [:]
        for raw in wire.samples {
            guard let metric = AgentUsageMetric(rawValue: raw.metric),
                  let unit = AgentUsageUnit(rawValue: raw.unit),
                  raw.value.isFinite, raw.value >= 0,
                  raw.limit.map({ $0.isFinite && $0 >= 0 }) ?? true,
                  validToken(raw.scope), validToken(raw.source), raw.observedAt.isFinite else {
                throw AgentMCPAdapterError.invalidUsage
            }
            let sample = AgentUsageSample(
                value: raw.value,
                limit: raw.limit,
                unit: unit,
                scope: raw.scope,
                source: raw.source,
                observedAt: Date(timeIntervalSince1970: raw.observedAt)
            )
            entries[AgentUsageKey(metric: metric, scope: raw.scope)] = sample
        }
        return AgentUsage(scopedSamples: entries)
    }

    private static func strictNestedKeys(_ root: [String: Any]) -> Bool {
        if let project = root["project"] as? [String: Any],
           !Set(project.keys).isSubset(of: projectKeys) { return false }
        if let usage = root["usage"] as? [String: Any] {
            guard Set(usage.keys).isSubset(of: usageKeys) else { return false }
            if let samples = usage["samples"] as? [[String: Any]],
               samples.contains(where: { !Set($0.keys).isSubset(of: sampleKeys) }) { return false }
        }
        return true
    }

    private static func validateShape(_ value: Any, depth: Int, containers: inout Int) -> Bool {
        guard depth <= AgentMCPAdapterLimits.maximumJSONDepth else { return false }
        if let dictionary = value as? [String: Any] {
            containers += 1
            guard containers <= AgentMCPAdapterLimits.maximumJSONContainers,
                  dictionary.count <= 64 else { return false }
            return dictionary.values.allSatisfy {
                validateShape($0, depth: depth + 1, containers: &containers)
            }
        }
        if let array = value as? [Any] {
            containers += 1
            guard containers <= AgentMCPAdapterLimits.maximumJSONContainers,
                  array.count <= AgentMCPAdapterLimits.maximumInitialObservations else { return false }
            return array.allSatisfy {
                validateShape($0, depth: depth + 1, containers: &containers)
            }
        }
        return value is String || value is NSNumber || value is NSNull
    }

    private static func validToken(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AgentDomainLimits.tokenLength &&
            value.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII &&
                    (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
            }
    }
}
