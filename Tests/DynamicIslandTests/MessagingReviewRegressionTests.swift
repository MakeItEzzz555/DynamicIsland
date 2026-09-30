import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
private final class GatedAdapter: MessagingProviderAdapter {
    let provider: MessagingProviderID = .messages
    var availability: MessagingProviderAvailability = .available
    let capabilities = MessagingProviderCapabilities(
        supported: [.composeDraft, .sendReply, .exactConversationTarget, .confirmSend, .openApp],
        limitations: [:]
    )
    var onIncoming: ((MessagingMessage) -> Void)?
    var pending: CheckedContinuation<MessagingSendOutcome, Never>?

    func send(_ text: String, to conversation: MessagingConversationID) async -> MessagingSendOutcome {
        await withCheckedContinuation { pending = $0 }
    }

    func finish(_ outcome: MessagingSendOutcome) {
        pending?.resume(returning: outcome)
        pending = nil
    }

    func open(_ conversation: MessagingConversation?) -> Bool { true }
    func refresh() {}
}

@MainActor
final class MessagingReviewRegressionTests: XCTestCase {
    func testMessageArrivingDuringInFlightSendIsNeverSettledAway() async throws {
        let adapter = GatedAdapter()
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.onIncoming?(MessagingFixtures.message(conversation: "a", messageID: "1", at: 10))
        let entry = controller.current!
        controller.updateDraft("reply", for: entry)

        let send = Task { await controller.send(for: entry) }
        for _ in 0..<50 where adapter.pending == nil { await Task.yield() }
        adapter.onIncoming?(MessagingFixtures.message(conversation: "a", messageID: "2", body: "one more thing", at: 11))
        adapter.finish(.confirmed)
        await send.value

        try await Task.sleep(nanoseconds: UInt64((MessagingController.sentSettleDelay + 0.5) * 1_000_000_000))
        XCTAssertEqual(controller.current?.latest.body, "one more thing")
    }

    func testGlobalLiveActivitiesSwitchIsRespectedAndRepublished() {
        var enabled = false
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: false)
        let activities = LiveActivityStore()
        let controller = MessagingController(
            adapters: [adapter], liveActivities: activities, focus: FakeFocus(),
            presentationEnabled: { enabled }
        )
        adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertTrue(activities.activities.isEmpty)
        XCTAssertEqual(controller.queue.entries.count, 1)

        enabled = true
        controller.republishActivity()
        XCTAssertEqual(activities.activities.first?.kind, .message)
    }

    func testFocusEndingReleasesHeldMessageWithoutAnotherEvent() {
        let focus = FakeFocus()
        focus.isFocused = true
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: false)
        let activities = LiveActivityStore()
        let controller = MessagingController(adapters: [adapter], liveActivities: activities, focus: focus)
        adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertTrue(activities.activities.isEmpty)

        focus.isFocused = false
        XCTAssertEqual(activities.activities.first?.kind, .message)
        XCTAssertNotNil(controller.current)
    }

    func testOutOfOrderDistinctMessageCountsAsUnseen() {
        var queue = MessagingQueue()
        queue.insert(MessagingFixtures.message(conversation: "a", messageID: "2", body: "new", at: 20), heldByFocus: false)
        queue.acknowledge(queue.entries[0].key)
        XCTAssertEqual(queue.insert(MessagingFixtures.message(conversation: "a", messageID: "1", body: "old", at: 10), heldByFocus: false), .updated)
        XCTAssertEqual(queue.entries[0].latest.body, "new")
        XCTAssertEqual(queue.entries[0].unseenCount, 1)
        XCTAssertFalse(queue.entries[0].acknowledged)
    }

    func testConversationWithDraftIsNeverEvicted() {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "draft", at: 1))
        let draftEntry = controller.current!
        controller.updateDraft("half-written reply", for: draftEntry)

        for index in 0..<(MessagingQueue.maximumEntries + 3) {
            adapter.deliver(MessagingFixtures.message(conversation: "c\(index)", at: Double(10 + index)))
        }

        XCTAssertTrue(controller.queue.entries.contains { $0.key == draftEntry.key })
        XCTAssertEqual(controller.queue.entries.count, MessagingQueue.maximumEntries)
        XCTAssertEqual(controller.draft(for: draftEntry).text, "half-written reply")
    }

    func testOpenFailureIsReportedByMessagesAdapter() {
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/x") }, openApplication: { _ in false })
        XCTAssertFalse(adapter.open(nil))
    }
}
