import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class MessagesAppAdapterTests: XCTestCase {
    func testInstalledMessagesIsOpenAppOnlyWithExplainedLimitations() {
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/System/Applications/Messages.app") }, openApplication: { _ in true })
        XCTAssertEqual(adapter.availability, .available)
        XCTAssertEqual(adapter.capabilities.supported, [.openApp])
        XCTAssertFalse(adapter.capabilities.supportsInlineReply)
        for capability in [MessagingCapability.observeIncoming, .sendReply, .confirmSend, .exactConversationTarget, .openConversation] {
            XCTAssertNotNil(adapter.capabilities.limitations[capability], "\(capability) must explain why it is unsupported")
        }
    }

    func testReplyIsNeverOfferedEvenForAConversationWithANativeID() {
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/x") }, openApplication: { _ in true })
        let conversation = MessagingConversation(
            id: MessagingConversationID(provider: .messages, nativeID: "chat-guid"),
            provider: .messages, displayTitle: "Alex", participantHandles: [], isGroup: false
        )
        XCTAssertFalse(adapter.capabilities.canReply(to: conversation))
    }

    func testOpenActivatesMessagesAndFailsWhenMissing() {
        var opened: [URL] = []
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/System/Applications/Messages.app") }, openApplication: { opened.append($0); return true })
        XCTAssertTrue(adapter.open(nil))
        XCTAssertEqual(opened.map(\.lastPathComponent), ["Messages.app"])

        let missing = MessagesAppAdapter(applicationURL: { nil }, openApplication: { _ in XCTFail("must not open"); return true })
        XCTAssertEqual(missing.availability, .notInstalled)
        XCTAssertFalse(missing.open(nil))
        XCTAssertTrue(missing.capabilities.supported.isEmpty)
    }

    func testRefreshTracksInstallation() {
        var installed = false
        let adapter = MessagesAppAdapter(applicationURL: { installed ? URL(fileURLWithPath: "/x") : nil }, openApplication: { _ in true })
        XCTAssertEqual(adapter.availability, .notInstalled)
        installed = true
        adapter.refresh()
        XCTAssertEqual(adapter.availability, .available)
    }

    func testControllerNeverSendsThroughMessagesAdapter() async {
        let adapter = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/x") }, openApplication: { _ in true })
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        controller.receive(MessagingFixtures.message(conversation: "chat-guid", at: 10))
        let entry = controller.current!
        XCTAssertFalse(controller.canReply(to: entry))
        controller.updateDraft("hello", for: entry)
        await controller.send(for: entry)
        XCTAssertEqual(controller.draft(for: entry).state, .idle)
        XCTAssertEqual(MessagingInteractionMode.resolve(canReply: false, capabilities: adapter.capabilities), .openAppOnly)
    }
}
