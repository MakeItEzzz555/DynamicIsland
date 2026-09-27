import AppKit
import XCTest
@testable import DynamicIsland

final class AgentConsoleTests: XCTestCase {
    func testObservedAndInteractiveModesExposeOnlySupportedControls() {
        XCTAssertFalse(AgentConsoleMode.observed.showsComposer)
        XCTAssertFalse(AgentConsoleMode.observed.canInterrupt)
        XCTAssertTrue(AgentConsoleMode.interactive(canInterrupt: false).showsComposer)
        XCTAssertFalse(AgentConsoleMode.interactive(canInterrupt: false).canInterrupt)
        XCTAssertTrue(AgentConsoleMode.interactive(canInterrupt: true).canInterrupt)
    }

    func testSubmissionRejectsEmptyAndBoundsPromptLength() {
        XCTAssertNil(AgentPromptDraftPolicy.submission(from: " \n\t "))
        XCTAssertEqual(AgentPromptDraftPolicy.submission(from: "  hello\n"), "hello")

        let oversized = String(repeating: "a", count: AgentPromptDraftPolicy.maximumLength + 12)
        XCTAssertEqual(
            AgentPromptDraftPolicy.submission(from: oversized)?.count,
            AgentPromptDraftPolicy.maximumLength
        )
    }

    func testCommandReturnSubmitsWhileShiftReturnRemainsNativeNewline() {
        XCTAssertTrue(AgentPromptDraftPolicy.submitsReturn(with: [.command]))
        XCTAssertTrue(AgentPromptDraftPolicy.submitsReturn(with: [.command, .shift]))
        XCTAssertFalse(AgentPromptDraftPolicy.submitsReturn(with: [.shift]))
        XCTAssertFalse(AgentPromptDraftPolicy.submitsReturn(with: []))
    }
}
