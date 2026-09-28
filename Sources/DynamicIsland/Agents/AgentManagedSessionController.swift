import AgentBridgeShared
import Foundation

@MainActor
final class AgentManagedSessionController: ObservableObject {
    @Published private(set) var managed: [AgentSessionID: AgentManagedControlState] = [:]
    @Published private(set) var connecting: Set<AgentSessionID> = []
    @Published private(set) var discoveredSessionIDs: Set<AgentSessionID> = []
    @Published private(set) var lastTransportError: String?
    @Published private(set) var transportErrorsByProvider: [AgentProvider: String] = [:]
    @Published private(set) var accountUsageByProvider: [AgentProvider: AgentUsage] = [:]
    @Published private(set) var transcripts: [AgentSessionID: [AgentManagedTranscriptEntry]] = [:]
    @Published private(set) var modelsByProvider: [AgentProvider: [AgentManagedModelDescriptor]] = [:]
    @Published private(set) var pendingModelOverrides: [AgentSessionID: String] = [:]
    @Published private(set) var newSessionModelByProvider: [AgentProvider: String] = [:]
    @Published private(set) var selectedProvider: AgentProvider?
    @Published private(set) var selectedSessionIDs: [AgentProvider: AgentSessionInstanceID] = [:]
    @Published private(set) var verifiedAttachmentSessionIDs: Set<AgentSessionID> = []
    @Published private(set) var reconcilingAttachmentSessionIDs: Set<AgentSessionID> = []
    @Published private(set) var attachmentErrors: [AgentSessionID: String] = [:]

    private let providers: [AgentProvider: any AgentInteractiveProvider]
    private let coordinator: AgentIngestionCoordinator
    private let eventStore: AgentEventStore
    private let approvals: AgentApprovalController

    private var producerHandles: [AgentProvider: AgentProducerHandle] = [:]
    private var eventTasks: [AgentProvider: Task<Void, Never>] = [:]
    private var snapshotTask: Task<Void, Never>?
    private var inFlightSnapshotRefresh: Task<Void, Never>?
    private var approvalTasks: [String: Task<Void, Never>] = [:]
    private var managedApprovalKeys: Set<AgentApprovalControlKey> = []
    private var pendingApprovalConfirmations: [String: PendingApprovalConfirmation] = [:]
    private var knownDiscoveredSessionIDs: Set<AgentSessionID> = []

    init(
        provider: (any AgentInteractiveProvider)?,
        coordinator: AgentIngestionCoordinator,
        eventStore: AgentEventStore,
        approvals: AgentApprovalController
    ) {
        self.providers = provider.map { [$0.provider: $0] } ?? [:]
        self.coordinator = coordinator
        self.eventStore = eventStore
        self.approvals = approvals
        selectedProvider = provider?.provider
    }

    init(
        providers: [any AgentInteractiveProvider],
        coordinator: AgentIngestionCoordinator,
        eventStore: AgentEventStore,
        approvals: AgentApprovalController
    ) {
        self.providers = Dictionary(uniqueKeysWithValues: providers.map { ($0.provider, $0) })
        self.coordinator = coordinator
        self.eventStore = eventStore
        self.approvals = approvals
        selectedProvider = Self.sortedProviders(self.providers.keys).first
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

    var isAvailable: Bool { !providers.isEmpty }

    var managedProvider: AgentProvider? { selectedProvider ?? managedProviders.first }

    var selectedSessionID: AgentSessionInstanceID? {
        guard let selectedProvider else { return nil }
        return selectedSessionIDs[selectedProvider]
    }

    var accountUsage: AgentUsage {
        guard let provider = managedProvider else { return AgentUsage() }
        return accountUsageByProvider[provider] ?? AgentUsage()
    }

    var availableModels: [AgentManagedModelDescriptor] {
        guard let provider = managedProvider else { return [] }
        return availableModels(for: provider)
    }

    func availableModels(for provider: AgentProvider) -> [AgentManagedModelDescriptor] {
        modelsByProvider[provider] ?? []
    }

    func availableModels(for session: AgentSession) -> [AgentManagedModelDescriptor] {
        availableModels(for: session.id.sessionID.provider)
    }

    var managedProviders: [AgentProvider] {
        Self.sortedProviders(providers.compactMap { provider, adapter in
            adapter.interactiveCapabilities.intersection([
                .startSession, .resumeSession, .submitPrompt
            ]).isEmpty ? nil : provider
        })
    }

    var modelSelectionScope: AgentModelSelectionScope? {
        guard let provider = managedProvider else { return nil }
        return modelSelectionScope(for: provider)
    }

    func modelSelectionScope(for provider: AgentProvider) -> AgentModelSelectionScope? {
        providers[provider]?.modelSelectionScope
    }

    func modelSelectionScope(for session: AgentSession) -> AgentModelSelectionScope? {
        modelSelectionScope(for: session.id.sessionID.provider)
    }

    func capabilities(for agentProvider: AgentProvider) -> Set<AgentInteractiveCapability> {
        providers[agentProvider]?.interactiveCapabilities ?? []
    }

    func supportsManagedControl(for session: AgentSession) -> Bool {
        !capabilities(for: session.id.sessionID.provider).intersection([
            .resumeSession, .submitPrompt
        ]).isEmpty
    }

    var interactiveCapabilities: Set<AgentInteractiveCapability> {
        guard let provider = managedProvider else { return [] }
        return capabilities(for: provider)
    }

    var activeManagedSessionIDs: Set<AgentSessionID> {
        Set(managed.compactMap { sessionID, state in
            state.activeTurnID == nil ? nil : sessionID
        })
    }


    func approvalPolicy(for session: AgentSession) -> AgentApprovalPolicyMode {
        approvals.approvalPolicy(for: session.id)
    }

    func setApprovalPolicyChoice(_ choice: AgentApprovalPolicyChoice, for session: AgentSession) {
        guard capabilities(for: session.id.sessionID.provider).contains(.resolveApprovals),
              session.capabilities.contains(.approvalControl) else {
            approvals.setAutoApprove(false, for: session.id)
            return
        }
        switch choice {
        case .askEveryTime:
            approvals.setAutoApprove(false, for: session.id)
        case .autoApprove:
            approvals.setAutoApprove(true, for: session.id)
        }
    }

    func selectProvider(_ provider: AgentProvider) {
        guard managedProviders.contains(provider) else { return }
        selectedProvider = provider
        lastTransportError = transportErrorsByProvider[provider]
    }

    func selectSession(_ sessionID: AgentSessionInstanceID?) {
        if let provider = sessionID?.sessionID.provider {
            selectedProvider = provider
            selectedSessionIDs[provider] = sessionID
        } else if let selectedProvider {
            selectedSessionIDs.removeValue(forKey: selectedProvider)
        }
    }

    func reconcileSelection(with sessions: [AgentSession]) {
        let validInstances = Set(sessions.map(\.id))
        approvals.retainPolicies(for: validInstances)

        let candidates = selectedProvider.map { provider in
            sessions.filter { $0.id.sessionID.provider == provider }
        } ?? sessions
        let resolved = AgentWorkspaceSelection.resolve(
            current: selectedSessionID,
            sessions: candidates,
            activeManagedSessionIDs: activeManagedSessionIDs
        )
        if let provider = selectedProvider, selectedSessionIDs[provider] != resolved {
            selectedSessionIDs[provider] = resolved
        }
        if selectedProvider == nil, let provider = resolved?.sessionID.provider {
            selectedProvider = provider
        }
    }

    func startObserving() {
        guard !providers.isEmpty else { return }

        for (agentProvider, adapter) in providers where eventTasks[agentProvider] == nil {
            eventTasks[agentProvider] = Task { [weak self] in
                let stream = await adapter.events()
                for await event in stream {
                    guard !Task.isCancelled else { break }
                    await self?.handle(event, from: agentProvider)
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
        for task in eventTasks.values { task.cancel() }
        eventTasks.removeAll()
        snapshotTask?.cancel()
        snapshotTask = nil
        inFlightSnapshotRefresh?.cancel()
        inFlightSnapshotRefresh = nil
        for task in approvalTasks.values { task.cancel() }
        approvalTasks.removeAll()
        managedApprovalKeys.removeAll()
        pendingApprovalConfirmations.removeAll()
        approvals.clearPolicies()
        managed.removeAll()
        connecting.removeAll()
        discoveredSessionIDs.removeAll()
        knownDiscoveredSessionIDs.removeAll()
        accountUsageByProvider.removeAll()
        transportErrorsByProvider.removeAll()
        transcripts.removeAll()
        modelsByProvider.removeAll()
        verifiedAttachmentSessionIDs.removeAll()
        reconcilingAttachmentSessionIDs.removeAll()
        attachmentErrors.removeAll()

        let providers = self.providers
        let coordinator = self.coordinator
        let handles = producerHandles.values
        producerHandles.removeAll()
        Task {
            for handle in handles {
                _ = await coordinator.unregisterProducer(handle)
            }
            for provider in providers.values { await provider.stop() }
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
        guard !Task.isCancelled else { return }
        for (agentProvider, provider) in providers {
            await refreshPersistentSnapshot(for: agentProvider, using: provider)
        }
        reconcileSelection(with: eventStore.sessions.filter(shouldPresent))
    }

    private func refreshPersistentSnapshot(
        for agentProvider: AgentProvider,
        using provider: any AgentInteractiveProvider
    ) async {
        if provider.interactiveCapabilities.contains(.selectModel),
           let models = try? await provider.listModels() {
            let filtered = models.filter { !$0.model.isEmpty }
            modelsByProvider[agentProvider] = filtered
            let validModels = Set(filtered.map(\.model))
            pendingModelOverrides = pendingModelOverrides.filter { sessionID, model in
                sessionID.provider != agentProvider || validModels.contains(model)
            }
        }

        if provider.interactiveCapabilities.contains(.accountUsage) {
            do {
                let refreshed = try await provider.readAccountUsage()
                guard !Task.isCancelled else { return }
                var retained = accountUsageByProvider[agentProvider] ?? AgentUsage()
                retained.merge(refreshed)
                accountUsageByProvider[agentProvider] = retained
                setTransportError(nil, for: agentProvider)
            } catch {
                // Preserve the last trustworthy snapshot across transient provider failures.
                setTransportError(Self.safeError(error, provider: agentProvider), for: agentProvider)
            }
        } else {
            // Unsupported providers must never inherit/fabricate another provider's account usage.
            accountUsageByProvider.removeValue(forKey: agentProvider)
        }

        do {
            let discovered = try await provider.discoverSessions()
            guard !Task.isCancelled else { return }
            let refreshedIDs = Set(discovered.map(\.session.sessionID))
            discoveredSessionIDs.subtract(discoveredSessionIDs.filter { $0.provider == agentProvider })
            discoveredSessionIDs.formUnion(refreshedIDs)
            knownDiscoveredSessionIDs.formUnion(refreshedIDs)
            for descriptor in discovered {
                await registerDiscoveredSession(descriptor)
            }
        } catch {
            setTransportError(Self.safeError(error, provider: agentProvider), for: agentProvider)
        }
    }

    private static func sortedProviders<S: Sequence>(_ providers: S) -> [AgentProvider]
    where S.Element == AgentProvider {
        Array(providers).sorted { $0.deterministicSortKey < $1.deterministicSortKey }
    }

    private func registerDiscoveredSession(
        _ discovered: AgentDiscoveredSessionDescriptor
    ) async {
        let descriptor = discovered.session
        let sessionID = descriptor.sessionID
        verifiedAttachmentSessionIDs.insert(sessionID)
        let existing = eventStore.sessions.first {
            $0.id.sessionID == sessionID && $0.endedAt == nil
        }

        if existing == nil {
            _ = await emitDiscoveredSessionStart(discovered)
        } else {
            _ = await emit(
                provider: descriptor.provider,
                nativeSessionID: descriptor.nativeSessionID,
                type: .sessionMetadataUpdated,
                payload: .sessionMetadata(AgentSessionMetadata(
                    project: projectContext(for: descriptor),
                    availability: availability(for: discovered.runtimeState)
                )),
                providerTimestamp: min(discovered.updatedAt, Date())
            )
        }

        if let pending = pendingModelOverrides[sessionID],
           descriptor.model == pending {
            pendingModelOverrides.removeValue(forKey: sessionID)
        }

        if discovered.runtimeState == .systemError {
            _ = await emit(
                provider: descriptor.provider,
                nativeSessionID: descriptor.nativeSessionID,
                type: .taskFailed,
                payload: .terminal(AgentTerminalEvent(
                    summary: "\(providerName(descriptor.provider)) runtime unavailable"
                ))
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
            provider: descriptor.provider,
            nativeSessionID: descriptor.nativeSessionID,
            type: .sessionResumed,
            payload: .sessionMetadata(AgentSessionMetadata(project: projectContext(for: descriptor)))
        )
        _ = await emit(
            provider: descriptor.provider,
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
            provider: descriptor.provider,
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
                source: managedSourceID(for: descriptor.provider),
                observedAt: now
            ))
        }))
        _ = await emit(
            provider: descriptor.provider,
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
            sourceApplication: AgentSourceApplication(
                displayName: providerName(descriptor.provider),
                bundleIdentifier: nil
            )
        )
    }

    private func availability(
        for state: AgentDiscoveredSessionRuntimeState
    ) -> AgentSessionAvailability {
        state == .notLoaded ? .resumable : .loaded
    }

    func isManaged(_ session: AgentSession) -> Bool {
        managed[session.id.sessionID] != nil
    }

    func mode(for session: AgentSession) -> AgentConsoleMode {
        guard let state = managed[session.id.sessionID],
              capabilities(for: session.id.sessionID.provider).contains(.submitPrompt),
              state.acceptsDirectInput else {
            return .observed
        }
        let canInterrupt = state.canInterrupt &&
            capabilities(for: session.id.sessionID.provider).contains(.interrupt)
        return .interactive(canInterrupt: canInterrupt)
    }

    func statusMessage(for session: AgentSession) -> String? {
        if connecting.contains(session.id.sessionID) {
            return "Connecting…"
        }
        if reconcilingAttachmentSessionIDs.contains(session.id.sessionID) {
            return "Checking official thread…"
        }
        if managed[session.id.sessionID] == nil, session.state == .waitingForApproval {
            return "External approval · respond in source app"
        }
        if managed[session.id.sessionID] == nil, Self.hasExternallyActiveTurn(session) {
            return "Observed externally · managed control not attached"
        }
        if let attachmentError = attachmentErrors[session.id.sessionID] {
            return attachmentError
        }
        return managed[session.id.sessionID]?.lastError
    }

    func transcript(for session: AgentSession) -> [AgentManagedTranscriptEntry] {
        transcripts[session.id.sessionID] ?? []
    }

    /// Reconciles an observed session with the provider's exact native thread
    /// before offering managed control. This does not resume or create a thread.
    func reconcileObservedSession(_ session: AgentSession, limit: Int = 80) async {
        let sessionID = session.id.sessionID
        guard managed[sessionID] == nil,
              !reconcilingAttachmentSessionIDs.contains(sessionID),
              let provider = providers[sessionID.provider] else { return }

        reconcilingAttachmentSessionIDs.insert(sessionID)
        defer { reconcilingAttachmentSessionIDs.remove(sessionID) }
        do {
            guard let exact = try await provider.inspectSession(
                nativeSessionID: sessionID.nativeID
            ), exact.sessionID == sessionID else {
                verifiedAttachmentSessionIDs.remove(sessionID)
                attachmentErrors[sessionID] = "Official thread is unavailable for managed attachment"
                return
            }
            if provider.interactiveCapabilities.contains(.loadHistory) {
                try await hydrateTranscript(
                    sessionID: sessionID,
                    provider: provider,
                    limit: limit
                )
            }
            knownDiscoveredSessionIDs.insert(sessionID)
            verifiedAttachmentSessionIDs.insert(sessionID)
            attachmentErrors.removeValue(forKey: sessionID)
        } catch {
            verifiedAttachmentSessionIDs.remove(sessionID)
            attachmentErrors[sessionID] = "Official thread is unavailable for managed attachment"
        }
    }

    func refreshTranscript(for session: AgentSession, limit: Int = 80) async {
        guard let provider = providers[session.id.sessionID.provider],
              provider.interactiveCapabilities.contains(.loadHistory) else { return }
        do {
            try await hydrateTranscript(
                sessionID: session.id.sessionID,
                provider: provider,
                limit: limit
            )
        } catch CodexAppServerError.rpcError(let code, _) where code == -32601 {
            // Some persisted/legacy threads cannot serve the paginated v2
            // history method. Keep any live trustworthy entries and leave
            // control usable instead of surfacing an unrelated transport error.
            return
        } catch {
            recordError(error, for: session.id.sessionID)
        }
    }

    func canConnect(_ session: AgentSession) -> Bool {
        guard let provider = providers[session.id.sessionID.provider] else { return false }
        return
            provider.interactiveCapabilities.contains(.resumeSession) &&
            managed[session.id.sessionID] == nil &&
            verifiedAttachmentSessionIDs.contains(session.id.sessionID) &&
            attachmentErrors[session.id.sessionID] == nil &&
            !Self.hasExternallyActiveTurn(session) &&
            !connecting.contains(session.id.sessionID)
    }

    func shouldPresent(_ session: AgentSession) -> Bool {
        let sessionID = session.id.sessionID
        guard providers[sessionID.provider] != nil else { return true }
        guard knownDiscoveredSessionIDs.contains(sessionID) else { return true }
        if discoveredSessionIDs.contains(sessionID) || managed[sessionID] != nil { return true }
        switch AgentSessionPresentation.priority(for: session) {
        case .actionRequired, .failure, .working, .thinking:
            return true
        case .idle, .recent:
            return false
        }
    }

    func connect(_ session: AgentSession) {
        guard canConnect(session), let provider = providers[session.id.sessionID.provider] else { return }
        startObserving()
        let sessionID = session.id.sessionID
        let nativeID = session.id.sessionID.nativeID
        connecting.insert(sessionID)
        Task { [weak self] in
            guard let self else { return }
            do {
                guard let inspected = try await provider.inspectSession(nativeSessionID: nativeID),
                      inspected.sessionID == sessionID else {
                    throw CodexAppServerError.invalidResponse("thread/read identity mismatch")
                }
                if provider.interactiveCapabilities.contains(.loadHistory) {
                    try await self.hydrateTranscript(
                        sessionID: sessionID,
                        provider: provider,
                        limit: 80
                    )
                }
                let descriptor = try await provider.resumeSession(
                    nativeSessionID: nativeID,
                    cwd: session.project.workingDirectory
                )
                guard descriptor.nativeSessionID == nativeID else {
                    throw CodexAppServerError.invalidResponse("thread/resume identity mismatch")
                }
                self.markManaged(descriptor)
                self.verifiedAttachmentSessionIDs.insert(sessionID)
                self.attachmentErrors.removeValue(forKey: sessionID)
                _ = await self.emitSessionAvailability(descriptor, type: .sessionResumed)
            } catch {
                self.verifiedAttachmentSessionIDs.remove(sessionID)
                self.attachmentErrors[sessionID] = "Official thread could not be attached"
            }
            self.connecting.remove(sessionID)
        }
    }

    private func hydrateTranscript(
        sessionID: AgentSessionID,
        provider: any AgentInteractiveProvider,
        limit: Int
    ) async throws {
        let entries = try await provider.readTranscript(
            nativeSessionID: sessionID.nativeID,
            limit: min(max(limit, 1), 100)
        )
        guard entries.allSatisfy({ $0.nativeSessionID == sessionID.nativeID }) else {
            throw CodexAppServerError.invalidResponse("thread/items/list identity mismatch")
        }
        transcripts[sessionID] = Self.mergedTranscript(
            current: transcripts[sessionID] ?? [],
            incoming: entries
        )
    }

    private static func hasExternallyActiveTurn(_ session: AgentSession) -> Bool {
        switch session.state {
        case .working, .runningTool, .runningCommand, .thinking, .planning,
             .planReady, .waitingForApproval, .waitingForUser:
            true
        case .idle, .completed, .failed, .interrupted:
            false
        }
    }

    @discardableResult
    func startNewSession(cwd: String?) async -> AgentManagedSessionDescriptor? {
        guard let selectedProvider,
              let provider = providers[selectedProvider],
              provider.interactiveCapabilities.contains(.startSession) else { return nil }
        startObserving()
        do {
            let descriptor = try await provider.startSession(
                cwd: cwd,
                model: newSessionModelByProvider[selectedProvider]
            )
            markManaged(descriptor)
            _ = await emitSessionAvailability(descriptor, type: .sessionStarted)
            return descriptor
        } catch {
            setTransportError(Self.safeError(error, provider: selectedProvider), for: selectedProvider)
            return nil
        }
    }

    func selectedModel(for session: AgentSession) -> String? {
        session.project.model
    }

    func pendingModel(for session: AgentSession) -> String? {
        pendingModelOverrides[session.id.sessionID]
    }

    func newSessionModel(for provider: AgentProvider) -> String? {
        newSessionModelByProvider[provider]
    }

    @discardableResult
    func selectNewSessionModel(_ model: String?, for provider: AgentProvider) -> Bool {
        guard capabilities(for: provider).contains(.selectModel) else { return false }
        guard let model else {
            newSessionModelByProvider.removeValue(forKey: provider)
            return true
        }
        guard (modelsByProvider[provider] ?? []).contains(where: { $0.model == model }) else {
            return false
        }
        newSessionModelByProvider[provider] = model
        return true
    }

    func canSelectModel(for session: AgentSession) -> Bool {
        guard let provider = providers[session.id.sessionID.provider],
              provider.interactiveCapabilities.contains(.selectModel),
              provider.modelSelectionScope != nil else { return false }
        if let control = managed[session.id.sessionID] {
            return control.activeTurnID == nil && !control.isSubmitting
        }
        return true
    }

    @discardableResult
    func selectModel(_ model: String?, for session: AgentSession) -> Bool {
        guard canSelectModel(for: session) else { return false }
        let sessionID = session.id.sessionID
        guard let model else {
            pendingModelOverrides.removeValue(forKey: sessionID)
            return true
        }
        guard (modelsByProvider[sessionID.provider] ?? []).contains(where: { $0.model == model }) else {
            return false
        }
        pendingModelOverrides[sessionID] = model
        return true
    }

    /// Returns true only after the provider accepts the authoritative turn/start.
    /// The caller can therefore keep its draft intact across transport/RPC failure.
    func submit(_ prompt: String, for session: AgentSession) async -> Bool {
        guard let provider = providers[session.id.sessionID.provider],
              provider.interactiveCapabilities.contains(.submitPrompt),
              let bounded = AgentPromptDraftPolicy.submission(from: prompt),
              var state = managed[session.id.sessionID],
              state.acceptsDirectInput,
              !state.isSubmitting else {
            return false
        }

        state.isSubmitting = true
        state.lastError = nil
        managed[session.id.sessionID] = state
        let sessionID = session.id.sessionID
        let nativeID = session.id.sessionID.nativeID

        do {
            let turn = try await provider.submit(
                prompt: bounded,
                nativeSessionID: nativeID,
                model: pendingModelOverrides[session.id.sessionID]
            )
            updateControl(sessionID) {
                $0.isSubmitting = false
                $0.activeTurnID = turn.turnID
                $0.lastError = nil
            }
            projectAcceptedUserPrompt(
                bounded,
                sessionID: sessionID,
                turnID: turn.turnID
            )
            await projectManagedTurnStartIfNeeded(
                provider: sessionID.provider,
                nativeSessionID: nativeID,
                turnID: turn.turnID
            )
            Task { @MainActor [weak self] in
                await self?.refreshPersistentSnapshot()
            }
            return true
        } catch {
            let message = Self.safeError(error, provider: sessionID.provider)
            setTransportError(message, for: sessionID.provider)
            updateControl(sessionID) {
                $0.isSubmitting = false
                $0.lastError = message
            }
            return false
        }
    }

    func interrupt(_ session: AgentSession) {
        guard let provider = providers[session.id.sessionID.provider],
              provider.interactiveCapabilities.contains(.interrupt),
              let state = managed[session.id.sessionID],
              let turnID = state.activeTurnID else {
            return
        }
        let nativeID = session.id.sessionID.nativeID
        Task { [weak self] in
            do {
                try await provider.interrupt(nativeSessionID: nativeID, turnID: turnID)
            } catch {
                self?.recordError(error, for: session.id.sessionID)
            }
        }
    }

    private func handle(
        _ event: AgentInteractiveProviderEvent,
        from agentProvider: AgentProvider
    ) async {
        switch event {
        case .threadAvailable(let descriptor):
            guard descriptor.provider == agentProvider else { return }
            discoveredSessionIDs.insert(descriptor.sessionID)
            knownDiscoveredSessionIDs.insert(descriptor.sessionID)
            markManaged(descriptor)
            await refreshPersistentSnapshot()

        case .turnStarted(let turn):
            let sessionID = AgentSessionID(provider: agentProvider, nativeID: turn.nativeSessionID)
            updateControl(sessionID) {
                $0.activeTurnID = turn.turnID
                $0.isSubmitting = false
                $0.lastError = nil
            }
            _ = await emit(
                provider: agentProvider,
                nativeSessionID: turn.nativeSessionID,
                type: .sessionResumed,
                correlationID: AgentCorrelationID(rawValue: turn.turnID),
                payload: .none
            )
            _ = await emit(
                provider: agentProvider,
                nativeSessionID: turn.nativeSessionID,
                type: .agentWorking,
                correlationID: AgentCorrelationID(rawValue: turn.turnID),
                payload: .activity(AgentActivityDescriptor(
                    title: "Working",
                    summary: nil
                ))
            )
            reconcileSelection(with: eventStore.sessions.filter(shouldPresent))
            await refreshPersistentSnapshot()

        case .turnCompleted(let turn, let state, let summary):
            await confirmApprovalProgress(
                provider: agentProvider,
                nativeSessionID: turn.nativeSessionID,
                turnID: turn.turnID
            )
            let sessionID = AgentSessionID(provider: agentProvider, nativeID: turn.nativeSessionID)
            updateControl(sessionID) {
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
                provider: agentProvider,
                nativeSessionID: turn.nativeSessionID,
                type: type,
                correlationID: AgentCorrelationID(rawValue: turn.turnID),
                payload: .terminal(AgentTerminalEvent(
                    summary: AgentPrivacyProjection.summary(summary) ??
                        (state == .completed ? "\(providerName(agentProvider)) turn completed" :
                            state == .interrupted ? "\(providerName(agentProvider)) turn interrupted" :
                            "\(providerName(agentProvider)) turn failed")
                ))
            )
            await refreshPersistentSnapshot()

        case .providerFailure(let nativeSessionID, let summary):
            let targets: [AgentSessionID]
            if let nativeSessionID {
                targets = [AgentSessionID(provider: agentProvider, nativeID: nativeSessionID)]
            } else {
                targets = managed.compactMap { key, value in
                    key.provider == agentProvider && value.activeTurnID != nil ? key : nil
                }
            }
            for target in targets {
                updateControl(target) {
                    $0.activeTurnID = nil
                    $0.isSubmitting = false
                    $0.lastError = AgentPrivacyProjection.summary(summary) ??
                        "\(providerName(agentProvider)) turn failed"
                }
                _ = await emit(
                    provider: agentProvider,
                    nativeSessionID: target.nativeID,
                    type: .taskFailed,
                    payload: .terminal(AgentTerminalEvent(
                        summary: AgentPrivacyProjection.summary(summary) ??
                            "\(providerName(agentProvider)) turn failed"
                    ))
                )
            }
            await refreshPersistentSnapshot()

        case .transcript(let entry):
            if let turnID = entry.turnID {
                await confirmApprovalProgress(
                    provider: agentProvider,
                    nativeSessionID: entry.nativeSessionID,
                    turnID: turnID
                )
            }
            upsertTranscript(entry, provider: agentProvider)

        case .transcriptDelta(let nativeSessionID, let turnID, let itemID, let delta):
            await confirmApprovalProgress(
                provider: agentProvider,
                nativeSessionID: nativeSessionID,
                turnID: turnID
            )
            appendTranscriptDelta(
                sessionID: AgentSessionID(provider: agentProvider, nativeID: nativeSessionID),
                turnID: turnID,
                itemID: itemID,
                delta: delta
            )

        case .accountUsageChanged:
            await refreshPersistentSnapshot()

        case .normalized(let event):
            if let turnID = event.turnID {
                await confirmApprovalProgress(
                    provider: agentProvider,
                    nativeSessionID: event.nativeSessionID,
                    turnID: turnID
                )
            }
            _ = await emit(
                provider: agentProvider,
                nativeSessionID: event.nativeSessionID,
                type: event.type,
                correlationID: event.correlationID,
                payload: event.payload
            )

        case .approvalRequested(let request):
            await confirmApprovalProgress(
                provider: agentProvider,
                nativeSessionID: request.threadID,
                turnID: request.turnID
            )
            let key = "\(agentProvider.stableName):\(request.threadID):\(request.turnID):\(request.requestID)"
            guard approvalTasks[key] == nil else { return }
            approvalTasks[key] = Task { [weak self] in
                await self?.handleApproval(request, provider: agentProvider)
            }

        case .transportClosed:
            approvals.clearPolicies(for: agentProvider)
            let transportMessage = agentProvider == .codex
                ? "Codex app-server disconnected"
                : "\(providerName(agentProvider)) unavailable"
            setTransportError(transportMessage, for: agentProvider)
            for key in managedApprovalKeys where key.session.sessionID.provider == agentProvider {
                _ = approvals.resolve(
                    session: key.session,
                    requestID: key.requestID,
                    decision: .deny
                )
            }
            let managedIDs = managed.keys.filter { $0.provider == agentProvider }
            for key in managedIDs {
                updateControl(key) {
                    $0.activeTurnID = nil
                    $0.isSubmitting = false
                    $0.lastError = transportMessage
                }
                if eventStore.sessions.contains(where: {
                    $0.id.sessionID == key && $0.isActive
                }) {
                    _ = await emit(
                        provider: agentProvider,
                        nativeSessionID: key.nativeID,
                        type: .taskFailed,
                        payload: .terminal(AgentTerminalEvent(
                            summary: transportMessage
                        ))
                    )
                }
            }
        }
    }

    private func handleApproval(
        _ request: AgentManagedApprovalRequest,
        provider agentProvider: AgentProvider
    ) async {
        guard let provider = providers[agentProvider],
              provider.interactiveCapabilities.contains(.resolveApprovals) else {
            return
        }
        let approvalKey = "\(agentProvider.stableName):\(request.threadID):\(request.turnID):\(request.requestID)"
        defer { approvalTasks.removeValue(forKey: approvalKey) }
        let correlation = AgentCorrelationID(rawValue: request.requestID)
        let sessionID = AgentSessionID(provider: agentProvider, nativeID: request.threadID)
        guard managed[sessionID]?.activeTurnID == request.turnID,
              let existing = eventStore.sessions.first(where: {
                  $0.id.sessionID == sessionID && $0.endedAt == nil
              }),
              existing.capabilities.contains(.approvalControl) else {
            // A server request that cannot be bound to the exact managed
            // session and active turn is never projected into another
            // session's UI and is denied on its originating transport.
            try? await provider.resolveApproval(request, allow: false)
            return
        }
        guard let instance = await emit(
            provider: agentProvider,
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
            try? await provider.resolveApproval(request, allow: false)
            return
        }

        guard instance == existing.id else {
            try? await provider.resolveApproval(request, allow: false)
            return
        }

        let controlRequest = AgentApprovalControlRequest(
            key: AgentApprovalControlKey(session: instance, requestID: correlation),
            summary: AgentPrivacyProjection.summary(request.summary) ??
                "\(providerName(agentProvider)) approval required",
            expiresAt: Date().addingTimeInterval(75)
        )
        guard !approvals.hasHandled(controlRequest.key) else { return }
        let wasAutomatic = approvals.automaticallyApproves(controlRequest)
        managedApprovalKeys.insert(controlRequest.key)
        defer { managedApprovalKeys.remove(controlRequest.key) }
        guard let decision = await approvals.request(controlRequest) else {
            try? await provider.resolveApproval(request, allow: false)
            return
        }
        let allow = decision == .allow

        let confirmationKey = approvalKey
        pendingApprovalConfirmations[confirmationKey] = PendingApprovalConfirmation(
            provider: agentProvider,
            nativeSessionID: request.threadID,
            turnID: request.turnID,
            correlationID: correlation,
            state: allow ? .approved : .denied,
            automatic: allow && wasAutomatic
        )
        do {
            try await provider.resolveApproval(request, allow: allow)
        } catch {
            pendingApprovalConfirmations.removeValue(forKey: confirmationKey)
            _ = await emit(
                provider: agentProvider,
                nativeSessionID: request.threadID,
                type: .approvalResolved,
                correlationID: correlation,
                payload: .approvalResolution(AgentApprovalResolution(state: .cancelled))
            )
            recordError(error, for: AgentSessionID(
                provider: agentProvider,
                nativeID: request.threadID
            ))
        }
    }


    private func confirmApprovalProgress(
        provider: AgentProvider,
        nativeSessionID: String,
        turnID: String
    ) async {
        let matches = pendingApprovalConfirmations.filter { _, value in
            value.provider == provider &&
                value.nativeSessionID == nativeSessionID &&
                value.turnID == turnID
        }
        guard !matches.isEmpty else { return }
        for (key, confirmation) in matches {
            pendingApprovalConfirmations.removeValue(forKey: key)
            if confirmation.automatic && confirmation.state == .approved {
                upsertTranscript(AgentManagedTranscriptEntry(
                    id: "auto-approval:\(confirmation.nativeSessionID):\(confirmation.turnID):\(confirmation.correlationID.rawValue)",
                    nativeSessionID: confirmation.nativeSessionID,
                    turnID: confirmation.turnID,
                    role: .status,
                    text: "Approved automatically",
                    timestamp: Date()
                ), provider: provider)
            }
            _ = await emit(
                provider: provider,
                nativeSessionID: confirmation.nativeSessionID,
                type: .approvalResolved,
                correlationID: confirmation.correlationID,
                payload: .approvalResolution(AgentApprovalResolution(state: confirmation.state))
            )
        }
    }

    private func projectManagedTurnStartIfNeeded(
        provider: AgentProvider,
        nativeSessionID: String,
        turnID: String
    ) async {
        let sessionID = AgentSessionID(provider: provider, nativeID: nativeSessionID)
        let alreadyWorking = eventStore.sessions.first { $0.id.sessionID == sessionID }.map {
            switch $0.state {
            case .working, .runningTool, .runningCommand, .thinking, .planning,
                 .waitingForApproval, .waitingForUser:
                true
            default:
                false
            }
        } ?? false
        guard !alreadyWorking else { return }
        _ = await emit(
            provider: provider,
            nativeSessionID: nativeSessionID,
            type: .sessionResumed,
            correlationID: AgentCorrelationID(rawValue: turnID),
            payload: .none
        )
        _ = await emit(
            provider: provider,
            nativeSessionID: nativeSessionID,
            type: .agentWorking,
            correlationID: AgentCorrelationID(rawValue: turnID),
            payload: .activity(AgentActivityDescriptor(title: "Working", summary: nil))
        )
        reconcileSelection(with: eventStore.sessions.filter(shouldPresent))
    }

    private func markManaged(_ descriptor: AgentManagedSessionDescriptor) {
        var value = managed[descriptor.sessionID] ?? AgentManagedControlState(
            nativeSessionID: descriptor.nativeSessionID,
            activeTurnID: nil,
            isSubmitting: false,
            lastError: nil,
            acceptsDirectInput: descriptor.acceptsDirectInput
        )
        value.acceptsDirectInput = descriptor.acceptsDirectInput
        value.lastError = nil
        managed[descriptor.sessionID] = value
    }

    private func updateControl(
        _ sessionID: AgentSessionID,
        _ update: (inout AgentManagedControlState) -> Void
    ) {
        guard var state = managed[sessionID] else { return }
        update(&state)
        managed[sessionID] = state
    }

    private func recordError(_ error: Error, for sessionID: AgentSessionID) {
        let message = Self.safeError(error, provider: sessionID.provider)
        setTransportError(message, for: sessionID.provider)
        updateControl(sessionID) { $0.lastError = message }
    }

    private func setTransportError(_ message: String?, for provider: AgentProvider) {
        if let message {
            transportErrorsByProvider[provider] = message
        } else {
            transportErrorsByProvider.removeValue(forKey: provider)
        }
        if selectedProvider == provider || (selectedProvider == nil && managedProvider == provider) {
            lastTransportError = message
        }
    }

    private func ensureProducer(for provider: AgentProvider) async -> AgentProducerHandle? {
        if let handle = producerHandles[provider] { return handle }
        let sourceID = managedSourceID(for: provider)
        let policy: AgentProducerPolicy = provider == .codex ? .codexAppServer : .claudeManagedCLI
        let result = await coordinator.registerProducer(
            descriptor: AgentProducerDescriptor(
                sourceInstanceID: AgentSourceInstanceID(rawValue: sourceID),
                sourceKind: .officialLifecycleProtocol,
                runtimeVersion: nil
            ),
            policy: policy,
            authenticatedProducerID: "\(sourceID)-local"
        )
        guard case .success(let handle) = result else {
            setTransportError("\(providerName(provider)) producer registration failed", for: provider)
            return nil
        }
        producerHandles[provider] = handle
        return handle
    }

    private func managedSourceID(for provider: AgentProvider) -> String {
        switch provider {
        case .codex: "codex-app-server-v2"
        case .claude: "claude-managed-cli-v1"
        case .other(let name): "managed-\(name)"
        }
    }

    private func providerName(_ provider: AgentProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .other(let name): AgentPrivacyProjection.title(name, fallback: "Agent")
        }
    }

    private func emitSessionAvailability(
        _ descriptor: AgentManagedSessionDescriptor,
        type: AgentEventType
    ) async -> AgentSessionInstanceID? {
        let project = projectContext(for: descriptor)
        let instance = await emit(
            provider: descriptor.provider,
            nativeSessionID: descriptor.nativeSessionID,
            type: type,
            payload: .sessionMetadata(AgentSessionMetadata(
                project: project,
                availability: .loaded
            ))
        )

        let now = Date()
        let capabilities = AgentCapabilities(evidence: Dictionary(uniqueKeysWithValues:
            normalizedCapabilities(for: descriptor.provider).map {
            ($0, AgentCapabilityEvidence(
                authority: .lifecycle,
                source: managedSourceID(for: descriptor.provider),
                observedAt: now
            ))
        }))
        _ = await emit(
            provider: descriptor.provider,
            nativeSessionID: descriptor.nativeSessionID,
            type: .capabilitiesUpdated,
            payload: .capabilities(capabilities)
        )
        return instance
    }

    @discardableResult
    private func emit(
        provider: AgentProvider,
        nativeSessionID: String,
        type: AgentEventType,
        correlationID: AgentCorrelationID? = nil,
        payload: AgentEventPayload,
        providerTimestamp: Date? = nil
    ) async -> AgentSessionInstanceID? {
        guard let handle = await ensureProducer(for: provider) else { return nil }
        let event = AgentIngestionEvent(
            schemaVersion: AgentEvent.normalizedSchemaVersion,
            eventID: AgentEventID(rawValue:
                "\(provider.stableName)-managed-\(UUID().uuidString.lowercased())"),
            provider: provider,
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

    private func normalizedCapabilities(for provider: AgentProvider) -> Set<AgentCapability> {
        let interactive = capabilities(for: provider)
        var result: Set<AgentCapability> = [.sessionLifecycle, .taskLifecycle, .projectContext]
        if interactive.contains(.streamToolActivity) {
            result.formUnion([.toolLifecycle, .commandLifecycle])
        }
        if interactive.contains(.resolveApprovals) {
            result.formUnion([.approvalObservation, .approvalControl])
        }
        if interactive.contains(.accountUsage) { result.insert(.quotaUsage) }
        if interactive.contains(.contextUsage) {
            result.formUnion([.tokenUsage, .contextUsage])
        }
        if interactive.contains(.selectModel) { result.insert(.modelMetadata) }
        if provider == .codex { result.insert(.planLifecycle) }
        return result
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
        sessionID: AgentSessionID,
        turnID: String
    ) {
        let entries = transcripts[sessionID] ?? []
        guard !entries.contains(where: {
            $0.turnID == turnID && $0.role == .user && $0.text == prompt
        }) else { return }
        upsertTranscript(AgentManagedTranscriptEntry(
            id: "submitted-user:\(sessionID.nativeID):\(turnID)",
            nativeSessionID: sessionID.nativeID,
            turnID: turnID,
            role: .user,
            text: prompt,
            timestamp: Date()
        ), provider: sessionID.provider)
    }

    private func upsertTranscript(
        _ entry: AgentManagedTranscriptEntry,
        provider: AgentProvider
    ) {
        let sessionID = AgentSessionID(provider: provider, nativeID: entry.nativeSessionID)
        var entries = transcripts[sessionID] ?? []
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
        transcripts[sessionID] = Self.boundedTranscript(entries)
    }

    private func appendTranscriptDelta(
        sessionID: AgentSessionID,
        turnID: String,
        itemID: String,
        delta: String
    ) {
        guard !delta.isEmpty else { return }
        var entries = transcripts[sessionID] ?? []
        if let index = entries.firstIndex(where: { $0.id == itemID }) {
            let combined = entries[index].text + delta
            let bounded = AgentManagedTranscriptEntry.boundedText(combined) ?? entries[index].text
            entries[index] = AgentManagedTranscriptEntry(
                id: itemID,
                nativeSessionID: sessionID.nativeID,
                turnID: turnID,
                role: .agent,
                text: bounded,
                timestamp: entries[index].timestamp
            )
        } else if let bounded = AgentManagedTranscriptEntry.boundedText(delta) {
            entries.append(AgentManagedTranscriptEntry(
                id: itemID,
                nativeSessionID: sessionID.nativeID,
                turnID: turnID,
                role: .agent,
                text: bounded,
                timestamp: Date()
            ))
        }
        transcripts[sessionID] = Self.boundedTranscript(entries)
    }

    private nonisolated static func safeError(
        _ error: Error,
        provider: AgentProvider
    ) -> String {
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
        } else if let error = error as? ClaudeCodeStreamingError {
            switch error {
            case .executableNotFound: value = "Claude CLI not installed"
            case .launchFailed: value = "Claude unavailable"
            case .turnAlreadyRunning: value = "Claude turn already running"
            case .malformedMessage: value = "Claude returned an invalid response"
            case .unsupported: value = "Claude control is unsupported"
            }
        } else {
            value = "\(providerNameStatic(provider)) control request failed"
        }
        return AgentPrivacyProjection.title(
            value,
            fallback: "\(providerNameStatic(provider)) control error"
        )
    }

    private nonisolated static func providerNameStatic(_ provider: AgentProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .other: "Agent"
        }
    }
}

private struct PendingApprovalConfirmation: Sendable {
    let provider: AgentProvider
    let nativeSessionID: String
    let turnID: String
    let correlationID: AgentCorrelationID
    let state: AgentApprovalState
    let automatic: Bool
}
