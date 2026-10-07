import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
private final class HangingAdapter: MessagingProviderAdapter {
    let provider: MessagingProviderID = .messages
    var availability: MessagingProviderAvailability = .available
    let capabilities = MessagingProviderCapabilities(
        supported: [.composeDraft, .sendReply, .exactConversationTarget, .confirmSend, .openApp],
        limitations: [:]
    )
    var onIncoming: ((MessagingMessage) -> Void)?
    var delay: TimeInterval = 5
    var lateOutcome: MessagingSendOutcome = .confirmed

    func send(_ text: String, to conversation: MessagingConversationID) async -> MessagingSendOutcome {
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        return lateOutcome
    }

    func open(_ conversation: MessagingConversation?) -> Bool { true }
    func refresh() {}
}

@MainActor
final class MessagingFailureTests: XCTestCase {
    func testTimeoutYieldsUncertainAndKeepsDraft() async {
        let adapter = HangingAdapter()
        adapter.delay = 1.0
        let controller = MessagingController(
            adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus(), sendTimeout: 0.1
        )
        controller.receive(MessagingFixtures.message(conversation: "a", at: 10))
        let entry = controller.current!
        controller.updateDraft("are you there", for: entry)

        await controller.send(for: entry)

        XCTAssertEqual(controller.draft(for: entry).text, "are you there")
        guard case .uncertain = controller.draft(for: entry).state else {
            return XCTFail("Timeout must be uncertain, got \(controller.draft(for: entry).state)")
        }

        // The late provider answer is ignored: no false success afterwards.
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertEqual(controller.draft(for: entry).text, "are you there")
        XCTAssertNotEqual(controller.draft(for: entry).state, .sent)
    }

    func testProviderQuittingWhileComposingDisablesReplyAndKeepsDraft() async {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        let entry = controller.current!
        controller.updateDraft("draft", for: entry)

        adapter.availability = .unavailable(reason: "Quit")
        XCTAssertFalse(controller.canReply(to: entry))
        await controller.send(for: entry)

        XCTAssertTrue(adapter.sent.isEmpty)
        XCTAssertEqual(controller.draft(for: entry).text, "draft")
    }

    func testRejectedSendIsNotRetryableButDraftSurvives() async {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        adapter.outcomes = [.failed(reason: "Conversation no longer exists", retryable: false)]
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        let entry = controller.current!
        controller.updateDraft("hi", for: entry)
        await controller.send(for: entry)
        XCTAssertEqual(controller.draft(for: entry).state, .failed(reason: "Conversation no longer exists", retryable: false))
        XCTAssertEqual(controller.draft(for: entry).text, "hi")
    }

    func testMalformedEventWithEmptyTitleStillPresentsSafely() {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: false)
        let activities = LiveActivityStore()
        let controller = MessagingController(adapters: [adapter], liveActivities: activities, focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "a", title: "", body: "   ", at: 10))
        XCTAssertNotNil(controller.current)
        XCTAssertEqual(activities.activities.first?.title, "Messages")
        XCTAssertEqual(activities.activities.first?.subtitle, "New message")
    }

    func testOpenFailureIsReportedAndDoesNotAcknowledge() {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: false)
        adapter.openResult = false
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertFalse(controller.open(controller.current))
        XCTAssertFalse(controller.current?.acknowledged ?? true)
    }
}
