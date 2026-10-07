import Foundation
import XCTest
@testable import DynamicIsland

final class MessagingModelsTests: XCTestCase {
    private let replyCapable = MessagingProviderCapabilities(
        supported: [.observeIncoming, .openConversation, .composeDraft, .sendReply, .confirmSend,
                    .exactConversationTarget, .preserveDraft, .retrySend],
        limitations: [:]
    )
    private let readOnly = MessagingProviderCapabilities(
        supported: [.observeIncoming, .openApp],
        limitations: [.sendReply: "No public send API"]
    )
    private let sendWithoutExactTarget = MessagingProviderCapabilities(
        supported: [.observeIncoming, .composeDraft, .sendReply],
        limitations: [.exactConversationTarget: "Only display names are available"]
    )

    func testConversationIdentityRequiresNativeIDAndIsProviderScoped() {
        XCTAssertNil(MessagingConversationID(provider: .messages, nativeID: "   "))
        let messages = MessagingConversationID(provider: .messages, nativeID: "chat-1")
        let whatsapp = MessagingConversationID(provider: .whatsapp, nativeID: "chat-1")
        XCTAssertNotEqual(messages, whatsapp, "Same native id on two providers is two conversations")
        XCTAssertEqual(messages, MessagingConversationID(provider: .messages, nativeID: " chat-1 "))
    }

    func testDisplayNameIsNotIdentity() {
        let a = conversation("chat-a", title: "Alex")
        let b = conversation("chat-b", title: "Alex")
        XCTAssertNotEqual(a.id, b.id)
    }

    func testReplyRequiresExactTargetAndSendAuthority() {
        let exact = conversation("chat-a")
        let noTarget = MessagingConversation(id: nil, provider: .messages, displayTitle: "Alex", participantHandles: [], isGroup: false)

        XCTAssertTrue(replyCapable.canReply(to: exact))
        XCTAssertFalse(replyCapable.canReply(to: noTarget))
        XCTAssertFalse(readOnly.canReply(to: exact))
        XCTAssertFalse(sendWithoutExactTarget.canReply(to: exact))
        XCTAssertFalse(MessagingProviderCapabilities.none.supportsInlineReply)
    }

    func testReplyRejectsConversationFromAnotherProvider() {
        let mismatched = MessagingConversation(
            id: MessagingConversationID(provider: .whatsapp, nativeID: "x"),
            provider: .messages,
            displayTitle: "t",
            participantHandles: [],
            isGroup: false
        )
        XCTAssertFalse(replyCapable.canReply(to: mismatched))
    }

    func testBeginSendRefusesReadOnlyProviderAndKeepsDraft() {
        var book = MessagingDraftBook()
        let target = conversation("chat-a")
        book.updateText("hello", for: target.id!)
        XCTAssertThrowsError(try book.beginSend(for: target, capabilities: readOnly)) {
            XCTAssertEqual($0 as? MessagingDraftError, .replyNotSupported)
        }
        XCTAssertEqual(book.draft(for: target.id!).text, "hello")
        XCTAssertEqual(book.draft(for: target.id!).state, .drafting)
    }

    func testEmptyDraftAndDoubleSendAreRejected() throws {
        var book = MessagingDraftBook()
        let target = conversation("chat-a")
        XCTAssertThrowsError(try book.beginSend(for: target, capabilities: replyCapable)) {
            XCTAssertEqual($0 as? MessagingDraftError, .emptyDraft)
        }
        book.updateText("hi", for: target.id!)
        _ = try book.beginSend(for: target, capabilities: replyCapable)
        XCTAssertThrowsError(try book.beginSend(for: target, capabilities: replyCapable)) {
            XCTAssertEqual($0 as? MessagingDraftError, .alreadySending)
        }
    }

    func testDraftIsKeptWhileSendingAndClearedOnlyOnConfirmation() throws {
        var book = MessagingDraftBook()
        let target = conversation("chat-a")
        book.updateText("  on my way  ", for: target.id!)

        let (id, text) = try book.beginSend(for: target, capabilities: replyCapable)
        XCTAssertEqual(text, "on my way")
        XCTAssertEqual(book.draft(for: id).state, .sending)
        XCTAssertEqual(book.draft(for: id).text, "  on my way  ", "Invoking send never clears the draft")

        book.updateText("edited during send", for: id)
        XCTAssertEqual(book.draft(for: id).text, "  on my way  ", "Draft is frozen while sending")

        book.apply(.confirmed, for: id)
        XCTAssertEqual(book.draft(for: id).text, "")
        XCTAssertEqual(book.draft(for: id).state, .sent)
    }

    func testFailurePreservesDraftAndRetryCanFailAgain() throws {
        var book = MessagingDraftBook()
        let target = conversation("chat-a")
        book.updateText("retry me", for: target.id!)

        var (id, _) = try book.beginSend(for: target, capabilities: replyCapable)
        book.apply(.failed(reason: "offline", retryable: true), for: id)
        XCTAssertEqual(book.draft(for: id).text, "retry me")
        XCTAssertEqual(book.draft(for: id).state, .failed(reason: "offline", retryable: true))

        (id, _) = try book.beginSend(for: target, capabilities: replyCapable)
        book.apply(.failed(reason: "rejected", retryable: false), for: id)
        XCTAssertEqual(book.draft(for: id).text, "retry me")
    }

    func testUncertainOutcomeIsNotSuccess() throws {
        var book = MessagingDraftBook()
        let target = conversation("chat-a")
        book.updateText("maybe", for: target.id!)
        let (id, _) = try book.beginSend(for: target, capabilities: replyCapable)
        book.apply(.uncertain(reason: "no delivery report"), for: id)
        XCTAssertEqual(book.draft(for: id).text, "maybe")
        XCTAssertEqual(book.draft(for: id).state, .uncertain(reason: "no delivery report"))
    }

    func testConversationDraftsAreIsolated() throws {
        var book = MessagingDraftBook()
        let a = conversation("chat-a")
        let b = conversation("chat-b")
        book.updateText("for A", for: a.id!)
        book.updateText("for B", for: b.id!)

        let (idA, textA) = try book.beginSend(for: a, capabilities: replyCapable)
        XCTAssertEqual(textA, "for A")
        book.apply(.confirmed, for: idA)
        book.apply(.confirmed, for: b.id!)

        XCTAssertEqual(book.draft(for: b.id!).text, "for B", "An outcome for B without a send never touches B")
        XCTAssertEqual(book.draft(for: b.id!).state, .drafting)
        XCTAssertEqual(book.draft(for: a.id!).text, "")
    }

    func testDiscardIsRefusedWhileSendingAndDraftLengthIsBounded() throws {
        var book = MessagingDraftBook()
        let target = conversation("chat-a")
        book.updateText(String(repeating: "x", count: 10_000), for: target.id!)
        XCTAssertEqual(book.draft(for: target.id!).text.count, MessagingDraftBook.maximumDraftLength)
        _ = try book.beginSend(for: target, capabilities: replyCapable)
        book.discard(target.id!)
        XCTAssertEqual(book.draft(for: target.id!).state, .sending)
    }

    private func conversation(_ id: String, title: String = "Alex") -> MessagingConversation {
        MessagingConversation(
            id: MessagingConversationID(provider: .messages, nativeID: id),
            provider: .messages,
            displayTitle: title,
            participantHandles: [],
            isGroup: false
        )
    }
}
