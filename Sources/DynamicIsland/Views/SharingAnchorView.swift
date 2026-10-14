import AppKit
import SwiftUI

/// Holds the AppKit view the system share picker anchors to.
final class SharingAnchorHolder {
    weak var view: NSView?
}

struct SharingAnchorView: NSViewRepresentable {
    let holder: SharingAnchorHolder

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        holder.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        holder.view = nsView
    }
}
