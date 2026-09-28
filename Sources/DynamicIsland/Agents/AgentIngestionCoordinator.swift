import Foundation

actor AgentIngestionCoordinator {
    typealias StoreSink = @MainActor @Sendable ([AgentEvent]) -> AgentEventBatchApplication

    private let storeSink: StoreSink
    private var registry = AgentSourceRegistry()
    private var leases: [AgentSessionID: AgentSessionLease] = [:]
    private var nextGeneration: [AgentSessionID: AgentSessionGeneration] = [:]
    private var capabilityLedger: [AgentSessionInstanceID: [AgentProducerHandle: AgentCapabilities]] = [:]
    private var identityConflicts: [AgentIdentityConflict] = []
    private var syntheticEventSequence: UInt64 = 0

    // Actor reentrancy must not permit registration revocation or generation
    // replacement between staging and the MainActor store commit.
    private var mutationLocked = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    @MainActor
    init(eventStore: AgentEventStore) {
        storeSink = { events in eventStore.ingestAtomically(events) }
    }

    init(storeSink: @escaping StoreSink) {
        self.storeSink = storeSink
    }

    func registerProducer(
        descriptor: AgentProducerDescriptor,
        policy: AgentProducerPolicy,
        authenticatedProducerID: String = UUID().uuidString.lowercased()
    ) async -> Result<AgentProducerHandle, AgentIngestionError> {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            let previous = registry.registrations[descriptor.sourceInstanceID]?.handle
            var stagedRegistry = registry
            let handle = try stagedRegistry.register(
                descriptor: descriptor,
                policy: policy,
                authenticatedProducerID: authenticatedProducerID
            )
            var stagedLeases = leases
            var stagedLedger = capabilityLedger
            let capabilityEvents = removeEvidence(
                for: previous,
                leases: &stagedLeases,
                ledger: &stagedLedger,
                at: Date()
            )
            guard await commit(capabilityEvents) else { return .failure(.storeRejected) }
            registry = stagedRegistry
            leases = stagedLeases
            capabilityLedger = stagedLedger
            return .success(handle)
        } catch let error as AgentIngestionError {
            return .failure(error)
        } catch {
            return .failure(.invalidDescriptor)
        }
    }

    func unregisterProducer(_ handle: AgentProducerHandle, at date: Date = Date()) async -> Result<Void, AgentIngestionError> {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            var stagedRegistry = registry
            try stagedRegistry.unregister(handle)
            var stagedLeases = leases
            var stagedLedger = capabilityLedger
            let capabilityEvents = removeEvidence(
                for: handle,
                leases: &stagedLeases,
                ledger: &stagedLedger,
                at: date
            )
            guard await commit(capabilityEvents) else { return .failure(.storeRejected) }
            registry = stagedRegistry
            leases = stagedLeases
            capabilityLedger = stagedLedger
            return .success(())
        } catch let error as AgentIngestionError {
            return .failure(error)
        } catch {
            return .failure(.invalidProducer)
        }
    }

    func replacePolicy(
        _ policy: AgentProducerPolicy,
        for handle: AgentProducerHandle,
        at date: Date = Date()
    ) async -> Result<Void, AgentIngestionError> {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            var stagedRegistry = registry
            try stagedRegistry.replacePolicy(policy, for: handle)
            var stagedLedger = capabilityLedger
            var stagedLeases = leases
            let events = removeDisallowedEvidence(
                for: handle,
                policy: policy,
                leases: &stagedLeases,
                ledger: &stagedLedger,
                at: date
            )
            guard await commit(events) else { return .failure(.storeRejected) }
            registry = stagedRegistry
            leases = stagedLeases
            capabilityLedger = stagedLedger
            return .success(())
        } catch let error as AgentIngestionError {
            return .failure(error)
        } catch {
            return .failure(.invalidProducer)
        }
    }

    func ingest(
        _ event: AgentIngestionEvent,
        from handle: AgentProducerHandle
    ) async -> Result<AgentIngestionResult, AgentIngestionError> {
        await ingestAtomically([event], from: handle)
    }

    /// Read-only validation used by the integration router before it suppresses
    /// semantically duplicate observations. A duplicate must never mask a stale
    /// producer, policy violation, or malformed event.
    func validateForRouting(
        _ events: [AgentIngestionEvent],
        from handle: AgentProducerHandle
    ) -> Result<Void, AgentIngestionError> {
        guard !events.isEmpty else { return .failure(.invalidEvent) }
        do {
            let registration = try registry.registration(for: handle)
            for event in events {
                try validate(event, registration: registration)
            }
            return .success(())
        } catch let error as AgentIngestionError {
            return .failure(error)
        } catch {
            return .failure(.invalidEvent)
        }
    }

    func ingestAtomically(
        _ events: [AgentIngestionEvent],
        from handle: AgentProducerHandle
    ) async -> Result<AgentIngestionResult, AgentIngestionError> {
        await acquireMutation()
        defer { releaseMutation() }
        guard !events.isEmpty else { return .failure(.invalidEvent) }

        do {
            let registration = try registry.registration(for: handle)
            var stagedLeases = leases
            var stagedNextGeneration = nextGeneration
            var stagedLedger = capabilityLedger
            var normalized: [AgentEvent] = []
            normalized.reserveCapacity(events.count)

            for evidence in events {
                try validate(evidence, registration: registration)
                let requiresRecoveryBootstrap = stagedLeases[evidence.sessionID] == nil &&
                    permitsRecoveryBootstrap(for: evidence, registration: registration)
                let previousInstance = stagedLeases[evidence.sessionID]?.instanceID
                let lease = try resolveLease(
                    for: evidence,
                    handle: handle,
                    permitsRecoveryBootstrap: requiresRecoveryBootstrap,
                    leases: &stagedLeases,
                    nextGeneration: &stagedNextGeneration
                )
                if let previousInstance, previousInstance != lease.instanceID {
                    stagedLedger.removeValue(forKey: previousInstance)
                }
                if requiresRecoveryBootstrap {
                    let bootstrap = recoveryBootstrapEvent(
                        for: evidence,
                        lease: lease,
                        registration: registration
                    )
                    normalized.append(bootstrap)
                    applyLifecycleAuthority(of: bootstrap, to: &stagedLeases)
                }
                var event = normalize(evidence, lease: lease, registration: registration)
                if case .capabilities(let capabilities) = evidence.payload {
                    let snapshotAuthority = max(
                        stagedLeases[evidence.sessionID]?.capabilitySnapshotAuthority ?? .heuristic,
                        event.authority
                    )
                    stagedLeases[evidence.sessionID]?.capabilitySnapshotAuthority = snapshotAuthority
                    event = try capabilitySnapshotEvent(
                        from: event,
                        supplied: capabilities,
                        handle: handle,
                        registration: registration,
                        snapshotAuthority: snapshotAuthority,
                        ledger: &stagedLedger
                    )
                }
                if let error = event.validationError() {
                    _ = error
                    throw AgentIngestionError.invalidEvent
                }
                normalized.append(event)
                applyLifecycleAuthority(of: event, to: &stagedLeases)
            }

            let application = await storeSink(normalized)
            guard case .applied(let applications) = application else {
                try? registry.recordRejected(.storeRejected, dropped: events.count, for: handle)
                return .failure(.storeRejected)
            }
            leases = stagedLeases
            nextGeneration = stagedNextGeneration
            capabilityLedger = stagedLedger
            try registry.recordAccepted(events.count, at: events.last?.receivedTimestamp ?? Date(), for: handle)
            return .success(AgentIngestionResult(
                acceptedEvents: events.count,
                applications: applications,
                sessionInstances: normalized.map(\.instanceID)
            ))
        } catch let error as AgentIngestionError {
            let healthError: AgentSourceHealthError = switch error {
            case .unsupportedSchema: .schemaMismatch
            case .policyViolation: .policyRejected
            case .staleProducer: .staleProducer
            case .identityConflict: .identityConflict
            case .storeRejected: .storeRejected
            default: .invalidEvent
            }
            try? registry.recordRejected(
                healthError,
                schemaMismatch: error == .unsupportedSchema,
                dropped: events.count,
                for: handle
            )
            return .failure(error)
        } catch {
            try? registry.recordRejected(.invalidEvent, dropped: events.count, for: handle)
            return .failure(.invalidEvent)
        }
    }

    func updateHealth(
        _ state: AgentSourceHealthState,
        error: AgentSourceHealthError? = nil,
        for handle: AgentProducerHandle
    ) async -> Result<Void, AgentIngestionError> {
        await acquireMutation()
        defer { releaseMutation() }
        do {
            try registry.updateHealth(state, error: error, for: handle)
            return .success(())
        } catch let error as AgentIngestionError {
            return .failure(error)
        } catch {
            return .failure(.invalidProducer)
        }
    }

    func sourceHealth() async -> [AgentSourceHealthSnapshot] {
        await acquireMutation()
        defer { releaseMutation() }
        return registry.activeHealth
    }

    func stoppedSourceHealth() async -> [AgentSourceHealthSnapshot] {
        await acquireMutation()
        defer { releaseMutation() }
        return registry.healthHistory
    }

    func sessionLeases() async -> [AgentSessionLease] {
        await acquireMutation()
        defer { releaseMutation() }
        return leases.values.sorted {
            if $0.instanceID.sessionID.provider.deterministicSortKey != $1.instanceID.sessionID.provider.deterministicSortKey {
                return $0.instanceID.sessionID.provider.deterministicSortKey < $1.instanceID.sessionID.provider.deterministicSortKey
            }
            return $0.instanceID.sessionID.nativeID < $1.instanceID.sessionID.nativeID
        }
    }

    func recordedIdentityConflicts() async -> [AgentIdentityConflict] {
        await acquireMutation()
        defer { releaseMutation() }
        return identityConflicts
    }

    private func validate(
        _ event: AgentIngestionEvent,
        registration: AgentSourceRegistry.Registration
    ) throws {
        let policy = registration.policy
        guard registration.descriptor.normalizedSchemaVersions.contains(event.schemaVersion),
              policy.allowedSchemaVersions.contains(event.schemaVersion) else {
            throw AgentIngestionError.unsupportedSchema
        }
        guard policy.allowedSourceKinds.contains(registration.descriptor.sourceKind),
              policy.permits(provider: event.provider), policy.permits(source: event.source),
              policy.allowedEventTypes.contains(event.type),
              let domain = AgentAuthorityDomain.domain(for: event.type),
              let ceiling = policy.authorityCeilings[domain], event.authority <= ceiling else {
            throw AgentIngestionError.policyViolation
        }
        if let continuity = event.continuity {
            guard !continuity.immutableIdentity.isEmpty,
                  continuity.immutableIdentity.utf8.count <= AgentDomainLimits.identifierLength,
                  continuity.immutableIdentity.unicodeScalars.allSatisfy({
                      !$0.properties.isWhitespace && !CharacterSet.controlCharacters.contains($0)
                  }) else {
                throw AgentIngestionError.invalidEvent
            }
        }
        if case .capabilities(let capabilities) = event.payload {
            guard capabilities.all.isSubset(of: policy.allowedCapabilities),
                  (!capabilities.contains(.approvalControl) || policy.permitsApprovalControl),
                  capabilities.evidence.values.allSatisfy({ $0.authority <= ceiling && $0.authority <= event.authority }) else {
                throw AgentIngestionError.policyViolation
            }
        }
    }

    private func resolveLease(
        for event: AgentIngestionEvent,
        handle: AgentProducerHandle,
        permitsRecoveryBootstrap: Bool = false,
        leases: inout [AgentSessionID: AgentSessionLease],
        nextGeneration: inout [AgentSessionID: AgentSessionGeneration]
    ) throws -> AgentSessionLease {
        let id = event.sessionID
        if var current = leases[id] {
            if current.isTerminal, event.type == .sessionStarted {
                // A secondary producer discovering the same immutable provider
                // session after a stronger lifecycle source has already ended it
                // must converge on that generation rather than manufacture a
                // fresh run. The producer that already owns the lease may start
                // a new local incarnation explicitly.
                if !current.owners.contains(handle),
                   let currentContinuity = current.continuity,
                   let incomingContinuity = event.continuity,
                   currentContinuity == incomingContinuity {
                    current.owners.insert(handle)
                    leases[id] = current
                    try assertGeneration(event.assertedGeneration, equals: current.instanceID.generation)
                    return current
                }
                return try allocateLease(
                    id: id,
                    continuity: event.continuity,
                    owner: handle,
                    assertedGeneration: event.assertedGeneration,
                    leases: &leases,
                    nextGeneration: &nextGeneration
                )
            }
            if current.owners.contains(handle) {
                if let currentContinuity = current.continuity,
                   let incomingContinuity = event.continuity,
                   currentContinuity != incomingContinuity {
                    recordConflict(event, current: current, handle: handle)
                    throw AgentIngestionError.identityConflict
                }
                try assertGeneration(event.assertedGeneration, equals: current.instanceID.generation)
                return current
            }
            if let currentContinuity = current.continuity,
               let incomingContinuity = event.continuity {
                guard currentContinuity == incomingContinuity else {
                    recordConflict(event, current: current, handle: handle)
                    throw AgentIngestionError.identityConflict
                }
                current.owners.insert(handle)
                leases[id] = current
                try assertGeneration(event.assertedGeneration, equals: current.instanceID.generation)
                return current
            }
            guard event.type == .sessionStarted else { throw AgentIngestionError.generationConflict }
            return try allocateLease(
                id: id,
                continuity: event.continuity,
                owner: handle,
                assertedGeneration: event.assertedGeneration,
                leases: &leases,
                nextGeneration: &nextGeneration
            )
        }
        guard event.type == .sessionStarted || permitsRecoveryBootstrap else {
            throw AgentIngestionError.generationConflict
        }
        guard leases.count < AgentIngestionLimits.maximumSessionLeases else { throw AgentIngestionError.leaseCapacity }
        return try allocateLease(
            id: id,
            continuity: event.continuity,
            owner: handle,
            assertedGeneration: event.assertedGeneration,
            leases: &leases,
            nextGeneration: &nextGeneration
        )
    }

    private func allocateLease(
        id: AgentSessionID,
        continuity: AgentSessionContinuity?,
        owner: AgentProducerHandle,
        assertedGeneration: AgentSessionGeneration?,
        leases: inout [AgentSessionID: AgentSessionLease],
        nextGeneration: inout [AgentSessionID: AgentSessionGeneration]
    ) throws -> AgentSessionLease {
        let previous = nextGeneration[id]?.rawValue ?? 0
        guard previous < UInt64.max else { throw AgentIngestionError.generationConflict }
        let generation = AgentSessionGeneration(rawValue: previous + 1)
        try assertGeneration(assertedGeneration, equals: generation)
        let lease = AgentSessionLease(
            instanceID: AgentSessionInstanceID(sessionID: id, generation: generation),
            continuity: continuity,
            owners: [owner],
            isTerminal: false
        )
        leases[id] = lease
        nextGeneration[id] = generation
        return lease
    }

    private func assertGeneration(
        _ asserted: AgentSessionGeneration?,
        equals generation: AgentSessionGeneration
    ) throws {
        if let asserted, asserted != generation { throw AgentIngestionError.generationConflict }
    }

    private func normalize(
        _ evidence: AgentIngestionEvent,
        lease: AgentSessionLease,
        registration: AgentSourceRegistry.Registration
    ) -> AgentEvent {
        AgentEvent(
            schemaVersion: evidence.schemaVersion,
            eventID: evidence.eventID,
            sessionID: evidence.sessionID,
            generation: lease.instanceID.generation,
            source: evidence.source,
            type: evidence.type,
            providerTimestamp: evidence.providerTimestamp,
            receivedTimestamp: evidence.receivedTimestamp,
            correlationID: evidence.correlationID,
            sequence: evidence.sequence,
            authority: evidence.authority,
            origin: .live,
            payload: evidence.payload,
            provenance: AgentEventProvenance(
                sourceInstanceID: registration.descriptor.sourceInstanceID,
                producerEpoch: registration.handle.epoch,
                sourceKind: registration.descriptor.sourceKind,
                claimedAuthority: evidence.authority,
                schemaVersion: evidence.schemaVersion
            )
        )
    }

    private func permitsRecoveryBootstrap(
        for event: AgentIngestionEvent,
        registration: AgentSourceRegistry.Registration
    ) -> Bool {
        guard [.officialHook, .officialLifecycleProtocol].contains(registration.descriptor.sourceKind),
              registration.policy.permitsLifecycleRecovery,
              registration.policy.permits(provider: event.provider),
              event.provider == .codex,
              event.continuity != nil else {
            return false
        }
        switch event.type {
        case .sessionResumed, .agentWorking, .toolStarted, .commandStarted,
             .approvalRequested, .capabilitiesUpdated:
            return true
        default:
            return false
        }
    }

    private func recoveryBootstrapEvent(
        for evidence: AgentIngestionEvent,
        lease: AgentSessionLease,
        registration: AgentSourceRegistry.Registration
    ) -> AgentEvent {
        syntheticEventSequence = syntheticEventSequence == UInt64.max ? 1 : syntheticEventSequence + 1
        return AgentEvent(
            eventID: AgentEventID(rawValue: "coordinator-recovery-\(syntheticEventSequence)"),
            sessionID: evidence.sessionID,
            generation: lease.instanceID.generation,
            source: evidence.source,
            type: .sessionStarted,
            receivedTimestamp: evidence.receivedTimestamp,
            authority: .localStructuredRecord,
            origin: .localRecovery,
            payload: .sessionMetadata(AgentSessionMetadata(project: nil)),
            provenance: AgentEventProvenance(
                sourceInstanceID: registration.descriptor.sourceInstanceID,
                producerEpoch: registration.handle.epoch,
                sourceKind: registration.descriptor.sourceKind,
                claimedAuthority: .localStructuredRecord,
                schemaVersion: evidence.schemaVersion
            )
        )
    }

    private func capabilitySnapshotEvent(
        from event: AgentEvent,
        supplied: AgentCapabilities,
        handle: AgentProducerHandle,
        registration: AgentSourceRegistry.Registration,
        snapshotAuthority: AgentEvidenceAuthority,
        ledger: inout [AgentSessionInstanceID: [AgentProducerHandle: AgentCapabilities]]
    ) throws -> AgentEvent {
        var byProducer = ledger[event.instanceID, default: [:]]
        let currentEntryCount = ledger.values.reduce(0) { total, entries in
            total + entries.values.reduce(0) { $0 + $1.all.count }
        }
        let previousCount = byProducer[handle]?.all.count ?? 0
        let proposedCount = currentEntryCount - previousCount + supplied.all.count
        guard proposedCount <= AgentIngestionLimits.maximumCapabilityEvidenceEntries else {
            throw AgentIngestionError.capabilityCapacity
        }
        let trusted = AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: supplied.evidence.map { capability, evidence in
            (capability, AgentCapabilityEvidence(
                authority: evidence.authority,
                source: "\(registration.descriptor.sourceKind.rawValue):\(registration.descriptor.sourceInstanceID.rawValue)",
                observedAt: evidence.observedAt
            ))
        }))
        if trusted.all.isEmpty { byProducer.removeValue(forKey: handle) } else { byProducer[handle] = trusted }
        ledger[event.instanceID] = byProducer
        return AgentEvent(
            schemaVersion: event.schemaVersion,
            eventID: event.eventID,
            sessionID: event.sessionID,
            generation: event.generation,
            source: event.source,
            type: event.type,
            providerTimestamp: event.providerTimestamp,
            receivedTimestamp: event.receivedTimestamp,
            correlationID: event.correlationID,
            sequence: event.sequence,
            // This event is a coordinator-owned complete aggregate snapshot.
            // Its snapshot authority is the strongest authority legitimately
            // observed for this generation; individual capability evidence
            // retains its actual source authority.
            authority: snapshotAuthority,
            origin: event.origin,
            payload: .capabilities(aggregateCapabilities(byProducer)),
            provenance: event.provenance
        )
    }

    private func aggregateCapabilities(_ ledger: [AgentProducerHandle: AgentCapabilities]) -> AgentCapabilities {
        ledger.values.reduce(AgentCapabilities()) { $0.mergingStrongerEvidence(from: $1) }
    }

    private func removeEvidence(
        for handle: AgentProducerHandle?,
        leases: inout [AgentSessionID: AgentSessionLease],
        ledger: inout [AgentSessionInstanceID: [AgentProducerHandle: AgentCapabilities]],
        at date: Date
    ) -> [AgentEvent] {
        guard let handle else { return [] }
        var events: [AgentEvent] = []
        for id in leases.keys {
            leases[id]?.owners.remove(handle)
        }
        for instanceID in ledger.keys.sorted(by: instanceSort) {
            guard ledger[instanceID]?.removeValue(forKey: handle) != nil else { continue }
            let aggregate = aggregateCapabilities(ledger[instanceID] ?? [:])
            let authority = capabilitySnapshotAuthority(for: instanceID, leases: leases)
            events.append(syntheticCapabilityEvent(
                instanceID: instanceID,
                capabilities: aggregate,
                authority: authority,
                date: date
            ))
        }
        return events
    }

    private func removeDisallowedEvidence(
        for handle: AgentProducerHandle,
        policy: AgentProducerPolicy,
        leases: inout [AgentSessionID: AgentSessionLease],
        ledger: inout [AgentSessionInstanceID: [AgentProducerHandle: AgentCapabilities]],
        at date: Date
    ) -> [AgentEvent] {
        var events: [AgentEvent] = []
        for instanceID in ledger.keys.sorted(by: instanceSort) {
            guard let existing = ledger[instanceID]?[handle] else { continue }
            let filtered = AgentCapabilities(evidence: existing.evidence.filter { policy.allowedCapabilities.contains($0.key) })
            guard filtered != existing else { continue }
            if filtered.all.isEmpty { ledger[instanceID]?.removeValue(forKey: handle) }
            else { ledger[instanceID]?[handle] = filtered }
            events.append(syntheticCapabilityEvent(
                instanceID: instanceID,
                capabilities: aggregateCapabilities(ledger[instanceID] ?? [:]),
                authority: capabilitySnapshotAuthority(for: instanceID, leases: leases),
                date: date
            ))
        }
        return events
    }

    private func syntheticCapabilityEvent(
        instanceID: AgentSessionInstanceID,
        capabilities: AgentCapabilities,
        authority: AgentEvidenceAuthority,
        date: Date
    ) -> AgentEvent {
        syntheticEventSequence = syntheticEventSequence == UInt64.max ? 1 : syntheticEventSequence + 1
        return AgentEvent(
            eventID: AgentEventID(rawValue: "coordinator-capability-\(syntheticEventSequence)"),
            sessionID: instanceID.sessionID,
            generation: instanceID.generation,
            source: .unknown,
            type: .capabilitiesUpdated,
            receivedTimestamp: date,
            authority: authority,
            payload: .capabilities(capabilities)
        )
    }

    private func applyLifecycleAuthority(
        of event: AgentEvent,
        to leases: inout [AgentSessionID: AgentSessionLease]
    ) {
        guard var lease = leases[event.sessionID] else { return }
        switch event.type {
        case .sessionStarted:
            lease.terminalAuthority = max(lease.terminalAuthority, event.authority)
        case .sessionResumed:
            guard event.authority >= lease.terminalAuthority else { return }
            lease.terminalAuthority = event.authority
            lease.isTerminal = false
        case .sessionEnded, .taskCompleted, .taskFailed, .interrupted:
            guard event.authority >= lease.terminalAuthority else { return }
            lease.terminalAuthority = event.authority
            lease.isTerminal = true
        default:
            return
        }
        leases[event.sessionID] = lease
    }

    private func capabilitySnapshotAuthority(
        for instanceID: AgentSessionInstanceID,
        leases: [AgentSessionID: AgentSessionLease]
    ) -> AgentEvidenceAuthority {
        guard let lease = leases[instanceID.sessionID],
              lease.instanceID == instanceID else {
            return .heuristic
        }
        return lease.capabilitySnapshotAuthority
    }

    private func recordConflict(
        _ event: AgentIngestionEvent,
        current: AgentSessionLease,
        handle: AgentProducerHandle
    ) {
        identityConflicts.append(AgentIdentityConflict(
            sessionID: event.sessionID,
            currentGeneration: current.instanceID.generation,
            sourceInstanceID: handle.sourceInstanceID,
            recordedAt: event.receivedTimestamp
        ))
        if identityConflicts.count > AgentIngestionLimits.maximumIdentityConflicts {
            identityConflicts.removeFirst(identityConflicts.count - AgentIngestionLimits.maximumIdentityConflicts)
        }
    }

    private func commit(_ events: [AgentEvent]) async -> Bool {
        guard !events.isEmpty else { return true }
        if case .applied = await storeSink(events) { return true }
        return false
    }

    private func instanceSort(_ lhs: AgentSessionInstanceID, _ rhs: AgentSessionInstanceID) -> Bool {
        if lhs.sessionID.provider.deterministicSortKey != rhs.sessionID.provider.deterministicSortKey {
            return lhs.sessionID.provider.deterministicSortKey < rhs.sessionID.provider.deterministicSortKey
        }
        if lhs.sessionID.nativeID != rhs.sessionID.nativeID { return lhs.sessionID.nativeID < rhs.sessionID.nativeID }
        return lhs.generation < rhs.generation
    }

    private func acquireMutation() async {
        if !mutationLocked {
            mutationLocked = true
            return
        }
        await withCheckedContinuation { mutationWaiters.append($0) }
    }

    private func releaseMutation() {
        if mutationWaiters.isEmpty {
            mutationLocked = false
        } else {
            mutationWaiters.removeFirst().resume()
        }
    }
}
