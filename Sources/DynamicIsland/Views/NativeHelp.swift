import AppKit
import SwiftUI

extension View {
    /// Unlike SwiftUI's dynamic TooltipResponder, AppKit retains this literal
    /// string without consulting an AttributeGraph node after tab removal.
    func nativeHelp(_ text: String) -> some View {
        background(NativeHelpAnchor(text: text).allowsHitTesting(false).accessibilityHidden(true))
    }
}

struct NativeHelpAnchor: NSViewRepresentable {
    let text: String
    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) { view.toolTip = text }
    static func dismantleNSView(_ view: Anchor, coordinator: ()) {
        view.toolTip = nil
        view.removeAllToolTips()
    }
    final class Anchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { toolTip = nil; removeAllToolTips() }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}
