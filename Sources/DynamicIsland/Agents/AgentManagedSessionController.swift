import AgentBridgeShared
import Foundation

@MainActor
final class AgentManagedSessionController: ObservableObject {
    @Published private(set) var managed: [String: AgentManagedControlState] = [:]
    @Published private(set) var connecting: Set<String> = []
    @Published private(set) var discoveredSessionIDs: Set<String> = []
    @Published private(set) var lastTransportError: String?
    @Published private(set) var accountUsage = AgentUsage()
    @Published private(set) var transcripts: [String: [AgentManagedTranscriptEntry]] = [:]
    @Published private(set) var availableModels: [AgentManagedModelDescriptor] = []
    @Published private(set) var selectedModelOverrides: [AgentSessionID: String] = [:]

    private let provider: (any AgentInteractiveProvider)?
    private let coordinator: AgentIngestionCoordinator
    private let eventStore: AgentEventStore
    private let approvals: AgentApprovalController

    private var producerHandle: AgentProducerHandle?
    private var eventTask: Task<Void, Never>?
    private var snapshotTask: Task<Void, Never>?
    private var inFlightSnapshotRefresh: Task<Void, Never>?
    private var approvalTasks: [String: Task<Void, Never>] = [:]
    private var managedApprovalKeys: Set<AgentApprovalControlKey> = []
    private var knownDiscoveredSessionIDs: Set<String> = []

    init(
        provider: (any AgentInteractiveProvider)?,
        coordinator: AgentIngestionCoordinator,
        eventStore: AgentEventStore,
        approvals: AgentApprovalController
    ) {
        self.provider = provider
        self.coordinator = coordinator
        self.eventStore = eventStore
        self.approvals = approvals
    }

    convenience init?(
        coordinator: AgentIngestionCoordinator,
        eventStore: AgentEventStore,
        approvals: AgentApprovalController
    ) {
        guard let provider = try? CodexAppServerProvider.makeDefault() else { return nil }
        self.init(
            provider: provider,
            coordinator: coordinator,
            eventStore: eventStore,
            approvals: approvals
        )
    }

    var isAvailable: Bool { provider != nil }

    var managedProvider: AgentProvider? { provider?.provider }

    var managedProviders: [AgentProvider] {
        guard let provider, !provider.interactiveCapabilities.isEmpty else { return [] }
        return [provider.provider]
    }

    var modelSelectionScope: AgentModelSelectionScope? {
        provider?.modelSelectionScope
    }

    var interactiveCapabilities: Set<AgentInteractiveCapability> {
        provider?.interactiveCapabilities ?? []
    }

    func startObserving() {
        guard let provider else { return }

        if eventTask == nil {
            eventTask = Task { [weak self] in
                let stream = await provider.events()
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    await self?.handle(event)
                }
            }
        }

        if snapshotTask == nil {
            snapshotTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshPersistentSnapshot()
                    do {
                        try await Task.sleep(for: .seconds(30))
                    } catch {
                        break
                    }
                }
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        eventTask = nil
        snapshotTask?.cancel()
        snapshotTask = nil
        inFlightSnapshotRefresh?.cancel()
        inFlightSnapshotRefresh = nil
        for task in approvalTasks.values { task.cancel() }
        approvalTasks.removeAll()
        managedApprovalKeys.removeAll()
        managed.removeAll()
        connecting.removeAll()
        discoveredSessionIDs.removeAll()
        knownDiscoveredSessionIDs.removeAll()
        accountUsage = AgentUsage()
        transcripts.removeAll()
        availableModels.removeAll()
        selectedModelOverrides.removeAll()

        let provider = self.provider
        let coordinator = self.coordinator
        let handle = producerHandle
        producerHandle = nil
        Task {
            if let handle {
                _ = await coordinator.unregisterProducer(handle)
            }
            await provider?.stop()
        }
    }

    func refreshPersistentSnapshot() async {
        if let inFlightSnapshotRefresh {
            await inFlightSnapshotRefresh.value
            return
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performPersistentSnapshotRefresh()
        }
        inFlightSnapshotRefresh = task
        await task.value
        inFlightSnapshotRefresh = nil
    }

    private func performPersistentSnapshotRefresh() async {
        guard let provider, !Task.isCancelled else { return }

        if interactiveCapabilities.contains(.selectModel),
           let models = try? await provider.listModels() {
            let filtered = models.filter { !$0.model.isEmpty }
            if !filtered.isEmpty {
                availableModels = filtered
            }
        }

        do {
            let refreshed = try await provider.readAccountUsage()
            guard !Task.isCancelled else { return }
            var retained = accountUsage
            retained.merge(refreshed)
            accountUsage = retained
            lastTransportError = nil
        } catch {
            // Preserve the last trustworthy snapshot across transient transport/backend failures.
            lastTransportError = Self.safeError(error)
        }

        do {
            let discovered = try await provider.discoverSessions()
            guard !Task.isCancelled else { return }
            discoveredSessionIDs = Set(discovered.map(\.session.nativeSessionID))
            knownDiscoveredSessionIDs.formUnion(discoveredSessionIDs)
            for descriptor in discovered {
                await registerDiscoveredSession(descriptor)
            }
        } catch {
            lastTransportError = Self.safeError(error)
        }
    }

    private func registerDiscoveredSession(
        _ discovered: AgentDiscoveredSessionDescriptor
    ) async {
        let descriptor = discovered.session
        let sessionID = descriptor.sessionID
        let existing = eventStore.sessions.first {
            $0.id.sessionID == sessionID && $0.endedAt == nil
        }

        if existing == nil {
            _ = await emitDiscoveredSessionStart(discovered)
        } else {
            _ = await emit(
                nativeSessionID: descriptor.nativeSessionID,
                type: .sessionMetadataUpdated,
                payload: .sessionMetadata(AgentSessionMetadata(
                    project: projectContext(for: descriptor),
                    availability: availability(for: discovered.runtimeState)
                )),
                providerTimestamp: min(discovered.updatedAt, Date())
            )
        }

        if discovered.runtimeState == .systemError {
            _ = await emit(
                nativeSessionID: descriptor.nativeSessionID,
                type: .taskFailed,
                payload: .terminal(AgentTerminalEvent(summary: "Codex runtime unavailable"))
            )
            return
        }

        guard discovered.runtimeState == .active else { return }
        let current = eventStore.sessions.first {
            $0.id.sessionID == sessionID && $0.endedAt == nil
        }
        guard current?.state != .working,
              current?.state != .runningTool,
              current?.state != .runningCommand,
              current?.state != .thinking,
              current?.state != .planning,
              current?.state != .waitingForApproval,
              current?.state != .waitingForUser else {
            return
        }

        _ = await emit(
            nativeSessionID: descriptor.nativeSessionID,
            type: .sessionResumed,
            payload: .sessionMetadata(AgentSessionMetadata(project: projectContext(for: descriptor)))
        )
        _ = await emit(
            nativeSessionID: descriptor.nativeSessionID,
            type: .agentWorking,
            payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil))
        )
    }

    @discardableResult
    private func emitDiscoveredSessionStart(
        _ discovered: AgentDiscoveredSessionDescriptor
    ) async -> AgentSessionInstanceID? {
        let descriptor = discovered.session
        // Persisted thread timestamps are useful for ordering, but a provider
        // clock ahead of the host must not make subsequent live events stale.
        let discoveryTimestamp = min(discovered.updatedAt, Date())
        let instance = await emit(
            nativeSessionID: descriptor.nativeSessionID,
            type: .sessionStarted,
            payload: .sessionMetadata(AgentSessionMetadata(
                project: projectContext(for: descriptor),
                availability: availability(for: discovered.runtimeState)
            )),
            providerTimestamp: discoveryTimestamp
        )
        guard instance != nil else { return nil }

        let now = Date()
        let capabilities = AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: [
            AgentCapability.sessionLifecycle,
            .modelMetadata,
            .projectContext
        ].map {
            ($0, AgentCapabilityEvidence(
                authority: .lifecycle,
                source: "codex-app-server-discovery",
                observedAt: now
            ))
        }))
        _ = await emit(
            nativeSessionID: descriptor.nativeSessionID,
            type: .capabilitiesUpdated,
            payload: .capabilities(capabilities),
            providerTimestamp: discoveryTimestamp
        )
        return instance
    }

    private func projectContext(
        for descriptor: AgentManagedSessionDescriptor
    ) -> AgentProjectContext {
        AgentProjectContext(
            displayName: descriptor.cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            workingDirectory: descriptor.cwd,
            model: descriptor.model,
            sourceApplication: AgentSourceApplication(displayName: "Codex", bundleIdentifier: nil)
        )
    }

    private func availability(
        for state: AgentDiscoveredSessionRuntimeState
    ) -> AgentSessionAvailability {
        state == .notLoaded ? .resumable : .loaded
    }

    func isManaged(_ session: AgentSession) -> Bool {
        session.id.sessionID.provider == .codex &&
            managed[session.id.sessionID.nativeID] != nil
    }

    func mode(for session: AgentSession) -> AgentConsoleMode {
        guard let state = managed[session.id.sessionID.nativeID],
              state.acceptsDirectInput else {
            return .observed
        }
        return .interactive(canInterrupt: state.canInterrupt)
    }

    func statusMessage(for session: AgentSession) -> String? {
        if connecting.contains(session.id.sessionID.nativeID) {
            return "Connecting…"
        }
        return managed[session.id.sessionID.nativeID]?.lastError
    }

    func transcript(for session: AgentSession) -> [AgentManagedTranscriptEntry] {
        transcripts[session.id.sessionID.nativeID] ?? []
    }

    func refreshTranscript(for session: AgentSession, limit: Int = 80) async {
        guard let provider,
              session.id.sessionID.provider == provider.provider else { return }
        do {
            let entries = try await provider.readTranscript(
                nativeSessionID: session.id.sessionID.nativeID,
                limit: min(max(limit, 1), 100)
            )
            let nativeID = session.id.sessionID.nativeID
            transcripts[nativeID] = Self.mergedTranscript(
                current: transcripts[nativeID] ?? [],
                incoming: entries
            )
        } catch CodexAppServerError.rpcError(let code, _) where code == -32601 {
            // Some persisted/legacy threads cannot serve the paginated v2
            // history method. Keep any live trustworthy entries and leave
            // control usable instead of surfacing an unrelated transport error.
            return
        } catch {
            recordError(error, for: session.id.sessionID.nativeID)
        }
    }

    func canConnect(_ session: AgentSession) -> Bool {
        provider != nil &&
            session.id.sessionID.provider == .codex &&
            discoveredSessionIDs.contains(session.id.sessionID.nativeID) &&
            managed[session.id.sessionID.nativeID] == nil &&
            !connecting.contains(session.id.sessionID.nativeID)
    }

    func shouldPresent(_ session: AgentSession) -> Bool {
        guard session.id.sessionID.provider == .codex else { return true }
        let nativeID = session.id.sessionID.nativeID
        guard knownDiscoveredSessionIDs.contains(nativeID) else { return true }
        if discoveredSessionIDs.contains(nativeID) || managed[nativeID] != nil { return true }
        switch AgentSessionPresentation.priority(for: session) {
        case .actionRequired, .failure, .working, .thinking:
            return true
        case .idle, .recent:
            return false
        }
    }

    func connect(_ session: AgentSession) {
        guard canConnect(session), let provider else { return }
        startObserving()
        let nativeID = session.id.sessionID.nativeID
        connecting.insert(nativeID)
        Task { [weak self] in
            guard let self else { return }
            do {
                let descriptor = try await provider.resumeSession(nativeSessionID: nativeID)
                guard descriptor.nativeSessionID == nativeID else {
                    throw CodexAppServerError.invalidResponse("thread/resume identity mismatch")
                }
                self.markManaged(descriptor)
                _ = await self.emitSessionAvailability(descriptor, type: .sessionResumed)
            } catch {
                self.recordError(error, for: nativeID)
            }
            self.connecting.remove(nativeID)
        }
    }

    @discardableResult
    func startNewSession(cwd: String?) async -> AgentManagedSessionDescriptor? {
        guard let provider else { return nil }
        startObserving()
        do {
            let descriptor = try await provider.startSession(cwd: cwd)
            markManaged(descriptor)
            _ = await emitSessionAvailability(descriptor, type: .sessionStarted)
            return descriptor
        } catch {
            lastTransportError = Self.safeError(error)
            return nil
        }
    }

    func selectedModel(for session: AgentSession) -> String? {
        selectedModelOverrides[session.id.sessionID] ?? session.project.model
    }

    @discardableResult
    func selectModel(_ model: String?, for session: AgentSession) -> Bool {
        guard let provider,
              provider.provider == session.id.sessionID.provider,
              provider.interactiveCapabilities.contains(.selectModel),
              provider.modelSelectionScope != nil else { return false }
        let sessionID = session.id.sessionID
        guard let model else {
            selectedModelOverrides.removeValue(forKey: sessionID)
            return true
        }
        guard availableModels.contains(where: { $0.model == model }) else { return false }
        selectedModelOverrides[sessionID] = model
        return true
    }

    /// Returns true only after the provider accepts the authoritative turn/start.
    /// The caller can therefore keep its draft intact across transport/RPC failure.
    func submit(_ prompt: String, for session: AgentSession) async -> Bool {
        guard let provider,
              let bounded = AgentPromptDraftPolicy.submission(from: prompt),
              var state = managed[session.id.sessionID.nativeID],
              state.acceptsDirectInput,
              !state.isSubmitting else {
            return false
        }

        state.isSubmitting = true
        state.lastError = nil
        managed[session.id.sessionID.nativeID] = state
        let nativeID = session.id.sessionID.nativeID

        do {
            let turn = try await provider.submit(
                prompt: bounded,
                nativeSessionID: nativeID,
                model: selectedModelOverrides[session.id.sessionID]
            )
            updateControl(nativeID) {
                $0.isSubmitting = false
                $0.activeTurnID = turn.turnID
                $0.lastError = nil
            }
            projectAcceptedUserPrompt(
                bounded,
                nativeSessionID: nativeID,
                turnID: turn.turnID
            )
            return true
        } catch {
            updateControl(nativeID) {
                $0.isSubmitting = false
                $0.lastError = Self.safeError(error)
            }
            return false
        }
    }

    func interrupt(_ session: AgentSession) {
        guard let provider,
              let state = managed[session.id.sessionID.nativeID],
              let turnID = state.activeTurnID else {
            return
        }
        let nativeID = session.id.sessionID.nativeID
        Task { [weak self] in
            do {
                try await provider.interrupt(nativeSessionID: nativeID, turnID: turnID)
            } catch {
                self?.recordError(error, for: nativeID)
            }
        }
    }

    private func handle(_ event: AgentInteractiveProviderEvent) async {
        switch event {
        case .threadAvailable(let descriptor):
            discoveredSessionIDs.insert(descriptor.nativeSessionID)
            knownDiscoveredSessionIDs.insert(descriptor.nativeSessionID)
            markManaged(descriptor)
            await refreshPersistentSnapshot()

        case .turnStarted(let turn):
            updateControl(turn.nativeSessionID) {
                $0.activeTurnID = turn.turnID
                $0.isSubmitting = false
                $0.lastError = nil
            }
            _ = await emit(
                nativeSessionID: turn.nativeSessionID,
                type: .sessionResumed,
                correlationID: AgentCorrelationID(rawValue: turn.turnID),
                payload: .none
            )
            _ = await emit(
                nativeSessionID: turn.nativeSessionID,
                type: .agentWorking,
                correlationID: AgentCorrelationID(rawValue: turn.turnID),
                payload: .activity(AgentActivityDescriptor(
                    title: "Working",
                    summary: nil
                ))
            )
            await refreshPersistentSnapshot()

        case .turnCompleted(let turn, let state, let summary):
            updateControl(turn.nativeSessionID) {
                if $0.activeTurnID == turn.turnID {
                    $0.activeTurnID = nil
                }
                $0.isSubmitting = false
                if state == .failed {
                    $0.lastError = AgentPrivacyProjection.summary(summary)
                }
            }
            let type: AgentEventType = switch state {
            case .completed: .taskCompleted
            case .failed: .taskFailed
            case .interrupted: .interrupted
            default: .taskFailed
            }
            _ = await emit(
                nativeSessionID: turn.nativeSessionID,
                type: type,
                correlationID: AgentCorrelationID(rawValue: turn.turnID),
                payload: .terminal(AgentTerminalEvent(
                    summary: AgentPrivacyProjection.summary(summary) ??
                        (state == .completed ? "Codex turn completed" :
                            state == .interrupted ? "Codex turn interrupted" : "Codex turn failed")
                ))
            )
            await refreshPersistentSnapshot()

        case .providerFailure(let nativeSessionID, let summary):
            let targets: [String]
            if let nativeSessionID {
                targets = [nativeSessionID]
            } else {
                targets = managed.compactMap { key, value in
                    value.activeTurnID == nil ? nil : key
                }
            }
            for target in targets {
                updateControl(target) {
                    $0.activeTurnID = nil
                    $0.isSubmitting = false
                    $0.lastError = AgentPrivacyProjection.summary(summary) ?? "Codex turn failed"
                }
                _ = await emit(
                    nativeSessionID: target,
                    type: .taskFailed,
                    payload: .terminal(AgentTerminalEvent(
                        summary: AgentPrivacyProjection.summary(summary) ?? "Codex turn failed"
                    ))
                )
            }
            await refreshPersistentSnapshot()

        case .transcript(let entry):
            upsertTranscript(entry)

        case .transcriptDelta(let nativeSessionID, let turnID, let itemID, let delta):
            appendTranscriptDelta(
                nativeSessionID: nativeSessionID,
                turnID: turnID,
                itemID: itemID,
                delta: delta
            )

        case .accountUsageChanged:
            await refreshPersistentSnapshot()

        case .normalized(let event):
            _ = await emit(
                nativeSessionID: event.nativeSessionID,
                type: event.type,
                correlationID: event.correlationID,
                payload: event.payload
            )

        case .approvalRequested(let request):
            let key = "\(request.threadID):\(request.itemID)"
            approvalTasks[key]?.cancel()
            approvalTasks[key] = Task { [weak self] in
                await self?.handleApproval(request)
            }

        case .transportClosed:
            lastTransportError = "Codex app-server disconnected"
            for key in managedApprovalKeys {
                _ = approvals.resolve(
                    session: key.session,
                    requestID: key.requestID,
                    decision: .deny
                )
            }
            let managedIDs = Array(managed.keys)
            for key in managedIDs {
                updateControl(key) {
                    $0.activeTurnID = nil
                    $0.isSubmitting = false
                    $0.lastError = lastTransportError
                }
                if eventStore.sessions.contains(where: {
                    $0.id.sessionID.provider == .codex &&
                        $0.id.sessionID.nativeID == key && $0.isActive
                }) {
                    _ = await emit(
                        nativeSessionID: key,
                        type: .taskFailed,
                        payload: .terminal(AgentTerminalEvent(
                            summary: "Codex app-server disconnected"
                        ))
                    )
                }
            }
        }
    }

    private func handleApproval(_ request: AgentManagedApprovalRequest) async {
        let approvalKey = "\(request.threadID):\(request.itemID)"
        defer { approvalTasks.removeValue(forKey: approvalKey) }
        let correlation = AgentCorrelationID(rawValue: request.itemID)
        guard let instance = await emit(
            nativeSessionID: request.threadID,
            type: .approvalRequested,
            correlationID: correlation,
            payload: .approvalRequest(AgentApprovalRequest(
                summary: AgentPrivacyProjection.summary(request.summary),
                operationCorrelationID: correlation,
                expiresAt: Date().addingTimeInterval(75)
            ))
        ) else {
            // If the request cannot be represented safely in the normalized
            // store, fail closed instead of leaving the app-server blocked.
            try? await provider?.resolveApproval(request, allow: false)
            return
        }

        let controlRequest = AgentApprovalControlRequest(
            key: AgentApprovalControlKey(session: instance, requestID: correlation),
            summary: AgentPrivacyProjection.summary(request.summary) ?? "Codex approval required",
            expiresAt: Date().addingTimeInterval(75)
        )
        managedApprovalKeys.insert(controlRequest.key)
        defer { managedApprovalKeys.remove(controlRequest.key) }
        let decision = await approvals.request(controlRequest)

        guard let provider else { return }
        // This isolated app-server has no secondary approval UI. Timeout or
        // dismissal must fail closed so its turn cannot remain blocked forever.
        let allow = decision == .allow
        do {
            try await provider.resolveApproval(request, allow: allow)
            _ = await emit(
                nativeSessionID: request.threadID,
                type: .approvalResolved,
                correlationID: correlation,
                payload: .approvalResolution(AgentApprovalResolution(
                    state: allow ? .approved : .denied
                ))
            )
        } catch {
            _ = await emit(
                nativeSessionID: request.threadID,
                type: .approvalResolved,
                correlationID: correlation,
                payload: .approvalResolution(AgentApprovalResolution(state: .cancelled))
            )
            recordError(error, for: request.threadID)
        }
    }

    private func markManaged(_ descriptor: AgentManagedSessionDescriptor) {
        var value = managed[descriptor.nativeSessionID] ?? AgentManagedControlState(
            nativeSessionID: descriptor.nativeSessionID,
            activeTurnID: nil,
            isSubmitting: false,
            lastError: nil,
            acceptsDirectInput: descriptor.acceptsDirectInput
        )
        value.acceptsDirectInput = descriptor.acceptsDirectInput
        value.lastError = nil
        managed[descriptor.nativeSessionID] = value
    }

    private func updateControl(
        _ nativeSessionID: String,
        _ update: (inout AgentManagedControlState) -> Void
    ) {
        guard var state = managed[nativeSessionID] else { return }
        update(&state)
        managed[nativeSessionID] = state
    }

    private func recordError(_ error: Error, for nativeSessionID: String) {
        let message = Self.safeError(error)
        lastTransportError = message
        updateControl(nativeSessionID) { $0.lastError = message }
    }

    private func ensureProducer() async -> AgentProducerHandle? {
        if let producerHandle { return producerHandle }
        let result = await coordinator.registerProducer(
            descriptor: AgentProducerDescriptor(
                sourceInstanceID: AgentSourceInstanceID(rawValue: "codex-app-server-v2"),
                sourceKind: .officialLifecycleProtocol,
                runtimeVersion: nil
            ),
            policy: .codexAppServer,
            authenticatedProducerID: "codex-app-server-local"
        )
        guard case .success(let handle) = result else {
            lastTransportError = "Codex app-server producer registration failed"
            return nil
        }
        producerHandle = handle
        return handle
    }

    private func emitSessionAvailability(
        _ descriptor: AgentManagedSessionDescriptor,
        type: AgentEventType
    ) async -> AgentSessionInstanceID? {
        let project = projectContext(for: descriptor)
        let instance = await emit(
            nativeSessionID: descriptor.nativeSessionID,
            type: type,
            payload: .sessionMetadata(AgentSessionMetadata(
                project: project,
                availability: .loaded
            ))
        )

        let now = Date()
        let capabilities = AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues: [
            AgentCapability.sessionLifecycle,
            .planLifecycle,
            .toolLifecycle,
            .commandLifecycle,
            .approvalObservation,
            .approvalControl,
            .taskLifecycle,
            .tokenUsage,
            .contextUsage,
            .modelMetadata,
            .projectContext
        ].map {
            ($0, AgentCapabilityEvidence(
                authority: .lifecycle,
                source: "codex-app-server-v2",
                observedAt: now
            ))
        }))
        _ = await emit(
            nativeSessionID: descriptor.nativeSessionID,
            type: .capabilitiesUpdated,
            payload: .capabilities(capabilities)
        )
        return instance
    }

    @discardableResult
    private func emit(
        nativeSessionID: String,
        type: AgentEventType,
        correlationID: AgentCorrelationID? = nil,
        payload: AgentEventPayload,
        providerTimestamp: Date? = nil
    ) async -> AgentSessionInstanceID? {
        guard let handle = await ensureProducer() else { return nil }
        let event = AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: AgentEventID(rawValue: "codex-appserver-\(UUID().uuidString.lowercased())"),
            provider: .codex,
            source: .desktopApp,
            nativeSessionID: nativeSessionID,
            assertedGeneration: nil,
            type: type,
            providerTimestamp: providerTimestamp,
            receivedTimestamp: Date(),
            correlationID: correlationID,
            sequence: nil,
            authority: .lifecycle,
            payload: payload,
            continuity: AgentSessionContinuity(immutableIdentity: nativeSessionID)
        )
        let result = await coordinator.ingest(event, from: handle)
        guard case .success(let accepted) = result else { return nil }
        return accepted.sessionInstances.last
    }

    private static let maximumTranscriptEntries = 80

    private static func boundedTranscript(
        _ entries: [AgentManagedTranscriptEntry]
    ) -> [AgentManagedTranscriptEntry] {
        Array(
            entries
                .sorted {
                    if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                    return $0.id < $1.id
                }
                .suffix(maximumTranscriptEntries)
        )
    }

    private static func mergedTranscript(
        current: [AgentManagedTranscriptEntry],
        incoming: [AgentManagedTranscriptEntry]
    ) -> [AgentManagedTranscriptEntry] {
        var entries = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
        for entry in incoming {
            if entry.role == .user, let turnID = entry.turnID,
               !entry.id.hasPrefix("submitted-user:") {
                let provisionalKeys = entries.compactMap { key, existing in
                    existing.id.hasPrefix("submitted-user:") &&
                        existing.turnID == turnID && existing.role == .user ? key : nil
                }
                for key in provisionalKeys { entries.removeValue(forKey: key) }
            }
            entries[entry.id] = entry
        }
        return boundedTranscript(Array(entries.values))
    }

    private func projectAcceptedUserPrompt(
        _ prompt: String,
        nativeSessionID: String,
        turnID: String
    ) {
        let entries = transcripts[nativeSessionID] ?? []
        guard !entries.contains(where: {
            $0.turnID == turnID && $0.role == .user && $0.text == prompt
        }) else { return }
        upsertTranscript(AgentManagedTranscriptEntry(
            id: "submitted-user:\(nativeSessionID):\(turnID)",
            nativeSessionID: nativeSessionID,
            turnID: turnID,
            role: .user,
            text: prompt,
            timestamp: Date()
        ))
    }

    private func upsertTranscript(_ entry: AgentManagedTranscriptEntry) {
        var entries = transcripts[entry.nativeSessionID] ?? []
        if entry.role == .user, let turnID = entry.turnID,
           !entry.id.hasPrefix("submitted-user:") {
            entries.removeAll {
                $0.id.hasPrefix("submitted-user:") &&
                    $0.turnID == turnID && $0.role == .user
            }
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        transcripts[entry.nativeSessionID] = Self.boundedTranscript(entries)
    }

    private func appendTranscriptDelta(
        nativeSessionID: String,
        turnID: String,
        itemID: String,
        delta: String
    ) {
        guard !delta.isEmpty else { return }
        var entries = transcripts[nativeSessionID] ?? []
        if let index = entries.firstIndex(where: { $0.id == itemID }) {
            let combined = entries[index].text + delta
            let bounded = AgentManagedTranscriptEntry.boundedText(combined) ?? entries[index].text
            entries[index] = AgentManagedTranscriptEntry(
                id: itemID,
                nativeSessionID: nativeSessionID,
                turnID: turnID,
                role: .agent,
                text: bounded,
                timestamp: entries[index].timestamp
            )
        } else if let bounded = AgentManagedTranscriptEntry.boundedText(delta) {
            entries.append(AgentManagedTranscriptEntry(
                id: itemID,
                nativeSessionID: nativeSessionID,
                turnID: turnID,
                role: .agent,
                text: bounded,
                timestamp: Date()
            ))
        }
        transcripts[nativeSessionID] = Self.boundedTranscript(entries)
    }

    private nonisolated static func safeError(_ error: Error) -> String {
        let value: String
        if let error = error as? CodexAppServerError {
            switch error {
            case .executableNotFound: value = "Codex executable not found"
            case .launchFailed: value = "Could not start Codex app-server"
            case .notRunning: value = "Codex app-server is not running"
            case .requestTimedOut(let method): value = "\(method) timed out"
            case .transportClosed: value = "Codex app-server disconnected"
            case .malformedMessage: value = "Malformed Codex app-server message"
            case .rpcError: value = "Codex app-server request failed"
            case .invalidResponse(let method): value = "Invalid \(method) response"
            }
        } else {
            value = "Codex control request failed"
        }
        return AgentPrivacyProjection.title(value, fallback: "Codex control error")
    }
}
