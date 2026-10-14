import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class IslandKeyboardAcquisitionTests: XCTestCase {
    func testComposerClaimsKeyBeforeImmediateTypingAndEscapeReleases() throws {
        let (panel, editor, other, otherEditor) = try fixture()
        defer { panel.close(); other.close() }
        let router = CameraInteractionRouter(window: panel, monitorsPhysicalInput: false)
        defer { router.shutdown() }
        CameraNativeHostedFixture.click(router, at: CGPoint(x: 40, y: 35))
        XCTAssertTrue(panel.isKeyWindow)
        XCTAssertTrue(panel.firstResponder === editor)
        NSApp.sendEvent(key(0, characters: "a", window: panel))
        XCTAssertEqual(editor.string, "a")
        XCTAssertEqual(otherEditor.string, "")
        NSApp.sendEvent(key(53, characters: "\u{1b}", window: panel))
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertFalse(panel.firstResponder === editor)
    }

    func testReturnShiftReturnDeleteAndRepeatedReopenUseExactEditor() throws {
        let (panel, editor, other, _) = try fixture()
        defer { panel.close(); other.close() }
        var submits = 0
        editor.submitHandler = { submits += 1; return true }
        let router = CameraInteractionRouter(window: panel, monitorsPhysicalInput: false)
        defer { router.shutdown() }
        for _ in 0..<3 {
            NSApp.activate(ignoringOtherApps: true)
            other.makeKeyAndOrderFront(nil)
            CameraNativeHostedFixture.pump()
            CameraNativeHostedFixture.click(router, at: CGPoint(x: 40, y: 35))
            XCTAssertTrue(panel.isKeyWindow)
            XCTAssertTrue(panel.firstResponder === editor)
            NSApp.sendEvent(key(36, characters: "\r", window: panel))
            NSApp.sendEvent(key(36, characters: "\r", flags: .shift, window: panel))
            XCTAssertTrue(editor.string.contains("\n"))
            NSApp.sendEvent(key(51, characters: "\u{7f}", window: panel))
            XCTAssertTrue(editor.string.isEmpty)
            editor.releaseKeyboardOwnership()
            panel.orderOut(nil)
            panel.orderFront(nil)
            CameraNativeHostedFixture.pump()
        }
        XCTAssertEqual(submits, 3)
    }

    func testOrdinaryButtonDoesNotStealKeyFromOtherWindow() throws {
        let (panel, _, other, _) = try fixture()
        defer { panel.close(); other.close() }
        panel.contentView = NSButton(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        other.makeKeyAndOrderFront(nil)
        let router = CameraInteractionRouter(window: panel, monitorsPhysicalInput: false)
        defer { router.shutdown() }
        CameraNativeHostedFixture.click(router, at: CGPoint(x: 40, y: 35))
        XCTAssertTrue(other.isKeyWindow)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testEnabledComposerOptsIntoNativePanelContractOnly() {
        let editor = AgentPromptTextView()
        editor.isEditable = true
        XCTAssertTrue(editor.needsPanelToBecomeKey)
        XCTAssertTrue(editor.acceptsFirstResponder)
        editor.isEditable = false
        XCTAssertFalse(editor.needsPanelToBecomeKey)
        XCTAssertFalse(editor.acceptsFirstResponder)
    }

    func testMainEligibilityFollowsExplicitEditableResponderWithoutPassiveActivation() throws {
        let (panel, editor, other, _) = try fixture()
        defer { panel.close(); other.close() }
        XCTAssertFalse(panel.isMainWindow)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(panel.makeFirstResponder(editor))
        XCTAssertTrue(panel.canBecomeMain)
        XCTAssertFalse(panel.isMainWindow)
        XCTAssertTrue(other.isKeyWindow, "automatic responder selection does not acquire typing")
        XCTAssertTrue(IslandKeyboardFocusPolicy.acquireKeyboard(for: editor, in: panel))
        XCTAssertTrue(panel.isKeyWindow)
        XCTAssertTrue(panel.isMainWindow)
        editor.releaseKeyboardOwnership()
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.isKeyWindow)
    }

    func testProductionComposerHierarchyReceivesImmediateTypingEditingPasteAndIME() throws {
        let (panel, _, other, otherEditor) = try fixture()
        defer { panel.close(); other.close() }
        var draft = "", submissions = 0
        let host = NSHostingView(rootView: AgentPromptEditor(text: Binding(get: { draft }, set: { draft = $0 }),
            placeholder: "Fixture", isEnabled: true, onSubmit: { submissions += 1; return true }))
        panel.contentView = host
        CameraNativeHostedFixture.pump()
        let editor = try XCTUnwrap(descendants(host).compactMap { $0 as? AgentPromptTextView }.first)
        let router = CameraInteractionRouter(window: panel, monitorsPhysicalInput: false)
        defer { router.shutdown() }
        CameraNativeHostedFixture.click(router, at: CGPoint(x: 40, y: 35))
        XCTAssertTrue(panel.isKeyWindow)
        XCTAssertTrue(panel.firstResponder === editor)
        NSApp.sendEvent(key(0, characters: "a", window: panel))
        XCTAssertEqual(editor.string, "a")
        XCTAssertEqual(draft, "a")
        XCTAssertEqual(otherEditor.string, "")
        NSApp.sendEvent(key(36, characters: "\r", window: panel))
        XCTAssertEqual(submissions, 1)
        NSApp.sendEvent(key(36, characters: "\r", flags: .shift, window: panel))
        XCTAssertTrue(editor.string.contains("\n"))
        NSApp.sendEvent(key(51, characters: "\u{7f}", window: panel))
        let board = NSPasteboard(name: .init("DynamicIsland.KeyboardFixture.\(UUID().uuidString)"))
        defer { board.clearContents() }
        board.setString("paste", forType: .string)
        XCTAssertTrue(editor.readSelection(from: board))
        XCTAssertTrue(editor.string.contains("paste"))
        editor.setMarkedText("composition", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        NSApp.sendEvent(key(36, characters: "\r", window: panel))
        XCTAssertEqual(submissions, 1, "Return during IME composition does not submit")
        editor.unmarkText()
        XCTAssertTrue(panel.firstResponder === editor)
    }

    func testStreamingAllowsEditingWithoutSubmissionAuthority() {
        for state: AgentManagedInteractionState in [.submitting, .working(canInterrupt: true), .stopping] {
            XCTAssertTrue(state.allowsDraftEditing)
            XCTAssertFalse(state.allowsPromptSubmission)
        }
        XCTAssertTrue(AgentManagedInteractionState.ready.allowsPromptSubmission)
        XCTAssertFalse(AgentManagedInteractionState.observed.allowsDraftEditing)
    }

    func testHarmlessSwiftUIUpdateRetainsResponderSelectionAndMarkedText() throws {
        let (panel, _, other, _) = try fixture()
        defer { panel.close(); other.close() }
        var text = "draft"
        let host = NSHostingView(rootView: AgentPromptEditor(text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "Prompt", isEnabled: true, onSubmit: { true }))
        panel.contentView = host
        CameraNativeHostedFixture.pump()
        let editor = descendants(host).compactMap { $0 as? AgentPromptTextView }.first!
        panel.makeKey()
        XCTAssertTrue(panel.makeFirstResponder(editor))
        editor.setSelectedRange(NSRange(location: 2, length: 0))
        host.rootView = AgentPromptEditor(text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "Streaming", isEnabled: true, onSubmit: { false })
        CameraNativeHostedFixture.pump()
        XCTAssertTrue(panel.firstResponder === editor)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 2, length: 0))
        editor.setMarkedText("composition", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        host.rootView = AgentPromptEditor(text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "Updated", isEnabled: true, onSubmit: { false })
        CameraNativeHostedFixture.pump()
        XCTAssertTrue(editor.hasMarkedText())
    }

    func testResignKeyReleasesEngagementWithoutDestroyingDraft() async throws {
        let (panel, editor, other, _) = try fixture()
        defer { panel.close(); other.close() }
        let released = expectation(description: "resigned key releases hold")
        let acquired = expectation(description: "click engages exact composer")
        var focused = false
        editor.focusHandler = { if $0 { focused = true; acquired.fulfill() } else if focused { released.fulfill() } }
        let router = CameraInteractionRouter(window: panel, monitorsPhysicalInput: false)
        defer { router.shutdown() }
        CameraNativeHostedFixture.click(router, at: CGPoint(x: 40, y: 35))
        await fulfillment(of: [acquired], timeout: 1)
        editor.insertText("synthetic", replacementRange: NSRange(location: NSNotFound, length: 0))
        other.makeKeyAndOrderFront(nil)
        CameraNativeHostedFixture.pump()
        XCTAssertFalse(panel.isKeyWindow)
        await fulfillment(of: [released], timeout: 1)
        XCTAssertEqual(editor.string, "synthetic")
    }

    func testOldEditorBlurCannotReleaseNewEditorOrNativeInputOwner() {
        let layout = IslandLayoutStore()
        let old = UUID(), new = UUID()
        layout.setTextInputFocused(true, owner: old)
        layout.setTextInputFocused(true, owner: new)
        layout.setTextInputFocused(false, owner: old)
        XCTAssertTrue(layout.isTextInputFocused)
        layout.setTextInputFocused(true)
        layout.setTextInputFocused(false, owner: new)
        XCTAssertTrue(layout.isTextInputFocused)
        layout.setTextInputFocused(false)
        XCTAssertFalse(layout.isTextInputFocused)
    }

    func testOverlayEscapePolicyReleasesExactEditorAndPreservesIMEAndPresentations() {
        _ = NSApplication.shared
        let panel = IslandOverlayPanel(contentRect: CGRect(x: -4000, y: -4000, width: 220, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let editor = AgentPromptTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        panel.contentView = editor
        XCTAssertTrue(panel.makeFirstResponder(editor))
        XCTAssertFalse(IslandKeyboardFocusPolicy.releaseComposerForEscape(editor, hasPresentation: true))
        XCTAssertTrue(panel.firstResponder === editor)
        editor.setMarkedText("synthetic", selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(IslandKeyboardFocusPolicy.releaseComposerForEscape(editor, hasPresentation: false))
        XCTAssertTrue(editor.hasMarkedText())
        XCTAssertTrue(panel.firstResponder === editor)
        editor.unmarkText()
        XCTAssertTrue(IslandKeyboardFocusPolicy.releaseComposerForEscape(editor, hasPresentation: false))
        XCTAssertFalse(panel.firstResponder === editor)
        XCTAssertFalse(IslandKeyboardFocusPolicy.releaseComposerForEscape(NSButton(), hasPresentation: false))
    }

    private func fixture() throws -> (IslandOverlayPanel, AgentPromptTextView, NSWindow, NSTextView) {
        try XCTSkipIf(CGDisplayIsActive(CGMainDisplayID()) == 0 || CGDisplayIsAsleep(CGMainDisplayID()) != 0,
            "Native keyboard acquisition requires an awake display; no key-delivery acceptance is claimed.")
        _ = NSApplication.shared
        let previousPolicy = NSApp.activationPolicy()
        addTeardownBlock { await MainActor.run { _ = NSApp.setActivationPolicy(previousPolicy) } }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        CameraNativeHostedFixture.pump()
        let screen = try XCTUnwrap(NSScreen.main)
        let origin = CGPoint(x: screen.visibleFrame.minX + 40, y: screen.visibleFrame.midY - 50)
        let other = NSWindow(contentRect: CGRect(x: origin.x, y: origin.y, width: 220, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        let otherEditor = NSTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        other.contentView = otherEditor
        other.makeKeyAndOrderFront(nil)
        other.makeFirstResponder(otherEditor)
        CameraNativeHostedFixture.pump()
        let panel = IslandOverlayPanel(contentRect: CGRect(x: origin.x + 260, y: origin.y, width: 220, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        let editor = AgentPromptTextView(frame: CGRect(x: 0, y: 0, width: 220, height: 100))
        editor.isRichText = false
        panel.contentView = editor
        panel.orderFront(nil)
        CameraNativeHostedFixture.pump()
        XCTAssertTrue(panel.isVisible)
        XCTAssertTrue(other.isKeyWindow, "showing a passive panel never steals the existing editor")
        return (panel, editor, other, otherEditor)
    }

    private func key(_ code: UInt16, characters: String, flags: NSEvent.ModifierFlags = [], window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
}
