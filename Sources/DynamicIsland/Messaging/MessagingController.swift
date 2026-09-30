import Foundation
import Intents

// MARK: - Provider adapter boundary

/// Provider-specific authority lives behind this protocol. The controller
/// and UI never assume a capability the adapter does not report.
@MainActor
protocol MessagingProviderAdapter: AnyObject {
    var provider: MessagingProviderID { get }
    var availability: MessagingProviderAvailability { get }
    var capabilities: MessagingProviderCapabilities { get }
    /// Set by the controller; adapters deliver normalized incoming messages.
    var onIncoming: ((MessagingMessage) -> Void)? { get set }
    /// Only called when `capabilities.supportsInlineReply` and the
    /// conversation has an exact target.
    func send(_ text: String, to conversation: MessagingConversationID) async -> MessagingSendOutcome
    /// Opens the exact conversation when possible, otherwise the app.
    /// Returns false when nothing could be opened.
    func open(_ conversation: MessagingConversation?) -> Bool
    func refresh()
}

// MARK: - Focus

@MainActor
protocol MessagingFocusProviding: AnyObject {
    /// Authoritative Focus state, or nil when unknown/unauthorized.
    /// Absence of notifications is never treated as Focus.
    var isFocused: Bool? { get }
    /// Called when the authoritative Focus state may have changed.
    var onChange: (() -> Void)? { get set }
}

/// Reads Focus status only when the user already authorized it (the Focus
/// HUD owns the permission request). Never prompts.
@MainActor
final class SystemMessagingFocusProvider: MessagingFocusProviding {
    var onChange: (() -> Void)?
    private var observation: NSKeyValueObservation?

    init() {
        observation = INFocusStatusCenter.default.observe(\.focusStatus, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.onChange?() }
        }
    }

    deinit {
        observation?.invalidate()
    }

    var isFocused: Bool? {
        guard INFocusStatusCenter.default.authorizationStatus == .authorized else { return nil }
        return INFocusStatusCenter.default.focusStatus.isFocused
    }
}

// MARK: - Queue

struct MessagingQueueEntry: Equatable, Sendable, Identifiable {
    /// Queue identity: exact conversation when known, otherwise a
    /// per-event key so unidentifiable messages never merge.
    let key: String
    var latest: MessagingMessage
    var unseenCount: Int
    var seenMessageIDs: [MessagingMessageID]
    let firstReceivedAt: Date
    var acknowledged: Bool
    var heldByFocus: Bool

    var id: String { key }
    var conversation: MessagingConversation { latest.conversation }
}

/// Bounded, deduplicating queue. One entry per exact conversation; newer
/// messages update their conversation's entry instead of replacing
/// unrelated conversations.
struct MessagingQueue: Equatable, Sendable {
    static let maximumEntries = 6
    static let maximumRememberedMessageIDs = 20

    private(set) var entries: [MessagingQueueEntry] = []
    private var sequence = 0

    enum InsertResult: Equatable {
        case inserted
        case updated
        case duplicate
    }

    static func key(for message: MessagingMessage, fallbackSequence: Int) -> String {
        if let id = message.conversation.id {
            return "conversation:\(id.provider.stableName):\(id.nativeID)"
        }
        return "event:\(message.conversation.provider.stableName):\(fallbackSequence)"
    }

    /// `protectedKeys`: conversations the user is replying in (draft text
    /// or a send in flight); they are never evicted by trimming.
    @discardableResult
    mutating func insert(
        _ message: MessagingMessage,
        heldByFocus: Bool,
        protectedKeys: Set<String> = []
    ) -> InsertResult {
        sequence += 1
        let key = Self.key(for: message, fallbackSequence: sequence)
        if let index = entries.firstIndex(where: { $0.key == key }) {
            var entry = entries[index]
            if let messageID = message.id, entry.seenMessageIDs.contains(messageID) {
                return .duplicate
            }
            guard message.receivedAt >= entry.latest.receivedAt else {
                // Older but distinct message (delivered out of order): count
                // it as unseen, keep the newer message as latest.
                if let messageID = message.id { entry.remember(messageID) }
                entry.unseenCount += 1
                entry.acknowledged = false
                entries[index] = entry
                return .updated
            }
            entry.latest = message
            entry.unseenCount += 1
            entry.acknowledged = false
            entry.heldByFocus = heldByFocus
            if let messageID = message.id { entry.remember(messageID) }
            entries[index] = entry
            sortEntries()
            return .updated
        }
        var entry = MessagingQueueEntry(
            key: key,
            latest: message,
            unseenCount: 1,
            seenMessageIDs: [],
            firstReceivedAt: message.receivedAt,
            acknowledged: false,
            heldByFocus: heldByFocus
        )
        if let messageID = message.id { entry.remember(messageID) }
        entries.append(entry)
        sortEntries()
        trim(protectedKeys: protectedKeys.union([key]))
        return .inserted
    }

    mutating func acknowledge(_ key: String) {
        guard let index = entries.firstIndex(where: { $0.key == key }) else { return }
        entries[index].acknowledged = true
        entries[index].unseenCount = 0
    }

    mutating func remove(_ key: String) {
        entries.removeAll { $0.key == key }
    }

    mutating func releaseFocusHolds() {
        for index in entries.indices { entries[index].heldByFocus = false }
    }

    /// Newest first; ties broken by stable key.
    private mutating func sortEntries() {
        entries.sort {
            if $0.latest.receivedAt != $1.latest.receivedAt { return $0.latest.receivedAt > $1.latest.receivedAt }
            return $0.key < $1.key
        }
    }

    /// Drops the oldest acknowledged entries first, then the oldest, never
    /// a protected conversation. May exceed the bound only when every
    /// entry is protected.
    private mutating func trim(protectedKeys: Set<String>) {
        while entries.count > Self.maximumEntries {
            if let index = entries.lastIndex(where: { $0.acknowledged && !protectedKeys.contains($0.key) }) {
                entries.remove(at: index)
            } else if let index = entries.lastIndex(where: { !protectedKeys.contains($0.key) }) {
                entries.remove(at: index)
            } else {
                return
            }
        }
    }
}

private extension MessagingQueueEntry {
    mutating func remember(_ id: MessagingMessageID) {
        seenMessageIDs.append(id)
        if seenMessageIDs.count > MessagingQueue.maximumRememberedMessageIDs {
            seenMessageIDs.removeFirst(seenMessageIDs.count - MessagingQueue.maximumRememberedMessageIDs)
        }
    }
}

// MARK: - Controller

/// Messaging state lives in memory only: no message bodies, history,
/// recipients or drafts are persisted.
@MainActor
final class MessagingController: ObservableObject {
    static let activityID = "message.current"
    /// Above playing media (120); below live mic (125), camera (128) and agents (130).
    static let freshPriority = 124
    static let acknowledgedPriority = 112
    static let sentSettleDelay: TimeInterval = 2.5
    static let compactPreviewLength = 80
    /// A provider that does not answer within this time yields an
    /// uncertain outcome (draft kept). The send itself is not cancelled,
    /// because a hand-off cannot be taken back.
    static let defaultSendTimeout: TimeInterval = 20

    struct Preferences: Equatable, Sendable {
        var enabled = true
        var showPreviewOnCompact = true
        var mutedProviders: Set<MessagingProviderID> = []
    }

    @Published private(set) var queue = MessagingQueue()
    @Published private(set) var drafts = MessagingDraftBook()
    @Published private(set) var providerHealth: [MessagingProviderID: Date] = [:]
    @Published var preferences: Preferences {
        didSet { applyPreferences() }
    }

    let adapters: [MessagingProviderID: MessagingProviderAdapter]
    private let liveActivities: LiveActivityStore
    private let focus: MessagingFocusProviding
    private let now: () -> Date
    private let sendTimeout: TimeInterval
    private let presentationEnabled: () -> Bool
    private var settleTasks: [MessagingConversationID: Task<Void, Never>] = [:]

    init(
        adapters: [MessagingProviderAdapter],
        liveActivities: LiveActivityStore,
        focus: MessagingFocusProviding = SystemMessagingFocusProvider(),
        preferences: Preferences = Preferences(),
        sendTimeout: TimeInterval = MessagingController.defaultSendTimeout,
        presentationEnabled: @escaping () -> Bool = { true },
        now: @escaping () -> Date = Date.init
    ) {
        self.sendTimeout = sendTimeout
        self.presentationEnabled = presentationEnabled
        self.adapters = Dictionary(adapters.map { ($0.provider, $0) }, uniquingKeysWith: { first, _ in first })
        self.liveActivities = liveActivities
        self.focus = focus
        self.preferences = preferences
        self.now = now
        for adapter in adapters {
            adapter.onIncoming = { [weak self] message in
                self?.receive(message)
            }
        }
        focus.onChange = { [weak self] in
            self?.focusDidChange()
        }
        publishActivity()
    }

    deinit {
        settleTasks.values.forEach { $0.cancel() }
    }

    // MARK: Queries

    var orderedProviders: [MessagingProviderID] {
        adapters.keys.sorted { $0.stableName < $1.stableName }
    }

    /// The conversation shown in the expanded surface.
    var current: MessagingQueueEntry? {
        visibleEntries.first
    }

    var visibleEntries: [MessagingQueueEntry] {
        guard preferences.enabled else { return [] }
        return queue.entries.filter { !preferences.mutedProviders.contains($0.latest.conversation.provider) }
    }

    func capabilities(for provider: MessagingProviderID) -> MessagingProviderCapabilities {
        adapters[provider]?.capabilities ?? .none
    }

    func canReply(to entry: MessagingQueueEntry) -> Bool {
        guard adapters[entry.conversation.provider]?.availability == .available else { return false }
        return capabilities(for: entry.conversation.provider).canReply(to: entry.conversation)
    }

    func draft(for entry: MessagingQueueEntry) -> MessagingDraft {
        entry.conversation.id.map { drafts.draft(for: $0) } ?? MessagingDraft()
    }

    // MARK: Incoming

    func receive(_ message: MessagingMessage) {
        guard message.direction == .incoming else { return }
        providerHealth[message.conversation.provider] = now()
        guard preferences.enabled,
              !preferences.mutedProviders.contains(message.conversation.provider),
              adapters[message.conversation.provider] != nil else { return }
        let held = focus.isFocused == true
        queue.insert(message, heldByFocus: held, protectedKeys: replyingKeys)
        publishActivity()
    }

    /// Queue keys of conversations with draft text or a send in flight.
    private var replyingKeys: Set<String> {
        Set(queue.entries.compactMap { entry in
            guard let id = entry.conversation.id else { return nil }
            let draft = drafts.draft(for: id)
            return draft.state.isSending || !draft.text.isEmpty ? entry.key : nil
        })
    }

    /// Re-publishes after the global Live Activities setting changes.
    func republishActivity() {
        publishActivity()
    }

    // MARK: Actions

    func acknowledge(_ entry: MessagingQueueEntry) {
        queue.acknowledge(entry.key)
        publishActivity()
    }

    func dismiss(_ entry: MessagingQueueEntry) {
        if let id = entry.conversation.id {
            drafts.discard(id)
            settleTasks[id]?.cancel()
            settleTasks[id] = nil
        }
        queue.remove(entry.key)
        publishActivity()
    }

    func updateDraft(_ text: String, for entry: MessagingQueueEntry) {
        guard let id = entry.conversation.id, canReply(to: entry) else { return }
        drafts.updateText(text, for: id)
    }

    /// Sends the draft for exactly this entry's conversation. The draft is
    /// cleared only on a confirmed outcome.
    func send(for entry: MessagingQueueEntry) async {
        guard canReply(to: entry),
              let adapter = adapters[entry.conversation.provider] else { return }
        let target: MessagingConversationID
        let text: String
        do {
            (target, text) = try drafts.beginSend(
                for: entry.conversation,
                capabilities: adapter.capabilities
            )
        } catch {
            return
        }
        queue.acknowledge(entry.key)
        publishActivity()
        // Captured before awaiting: a message that arrives during the send
        // must keep the conversation visible.
        let latestAtSend = queue.entries.first { $0.key == entry.key }?.latest.receivedAt

        let outcome = await Self.send(text, to: target, via: adapter, timeout: sendTimeout)
        drafts.apply(outcome, for: target)
        if case .confirmed = outcome {
            scheduleSettle(entryKey: entry.key, conversation: target, latestAt: latestAtSend)
        }
        publishActivity()
    }

    @discardableResult
    func open(_ entry: MessagingQueueEntry?) -> Bool {
        let provider = entry?.conversation.provider
        guard let provider, let adapter = adapters[provider] else { return false }
        let opened = adapter.open(entry?.conversation)
        if opened, let entry { queue.acknowledge(entry.key) }
        publishActivity()
        return opened
    }

    func refreshProviders() {
        adapters.values.forEach { $0.refresh() }
        objectWillChange.send()
    }

    /// Re-evaluates Focus holds (e.g. when Focus turns off).
    func focusDidChange() {
        if focus.isFocused != true {
            queue.releaseFocusHolds()
        }
        publishActivity()
    }

    /// First result wins: the provider's outcome, or `.uncertain` on timeout.
    private static func send(
        _ text: String,
        to target: MessagingConversationID,
        via adapter: MessagingProviderAdapter,
        timeout: TimeInterval
    ) async -> MessagingSendOutcome {
        await withCheckedContinuation { (continuation: CheckedContinuation<MessagingSendOutcome, Never>) in
            let once = OnceOutcome(continuation)
            Task { @MainActor in
                once.resume(await adapter.send(text, to: target))
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(max(timeout, 0) * 1_000_000_000))
                once.resume(.uncertain(reason: "No response from \(adapter.provider.displayName)"))
            }
        }
    }

    // MARK: Live activity

    static func compactPreview(for message: MessagingMessage, showBody: Bool) -> String {
        guard showBody, let body = message.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else {
            return "New message"
        }
        let singleLine = body.replacingOccurrences(of: "\n", with: " ")
        return singleLine.count > compactPreviewLength
            ? String(singleLine.prefix(compactPreviewLength - 1)) + "…"
            : singleLine
    }

    static func makeActivity(
        for entry: MessagingQueueEntry,
        queuedCount: Int,
        showBody: Bool,
        updatedAt: Date
    ) -> DynamicIslandLiveActivity {
        let conversation = entry.conversation
        let extra = queuedCount > 1 ? " · +\(queuedCount - 1)" : ""
        return DynamicIslandLiveActivity(
            id: activityID,
            kind: .message,
            title: conversation.displayTitle.isEmpty ? conversation.provider.displayName : conversation.displayTitle,
            subtitle: compactPreview(for: entry.latest, showBody: showBody) + extra,
            symbolName: conversation.provider.symbolName,
            priority: entry.acknowledged ? acknowledgedPriority : freshPriority,
            isActive: true,
            progress: nil,
            updatedAt: updatedAt,
            lifecycle: LiveActivityLifecycleMetadata(
                authority: .integrationAdapter,
                startEvidence: "Messaging provider adapter delivered an incoming message",
                progressEvidence: nil,
                completionEvidence: "User dismissed, opened, or a confirmed reply settled the conversation",
                dismissPolicy: .userDismissible,
                supportsCancellation: false
            )
        )
    }

    private func publishActivity() {
        guard presentationEnabled() else {
            liveActivities.remove(id: Self.activityID)
            objectWillChange.send()
            return
        }
        let focused = focus.isFocused == true
        let presentable = visibleEntries.filter { !($0.heldByFocus && focused) }
        guard let entry = presentable.first else {
            liveActivities.remove(id: Self.activityID)
            objectWillChange.send()
            return
        }
        liveActivities.update(Self.makeActivity(
            for: entry,
            queuedCount: presentable.count,
            showBody: preferences.showPreviewOnCompact,
            updatedAt: entry.latest.receivedAt
        ))
    }

    private func applyPreferences() {
        if !preferences.enabled {
            for id in settleTasks.keys { settleTasks[id]?.cancel() }
            settleTasks.removeAll()
        }
        publishActivity()
    }

    /// Removes a replied conversation after a short confirmation beat,
    /// unless a newer message arrived for it in the meantime.
    private func scheduleSettle(entryKey: String, conversation: MessagingConversationID, latestAt: Date?) {
        settleTasks[conversation]?.cancel()
        let delay = Self.sentSettleDelay
        settleTasks[conversation] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            guard self.drafts.draft(for: conversation).state == .sent else { return }
            let current = self.queue.entries.first { $0.key == entryKey }
            if let current, current.latest.receivedAt == latestAt, current.unseenCount == 0 {
                self.queue.remove(entryKey)
            }
            self.drafts.discard(conversation)
            self.settleTasks[conversation] = nil
            self.publishActivity()
        }
    }
}

@MainActor
private final class OnceOutcome {
    private var continuation: CheckedContinuation<MessagingSendOutcome, Never>?

    init(_ continuation: CheckedContinuation<MessagingSendOutcome, Never>) {
        self.continuation = continuation
    }

    func resume(_ outcome: MessagingSendOutcome) {
        continuation?.resume(returning: outcome)
        continuation = nil
    }
}
