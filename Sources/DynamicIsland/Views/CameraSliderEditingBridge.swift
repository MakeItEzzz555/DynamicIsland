import AppKit
import SwiftUI

/// Preserves the existing SwiftUI Slider editing transaction when its native
/// control requires the island-local camera adapter instead of mouse tracking.
struct CameraSliderEditingBridge: NSViewRepresentable {
    var onEditingChanged: (Bool) -> Void
    var onCancel: () -> Void
    func makeNSView(context: Context) -> EditingView { EditingView() }
    func updateNSView(_ view: EditingView, context: Context) {
        view.onEditingChanged = onEditingChanged; view.onCancel = onCancel
    }
    final class EditingView: NSView {
        var onEditingChanged: (Bool) -> Void = { _ in }
        var onCancel: () -> Void = {}
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
    @MainActor
    static func find(in view: NSView, at point: CGPoint) -> EditingView? {
        if let bridge = view as? EditingView, bridge.convert(bridge.bounds, to: nil).contains(point) { return bridge }
        for child in view.subviews { if let match = find(in: child, at: point) { return match } }
        return nil
    }
}
