import AppKit
import Foundation

/// Apple Messages provider.
///
/// Incoming: opt-in reading of macOS Notification Center records (needs
/// Full Disk Access, which the user grants in System Settings).
/// Target: each Messages notification is resolved against the local
/// Messages database to exactly one chat (bounded time window + body
/// match); zero or several candidates means no inline reply.
/// Send: Apple Events `send … to chat id` for that exact chat, then the
/// outgoing message must be observed in that chat in the Messages database
/// before the send counts as confirmed. Otherwise the result is uncertain
/// and the draft is kept.
@MainActor
final class MessagesAppAdapter: MessagingProviderAdapter {
    static let bundleIdentifier = "com.apple.MobileSMS"
    static let notificationBundleIdentifiers: Set<String> = ["com.apple.mobilesms", "com.apple.ichat"]
    static let confirmationTimeout: TimeInterval = 6
    static let confirmationPollInterval: TimeInterval = 0.4

    static let observeLimitation = "Turn on “Read message notifications” in Messaging settings"
    static let fullDiskAccessLimitation =
        "Full Disk Access is required to read message notifications and match them to a conversation"
    static let replyLimitation =
        "Replies need notification access so each message can be matched to its exact conversation"
    static let conversationLimitation =
        "A message is only replyable when it matches exactly one Messages conversation"

    enum ObservationState: Equatable {
        case disabled
        case permissionRequired
        case unavailable(String)
        case running
    }

    let provider: MessagingProviderID = .messages
    var onIncoming: ((MessagingMessage) -> Void)?
    private(set) var availability: MessagingProviderAvailability
    private(set) var observationState: ObservationState = .disabled

    private let applicationURL: () -> URL?
    private let openApplication: (URL) -> Bool
    private let monitor: SystemNotificationMonitor
    private let store: MessagesConversationStore
    private let automation: MessagesAutomating
    private let resolveQueue = DispatchQueue(label: "DynamicIsland.MessagesResolver")
    private let now: () -> Date
    private let sleep: (TimeInterval) async -> Void

    init(
        applicationURL: @escaping () -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: MessagesAppAdapter.bundleIdentifier)
        },
        // Synchronous launch result, so success is never assumed.
        openApplication: @escaping (URL) -> Bool = { url in
            NSWorkspace.shared.open(url)
        },
        monitor: SystemNotificationMonitor = SystemNotificationMonitor(),
        store: MessagesConversationStore = MessagesDatabaseStore(),
        automation: MessagesAutomating = AppleScriptMessagesAutomation(),
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.applicationURL = applicationURL
        self.openApplication = openApplication
        self.monitor = monitor
        self.store = store
        self.automation = automation
        self.now = now
        self.sleep = sleep
        self.availability = applicationURL() == nil ? .notInstalled : .available
        monitor.onRecord = { [weak self] record in
            self?.handle(record)
        }
    }

    var capabilities: MessagingProviderCapabilities {
        guard availability == .available else {
            return MessagingProviderCapabilities(supported: [], limitations: [.openApp: "Messages is not installed"])
        }
        switch observationState {
        case .running:
            return MessagingProviderCapabilities(
                supported: [.observeIncoming, .openApp, .composeDraft, .sendReply, .confirmSend,
                            .exactConversationTarget, .preserveDraft, .retrySend],
                limitations: [
                    .openConversation: "Messages opens without selecting the conversation",
                    .exactConversationTarget: Self.conversationLimitation
                ]
            )
        case .disabled, .permissionRequired, .unavailable:
            let reason = observationReason
            return MessagingProviderCapabilities(
                supported: [.openApp],
                limitations: [
                    .observeIncoming: reason,
                    .sendReply: Self.replyLimitation,
                    .confirmSend: Self.replyLimitation,
                    .composeDraft: Self.replyLimitation,
                    .exactConversationTarget: Self.conversationLimitation,
                    .openConversation: Self.conversationLimitation
                ]
            )
        }
    }

    var observationReason: String {
        switch observationState {
        case .disabled: Self.observeLimitation
        case .permissionRequired: Self.fullDiskAccessLimitation
        case .unavailable(let reason): reason
        case .running: "Reading Messages notifications"
        }
    }

    var automationPermission: MessagesAutomationPermission {
        automation.permission(askIfNeeded: false)
    }

    func setObservationEnabled(_ enabled: Bool) {
        guard enabled, availability == .available else {
            monitor.stop()
            observationState = .disabled
            return
        }
        monitor.start()
        switch monitor.state {
        case .running:
            do {
                _ = try store.messages(from: now(), to: now(), limit: 1)
                observationState = .running
            } catch ReadOnlySQLiteError.notPermitted {
                monitor.stop()
                observationState = .permissionRequired
            } catch ReadOnlySQLiteError.unsupportedSchema(let detail) {
                monitor.stop()
                observationState = .unavailable("Unsupported Messages database: \(detail)")
            } catch {
                monitor.stop()
                observationState = .unavailable("The Messages database could not be read")
            }
        case .permissionRequired:
            observationState = .permissionRequired
        case .unavailable(let reason), .failed(let reason):
            observationState = .unavailable(reason)
        case .stopped:
            observationState = .disabled
        }
    }

    // MARK: Incoming

    /// Visible for tests: processes one Notification Center record.
    func handle(_ record: SystemNotificationRecord) {
        guard Self.notificationBundleIdentifiers.contains(record.bundleIdentifier.lowercased()) else { return }
        let store = store
        resolveQueue.async { @Sendable [weak self] in
            let low = record.deliveredAt.addingTimeInterval(-MessagesConversationResolver.windowBefore)
            let high = record.deliveredAt.addingTimeInterval(MessagesConversationResolver.windowAfter)
            let resolution: MessagesResolution
            if let candidates = try? store.messages(from: low, to: high, limit: 200) {
                resolution = MessagesConversationResolver.resolve(notification: record, candidates: candidates)
            } else {
                resolution = .notFound
            }
            Task { @MainActor [weak self] in
                self?.deliver(record, resolution: resolution)
            }
        }
    }

    private func deliver(_ record: SystemNotificationRecord, resolution: MessagesResolution) {
        let conversationID: MessagingConversationID?
        let isGroup: Bool
        switch resolution {
        case .exact(let guid, let group, _):
            conversationID = MessagingConversationID(provider: .messages, nativeID: guid)
            isGroup = group
        case .ambiguous, .notFound:
            conversationID = nil
            isGroup = false
        }
        let title = record.title ?? record.subtitle ?? "Messages"
        onIncoming?(MessagingMessage(
            id: MessagingMessageID(provider: .messages, nativeID: "notification:\(record.recordID)"),
            conversation: MessagingConversation(
                id: conversationID,
                provider: .messages,
                displayTitle: title,
                participantHandles: [],
                isGroup: isGroup
            ),
            senderDisplayName: title,
            body: record.body,
            receivedAt: record.deliveredAt,
            direction: .incoming,
            authority: .systemNotification
        ))
    }

    // MARK: Send

    func send(_ text: String, to conversation: MessagingConversationID) async -> MessagingSendOutcome {
        guard conversation.provider == .messages, observationState == .running else {
            return .failed(reason: "Replying is not available", retryable: false)
        }
        do {
            guard try await automation.chatExists(conversation.nativeID) else {
                return .failed(reason: "This conversation no longer exists in Messages", retryable: false)
            }
        } catch let error as MessagesAutomationError {
            return Self.outcome(for: error)
        } catch {
            return .failed(reason: "Messages could not be reached", retryable: true)
        }

        let startedAt = now().addingTimeInterval(-2)
        do {
            try await automation.send(text, toChat: conversation.nativeID)
        } catch let error as MessagesAutomationError {
            return Self.outcome(for: error)
        } catch {
            return .uncertain(reason: "Messages did not report whether the message was sent")
        }

        // Accepted by Messages; confirm by observing it in this exact chat.
        let expected = MessagesConversationResolver.normalize(text)
        var waited: TimeInterval = 0
        while waited <= Self.confirmationTimeout {
            if let outgoing = try? store.outgoingMessages(inChat: conversation.nativeID, since: startedAt),
               outgoing.contains(where: { MessagesConversationResolver.normalize($0.text) == expected }) {
                return .confirmed
            }
            await sleep(Self.confirmationPollInterval)
            waited += Self.confirmationPollInterval
        }
        return .uncertain(reason: "Messages accepted the reply, but it was not seen in the conversation yet")
    }

    static func outcome(for error: MessagesAutomationError) -> MessagingSendOutcome {
        switch error {
        case .notAuthorized:
            .failed(reason: "Allow DynamicIsland to control Messages in Privacy & Security › Automation", retryable: true)
        case .conversationMissing:
            .failed(reason: "This conversation no longer exists in Messages", retryable: false)
        case .scriptFailed:
            .failed(reason: "Messages could not send the reply", retryable: true)
        }
    }

    // MARK: Open

    func open(_ conversation: MessagingConversation?) -> Bool {
        guard availability == .available, let url = applicationURL() else { return false }
        return openApplication(url)
    }

    func refresh() {
        availability = applicationURL() == nil ? .notInstalled : .available
        if observationState != .disabled {
            setObservationEnabled(true)
        }
    }
}
