import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class FakeMessagingAdapter: MessagingProviderAdapter {
    let provider: MessagingProviderID
    var availability: MessagingProviderAvailability = .available
    var capabilities: MessagingProviderCapabilities
    var onIncoming: ((MessagingMessage) -> Void)?
    var outcomes: [MessagingSendOutcome] = [.confirmed]
    var sent: [(String, MessagingConversationID)] = []
    var opened: [MessagingConversation?] = []
    var openResult = true
    var refreshCount = 0

    init(provider: MessagingProviderID, replyCapable: Bool) {
        self.provider = provider
        self.capabilities = replyCapable
            ? MessagingProviderCapabilities(
                supported: [.observeIncoming, .openConversation, .composeDraft, .sendReply,
                            .confirmSend, .exactConversationTarget, .preserveDraft, .retrySend],
                limitations: [:]
            )
            : MessagingProviderCapabilities(
                supported: [.observeIncoming, .openApp],
                limitations: [.sendReply: "No public send API"]
            )
    }

    func deliver(_ message: MessagingMessage) { onIncoming?(message) }

    func send(_ text: String, to conversation: MessagingConversationID) async -> MessagingSendOutcome {
        sent.append((text, conversation))
        return outcomes.isEmpty ? .confirmed : outcomes.removeFirst()
    }

    func open(_ conversation: MessagingConversation?) -> Bool {
        opened.append(conversation)
        return openResult
    }

    func refresh() { refreshCount += 1 }
}

@MainActor
final class FakeFocus: MessagingFocusProviding {
    var isFocused: Bool? {
        didSet { onChange?() }
    }
    var onChange: (() -> Void)?
}

enum MessagingFixtures {
    static func message(
        provider: MessagingProviderID = .messages,
        conversation: String?,
        messageID: String? = nil,
        title: String = "Alex",
        body: String? = "Nachos at seven?",
        at seconds: TimeInterval
    ) -> MessagingMessage {
        MessagingMessage(
            id: messageID.map { MessagingMessageID(provider: provider, nativeID: $0) },
            conversation: MessagingConversation(
                id: conversation.flatMap { MessagingConversationID(provider: provider, nativeID: $0) },
                provider: provider,
                displayTitle: title,
                participantHandles: [],
                isGroup: false
            ),
            senderDisplayName: title,
            body: body,
            receivedAt: Date(timeIntervalSince1970: seconds),
            direction: .incoming,
            authority: .fixture
        )
    }
}

final class MessagingQueueTests: XCTestCase {
    func testNewestFirstAndOneEntryPerConversation() {
        var queue = MessagingQueue()
        queue.insert(MessagingFixtures.message(conversation: "a", messageID: "1", at: 10), heldByFocus: false)
        queue.insert(MessagingFixtures.message(conversation: "b", messageID: "2", at: 20), heldByFocus: false)
        XCTAssertEqual(queue.insert(MessagingFixtures.message(conversation: "a", messageID: "3", at: 30), heldByFocus: false), .updated)

        XCTAssertEqual(queue.entries.map { $0.conversation.id?.nativeID }, ["a", "b"])
        XCTAssertEqual(queue.entries.first?.unseenCount, 2)
    }

    func testDuplicateMessageIDIsIgnored() {
        var queue = MessagingQueue()
        queue.insert(MessagingFixtures.message(conversation: "a", messageID: "1", at: 10), heldByFocus: false)
        XCTAssertEqual(queue.insert(MessagingFixtures.message(conversation: "a", messageID: "1", at: 10), heldByFocus: false), .duplicate)
        XCTAssertEqual(queue.entries.count, 1)
        XCTAssertEqual(queue.entries.first?.unseenCount, 1)
    }

    func testOlderMessageDoesNotReplaceLatest() {
        var queue = MessagingQueue()
        queue.insert(MessagingFixtures.message(conversation: "a", messageID: "2", body: "new", at: 20), heldByFocus: false)
        queue.insert(MessagingFixtures.message(conversation: "a", messageID: "1", body: "old", at: 10), heldByFocus: false)
        XCTAssertEqual(queue.entries.first?.latest.body, "new")
    }

    func testMessagesWithoutExactTargetNeverMerge() {
        var queue = MessagingQueue()
        queue.insert(MessagingFixtures.message(conversation: nil, title: "Alex", at: 10), heldByFocus: false)
        queue.insert(MessagingFixtures.message(conversation: nil, title: "Alex", at: 11), heldByFocus: false)
        XCTAssertEqual(queue.entries.count, 2)
    }

    func testProvidersAreIsolated() {
        var queue = MessagingQueue()
        queue.insert(MessagingFixtures.message(provider: .messages, conversation: "x", at: 10), heldByFocus: false)
        queue.insert(MessagingFixtures.message(provider: .whatsapp, conversation: "x", at: 11), heldByFocus: false)
        XCTAssertEqual(queue.entries.count, 2)
    }

    func testBoundedRetentionDropsAcknowledgedFirst() {
        var queue = MessagingQueue()
        for index in 0..<MessagingQueue.maximumEntries {
            queue.insert(MessagingFixtures.message(conversation: "c\(index)", at: Double(index)), heldByFocus: false)
        }
        let oldestUnacked = queue.entries.last!.key
        let acked = queue.entries[2].key
        queue.acknowledge(acked)
        queue.insert(MessagingFixtures.message(conversation: "new", at: 100), heldByFocus: false)

        XCTAssertEqual(queue.entries.count, MessagingQueue.maximumEntries)
        XCTAssertFalse(queue.entries.contains { $0.key == acked })
        XCTAssertTrue(queue.entries.contains { $0.key == oldestUnacked })
    }

    func testRememberedMessageIDsAreBounded() {
        var queue = MessagingQueue()
        for index in 0..<50 {
            queue.insert(MessagingFixtures.message(conversation: "a", messageID: "\(index)", at: Double(index)), heldByFocus: false)
        }
        XCTAssertEqual(queue.entries.first?.seenMessageIDs.count, MessagingQueue.maximumRememberedMessageIDs)
    }
}

@MainActor
final class MessagingControllerTests: XCTestCase {
    func testIncomingMessagePublishesPersistentMessageActivity() {
        let fixture = makeFixture(replyCapable: true)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))

        let activity = fixture.activities.activities.first
        XCTAssertEqual(activity?.kind, .message)
        XCTAssertEqual(activity?.id, MessagingController.activityID)
        XCTAssertEqual(activity?.priority, MessagingController.freshPriority)
        XCTAssertEqual(activity?.title, "Alex")
        XCTAssertEqual(activity?.subtitle, "Nachos at seven?")
        XCTAssertEqual(activity?.lifecycle.authority, .integrationAdapter)
        XCTAssertNil(activity?.progress)
    }

    func testAcknowledgeLowersPriorityAndDismissRemovesOnlyMessageActivity() {
        let fixture = makeFixture(replyCapable: true)
        fixture.activities.update(LiveActivityPreviewCatalog.timer)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        let entry = fixture.controller.current!

        fixture.controller.acknowledge(entry)
        XCTAssertEqual(fixture.activities.activities.first { $0.kind == .message }?.priority, MessagingController.acknowledgedPriority)

        fixture.controller.dismiss(fixture.controller.current!)
        XCTAssertNil(fixture.activities.activities.first { $0.kind == .message })
        XCTAssertNotNil(fixture.activities.activities.first { $0.kind == .timer }, "Unrelated activities survive")
    }

    func testQueuedCountAndBodyHiding() {
        let fixture = makeFixture(replyCapable: false)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "b", title: "Sam", body: "Secret", at: 20))
        XCTAssertEqual(fixture.activities.activities.first?.title, "Sam")
        XCTAssertEqual(fixture.activities.activities.first?.subtitle, "Secret · +1")

        fixture.controller.preferences.showPreviewOnCompact = false
        XCTAssertEqual(fixture.activities.activities.first?.subtitle, "New message · +1")
    }

    func testMutedProviderAndDisabledMessagingPresentNothing() {
        let fixture = makeFixture(replyCapable: false)
        fixture.controller.preferences.mutedProviders = [.messages]
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertTrue(fixture.controller.queue.entries.isEmpty)

        fixture.controller.preferences.mutedProviders = []
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 11))
        XCTAssertFalse(fixture.activities.activities.isEmpty)
        fixture.controller.preferences.enabled = false
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testAuthoritativeFocusHoldsCompactActivityUntilFocusEnds() {
        let fixture = makeFixture(replyCapable: false)
        fixture.focus.isFocused = true
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertTrue(fixture.activities.activities.isEmpty)
        XCTAssertEqual(fixture.controller.queue.entries.count, 1, "Held, not dropped")

        fixture.focus.isFocused = false
        fixture.controller.focusDidChange()
        XCTAssertEqual(fixture.activities.activities.first?.kind, .message)
    }

    func testUnknownFocusDoesNotSuppress() {
        let fixture = makeFixture(replyCapable: false)
        fixture.focus.isFocused = nil
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertEqual(fixture.activities.activities.first?.kind, .message)
    }

    func testReadOnlyProviderNeverSends() async {
        let fixture = makeFixture(replyCapable: false)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        let entry = fixture.controller.current!
        XCTAssertFalse(fixture.controller.canReply(to: entry))

        fixture.controller.updateDraft("hello", for: entry)
        await fixture.controller.send(for: entry)
        XCTAssertTrue(fixture.adapter.sent.isEmpty)
        XCTAssertEqual(fixture.controller.draft(for: entry).text, "")
    }

    func testNoExactTargetNeverSendsEvenWithReplyCapableProvider() async {
        let fixture = makeFixture(replyCapable: true)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: nil, at: 10))
        let entry = fixture.controller.current!
        XCTAssertFalse(fixture.controller.canReply(to: entry))
        await fixture.controller.send(for: entry)
        XCTAssertTrue(fixture.adapter.sent.isEmpty)
    }

    func testUnavailableProviderCannotReply() {
        let fixture = makeFixture(replyCapable: true)
        fixture.adapter.availability = .unavailable(reason: "Quit")
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertFalse(fixture.controller.canReply(to: fixture.controller.current!))
    }

    func testConfirmedSendClearsDraftAndSettles() async throws {
        let fixture = makeFixture(replyCapable: true)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        let entry = fixture.controller.current!
        fixture.controller.updateDraft("Count me in", for: entry)

        await fixture.controller.send(for: entry)

        XCTAssertEqual(fixture.adapter.sent.first?.0, "Count me in")
        XCTAssertEqual(fixture.adapter.sent.first?.1.nativeID, "a")
        XCTAssertEqual(fixture.controller.draft(for: entry).state, .sent)
        XCTAssertEqual(fixture.controller.draft(for: entry).text, "")
        for _ in 0..<60 where fixture.controller.current != nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertNil(fixture.controller.current)
        XCTAssertTrue(fixture.activities.activities.isEmpty)
    }

    func testFailedAndUncertainSendsPreserveDraft() async {
        let fixture = makeFixture(replyCapable: true)
        fixture.adapter.outcomes = [
            .failed(reason: "Transport failure", retryable: true),
            .uncertain(reason: "No delivery report")
        ]
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        let entry = fixture.controller.current!
        fixture.controller.updateDraft("keep me", for: entry)

        await fixture.controller.send(for: entry)
        XCTAssertEqual(fixture.controller.draft(for: entry).text, "keep me")
        XCTAssertEqual(fixture.controller.draft(for: entry).state, .failed(reason: "Transport failure", retryable: true))

        await fixture.controller.send(for: entry)
        XCTAssertEqual(fixture.controller.draft(for: entry).text, "keep me")
        XCTAssertEqual(fixture.controller.draft(for: entry).state, .uncertain(reason: "No delivery report"))
        XCTAssertNotNil(fixture.controller.current, "Unconfirmed conversations stay visible")
    }

    func testSendTargetsOnlyItsOwnConversation() async {
        let fixture = makeFixture(replyCapable: true)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", title: "A", at: 10))
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "b", title: "B", at: 20))
        let b = fixture.controller.queue.entries.first { $0.conversation.id?.nativeID == "b" }!
        let a = fixture.controller.queue.entries.first { $0.conversation.id?.nativeID == "a" }!
        fixture.controller.updateDraft("to A", for: a)
        fixture.controller.updateDraft("to B", for: b)

        await fixture.controller.send(for: a)

        XCTAssertEqual(fixture.adapter.sent.map(\.0), ["to A"])
        XCTAssertEqual(fixture.adapter.sent.map(\.1.nativeID), ["a"])
        XCTAssertEqual(fixture.controller.draft(for: b).text, "to B")
    }

    func testNewerMessageDuringSettleKeepsConversation() async throws {
        let fixture = makeFixture(replyCapable: true)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", messageID: "1", at: 10))
        let entry = fixture.controller.current!
        fixture.controller.updateDraft("ok", for: entry)
        await fixture.controller.send(for: entry)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", messageID: "2", body: "and bring chips", at: 11))
        try await Task.sleep(nanoseconds: UInt64((MessagingController.sentSettleDelay + 0.5) * 1_000_000_000))
        XCTAssertEqual(fixture.controller.current?.latest.body, "and bring chips")
    }

    func testOpenUsesAdapterAndAcknowledges() {
        let fixture = makeFixture(replyCapable: false)
        fixture.adapter.deliver(MessagingFixtures.message(conversation: "a", at: 10))
        XCTAssertTrue(fixture.controller.open(fixture.controller.current))
        XCTAssertEqual(fixture.adapter.opened.count, 1)
        XCTAssertTrue(fixture.controller.current?.acknowledged ?? false)

        fixture.adapter.openResult = false
        XCTAssertFalse(fixture.controller.open(fixture.controller.current))
    }

    func testOutgoingAndUnknownProviderEventsAreIgnored() {
        let fixture = makeFixture(replyCapable: false)
        var outgoing = MessagingFixtures.message(conversation: "a", at: 10)
        outgoing = MessagingMessage(
            id: nil, conversation: outgoing.conversation, senderDisplayName: "me", body: "x",
            receivedAt: outgoing.receivedAt, direction: .outgoing, authority: .fixture
        )
        fixture.controller.receive(outgoing)
        fixture.controller.receive(MessagingFixtures.message(provider: .telegram, conversation: "t", at: 11))
        XCTAssertTrue(fixture.controller.queue.entries.isEmpty)
    }

    private func makeFixture(replyCapable: Bool) -> (
        controller: MessagingController,
        adapter: FakeMessagingAdapter,
        activities: LiveActivityStore,
        focus: FakeFocus
    ) {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: replyCapable)
        let activities = LiveActivityStore()
        let focus = FakeFocus()
        let controller = MessagingController(adapters: [adapter], liveActivities: activities, focus: focus)
        return (controller, adapter, activities, focus)
    }
}

@MainActor
final class MessagingLiveActivityArbitrationTests: XCTestCase {
    private var message: DynamicIslandLiveActivity {
        let entry = MessagingQueueEntry(
            key: "k",
            latest: MessagingFixtures.message(conversation: "a", at: 10),
            unseenCount: 1,
            seenMessageIDs: [],
            firstReceivedAt: Date(timeIntervalSince1970: 10),
            acknowledged: false,
            heldByFocus: false
        )
        return MessagingController.makeActivity(for: entry, queuedCount: 1, showBody: true, updatedAt: .distantPast)
    }

    func testMessagePrimaryWithSidecars() {
        for (other, kind) in [
            (LiveActivityPreviewCatalog.timer, DynamicIslandLiveActivityKind.timer),
            (LiveActivityPreviewCatalog.keepAwake, .keepAwake),
            (LiveActivityPreviewCatalog.reminder, .reminder)
        ] {
            let result = resolve([message, other])
            XCTAssertEqual(result.primary?.activity.kind, .message, "with \(kind)")
            XCTAssertEqual(
                [result.leadingSidecar?.activity.kind, result.trailingSidecar?.activity.kind].compactMap { $0 },
                [kind]
            )
        }
    }

    func testFreshMessageBeatsPlayingMediaButNotAgentsCameraOrVoice() {
        XCTAssertEqual(resolve([message, LiveActivityPreviewCatalog.media]).primary?.activity.kind, .message)
        XCTAssertEqual(resolve([message, LiveActivityPreviewCatalog.agent]).primary?.activity.kind, .agent)
        XCTAssertEqual(resolve([message, LiveActivityPreviewCatalog.camera]).primary?.activity.kind, .camera)
        XCTAssertEqual(resolve([message, LiveActivityPreviewCatalog.voiceRecording]).primary?.activity.kind, .voiceRecording)
    }

    func testTransientVolumeAndBrightnessHUDsPreserveMessage() {
        let brightness = DynamicIslandLiveActivity(
            id: "preview-brightness", kind: .system, title: "Brightness", subtitle: "40%",
            symbolName: "sun.max.fill", priority: 200, isActive: true, progress: 0.4, updatedAt: .distantPast
        )
        for hud in [LiveActivityPreviewCatalog.volume, brightness] {
            let base = resolve([message, LiveActivityPreviewCatalog.timer])
            let withHUD = resolve([message, LiveActivityPreviewCatalog.timer, hud])
            XCTAssertEqual(withHUD.overlayTransient?.activity.kind, .system)
            XCTAssertEqual(withHUD.primary, base.primary)
            XCTAssertEqual(withHUD.trailingSidecar, base.trailingSidecar)
            XCTAssertEqual(withHUD.leadingSidecar, base.leadingSidecar)
        }
    }

    func testResolutionIsOrderIndependentUnderWidthPressure() {
        let set = [message, LiveActivityPreviewCatalog.timer, LiveActivityPreviewCatalog.keepAwake, LiveActivityPreviewCatalog.media]
        XCTAssertEqual(resolve(set, width: 240), resolve(set.reversed(), width: 240))
        XCTAssertEqual(resolve(set, width: 240).primary?.activity.kind, .message)
    }

    private func resolve(_ activities: [DynamicIslandLiveActivity], width: CGFloat = 320) -> LiveActivityLayoutResolution {
        LiveActivityLayoutResolver.resolve(
            activities: activities,
            context: LiveActivityLayoutContext(
                availableWidth: width,
                hasHardwareNotch: true,
                hardwareNotchWidth: 180,
                primaryMinimumWidth: 172,
                primaryIdealWidth: 226,
                sidecarDiameter: 30,
                sidecarGap: 7,
                allowSimultaneousSidecars: true,
                timerSidePreference: .automatic
            )
        )
    }
}
