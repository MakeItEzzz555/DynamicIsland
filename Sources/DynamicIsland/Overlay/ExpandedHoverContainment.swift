import CoreGraphics

/// Decides whether the pointer has genuinely left the expanded island.
///
/// The safe region is the rendered expanded shell (`expandedSurfaceFrame`,
/// which already reflects page presentation profiles such as the taller
/// Agents workspace) plus a small tolerance. Everything the Agents
/// workspace draws is clipped inside that shell, so header, transcript,
/// composer, Send and Stop are all covered, including internal gaps.
/// Nothing outside the shell is claimed, so mouse passthrough is unchanged.
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

    static func decide(
        pointer: CGPoint,
        shellFrame: CGRect,
        holds: Holds,
        tolerance: CGFloat = tolerance
    ) -> Decision {
        if !holds.isEmpty { return .held(holds) }
        let region = safeRegion(shellFrame: shellFrame, tolerance: tolerance)
        guard !region.isEmpty else { return .keepExpanded }
        return region.contains(pointer) ? .keepExpanded : .collapse
    }
}
