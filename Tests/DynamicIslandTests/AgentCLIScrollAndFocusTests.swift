import AppKit
import XCTest
@testable import DynamicIsland

final class ExpandedScrollIntentTests: XCTestCase {
    func testTinyFirstFramesAreUndecided() {
        XCTAssertNil(ExpandedScrollIntent.isVertical(deltaX: 0.6, deltaY: 0.4, insideContent: true))
        XCTAssertNil(ExpandedScrollIntent.isVertical(deltaX: 0, deltaY: 0, insideContent: false))
    }

    func testDiagonalScrollOverTranscriptStaysVertical() {
        XCTAssertEqual(ExpandedScrollIntent.isVertical(deltaX: 3, deltaY: 2, insideContent: true), true)
        XCTAssertEqual(ExpandedScrollIntent.isVertical(deltaX: -3.5, deltaY: 2, insideContent: true), true)
    }

    func testClearHorizontalOverTranscriptIsIslandGesture() {
        XCTAssertEqual(ExpandedScrollIntent.isVertical(deltaX: 10, deltaY: 2, insideContent: true), false)
    }

    func testOutsideContentUsesSimpleDominance() {
        XCTAssertEqual(ExpandedScrollIntent.isVertical(deltaX: 3, deltaY: 2, insideContent: false), false)
        XCTAssertEqual(ExpandedScrollIntent.isVertical(deltaX: 2, deltaY: 3, insideContent: false), true)
    }

    func testUndecidedFramesInsideContentScrollContentThenVerticalKeepsOwnership() {
        var ownership = ExpandedContentScrollSequenceOwnership()
        XCTAssertEqual(
            ownership.route(phase: .physicalBegan, startsInsideContent: true, verticalIntent: nil),
            .passThroughToContent
        )
        XCTAssertNil(ownership.owner)
        XCTAssertEqual(
            ownership.route(phase: .physicalChanged, startsInsideContent: true, verticalIntent: true),
            .passThroughToContent
        )
        XCTAssertEqual(ownership.owner, .content)
        XCTAssertEqual(
            ownership.route(phase: .momentumChanged, startsInsideContent: false, verticalIntent: false),
            .passThroughToContent,
            "Inertial tail stays with the transcript even if the pointer drifts"
        )
    }

    func testUndecidedFramesOutsideContentRemainIslandGestures() {
        var ownership = ExpandedContentScrollSequenceOwnership()
        XCTAssertEqual(
            ownership.route(phase: .physicalBegan, startsInsideContent: false, verticalIntent: nil),
            .islandGesture
        )
    }
}

final class CameraMirrorScrollRoutingPolicyTests: XCTestCase {
    func testMirrorVerticalAndUndecidedInputPassesThroughToContent() {
        XCTAssertTrue(CameraMirrorScrollRoutingPolicy.shouldPassThroughToContent(
            mirrorActive: true,
            pointerInsideRightWorkspace: true,
            deltaX: 2,
            deltaY: 12
        ))
        XCTAssertTrue(CameraMirrorScrollRoutingPolicy.shouldPassThroughToContent(
            mirrorActive: true,
            pointerInsideRightWorkspace: true,
            deltaX: 0.4,
            deltaY: 0.3
        ))
    }

    func testMirrorStrongHorizontalInputRemainsEligibleForNavigation() {
        XCTAssertFalse(CameraMirrorScrollRoutingPolicy.shouldPassThroughToContent(
            mirrorActive: true,
            pointerInsideRightWorkspace: true,
            deltaX: 20,
            deltaY: 2
        ))
    }

    func testPolicyDoesNotChangeOtherRegionsOrInactiveMirror() {
        XCTAssertFalse(CameraMirrorScrollRoutingPolicy.shouldPassThroughToContent(
            mirrorActive: false,
            pointerInsideRightWorkspace: true,
            deltaX: 1,
            deltaY: 12
        ))
        XCTAssertFalse(CameraMirrorScrollRoutingPolicy.shouldPassThroughToContent(
            mirrorActive: true,
            pointerInsideRightWorkspace: false,
            deltaX: 1,
            deltaY: 12
        ))
    }
}

final class AgentTranscriptFollowStateTests: XCTestCase {
    func testFollowsNewContentWhileAtBottom() {
        var state = AgentTranscriptFollowState()
        state.observeViewport(distanceFromBottom: 0, contentToken: "a")
        XCTAssertTrue(state.contentDidChange(to: "b"))
        XCTAssertTrue(state.isFollowing)
    }

    func testContentGrowthAloneNeverCancelsFollowing() {
        var state = AgentTranscriptFollowState()
        state.observeViewport(distanceFromBottom: 0, contentToken: "a")
        // New output pushes the bottom 300pt down before the auto-scroll lands.
        state.observeViewport(distanceFromBottom: 300, contentToken: "b")
        XCTAssertTrue(state.contentDidChange(to: "b"))
        state.observeViewport(distanceFromBottom: 300, contentToken: "b")
        state.observeViewport(distanceFromBottom: 280, contentToken: "b")
        XCTAssertTrue(state.isFollowing)
        state.observeViewport(distanceFromBottom: 0, contentToken: "b")
        XCTAssertTrue(state.isFollowing)
    }

    func testUserScrollUpStopsFollowingAndNewContentDoesNotYank() {
        var state = AgentTranscriptFollowState()
        state.observeViewport(distanceFromBottom: 0, contentToken: "a")
        state.observeViewport(distanceFromBottom: 240, contentToken: "a")
        XCTAssertFalse(state.isFollowing)

        XCTAssertFalse(state.contentDidChange(to: "b"))
        XCTAssertTrue(state.hasUnseenContent)
        state.observeViewport(distanceFromBottom: 400, contentToken: "b")
        XCTAssertFalse(state.isFollowing)
        XCTAssertFalse(state.contentDidChange(to: "c"))
    }

    func testReturningNearBottomResumesFollowing() {
        var state = AgentTranscriptFollowState()
        state.observeViewport(distanceFromBottom: 0, contentToken: "a")
        state.observeViewport(distanceFromBottom: 240, contentToken: "a")
        _ = state.contentDidChange(to: "b")
        state.observeViewport(distanceFromBottom: 20, contentToken: "b")
        XCTAssertTrue(state.isFollowing)
        XCTAssertFalse(state.hasUnseenContent)
        XCTAssertTrue(state.contentDidChange(to: "c"))
    }

    func testJumpToLatestResumesFollowing() {
        var state = AgentTranscriptFollowState()
        state.observeViewport(distanceFromBottom: 0, contentToken: "a")
        state.observeViewport(distanceFromBottom: 240, contentToken: "a")
        _ = state.contentDidChange(to: "b")
        state.jumpToLatest()
        XCTAssertTrue(state.isFollowing)
        XCTAssertFalse(state.hasUnseenContent)
        state.observeViewport(distanceFromBottom: 240, contentToken: "b")
        XCTAssertTrue(state.isFollowing, "Grace passes while the jump animation lands")
    }
}

final class AgentPromptEditingShortcutTests: XCTestCase {
    func testStandardEditingShortcuts() {
        XCTAssertEqual(AgentPromptEditingShortcut.action(characters: "a", modifiers: .command), #selector(NSResponder.selectAll(_:)))
        XCTAssertEqual(AgentPromptEditingShortcut.action(characters: "c", modifiers: .command), #selector(NSText.copy(_:)))
        XCTAssertEqual(AgentPromptEditingShortcut.action(characters: "v", modifiers: .command), #selector(NSText.paste(_:)))
        XCTAssertEqual(AgentPromptEditingShortcut.action(characters: "x", modifiers: .command), #selector(NSText.cut(_:)))
        XCTAssertEqual(AgentPromptEditingShortcut.action(characters: "z", modifiers: .command), Selector(("undo:")))
        XCTAssertEqual(AgentPromptEditingShortcut.action(characters: "Z", modifiers: [.command, .shift]), Selector(("redo:")))
    }

    func testNonEditingCombinationsPassThrough() {
        XCTAssertNil(AgentPromptEditingShortcut.action(characters: "c", modifiers: []))
        XCTAssertNil(AgentPromptEditingShortcut.action(characters: "c", modifiers: [.command, .option]))
        XCTAssertNil(AgentPromptEditingShortcut.action(characters: "\r", modifiers: .command))
        XCTAssertNil(AgentPromptEditingShortcut.action(characters: ".", modifiers: .command))
    }

    func testReturnAndCommandReturnSubmitWhileShiftReturnInsertsNewline() {
        XCTAssertTrue(AgentPromptDraftPolicy.submitsReturn(with: []))
        XCTAssertTrue(AgentPromptDraftPolicy.submitsReturn(with: .command))
        XCTAssertFalse(AgentPromptDraftPolicy.submitsReturn(with: .shift))
        XCTAssertFalse(AgentPromptDraftPolicy.submitsReturn(with: [.command, .shift]))
    }
}

@MainActor
final class EditMenuInstallerTests: XCTestCase {
    func testEditMenuHasStandardActionsAndNoQuit() {
        let menu = EditMenuInstaller.makeEditMenu()
        let actions = menu.items.compactMap(\.action)
        XCTAssertTrue(actions.contains(#selector(NSText.copy(_:))))
        XCTAssertTrue(actions.contains(#selector(NSText.paste(_:))))
        XCTAssertTrue(actions.contains(#selector(NSResponder.selectAll(_:))))
        XCTAssertFalse(actions.contains(#selector(NSApplication.terminate(_:))))
    }

    func testInstallIsIdempotent() {
        let app = NSApplication.shared
        let previous = app.mainMenu
        defer { app.mainMenu = previous }
        app.mainMenu = nil

        EditMenuInstaller.installIfNeeded(on: app)
        EditMenuInstaller.installIfNeeded(on: app)

        let editMenus = app.mainMenu?.items.filter { $0.submenu?.title == EditMenuInstaller.editMenuTitle } ?? []
        XCTAssertEqual(editMenus.count, 1)
    }
}
