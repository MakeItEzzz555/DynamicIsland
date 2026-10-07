import Foundation

// MARK: - Provider identity

enum MessagingProviderID: Hashable, Sendable, Codable {
    case messages
    case whatsapp
    case telegram
    case custom(String)

    var stableName: String {
        switch self {
        case .messages: "messages"
        case .whatsapp: "whatsapp"
        case .telegram: "telegram"
        case .custom(let name): "custom:\(name)"
        }
    }

    var displayName: String {
        switch self {
        case .messages: "Messages"
        case .whatsapp: "WhatsApp"
        case .telegram: "Telegram"
        case .custom(let name): name
        }
    }

    var symbolName: String {
        switch self {
        case .messages: "message.fill"
        case .whatsapp, .telegram, .custom: "bubble.left.and.bubble.right.fill"
        }
    }
}

// MARK: - Conversation and message identity

/// Exact provider-native conversation identity. Display titles, contact
/// names and notification titles are never part of identity.
struct MessagingConversationID: Hashable, Sendable {
    let provider: MessagingProviderID
    let nativeID: String

    init?(provider: MessagingProviderID, nativeID: String) {
        let trimmed = nativeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.provider = provider
        self.nativeID = trimmed
    }
}

/// Provider-native message identity, only when the provider exposes one.
struct MessagingMessageID: Hashable, Sendable {
    let provider: MessagingProviderID
    let nativeID: String
}

enum MessagingAuthority: String, Equatable, Sendable {
    /// Provider-published structured event (scripting/API).
    case providerEvent
    /// Derived from a system notification; content may be truncated.
    case systemNotification
    /// Synthetic fixture for tests and previews only.
    case fixture
}

struct MessagingConversation: Equatable, Sendable {
    /// Exact target; nil when the source cannot identify the conversation.
    let id: MessagingConversationID?
    let provider: MessagingProviderID
    /// Presentation only.
    let displayTitle: String
    /// Presentation only; never used for targeting.
    let participantHandles: [String]
    let isGroup: Bool

    var hasExactTarget: Bool { id != nil }
}

enum MessagingDirection: String, Equatable, Sendable {
    case incoming
    case outgoing
}

struct MessagingMessage: Equatable, Sendable {
    let id: MessagingMessageID?
    let conversation: MessagingConversation
    /// Presentation only.
    let senderDisplayName: String
    /// Preview text; nil when the source does not expose the body.
    let body: String?
    let receivedAt: Date
    let direction: MessagingDirection
    let authority: MessagingAuthority
}

// MARK: - Capabilities

enum MessagingCapability: String, CaseIterable, Hashable, Sendable {
    case observeIncoming
    case openApp
    case openConversation
    case composeDraft
    case sendReply
    case confirmSend
    case exactConversationTarget
    case preserveDraft
    case retrySend
}

enum MessagingProviderAvailability: Equatable, Sendable {
    case available
    case notInstalled
    case unavailable(reason: String)
}

/// Explicit provider authority. UI derives every control from this.
struct MessagingProviderCapabilities: Equatable, Sendable {
    let supported: Set<MessagingCapability>
    /// Human-readable reason per unsupported capability, for Settings.
    let limitations: [MessagingCapability: String]

    static let none = MessagingProviderCapabilities(supported: [], limitations: [:])

    func contains(_ capability: MessagingCapability) -> Bool {
        supported.contains(capability)
    }

    /// Inline reply requires exact targeting plus send authority.
    var supportsInlineReply: Bool {
        contains(.composeDraft) && contains(.sendReply) && contains(.exactConversationTarget)
    }

    func canReply(to conversation: MessagingConversation) -> Bool {
        supportsInlineReply && conversation.hasExactTarget && conversation.id?.provider == conversation.provider
    }
}

// MARK: - Send outcome

/// What the provider actually proved about a send attempt.
enum MessagingSendOutcome: Equatable, Sendable {
    /// The provider confirmed it accepted the message for the exact
    /// conversation. This is the only outcome that clears a draft.
    case confirmed
    /// The provider rejected or failed the send.
    case failed(reason: String, retryable: Bool)
    /// The send was handed off but the provider gives no authoritative
    /// result. Never treated as success.
    case uncertain(reason: String)
}

// MARK: - Draft lifecycle

enum MessagingDraftState: Equatable, Sendable {
    case idle
    case drafting
    case sending
    case sent
    case failed(reason: String, retryable: Bool)
    case uncertain(reason: String)

    var isSending: Bool { self == .sending }
}

struct MessagingDraft: Equatable, Sendable {
    var text: String = ""
    var state: MessagingDraftState = .idle
}

enum MessagingDraftError: Error, Equatable {
    case replyNotSupported
    case emptyDraft
    case alreadySending
}

/// Per-conversation drafts. Keyed by exact conversation identity, so a
/// draft can never be sent to or erased by another conversation.
struct MessagingDraftBook: Equatable, Sendable {
    static let maximumDraftLength = 4_000

    private(set) var drafts: [MessagingConversationID: MessagingDraft] = [:]

    func draft(for id: MessagingConversationID) -> MessagingDraft {
        drafts[id] ?? MessagingDraft()
    }

    mutating func updateText(_ text: String, for id: MessagingConversationID) {
        var draft = draft(for: id)
        guard !draft.state.isSending else { return }
        draft.text = String(text.prefix(Self.maximumDraftLength))
        switch draft.state {
        case .sending:
            break
        case .idle, .sent, .drafting, .failed, .uncertain:
            draft.state = draft.text.isEmpty ? .idle : .drafting
        }
        drafts[id] = draft
    }

    /// Returns the text to send and marks the draft `sending`. The text is
    /// kept until a confirmed outcome arrives.
    mutating func beginSend(
        for conversation: MessagingConversation,
        capabilities: MessagingProviderCapabilities
    ) throws -> (MessagingConversationID, String) {
        guard let id = conversation.id, capabilities.canReply(to: conversation) else {
            throw MessagingDraftError.replyNotSupported
        }
        var draft = draft(for: id)
        guard !draft.state.isSending else { throw MessagingDraftError.alreadySending }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw MessagingDraftError.emptyDraft }
        draft.state = .sending
        drafts[id] = draft
        return (id, text)
    }

    mutating func apply(_ outcome: MessagingSendOutcome, for id: MessagingConversationID) {
        var draft = draft(for: id)
        guard draft.state.isSending else { return }
        switch outcome {
        case .confirmed:
            draft.text = ""
            draft.state = .sent
        case .failed(let reason, let retryable):
            draft.state = .failed(reason: reason, retryable: retryable)
        case .uncertain(let reason):
            draft.state = .uncertain(reason: reason)
        }
        drafts[id] = draft
    }

    mutating func discard(_ id: MessagingConversationID) {
        guard !draft(for: id).state.isSending else { return }
        drafts.removeValue(forKey: id)
    }
}
