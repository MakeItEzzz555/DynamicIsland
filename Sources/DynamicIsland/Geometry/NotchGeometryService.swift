import AppKit

public struct ScreenSnapshot: Equatable {
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let safeAreaInsets: NSEdgeInsets
    public let auxiliaryTopLeftArea: CGRect?
    public let auxiliaryTopRightArea: CGRect?

    public init(
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) {
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
    }

    public static func == (lhs: ScreenSnapshot, rhs: ScreenSnapshot) -> Bool {
        lhs.frame == rhs.frame &&
            lhs.visibleFrame == rhs.visibleFrame &&
            lhs.safeAreaInsets.top == rhs.safeAreaInsets.top &&
            lhs.safeAreaInsets.left == rhs.safeAreaInsets.left &&
            lhs.safeAreaInsets.bottom == rhs.safeAreaInsets.bottom &&
            lhs.safeAreaInsets.right == rhs.safeAreaInsets.right &&
            lhs.auxiliaryTopLeftArea == rhs.auxiliaryTopLeftArea &&
            lhs.auxiliaryTopRightArea == rhs.auxiliaryTopRightArea
    }
}

public struct IslandGeometry: Equatable {
    public let screenFrame: CGRect
    public let notchRect: CGRect?
    public let collapsedFrame: CGRect
    public let expandedFrame: CGRect
    public let hasHardwareNotch: Bool
}

public final class NotchGeometryService {
    public init() {}

    @MainActor
    public func geometry(
        for screen: NSScreen? = NSScreen.main,
        collapsedSize: CGSize,
        expandedSize: CGSize
    ) -> IslandGeometry {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first
        let snapshot = screen.map(Self.snapshot) ?? ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaInsets: NSEdgeInsetsZero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        return geometry(for: snapshot, collapsedSize: collapsedSize, expandedSize: expandedSize)
    }

    public func geometry(
        for snapshot: ScreenSnapshot,
        collapsedSize: CGSize,
        expandedSize: CGSize
    ) -> IslandGeometry {
        let notchRect = inferNotchRect(from: snapshot)
        let topY = snapshot.frame.maxY
        let collapsedCenterX = notchRect?.midX ?? snapshot.frame.midX
        let expandedCenterX = snapshot.frame.midX
        let collapsedY = topY - collapsedSize.height - (notchRect == nil ? 8 : 0)
        let expandedY = topY - expandedSize.height - (notchRect == nil ? 10 : 0)
        let resolvedExpandedWidth = min(expandedSize.width, max(360, snapshot.frame.width - 64))

        let collapsedFrame = CGRect(
            x: collapsedCenterX - collapsedSize.width / 2,
            y: collapsedY,
            width: collapsedSize.width,
            height: collapsedSize.height
        )

        let expandedFrame = CGRect(
            x: expandedCenterX - resolvedExpandedWidth / 2,
            y: expandedY,
            width: resolvedExpandedWidth,
            height: expandedSize.height
        )

        return IslandGeometry(
            screenFrame: snapshot.frame,
            notchRect: notchRect,
            collapsedFrame: collapsedFrame.integral,
            expandedFrame: expandedFrame.integral,
            hasHardwareNotch: notchRect != nil
        )
    }

    private func inferNotchRect(from snapshot: ScreenSnapshot) -> CGRect? {
        guard snapshot.safeAreaInsets.top > 0 else {
            return nil
        }

        if let left = snapshot.auxiliaryTopLeftArea,
           let right = snapshot.auxiliaryTopRightArea,
           left.maxX < right.minX {
            return CGRect(
                x: left.maxX,
                y: min(left.minY, right.minY),
                width: right.minX - left.maxX,
                height: max(left.height, right.height, snapshot.safeAreaInsets.top)
            ).integral
        }

        let fallbackWidth = min(max(snapshot.frame.width * 0.14, 180), 260)
        return CGRect(
            x: snapshot.frame.midX - fallbackWidth / 2,
            y: snapshot.frame.maxY - snapshot.safeAreaInsets.top,
            width: fallbackWidth,
            height: snapshot.safeAreaInsets.top
        ).integral
    }

    @MainActor
    private static func snapshot(from screen: NSScreen) -> ScreenSnapshot {
        ScreenSnapshot(
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }
}
