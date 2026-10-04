import AppKit
import SwiftUI
import XCTest
@testable import DynamicIsland

@MainActor
final class NativeHelpTests: XCTestCase {
    func testDetachedTooltipDiscardsStoredTextAndNeverInterceptsMouse() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        for _ in 0..<100 {
            let anchor = NativeHelpAnchor.Anchor(frame: NSRect(x: 0, y: 0, width: 30, height: 26))
            anchor.toolTip = "File Shelf"
            window.contentView!.addSubview(anchor)
            XCTAssertNil(anchor.hitTest(.zero))
            anchor.removeFromSuperview()
            XCTAssertNil(anchor.toolTip)
        }
    }
}
