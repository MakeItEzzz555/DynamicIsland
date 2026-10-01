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

    /// Padded accessory frames plus a bridge spanning their horizontal
    /// extent up to the shell's bottom edge.
    static func accessoryRegions(
        shellFrame: CGRect,
        accessoryFrames: [CGRect],
        tolerance: CGFloat = tolerance
    ) -> [CGRect] {
        let accessories = accessoryFrames.filter { !$0.isEmpty }
        guard !accessories.isEmpty, !shellFrame.isEmpty else { return [] }
        var regions = accessories.map { $0.insetBy(dx: -tolerance, dy: -tolerance) }
        let union = accessories.dropFirst().reduce(accessories[0]) { $0.union($1) }
        if union.maxY <= shellFrame.minY {
            regions.append(CGRect(
                x: union.minX - tolerance,
                y: union.maxY,
                width: union.width + tolerance * 2,
                height: shellFrame.minY - union.maxY + tolerance
            ))
        }
        return regions
    }
}
