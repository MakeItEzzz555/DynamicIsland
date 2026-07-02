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
    public let canvas: IslandCanvasGeometry
    public let hasHardwareNotch: Bool
}

public struct IslandCanvasGeometry: Equatable {
    public let frame: CGRect
    public let collapsedSurfaceFrame: CGRect
    public let expandedSurfaceFrame: CGRect
}

public final class NotchGeometryService {
    public init() {}

    @MainActor
    public func geometry(
        for screen: NSScreen? = nil,
        collapsedSize: CGSize,
        expandedSize: CGSize
    ) -> IslandGeometry {
        let screen = screen ?? Self.preferredScreen()
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
        let expandedCenterX = snapshot.frame.midX
        let resolvedExpandedWidth = min(760, max(620, snapshot.frame.width - 520))
        let resolvedExpandedHeight: CGFloat = 260

        let collapsedFrame: CGRect
        if let notchRect {
            let resolvedCollapsedWidth = min(max((notchRect.width + 50) * 1.05, 226), 254)
            let resolvedCollapsedHeight = min(max(notchRect.height + 5, 33), 40)
            collapsedFrame = CGRect(
                x: notchRect.midX - resolvedCollapsedWidth / 2,
                y: topY - resolvedCollapsedHeight,
                width: resolvedCollapsedWidth,
                height: resolvedCollapsedHeight
            )
        } else {
            collapsedFrame = CGRect(
                x: snapshot.frame.midX - collapsedSize.width / 2,
                y: topY - collapsedSize.height - 8,
                width: collapsedSize.width,
                height: collapsedSize.height
            )
        }

        let expandedFrame = CGRect(
            x: expandedCenterX - resolvedExpandedWidth / 2,
            y: topY - resolvedExpandedHeight - (notchRect == nil ? 10 : 0),
            width: resolvedExpandedWidth,
            height: resolvedExpandedHeight
        )

        let integralCollapsedFrame = collapsedFrame.integral
        let integralExpandedFrame = expandedFrame.integral
        let canvas = Self.canvasGeometry(
            topY: topY,
            collapsedFrame: integralCollapsedFrame,
            expandedFrame: integralExpandedFrame
        )

        return IslandGeometry(
            screenFrame: snapshot.frame,
            notchRect: notchRect,
            collapsedFrame: integralCollapsedFrame,
            expandedFrame: integralExpandedFrame,
            canvas: canvas,
            hasHardwareNotch: notchRect != nil
        )
    }

    private static func canvasGeometry(
        topY: CGFloat,
        collapsedFrame: CGRect,
        expandedFrame: CGRect
    ) -> IslandCanvasGeometry {
        let surfaceBounds = collapsedFrame.union(expandedFrame).integral
        let canvasFrame = CGRect(
            x: surfaceBounds.minX,
            y: surfaceBounds.minY,
            width: surfaceBounds.width,
            height: topY - surfaceBounds.minY
        ).integral
        return IslandCanvasGeometry(
            frame: canvasFrame,
            collapsedSurfaceFrame: collapsedFrame.offsetBy(dx: -canvasFrame.minX, dy: -canvasFrame.minY).integral,
            expandedSurfaceFrame: expandedFrame.offsetBy(dx: -canvasFrame.minX, dy: -canvasFrame.minY).integral
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
    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            screen.safeAreaInsets.top > 0
        } ?? NSScreen.main ?? NSScreen.screens.first
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
