import Foundation
import XCTest
@testable import DynamicIsland

// MARK: - Adapter with fakes

final class FakeMessagesStore: MessagesConversationStore, @unchecked Sendable {
    private let lock = NSLock()
    var incoming: [MessagesDatabaseMessage] = []
    var outgoing: [MessagesDatabaseMessage] = []
    var failure: Error?

    func messages(from start: Date, to end: Date, limit: Int) throws -> [MessagesDatabaseMessage] {
        try lock.withLock {
            if let failure { throw failure }
            return incoming
        }
    }

    func outgoingMessages(inChat chatGUID: String, since date: Date) throws -> [MessagesDatabaseMessage] {
        lock.withLock { outgoing.filter { $0.chatGUID == chatGUID } }
    }
}

final class FakeMessagesAutomation: MessagesAutomating, @unchecked Sendable {
    private let lock = NSLock()
    var exists = true
    var sendError: MessagesAutomationError?
    var sent: [(String, String)] = []
    var onSend: ((String, String) -> Void)?

    func permission(askIfNeeded: Bool) -> MessagesAutomationPermission { .granted }

    func chatExists(_ chatGUID: String) async throws -> Bool { lock.withLock { exists } }

    func send(_ text: String, toChat chatGUID: String) async throws {
        if let sendError { throw sendError }
        lock.withLock { sent.append((text, chatGUID)) }
        onSend?(text, chatGUID)
    }
}

private final class StaticNotificationSource: SystemNotificationSource, @unchecked Sendable {
    let watchedPaths: [String] = []
    func latestRecordID() throws -> Int64 { 0 }
    func records(after recordID: Int64, limit: Int) throws -> [SystemNotificationRecord] { [] }
}

@MainActor
final class MessagesAppAdapterAuthorityTests: XCTestCase {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func makeAdapter(store: FakeMessagesStore, automation: FakeMessagesAutomation, fda: FullDiskAccessState = .granted) -> MessagesAppAdapter {
        MessagesAppAdapter(
            applicationURL: { URL(fileURLWithPath: "/System/Applications/Messages.app") },
            openApplication: { _ in true },
            monitor: SystemNotificationMonitor(makeSource: { StaticNotificationSource() }, fullDiskAccess: { fda }),
            store: store,
            automation: automation,
            now: { self.base },
            sleep: { _ in await Task.yield() }
        )
    }

    private func notification(_ id: Int64, title: String, body: String) -> SystemNotificationRecord {
        SystemNotificationRecord(recordID: id, bundleIdentifier: "com.apple.MobileSMS", title: title, subtitle: nil, body: body, deliveredAt: base.addingTimeInterval(Double(id)))
    }

    private func incoming(_ id: Int64, chat: String, text: String) -> MessagesDatabaseMessage {
        MessagesDatabaseMessage(rowID: id, chatGUID: chat, isGroup: false, service: "iMessage", text: text, date: base, isFromMe: false)
    }

    func testObservationIsOptInAndRequiresFullDiskAccess() {
        let adapter = makeAdapter(store: FakeMessagesStore(), automation: FakeMessagesAutomation(), fda: .denied)
        XCTAssertEqual(adapter.capabilities.supported, [.openApp])
        adapter.setObservationEnabled(true)
        XCTAssertEqual(adapter.observationState, .permissionRequired)
        XCTAssertFalse(adapter.capabilities.supportsInlineReply)
        XCTAssertEqual(adapter.capabilities.limitations[.observeIncoming], MessagesAppAdapter.fullDiskAccessLimitation)
    }

    func testUnsupportedMessagesSchemaFailsClosed() {
        let store = FakeMessagesStore()
        store.failure = ReadOnlySQLiteError.unsupportedSchema("message is missing text")
        let adapter = makeAdapter(store: store, automation: FakeMessagesAutomation())
        adapter.setObservationEnabled(true)
        guard case .unavailable = adapter.observationState else { return XCTFail("\(adapter.observationState)") }
        XCTAssertFalse(adapter.capabilities.supportsInlineReply)
    }

    func testResolvedNotificationCarriesExactChatAndAmbiguousDoesNot() async throws {
        let store = FakeMessagesStore()
        store.incoming = [incoming(1, chat: "chat-A", text: "Nachos?"), incoming(2, chat: "chat-B", text: "Same"), incoming(3, chat: "chat-C", text: "Same")]
        let adapter = makeAdapter(store: store, automation: FakeMessagesAutomation())
        adapter.setObservationEnabled(true)
        XCTAssertTrue(adapter.capabilities.supportsInlineReply)
        var received: [MessagingMessage] = []
        adapter.onIncoming = { received.append($0) }

        adapter.handle(notification(1, title: "Alex", body: "Nachos?"))
        adapter.handle(notification(2, title: "Group", body: "Same"))
        adapter.handle(SystemNotificationRecord(recordID: 3, bundleIdentifier: "com.apple.mail", title: "x", subtitle: nil, body: "Nachos?", deliveredAt: base))
        for _ in 0..<200 where received.count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        try await Task.sleep(nanoseconds: 20_000_000)

        XCTAssertEqual(received.count, 2, "Non-Messages notifications are ignored")
        XCTAssertEqual(received[0].conversation.id?.nativeID, "chat-A")
        XCTAssertEqual(received[0].conversation.displayTitle, "Alex")
        XCTAssertNil(received[1].conversation.id, "Ambiguous match never gets a reply target")
    }

    func testSendConfirmedOnlyWhenObservedInExactChat() async {
        let store = FakeMessagesStore()
        let automation = FakeMessagesAutomation()
        automation.onSend = { text, chat in
            store.outgoing.append(MessagesDatabaseMessage(rowID: 99, chatGUID: chat, isGroup: false, service: "iMessage", text: text, date: Date(timeIntervalSinceReferenceDate: 800_000_001), isFromMe: true))
        }
        let adapter = makeAdapter(store: store, automation: automation)
        adapter.setObservationEnabled(true)

        let outcome = await adapter.send("Count me in", to: MessagingConversationID(provider: .messages, nativeID: "chat-A")!)
        XCTAssertEqual(outcome, .confirmed)
        XCTAssertEqual(automation.sent.map(\.1), ["chat-A"])
    }

    func testSendAcceptedButNotObservedIsUncertain() async {
        let adapter = makeAdapter(store: FakeMessagesStore(), automation: FakeMessagesAutomation())
        adapter.setObservationEnabled(true)
        let outcome = await adapter.send("hi", to: MessagingConversationID(provider: .messages, nativeID: "chat-A")!)
        guard case .uncertain = outcome else { return XCTFail("\(outcome)") }
    }

    func testSendFailuresMapTruthfully() async {
        let automation = FakeMessagesAutomation()
        let adapter = makeAdapter(store: FakeMessagesStore(), automation: automation)
        adapter.setObservationEnabled(true)
        let target = MessagingConversationID(provider: .messages, nativeID: "chat-A")!

        automation.exists = false
        let missing = await adapter.send("hi", to: target)
        XCTAssertEqual(missing, .failed(reason: "This conversation no longer exists in Messages", retryable: false))
        XCTAssertTrue(automation.sent.isEmpty, "Never sends to a missing conversation")

        automation.exists = true
        automation.sendError = .notAuthorized
        let unauthorized = await adapter.send("hi", to: target)
        guard case .failed(_, true) = unauthorized else { return XCTFail("\(unauthorized)") }

        automation.sendError = .scriptFailed(code: -1, message: "x")
        let scriptFailure = await adapter.send("hi", to: target)
        guard case .failed(_, true) = scriptFailure else { return XCTFail("\(scriptFailure)") }
    }

    func testSendRefusedWhenObservationNotRunning() async {
        let automation = FakeMessagesAutomation()
        let adapter = makeAdapter(store: FakeMessagesStore(), automation: automation)
        let outcome = await adapter.send("hi", to: MessagingConversationID(provider: .messages, nativeID: "chat-A")!)
        guard case .failed = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(automation.sent.isEmpty)
    }

    /// Regression for the wrong-conversation reply race: a second message
    /// arriving while composing for A must never retarget A's reply.
    func testReplyTargetStaysWithComposerConversationWhenAnotherMessageArrives() async throws {
        let store = FakeMessagesStore()
        store.incoming = [incoming(1, chat: "chat-A", text: "From A"), incoming(2, chat: "chat-B", text: "From B")]
        let automation = FakeMessagesAutomation()
        let adapter = makeAdapter(store: store, automation: automation)
        var preferences = MessagingController.Preferences()
        preferences.readsSystemNotifications = true
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus(), preferences: preferences)
        XCTAssertEqual(adapter.observationState, .running)

        adapter.handle(notification(1, title: "A", body: "From A"))
        for _ in 0..<200 where controller.current == nil { try await Task.sleep(nanoseconds: 5_000_000) }
        let composerEntry = controller.current!
        controller.updateDraft("Reply for A", for: composerEntry)

        adapter.handle(notification(2, title: "B", body: "From B"))
        for _ in 0..<200 where controller.queue.entries.count < 2 { try await Task.sleep(nanoseconds: 5_000_000) }
        XCTAssertEqual(controller.current?.conversation.id?.nativeID, "chat-B", "B is now newest")

        await controller.send(for: composerEntry)
        XCTAssertEqual(automation.sent.map(\.0), ["Reply for A"])
        XCTAssertEqual(automation.sent.map(\.1), ["chat-A"])
    }

    func testObservationTogglesOnlyWhenOptInChanges() {
        let adapter = makeAdapter(store: FakeMessagesStore(), automation: FakeMessagesAutomation())
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        XCTAssertEqual(adapter.observationState, .disabled, "Never enabled at launch")
        controller.preferences.readsSystemNotifications = true
        XCTAssertEqual(adapter.observationState, .running)
        controller.preferences.showPreviewOnCompact = false
        XCTAssertEqual(adapter.observationState, .running)
        controller.preferences.mutedProviders = [.messages]
        XCTAssertEqual(adapter.observationState, .disabled)
    }
}
