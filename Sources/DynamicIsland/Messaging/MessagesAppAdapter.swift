import AppKit
import Foundation

/// Apple Messages at the strongest level the public macOS API supports
/// (see research/MESSAGING_PROVIDER_AUTHORITY_AUDIT_2026-09-30.md):
///
/// - Incoming: blocked. Messages' scripting dictionary has no message
///   class or event handlers, other apps' notifications are not readable,
///   and chat.db is private.
/// - Reply: not offered. AppleScript `send` has no result (no delivery or
///   failure evidence), and no public incoming source yields the exact
///   chat id, so a reply could not be targeted or confirmed.
/// - Open: activates Messages. Needs no Automation permission.
@MainActor
final class MessagesAppAdapter: MessagingProviderAdapter {
    static let bundleIdentifier = "com.apple.MobileSMS"

    static let observeLimitation =
        "macOS provides no public way for other apps to read incoming Messages"
    static let replyLimitation =
        "Messages cannot confirm sends and no exact conversation is available, so replies open Messages instead"
    static let conversationLimitation =
        "No exact conversation identity is available to open a specific chat"

    let provider: MessagingProviderID = .messages
    var onIncoming: ((MessagingMessage) -> Void)?
    private(set) var availability: MessagingProviderAvailability

    private let applicationURL: () -> URL?
    private let openApplication: (URL) -> Bool

    init(
        applicationURL: @escaping () -> URL? = {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: MessagesAppAdapter.bundleIdentifier)
        },
        // Synchronous launch result, so success is never assumed.
        openApplication: @escaping (URL) -> Bool = { url in
            NSWorkspace.shared.open(url)
        }
    ) {
        self.applicationURL = applicationURL
        self.openApplication = openApplication
        self.availability = applicationURL() == nil ? .notInstalled : .available
    }

    var capabilities: MessagingProviderCapabilities {
        guard availability == .available else {
            return MessagingProviderCapabilities(
                supported: [],
                limitations: [.openApp: "Messages is not installed"]
            )
        }
        return MessagingProviderCapabilities(
            supported: [.openApp],
            limitations: [
                .observeIncoming: Self.observeLimitation,
                .sendReply: Self.replyLimitation,
                .confirmSend: Self.replyLimitation,
                .exactConversationTarget: Self.conversationLimitation,
                .openConversation: Self.conversationLimitation,
                .composeDraft: Self.replyLimitation
            ]
        )
    }

    func send(_ text: String, to conversation: MessagingConversationID) async -> MessagingSendOutcome {
        // Never reached: capabilities never include sendReply.
        .failed(reason: "Replying is not supported for Messages", retryable: false)
    }

    func open(_ conversation: MessagingConversation?) -> Bool {
        guard availability == .available, let url = applicationURL() else { return false }
        return openApplication(url)
    }

    func refresh() {
        availability = applicationURL() == nil ? .notInstalled : .available
    }
}
