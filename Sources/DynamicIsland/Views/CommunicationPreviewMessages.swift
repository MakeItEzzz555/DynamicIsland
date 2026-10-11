import Foundation

@MainActor
final class CommunicationPreviewMessages: ObservableObject {
    let controller: MessagingController
    init() {
        controller = MessagingController(adapters: [PreviewMessagesAdapter()], liveActivities: LiveActivityStore(),
            focus: PreviewMessagesFocus())
        let conversation = MessagingConversation(id: .init(provider: .messages, nativeID: "preview-chat"),
            provider: .messages, displayTitle: "Alex (sample)", participantHandles: [], isGroup: false)
        controller.receive(MessagingMessage(id: nil, conversation: conversation, senderDisplayName: "Alex (sample)",
            body: "See you at seven", receivedAt: LiveActivityPreviewCatalog.referenceDate,
            direction: .incoming, authority: .fixture))
    }
}

@MainActor
private final class PreviewMessagesAdapter: MessagingProviderAdapter {
    let provider: MessagingProviderID = .messages
    let availability: MessagingProviderAvailability = .available
    let capabilities = MessagingProviderCapabilities(supported: [.composeDraft, .sendReply, .confirmSend,
        .exactConversationTarget, .preserveDraft, .openApp], limitations: [:])
    var onIncoming: ((MessagingMessage) -> Void)?
    func send(_ text: String, to conversation: MessagingConversationID) async -> MessagingSendOutcome {
        .uncertain(reason: "Preview only")
    }
    func open(_ conversation: MessagingConversation?) -> Bool { false }
    func refresh() {}
}

@MainActor
private final class PreviewMessagesFocus: MessagingFocusProviding {
    let isFocused: Bool? = false
    var onChange: (() -> Void)?
}
