import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class MessagingDiagnosticsTests: XCTestCase {
    func testPreferencesRoundTripStoresNoMessageData() {
        let suite = "MessagingDiagnosticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let persistence = MessagingPreferencesPersistence(defaults: defaults)
        XCTAssertEqual(persistence.load(), MessagingController.Preferences())

        var preferences = MessagingController.Preferences()
        preferences.enabled = false
        preferences.showPreviewOnCompact = false
        preferences.mutedProviders = [.messages, .custom("Chat")]
        persistence.save(preferences)

        XCTAssertEqual(persistence.load(), preferences)
        let stored = defaults.persistentDomain(forName: suite) ?? [:]
        XCTAssertEqual(Set(stored.keys), [
            MessagingPreferencesPersistence.enabledKey,
            MessagingPreferencesPersistence.showPreviewKey,
            MessagingPreferencesPersistence.mutedProvidersKey
        ])
    }

    func testReportListsAuditedProvidersTruthfully() {
        let messages = MessagesAppAdapter(applicationURL: { URL(fileURLWithPath: "/x") }, openApplication: { _ in true })
        let controller = MessagingController(adapters: [messages], liveActivities: LiveActivityStore(), focus: FakeFocus())
        let report = MessagingDiagnosticsReport.make(controller: controller)

        XCTAssertEqual(report.providers.map(\.provider), [.messages, .whatsapp, .telegram])
        let messagesRow = report.providers[0]
        XCTAssertTrue(messagesRow.hasAdapter)
        XCTAssertFalse(messagesRow.observeIncoming)
        XCTAssertFalse(messagesRow.inlineReply)
        XCTAssertTrue(messagesRow.openAction)
        XCTAssertEqual(messagesRow.fallbackSummary, "Open-App fallback")
        XCTAssertEqual(messagesRow.replySummary, MessagesAppAdapter.replyLimitation)

        for row in report.providers.dropFirst() {
            XCTAssertFalse(row.hasAdapter)
            XCTAssertEqual(row.availability, .notInstalled)
            XCTAssertFalse(row.inlineReply)
            XCTAssertFalse(row.openAction)
        }
    }

    func testCopyTextNeverContainsMessageContent() {
        let adapter = FakeMessagingAdapter(provider: .messages, replyCapable: true)
        let controller = MessagingController(adapters: [adapter], liveActivities: LiveActivityStore(), focus: FakeFocus())
        adapter.deliver(MessagingFixtures.message(conversation: "chat-secret-guid", messageID: "msg-777", title: "Alex Private", body: "Top secret body", at: 10))
        controller.updateDraft("secret draft", for: controller.current!)

        let text = MessagingDiagnosticsReport.make(controller: controller).plainText()

        for forbidden in ["chat-secret-guid", "msg-777", "Alex Private", "Top secret body", "secret draft"] {
            XCTAssertFalse(text.contains(forbidden), "Diagnostics leaked \(forbidden)")
        }
        XCTAssertTrue(text.contains("queued conversations: 1"))
    }
}
