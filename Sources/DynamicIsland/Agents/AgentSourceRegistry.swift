import Foundation

struct AgentSourceRegistry: Sendable {
    struct Registration: Sendable {
        let handle: AgentProducerHandle
        let descriptor: AgentProducerDescriptor
        var policy: AgentProducerPolicy
        var health: AgentSourceHealthSnapshot
    }

    private(set) var registrations: [AgentSourceInstanceID: Registration] = [:]
    private(set) var healthHistory: [AgentSourceHealthSnapshot] = []
    private var latestEpoch: [AgentSourceInstanceID: AgentProducerEpoch] = [:]

    mutating func register(
        descriptor: AgentProducerDescriptor,
        policy: AgentProducerPolicy,
        authenticatedProducerID: String
    ) throws -> AgentProducerHandle {
        guard Self.valid(descriptor: descriptor), Self.valid(policy: policy),
              policy.allowedSourceKinds.contains(descriptor.sourceKind),
              !descriptor.normalizedSchemaVersions.isDisjoint(with: policy.allowedSchemaVersions),
              Self.validIdentifier(authenticatedProducerID) else {
            throw AgentIngestionError.invalidDescriptor
        }
        guard registrations[descriptor.sourceInstanceID] != nil ||
                registrations.count < AgentIngestionLimits.maximumRegisteredProducers else {
            throw AgentIngestionError.producerCapacity
        }
        if let existing = registrations.removeValue(forKey: descriptor.sourceInstanceID) {
            archive(Self.stopped(existing.health))
        }
        let previous = latestEpoch[descriptor.sourceInstanceID]?.rawValue ?? 0
        guard previous < UInt64.max else { throw AgentIngestionError.invalidDescriptor }
        let epoch = AgentProducerEpoch(rawValue: previous + 1)
        latestEpoch[descriptor.sourceInstanceID] = epoch
        let handle = AgentProducerHandle(
            sourceInstanceID: descriptor.sourceInstanceID,
            epoch: epoch,
            authenticatedProducerID: authenticatedProducerID,
            registrationToken: UUID()
        )
        registrations[descriptor.sourceInstanceID] = Registration(
            handle: handle,
            descriptor: descriptor,
            policy: policy,
            health: AgentSourceHealthSnapshot(
                sourceInstanceID: descriptor.sourceInstanceID,
                epoch: epoch,
                sourceKind: descriptor.sourceKind,
                state: .starting,
                lastAcceptedEventAt: nil,
                acceptedCount: 0,
                rejectedCount: 0,
                dropCount: 0,
                schemaMismatchCount: 0,
                lastError: nil
            )
        )
        trimEpochHistory()
        return handle
    }

    func registration(for handle: AgentProducerHandle) throws -> Registration {
        guard let registration = registrations[handle.sourceInstanceID],
              registration.handle == handle else {
            throw AgentIngestionError.staleProducer
        }
        return registration
    }

    mutating func replacePolicy(_ policy: AgentProducerPolicy, for handle: AgentProducerHandle) throws {
        guard Self.valid(policy: policy) else { throw AgentIngestionError.invalidDescriptor }
        let registration = try registration(for: handle)
        guard policy.allowedSourceKinds.contains(registration.descriptor.sourceKind),
              !registration.descriptor.normalizedSchemaVersions.isDisjoint(with: policy.allowedSchemaVersions) else {
            throw AgentIngestionError.invalidDescriptor
        }
        registrations[handle.sourceInstanceID]?.policy = policy
    }

    mutating func unregister(_ handle: AgentProducerHandle) throws {
        let registration = try registration(for: handle)
        registrations.removeValue(forKey: handle.sourceInstanceID)
        archive(Self.stopped(registration.health))
    }

    mutating func recordAccepted(_ count: Int, at date: Date, for handle: AgentProducerHandle) throws {
        _ = try registration(for: handle)
        guard var health = registrations[handle.sourceInstanceID]?.health else { return }
        health.state = .healthy
        health.lastAcceptedEventAt = date
        health.acceptedCount = Self.saturatingAdd(health.acceptedCount, UInt64(max(0, count)))
        health.lastError = nil
        registrations[handle.sourceInstanceID]?.health = health
    }

    mutating func recordRejected(
        _ error: AgentSourceHealthError,
        schemaMismatch: Bool = false,
        dropped: Int = 0,
        for handle: AgentProducerHandle
    ) throws {
        _ = try registration(for: handle)
        guard var health = registrations[handle.sourceInstanceID]?.health else { return }
        health.state = error == .producerFailure ? .failed : .degraded
        health.rejectedCount = Self.saturatingAdd(health.rejectedCount, 1)
        health.dropCount = Self.saturatingAdd(health.dropCount, UInt64(max(0, dropped)))
        if schemaMismatch { health.schemaMismatchCount = Self.saturatingAdd(health.schemaMismatchCount, 1) }
        health.lastError = error
        registrations[handle.sourceInstanceID]?.health = health
    }

    mutating func updateHealth(
        _ state: AgentSourceHealthState,
        error: AgentSourceHealthError?,
        for handle: AgentProducerHandle
    ) throws {
        _ = try registration(for: handle)
        registrations[handle.sourceInstanceID]?.health.state = state
        registrations[handle.sourceInstanceID]?.health.lastError = error
    }

    var activeHealth: [AgentSourceHealthSnapshot] {
        registrations.values.map(\.health).sorted {
            $0.sourceInstanceID.rawValue < $1.sourceInstanceID.rawValue
        }
    }

    private mutating func archive(_ health: AgentSourceHealthSnapshot) {
        healthHistory.append(health)
        if healthHistory.count > AgentIngestionLimits.maximumProducerHistories {
            healthHistory.removeFirst(healthHistory.count - AgentIngestionLimits.maximumProducerHistories)
        }
    }

    private mutating func trimEpochHistory() {
        guard latestEpoch.count > AgentIngestionLimits.maximumProducerHistories else { return }
        let active = Set(registrations.keys)
        for key in latestEpoch.keys.sorted(by: { $0.rawValue < $1.rawValue }) where !active.contains(key) {
            latestEpoch.removeValue(forKey: key)
            if latestEpoch.count <= AgentIngestionLimits.maximumProducerHistories { break }
        }
    }

    private static func stopped(_ health: AgentSourceHealthSnapshot) -> AgentSourceHealthSnapshot {
        var health = health
        health.state = .stopped
        return health
    }

    private static func valid(descriptor: AgentProducerDescriptor) -> Bool {
        validIdentifier(descriptor.sourceInstanceID.rawValue) &&
            descriptor.runtimeVersion.map { !$0.isEmpty && $0.utf8.count <= AgentIngestionLimits.maximumRuntimeVersionLength } ?? true &&
            !descriptor.normalizedSchemaVersions.isEmpty
    }

    private static func valid(policy: AgentProducerPolicy) -> Bool {
        !policy.allowedSourceKinds.isEmpty && !policy.allowedEventTypes.isEmpty &&
            !policy.allowedSchemaVersions.isEmpty
    }

    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= AgentDomainLimits.identifierLength &&
            value.unicodeScalars.allSatisfy {
                !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
            }
    }

    private static func saturatingAdd(_ value: UInt64, _ increment: UInt64) -> UInt64 {
        let (result, overflow) = value.addingReportingOverflow(increment)
        return overflow ? UInt64.max : result
    }
}
