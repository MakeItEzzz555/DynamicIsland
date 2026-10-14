import CoreGraphics

/// Decides whether the pointer has genuinely left the expanded island.
///
/// The safe region is the rendered expanded shell (`expandedSurfaceFrame`,
/// which already reflects page presentation profiles such as the taller
/// Agents workspace) plus a small tolerance. Everything the Agents
/// workspace draws is clipped inside that shell, so header, transcript,
/// composer, Send and Stop are all covered, including internal gaps.
/// Nothing outside the shell is claimed, so mouse passthrough is unchanged.
struct NativeMenuTrackingLifecycle: Equatable, Sendable {
    private(set) var depth = 0

    var isTracking: Bool { depth > 0 }

    mutating func begin() {
        depth &+= 1
    }

    mutating func end() {
        depth = max(depth - 1, 0)
    }
}

enum ExpandedHoverContainment {
    static let tolerance: CGFloat = 4

    struct Holds: OptionSet, Sendable {
        let rawValue: Int
        /// A native menu (project/session/model pickers) is tracking.
        static let menuTracking = Holds(rawValue: 1 << 0)
        /// An in-island transient surface (session launcher) is open.
        static let transientInteraction = Holds(rawValue: 1 << 1)
        /// The Agents composer owns keyboard focus in the key island panel.
        static let textInput = Holds(rawValue: 1 << 2)
        /// A file drag owns the Tray/orbit interaction even before the first
        /// accessory geometry preference has propagated to the window.
        static let fileDrag = Holds(rawValue: 1 << 3)
        /// An app-owned native popover window (e.g. the Calendar date
        /// picker) is visible; the pointer may legitimately be inside it.
        static let nativePopover = Holds(rawValue: 1 << 4)
        static let tabPointerAnchor = Holds(rawValue: 1 << 5)
    }

    /// App-owned transient native windows (NSPopover-backed SwiftUI
    /// popovers and calendar overlays) other than the island panel itself.
    /// Same signal Droppy uses (`hasActivePopoverWindow`).
    static func isTransientNativeWindow(className: String, isVisible: Bool, isIslandPanel: Bool) -> Bool {
        guard isVisible, !isIslandPanel else { return false }
        return className.contains("Popover") || className.contains("CalendarOverlay")
    }

    enum Decision: Equatable, Sendable {
        case keepExpanded
        case held(Holds)
        case collapse
    }

    static func safeRegion(shellFrame: CGRect, tolerance: CGFloat = tolerance) -> CGRect {
        guard !shellFrame.isEmpty, !shellFrame.isNull, !shellFrame.isInfinite else { return .zero }
        return shellFrame.insetBy(dx: -tolerance, dy: -tolerance)
    }

    /// `accessoryFrames`: visible controls attached to the shell (File Tray
    /// quick actions). Each owns its own padded area; the gap between the
    /// shell and the accessories is bridged so moving between them never
    /// collapses, without claiming space beside them.
    static func decide(
        pointer: CGPoint,
        shellFrame: CGRect,
        accessoryFrames: [CGRect] = [],
        holds: Holds,
        tolerance: CGFloat = tolerance
    ) -> Decision {
        if !holds.isEmpty { return .held(holds) }
        let region = safeRegion(shellFrame: shellFrame, tolerance: tolerance)
        guard !region.isEmpty else { return .keepExpanded }
        if region.contains(pointer) { return .keepExpanded }
        for accessory in accessoryRegions(shellFrame: shellFrame, accessoryFrames: accessoryFrames, tolerance: tolerance)
            where accessory.contains(pointer) {
            return .keepExpanded
        }
        return .collapse
    }

    static func interactiveRegions(frames: [CGRect], tolerance: CGFloat = 0) -> [CGRect] {
        frames.filter { !$0.isEmpty && !$0.isNull && !$0.isInfinite }
            .map { $0.insetBy(dx: -tolerance, dy: -tolerance) }
    }

    /// Connect adjacent rendered rows only where their horizontal extents overlap.
    static func accessoryRegions(
        shellFrame: CGRect,
        accessoryFrames: [CGRect],
        tolerance: CGFloat = tolerance
    ) -> [CGRect] {
        let accessories = interactiveRegions(frames: accessoryFrames)
        guard !accessories.isEmpty, !shellFrame.isEmpty else { return [] }
        var regions = interactiveRegions(frames: accessories, tolerance: tolerance)
        let rows = ([shellFrame] + accessories).sorted { $0.minY > $1.minY }
        for (upper, lower) in zip(rows, rows.dropFirst()) where lower.maxY <= upper.minY {
            let left = max(upper.minX, lower.minX)
            let right = min(upper.maxX, lower.maxX)
            guard right > left else { continue }
            regions.append(CGRect(x: left - tolerance, y: lower.maxY,
                width: right - left + 2 * tolerance, height: upper.minY - lower.maxY))
        }
        return regions
    }
}
