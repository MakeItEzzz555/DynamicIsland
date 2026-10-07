import Foundation

/// One session's transcript as the console observes it. Only the console of
/// the selected session subscribes, so streamed deltas never invalidate the
/// Agents chrome (provider buttons, project menu, usage, session list).
@MainActor
final class AgentTranscriptFeed: ObservableObject {
    let sessionID: AgentSessionID
    @Published fileprivate(set) var entries: [AgentManagedTranscriptEntry]

    fileprivate init(sessionID: AgentSessionID, entries: [AgentManagedTranscriptEntry]) {
        self.sessionID = sessionID
        self.entries = entries
    }
}

/// Authoritative bounded transcript storage for managed sessions.
///
/// Writes are synchronous (the controller, approvals and tests always read
/// the current truth). Publication to a feed is coalesced: the first change
/// after a quiet period publishes immediately, and a burst of provider deltas
/// publishes at most once per `minimumPublicationInterval` with the latest
/// value. Nothing is delayed when changes are sporadic, and nothing is lost.
@MainActor
final class AgentTranscriptStore {
    /// ~30 Hz: well above reading speed, far below token arrival rate.
    static let minimumPublicationInterval: Duration = .milliseconds(33)

    private var storage: [AgentSessionID: [AgentManagedTranscriptEntry]] = [:]
    private var feeds: [AgentSessionID: AgentTranscriptFeed] = [:]
    private var lastPublication: [AgentSessionID: ContinuousClock.Instant] = [:]
    private var scheduled: [AgentSessionID: Task<Void, Never>] = [:]
    private let clock = ContinuousClock()
    private let interval: Duration

    init(minimumPublicationInterval: Duration = AgentTranscriptStore.minimumPublicationInterval) {
        interval = minimumPublicationInterval
    }

    subscript(sessionID: AgentSessionID) -> [AgentManagedTranscriptEntry]? {
        get { storage[sessionID] }
        set {
            if let newValue {
                storage[sessionID] = newValue
            } else {
                storage.removeValue(forKey: sessionID)
            }
            schedulePublication(for: sessionID)
        }
    }

    /// The observable feed for one session; created on first request.
    func feed(for sessionID: AgentSessionID) -> AgentTranscriptFeed {
        if let feed = feeds[sessionID] { return feed }
        let feed = AgentTranscriptFeed(sessionID: sessionID, entries: storage[sessionID] ?? [])
        feeds[sessionID] = feed
        return feed
    }

    func removeAll() {
        storage.removeAll()
        for task in scheduled.values { task.cancel() }
        scheduled.removeAll()
        lastPublication.removeAll()
        for feed in feeds.values where !feed.entries.isEmpty { feed.entries = [] }
    }

    /// Publishes any coalesced change now (tests, teardown).
    func flush() {
        for sessionID in Array(scheduled.keys) {
            scheduled.removeValue(forKey: sessionID)?.cancel()
            publish(sessionID)
        }
    }

    private func schedulePublication(for sessionID: AgentSessionID) {
        guard feeds[sessionID] != nil, scheduled[sessionID] == nil else { return }
        let now = clock.now
        if let last = lastPublication[sessionID], now - last < interval {
            let wait = interval - (now - last)
            scheduled[sessionID] = Task { @MainActor [weak self] in
                try? await Task.sleep(for: wait)
                guard let self, !Task.isCancelled else { return }
                self.scheduled.removeValue(forKey: sessionID)
                self.publish(sessionID)
            }
        } else {
            publish(sessionID)
        }
    }

    private func publish(_ sessionID: AgentSessionID) {
        guard let feed = feeds[sessionID] else { return }
        lastPublication[sessionID] = clock.now
        let current = storage[sessionID] ?? []
        guard feed.entries != current else { return }
        AgentPerformanceProbe.count("agents.transcript.publish")
        feed.entries = current
    }
}
