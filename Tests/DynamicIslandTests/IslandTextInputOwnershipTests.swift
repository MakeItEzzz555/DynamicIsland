import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

/// P0-A / P0-B: which responders claim keyboard focus for the non-activating
/// island panel, and that only user-engaged text focus holds the island open.
@MainActor
final class IslandTextInputOwnershipTests: XCTestCase {
    func testOnlyEditableTextAndTheTerminalClaimKeyboardFocus() {
        _ = NSApplication.shared
        let editable = NSTextView(); editable.isEditable = true
        let readOnly = NSTextView(); readOnly.isEditable = false
        XCTAssertTrue(IslandKeyboardFocusPolicy.claimsKeyboard(editable))
        XCTAssertFalse(IslandKeyboardFocusPolicy.claimsKeyboard(readOnly))
        XCTAssertTrue(IslandKeyboardFocusPolicy.claimsKeyboard(InteractiveTerminalView()))
        XCTAssertFalse(IslandKeyboardFocusPolicy.claimsKeyboard(NSHostingView(rootView: Text("button"))),
                       "ordinary SwiftUI clicks must not steal the user's keyboard")
        XCTAssertFalse(IslandKeyboardFocusPolicy.claimsKeyboard(nil))
        XCTAssertFalse(IslandKeyboardFocusPolicy.claimsKeyboard(NSButton()))
    }

    func testAutomaticTerminalFocusDoesNotHoldButUserInputDoes() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -4000, y: -4000, width: 400, height: 240),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let host = TerminalMountView(frame: CGRect(x: 0, y: 0, width: 400, height: 240))
        window.contentView = host
        let terminal = InteractiveTerminalView()
        terminal.onSend = { _ in } // never touches a PTY
        var published: [Bool] = []
        host.onFocusChange = { published.append($0) }
        host.wasVisible = true
        host.mount(terminal)
        func update() {
            NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: window)
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        // Page shown: programmatic first responder only.
        XCTAssertTrue(window.makeFirstResponder(terminal))
        update()
        XCTAssertFalse(published.contains(true), "automatic focus must never veto pointer-exit collapse")
        // User types: engagement publishes text focus (holds while typing).
        terminal.send(source: terminal, data: ArraySlice([UInt8(ascii: "p")]))
        update()
        XCTAssertEqual(published.last, true)
        // Focus leaves: engagement clears and focus is released.
        window.makeFirstResponder(nil)
        update()
        XCTAssertEqual(published.last, false)
        XCTAssertFalse(terminal.userEngaged)
        // Refocus automatically (e.g. Chat -> Terminal again): still no hold.
        window.makeFirstResponder(terminal)
        update()
        XCTAssertEqual(published.last, false)
    }
}
