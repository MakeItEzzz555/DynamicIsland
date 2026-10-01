import Combine
import Foundation

@MainActor
final class AgentEventStore: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []
    @Published private(set) var attentionEvents: [AgentAttentionEvent] = []
    /// Called once per normalized event that was applied, with the session it
    /// produced. Record Activities observes the store here so every producer
    /// (managed providers, hooks, rollouts) has one source of truth.
    var appliedEventObserver: ((AgentEvent, AgentSession) -> Void)?

    let limits: AgentEventStoreLimits

    private var sessionsByID: [AgentSessionInstanceID: AgentSession] = [:]
    private var currentGeneration: [AgentSessionID: AgentSessionGeneration] = [:]

    init(limits: AgentEventStoreLimits = .standard) {
        self.limits = limits.normalized
    }

    var activeSessions: [AgentSession] {
        sessions.filter { session in
            session.isActive && currentGeneration[session.id.sessionID] == session.id.generation
        }
    }

    var sessionsRequiringAttention: [AgentSession] {
        sessions.filter { session in
            guard currentGeneration[session.id.sessionID] == session.id.generation else { return false }
            switch session.state {
            case .waitingForApproval, .waitingForUser, .planReady, .failed:
                return true
            default:
                return false
            }
        }
    }

    @discardableResult
    func ingest(_ event: AgentEvent) -> AgentEventApplication {
        if let error = event.validationError() {
            return .rejected(.validation(error))
        }

        prune(at: event.receivedTimestamp, publish: false)

        if let current = currentGeneration[event.sessionID] {
            if event.generation < current {
                return .staleGeneration
            }
            if event.generation > current, event.type != .sessionStarted {
                return .rejected(.generationMismatch)
            }
        } else if event.type != .sessionStarted {
            return .rejected(.missingSession)
        }

        let isNewGeneration = currentGeneration[event.sessionID] != event.generation
        if sessionsByID[event.instanceID] == nil,
           !makeRoomForSession(replacing: isNewGeneration ? event.sessionID : nil) {
            return .rejected(.sessionCapacity)
        }

        if isNewGeneration {
            currentGeneration[event.sessionID] = event.generation
        }

        let result = AgentEventReducer.reduce(
            session: sessionsByID[event.instanceID],
            event: event,
            limits: limits
        )

        guard let reducedSession = result.session else {
            if isNewGeneration { currentGeneration.removeValue(forKey: event.sessionID) }
            return result.application
        }

        switch result.application {
        case .applied, .ignoredAfterTerminal, .ignoredWeakerEvidence:
            sessionsByID[event.instanceID] = reducedSession
            if let attention = result.attention {
                appendAttention(attention)
            }
            enforceGlobalActivityLimit()
            publishSnapshots()
            if case .applied = result.application {
                appliedEventObserver?(event, reducedSession)
            }
        case .duplicate, .staleGeneration, .rejected:
            if isNewGeneration, sessionsByID[event.instanceID] == nil {
                currentGeneration.removeValue(forKey: event.sessionID)
            }
        }
        return result.application
    }

    /// Applies a batch to an isolated copy and publishes only when every event is
    /// semantically acceptable. This gives the transport an atomic A1 boundary
    /// without duplicating reducer logic or exposing mutable session state.
    func ingestAtomically(_ events: [AgentEvent]) -> AgentEventBatchApplication {
        let working = AgentEventStore(limits: limits)
        working.sessionsByID = sessionsByID
        working.currentGeneration = currentGeneration
        working.sessions = sessions
        working.attentionEvents = attentionEvents

        var applications: [AgentEventApplication] = []
        applications.reserveCapacity(events.count)
        for (index, event) in events.enumerated() {
            let application = working.ingest(event)
            switch application {
            case .applied, .duplicate, .ignoredAfterTerminal, .ignoredWeakerEvidence:
                applications.append(application)
            case .staleGeneration, .rejected:
                return .rejected(index: index, application: application)
            }
        }

        sessionsByID = working.sessionsByID
        currentGeneration = working.currentGeneration
        sessions = working.sessions
        attentionEvents = working.attentionEvents
        if let appliedEventObserver {
            for (event, application) in zip(events, applications) {
                guard case .applied = application, let session = sessionsByID[event.instanceID] else { continue }
                appliedEventObserver(event, session)
            }
        }
        return .applied(applications)
    }

    func session(for id: AgentSessionInstanceID) -> AgentSession? {
        sessionsByID[id]
    }

    func prune(at date: Date) {
        prune(at: date, publish: true)
    }

    private func prune(at date: Date, publish: Bool) {
        let cutoff = date.addingTimeInterval(-limits.completedSessionRetention)
        let expired = sessionsByID.values.filter { session in
            let isCurrent = currentGeneration[session.id.sessionID] == session.id.generation
            let isClosed = session.endedAt != nil
            return (isClosed || !isCurrent) && session.lastUpdatedAt < cutoff
        }
        for session in expired {
            removeSession(session.id)
        }
        if publish, !expired.isEmpty {
            publishSnapshots()
        }
    }

    private func makeRoomForSession(replacing sessionID: AgentSessionID?) -> Bool {
        guard sessionsByID.count >= limits.maximumSessions else { return true }

        let candidates = sessionsByID.values
            .filter { session in
                let isCurrent = currentGeneration[session.id.sessionID] == session.id.generation
                return !session.isActive || !isCurrent || session.id.sessionID == sessionID
            }
            .sorted(by: sessionAgeSort)

        // Persisted history that is only resumable (not loaded, not working)
        // is re-discoverable, so it yields its slot before a new or live
        // session is refused. Loaded idle sessions are still never evicted.
        let resumableHistory = sessionsByID.values
            .filter { $0.availability == .resumable && $0.state == .idle }
            .sorted(by: sessionAgeSort)

        guard let oldest = candidates.first ?? resumableHistory.first else { return false }
        removeSession(oldest.id)
        return sessionsByID.count < limits.maximumSessions
    }

    private func removeSession(_ id: AgentSessionInstanceID) {
        sessionsByID.removeValue(forKey: id)
        attentionEvents.removeAll { $0.session == id }
        if currentGeneration[id.sessionID] == id.generation {
            currentGeneration.removeValue(forKey: id.sessionID)
        }
    }

    private func appendAttention(_ attention: AgentAttentionEvent) {
        guard !attentionEvents.contains(where: { $0.id == attention.id }) else { return }
        attentionEvents.append(attention)
        attentionEvents.sort(by: attentionSort)
        if attentionEvents.count > limits.maximumAttentionEvents {
            attentionEvents.removeLast(attentionEvents.count - limits.maximumAttentionEvents)
        }
    }

    private func enforceGlobalActivityLimit() {
        var total = sessionsByID.values.reduce(0) { $0 + $1.recentActivity.count }
        while total > limits.maximumGlobalActivity {
            guard let owner = sessionsByID.values
                .filter({ !$0.recentActivity.isEmpty })
                .min(by: oldestActivitySort)?.id,
                var session = sessionsByID[owner] else {
                break
            }
            session.recentActivity.removeFirst()
            sessionsByID[owner] = session
            total -= 1
        }
    }

    private func publishSnapshots() {
        sessions = sessionsByID.values.sorted(by: sessionDisplaySort)
        attentionEvents.sort(by: attentionSort)
    }

    private func sessionDisplaySort(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        let lhsCurrent = currentGeneration[lhs.id.sessionID] == lhs.id.generation
        let rhsCurrent = currentGeneration[rhs.id.sessionID] == rhs.id.generation
        if lhsCurrent != rhsCurrent { return lhsCurrent && !rhsCurrent }
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt { return lhs.lastUpdatedAt > rhs.lastUpdatedAt }
        if lhs.id.sessionID.provider.deterministicSortKey != rhs.id.sessionID.provider.deterministicSortKey {
            return lhs.id.sessionID.provider.deterministicSortKey < rhs.id.sessionID.provider.deterministicSortKey
        }
        if lhs.id.sessionID.nativeID != rhs.id.sessionID.nativeID {
            return lhs.id.sessionID.nativeID < rhs.id.sessionID.nativeID
        }
        return lhs.id.generation > rhs.id.generation
    }

    private func sessionAgeSort(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt { return lhs.lastUpdatedAt < rhs.lastUpdatedAt }
        return sessionDisplaySort(lhs, rhs)
    }

    private func oldestActivitySort(_ lhs: AgentSession, _ rhs: AgentSession) -> Bool {
        guard let lhsDate = lhs.recentActivity.first?.timestamp else { return false }
        guard let rhsDate = rhs.recentActivity.first?.timestamp else { return true }
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return sessionAgeSort(lhs, rhs)
    }

    private func attentionSort(_ lhs: AgentAttentionEvent, _ rhs: AgentAttentionEvent) -> Bool {
        if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp > rhs.timestamp }
        if lhs.session.sessionID.provider.deterministicSortKey != rhs.session.sessionID.provider.deterministicSortKey {
            return lhs.session.sessionID.provider.deterministicSortKey < rhs.session.sessionID.provider.deterministicSortKey
        }
        if lhs.session.sessionID.nativeID != rhs.session.sessionID.nativeID {
            return lhs.session.sessionID.nativeID < rhs.session.sessionID.nativeID
        }
        if lhs.session.generation != rhs.session.generation {
            return lhs.session.generation > rhs.session.generation
        }
        return lhs.eventID.rawValue < rhs.eventID.rawValue
    }
}


@MainActor
final class AgentAttentionCoordinator: ObservableObject {
    @Published private(set) var presentation: AgentAttentionPresentation?
    @Published private(set) var badges: [AgentAttentionBadge] = []
    @Published private(set) var soundIntent: AgentAttentionSoundIntent?
    @Published private(set) var isEnabled = true

    private var policyState = AgentAttentionPolicyState()
    private var options: AgentAttentionPolicyOptions
    private let clock = ContinuousClock()
    private var retractTask: Task<Void, Never>?
    private var completionDebounceTasks: [AgentAttentionEventID: Task<Void, Never>] = [:]
    private var latestSessions: [AgentSession] = []

    init(options: AgentAttentionPolicyOptions = AgentAttentionPolicyOptions()) {
        self.options = options
    }

    func configure(
        peekDuration: TimeInterval? = nil,
        completionAlertsEnabled: Bool? = nil,
        approvalAlertsEnabled: Bool? = nil,
        soundsEnabled: Bool? = nil
    ) {
        if let peekDuration {
            options.peekDuration = min(max(peekDuration, 1), 15)
        }
        if let completionAlertsEnabled {
            options.completionAlertsEnabled = completionAlertsEnabled
        }
        if let approvalAlertsEnabled {
            options.approvalAlertsEnabled = approvalAlertsEnabled
        }
        if let soundsEnabled {
            options.soundsEnabled = soundsEnabled
        }
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        if !enabled {
            retractTask?.cancel()
            retractTask = nil
            completionDebounceTasks.values.forEach { $0.cancel() }
            completionDebounceTasks.removeAll()
            policyState = AgentAttentionPolicyEngine.dismissPresentation(state: policyState)
            publish(soundIntent: nil)
        }
    }

    func synchronize(
        attentionEvents: [AgentAttentionEvent],
        sessions: [AgentSession],
        now: Date = Date()
    ) {
        guard isEnabled else { return }
        latestSessions = sessions

        let reconciledState = AgentAttentionPolicyEngine.reconcilePresentation(
            with: sessions,
            state: policyState
        )
        if reconciledState.presentation != policyState.presentation {
            retractTask?.cancel()
            retractTask = nil
            policyState = reconciledState
        }

        // AgentNotch parity: true turn/session completion is deliberately
        // debounced for one second so individual tool completions cannot cause
        // repeated completion peeks.
        let immediate = attentionEvents.filter { $0.reason != .completed }
        let result = AgentAttentionPolicyEngine.apply(
            events: immediate,
            sessions: sessions,
            now: now,
            state: policyState,
            options: options
        )
        policyState = result.state
        publish(soundIntent: result.soundIntent)
        scheduleRetractIfNeeded()

        for event in attentionEvents where event.reason == .completed {
            scheduleCompletion(event)
        }
    }

    private func scheduleCompletion(_ event: AgentAttentionEvent) {
        guard !policyState.rememberedEventIDs.contains(event.id),
              completionDebounceTasks[event.id] == nil else { return }
        completionDebounceTasks[event.id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                self.completionDebounceTasks[event.id] = nil
                guard self.isEnabled,
                      let session = self.latestSessions.first(where: { $0.id == event.session }),
                      session.state == .completed else { return }
                let result = AgentAttentionPolicyEngine.apply(
                    events: [event],
                    sessions: self.latestSessions,
                    now: Date(),
                    state: self.policyState,
                    options: self.options
                )
                self.policyState = result.state
                self.publish(soundIntent: result.soundIntent)
                self.scheduleRetractIfNeeded()
            }
        }
    }

    func dismissForExpansion() {
        retractTask?.cancel()
        retractTask = nil
        policyState = AgentAttentionPolicyEngine.dismissPresentation(state: policyState)
        publish(soundIntent: nil)
    }

    func markViewed(session: AgentSessionInstanceID) {
        policyState = AgentAttentionPolicyEngine.markViewed(session: session, state: policyState)
        publish(soundIntent: nil)
    }

    func expirePresentation(
        generation: AgentAttentionGeneration,
        now: Date = Date()
    ) {
        let previous = policyState.presentation
        policyState = AgentAttentionPolicyEngine.expire(
            generation: generation,
            now: now,
            state: policyState
        )
        if previous != policyState.presentation {
            retractTask?.cancel()
            retractTask = nil
            publish(soundIntent: nil)
        }
    }

    private func publish(soundIntent newSoundIntent: AgentAttentionSoundIntent?) {
        presentation = policyState.presentation
        badges = policyState.badges.values.sorted {
            if $0.priority != $1.priority { return $0.priority > $1.priority }
            if $0.createdAt != $1.createdAt { return $0.createdAt > $1.createdAt }
            return $0.eventID.rawValue < $1.eventID.rawValue
        }
        soundIntent = newSoundIntent
    }

    private func scheduleRetractIfNeeded() {
        retractTask?.cancel()
        guard let current = policyState.presentation else {
            retractTask = nil
            return
        }

        let generation = current.generation
        let delay = max(0.1, options.peekDuration)
        let deadline = clock.now.advanced(by: .seconds(delay))
        retractTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(until: deadline)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            expirePresentation(generation: generation, now: current.retractAt)
        }
    }
}
