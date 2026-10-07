import Foundation
import XCTest
@testable import DynamicIsland

@MainActor
final class MessagingPageTests: XCTestCase {
    func testInteractionModeIsDerivedFromCapabilities() {
        let openApp = MessagingProviderCapabilities(supported: [.openApp], limitations: [:])
        let openConversation = MessagingProviderCapabilities(supported: [.openConversation], limitations: [:])
        XCTAssertEqual(MessagingInteractionMode.resolve(canReply: true, capabilities: openApp), .reply)
        XCTAssertEqual(MessagingInteractionMode.resolve(canReply: false, capabilities: openApp), .openAppOnly)
        XCTAssertEqual(MessagingInteractionMode.resolve(canReply: false, capabilities: openConversation), .openAppOnly)
        XCTAssertEqual(MessagingInteractionMode.resolve(canReply: false, capabilities: .none), .readOnly)
    }

    func testDraftStatusPresentation() {
        XCTAssertEqual(MessagingDraftStatusPresentation(.idle), .none)
        XCTAssertEqual(MessagingDraftStatusPresentation(.drafting), .none)
        XCTAssertEqual(MessagingDraftStatusPresentation(.sending), .sending)
        XCTAssertEqual(MessagingDraftStatusPresentation(.sent), .sent)
        XCTAssertEqual(MessagingDraftStatusPresentation(.failed(reason: "x", retryable: true)), .failed("x", retryable: true))
        XCTAssertEqual(MessagingDraftStatusPresentation(.uncertain(reason: "y")), .uncertain("y"))
    }

    func testMessagesPageExistsOnlyWhileMessagesAreQueued() {
        let settings = AppSettings(defaults: UserDefaults(suiteName: "MessagingPageTests-\(UUID().uuidString)")!)
        let navigation = IslandNavigationStore()
        XCTAssertFalse(navigation.availablePages(using: settings).contains(.messages))
        navigation.showMessages()
        XCTAssertNotEqual(navigation.selectedPage, .messages, "Cannot navigate to an empty Messages page")

        navigation.hasActionableMessages = true
        XCTAssertTrue(navigation.availablePages(using: settings).contains(.messages))
        navigation.showMessages()
        XCTAssertEqual(navigation.selectedPage, .messages)

        navigation.hasActionableMessages = false
        navigation.ensureValidSelection(using: settings)
        XCTAssertNotEqual(navigation.selectedPage, .messages)
    }

    func testMessagesPageUsesStandardShellProfile() {
        XCTAssertEqual(ExpandedPresentationProfile.resolve(for: .messages), .standard)
    }
}
