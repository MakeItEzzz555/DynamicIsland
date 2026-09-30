import AppKit
import SwiftUI

/// The single motion contract for expanded tab-to-tab shell morphs.
///
/// The NSPanel frame is the physical authority: its origin and size are
/// interpolated on one curve, and both endpoints share the notch-top edge
/// and horizontal center, so `maxY` and `midX` are invariant on every frame
/// (height grows or shrinks downward, width grows around the center). The
/// SwiftUI canvas animates with the identical curve and duration, and the
/// root is pinned to the top of the hosting view so any residual mismatch
/// can only touch the bottom edge, never the top. The shell is never scaled.
///
/// Behavioral reference: Droppy NotchWindowController resizes from the
/// screen top (`newFrame.origin.y = screen.frame.maxY - newHeight`) and keeps
/// AppKit frame management separate from SwiftUI content motion.
enum ExpandedShellMorph {
    /// CA ease-in-ease-out control points (kCAMediaTimingFunctionEaseInEaseOut).
    static let controlPoints = (c0x: 0.42, c0y: 0.0, c1x: 0.58, c1y: 1.0)

    static var panelTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeInEaseOut)
    }

    static func canvasAnimation(duration: TimeInterval) -> Animation {
        .timingCurve(controlPoints.c0x, controlPoints.c0y, controlPoints.c1x, controlPoints.c1y, duration: duration)
    }

    /// Frame at `progress` as AppKit interpolates it: origin and size
    /// component-wise on the same eased progress.
    static func interpolatedFrame(from source: CGRect, to target: CGRect, progress: CGFloat) -> CGRect {
        func lerp(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * progress }
        return CGRect(
            x: lerp(source.minX, target.minX),
            y: lerp(source.minY, target.minY),
            width: lerp(source.width, target.width),
            height: lerp(source.height, target.height)
        )
    }

}

/// Top-pins (and horizontally centers) the island root inside its hosting
/// view, instead of NSHostingView's default centering.
struct TopPinnedHostRoot<Content: View>: View {
    let content: Content

    var body: some View {
        // A fixed frame equal to the hosting bounds: a larger canvas
        // overflows downward (and equally left/right), never upward.
        GeometryReader { proxy in
            content.frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}
