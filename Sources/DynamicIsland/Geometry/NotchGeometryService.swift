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
    public let hardwareNotchWidth: CGFloat
    public let collapsedLeftRegionWidth: CGFloat
    public let collapsedNotchCoreWidth: CGFloat
    public let collapsedRightRegionWidth: CGFloat
}

public struct CollapsedActivityLayoutProfile: Equatable, Sendable {
    public static let leadingContentPadding: CGFloat = 5
    public static let mediaLeftContentWidth: CGFloat = 14
    public static let mediaRightContentWidth: CGFloat = 27
    public static let timerLeftContentWidth: CGFloat = 13
    public static let timerRightContentWidth: CGFloat = 38
    public static let batteryLeftContentWidth: CGFloat = 17
    public static let batteryRightContentWidth: CGFloat = 34
    public static let fileLeftContentWidth: CGFloat = 17
    public static let fileRightContentWidth: CGFloat = 44

    public let leftContentWidth: CGFloat
    public let rightContentWidth: CGFloat

    public init(leftContentWidth: CGFloat, rightContentWidth: CGFloat) {
        self.leftContentWidth = leftContentWidth
        self.rightContentWidth = rightContentWidth
    }

    var symmetricWingContentWidth: CGFloat {
        let paddedLeftContentWidth = leftContentWidth > 0
            ? leftContentWidth + Self.leadingContentPadding
            : 0
        return max(max(paddedLeftContentWidth, rightContentWidth), 0)
    }

    public static func media(showsArtwork: Bool, showsVisualizer: Bool) -> Self {
        Self(
            leftContentWidth: showsArtwork ? mediaLeftContentWidth : 0,
            rightContentWidth: showsVisualizer ? mediaRightContentWidth : 0
        )
    }

    static let timer = Self(leftContentWidth: timerLeftContentWidth, rightContentWidth: timerRightContentWidth)
    static let battery = Self(leftContentWidth: batteryLeftContentWidth, rightContentWidth: batteryRightContentWidth)
    static let file = Self(leftContentWidth: fileLeftContentWidth, rightContentWidth: fileRightContentWidth)
}

struct CollapsedActivityResolvedGeometry: Equatable {
    static let outerHorizontalPadding: CGFloat = 8
    static let notchSideSafetyClearance: CGFloat = 4

    let frame: CGRect
    let leftRegionWidth: CGFloat
    let notchCoreWidth: CGFloat
    let rightRegionWidth: CGFloat

    static func resolve(
        notchRect: CGRect,
        existingWidth: CGFloat,
        collapsedHeight: CGFloat,
        topY: CGFloat,
        profile: CollapsedActivityLayoutProfile
    ) -> Self {
        let minimumWingWidth = profile.symmetricWingContentWidth + notchSideSafetyClearance
        let requiredMinX = notchRect.minX - outerHorizontalPadding - minimumWingWidth
        let requiredMaxX = notchRect.maxX + minimumWingWidth + outerHorizontalPadding
        let requiredWidth = requiredMaxX - requiredMinX
        let targetWidth = max(existingWidth, requiredWidth)
        let extraPerSide = (targetWidth - requiredWidth) / 2
        let resolvedMinX = requiredMinX - extraPerSide

        return Self(
            frame: CGRect(
                x: resolvedMinX,
                y: topY - collapsedHeight,
                width: targetWidth,
                height: collapsedHeight
            ),
            leftRegionWidth: minimumWingWidth + extraPerSide,
            notchCoreWidth: notchRect.width,
            rightRegionWidth: minimumWingWidth + extraPerSide
        )
    }

    static func requiredWidth(
        hardwareNotchWidth: CGFloat,
        profile: CollapsedActivityLayoutProfile
    ) -> CGFloat {
        (2 * outerHorizontalPadding)
            + (2 * (profile.symmetricWingContentWidth + notchSideSafetyClearance))
            + max(hardwareNotchWidth, 0)
    }
}

private extension CollapsedActivityResolvedGeometry {
    static func inactive(frame: CGRect) -> Self {
        Self(
            frame: frame,
            leftRegionWidth: 0,
            notchCoreWidth: 0,
            rightRegionWidth: 0
        )
    }
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
        expandedSize: CGSize,
        collapsedActivityProfile: CollapsedActivityLayoutProfile? = .media(
            showsArtwork: true,
            showsVisualizer: true
        ),
        useAdaptiveNotchSizing: Bool = true,
        respectHardwareNotch: Bool = true
    ) -> IslandGeometry {
        let screen = screen ?? Self.preferredScreen()
        let snapshot = screen.map(Self.snapshot) ?? ScreenSnapshot(
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
            safeAreaInsets: NSEdgeInsetsZero,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        return geometry(
            for: snapshot,
            collapsedSize: collapsedSize,
            expandedSize: expandedSize,
            collapsedActivityProfile: collapsedActivityProfile,
            useAdaptiveNotchSizing: useAdaptiveNotchSizing,
            respectHardwareNotch: respectHardwareNotch
        )
    }

    public func geometry(
        for snapshot: ScreenSnapshot,
        collapsedSize: CGSize,
        expandedSize: CGSize,
        collapsedActivityProfile: CollapsedActivityLayoutProfile? = .media(
            showsArtwork: true,
            showsVisualizer: true
        ),
        useAdaptiveNotchSizing: Bool = true,
        respectHardwareNotch: Bool = true
    ) -> IslandGeometry {
        let inferredNotchRect = inferNotchRect(from: snapshot)
        let notchRect = respectHardwareNotch ? inferredNotchRect : nil
        let topY = snapshot.frame.maxY
        let expandedCenterX = snapshot.frame.midX
        let screenSafeExpandedWidth = min(expandedSize.width, max(520, snapshot.frame.width - 280))
        let resolvedExpandedWidth = max(min(screenSafeExpandedWidth, expandedSize.width), 1)
        let resolvedExpandedHeight = max(expandedSize.height, 1)

        let collapsedGeometry: CollapsedActivityResolvedGeometry
        if let notchRect, useAdaptiveNotchSizing {
            let notchMinimumActiveWidth = min(max((notchRect.width + 50) * 1.05, 226), 254)
            let notchMinimumInactiveWidth = min(notchMinimumActiveWidth - 28, max(172, notchRect.width * 0.94))
            let hasActiveContent = collapsedActivityProfile != nil
            let preferredCollapsedWidth = hasActiveContent ? collapsedSize.width : max(126, collapsedSize.width * 0.70)
            let resolvedCollapsedWidth = max(
                preferredCollapsedWidth,
                hasActiveContent ? notchMinimumActiveWidth : notchMinimumInactiveWidth
            )
            let resolvedCollapsedHeight = max(collapsedSize.height, 1)

            if let collapsedActivityProfile {
                collapsedGeometry = CollapsedActivityResolvedGeometry.resolve(
                    notchRect: notchRect,
                    existingWidth: resolvedCollapsedWidth,
                    collapsedHeight: resolvedCollapsedHeight,
                    topY: topY,
                    profile: collapsedActivityProfile
                )
            } else {
                collapsedGeometry = .inactive(
                    frame: CGRect(
                        x: notchRect.midX - resolvedCollapsedWidth / 2,
                        y: topY - resolvedCollapsedHeight,
                        width: resolvedCollapsedWidth,
                        height: resolvedCollapsedHeight
                    )
                )
            }
        } else {
            let resolvedCollapsedWidth = collapsedActivityProfile != nil
                ? collapsedSize.width
                : max(126, collapsedSize.width * 0.70)
            collapsedGeometry = .inactive(
                frame: CGRect(
                    x: snapshot.frame.midX - resolvedCollapsedWidth / 2,
                    y: topY - collapsedSize.height - 8,
                    width: resolvedCollapsedWidth,
                    height: collapsedSize.height
                )
            )
        }

        let collapsedFrame = collapsedGeometry.frame

        let expandedFrame = CGRect(
            x: expandedCenterX - resolvedExpandedWidth / 2,
            y: topY - resolvedExpandedHeight - (notchRect == nil ? 10 : 0),
            width: resolvedExpandedWidth,
            height: resolvedExpandedHeight
        )

        let integralCollapsedFrame = collapsedFrame.integral
        let integralExpandedFrame = expandedFrame.integral
        let resolvedLeftRegionWidth: CGFloat
        let resolvedRightRegionWidth: CGFloat
        if collapsedGeometry.notchCoreWidth > 0, let notchRect {
            resolvedLeftRegionWidth = max(
                notchRect.minX - integralCollapsedFrame.minX - CollapsedActivityResolvedGeometry.outerHorizontalPadding,
                0
            )
            resolvedRightRegionWidth = max(
                integralCollapsedFrame.maxX - notchRect.maxX - CollapsedActivityResolvedGeometry.outerHorizontalPadding,
                0
            )
        } else {
            resolvedLeftRegionWidth = 0
            resolvedRightRegionWidth = 0
        }
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
            hasHardwareNotch: inferredNotchRect != nil,
            hardwareNotchWidth: inferredNotchRect?.width ?? 0,
            collapsedLeftRegionWidth: resolvedLeftRegionWidth,
            collapsedNotchCoreWidth: collapsedGeometry.notchCoreWidth,
            collapsedRightRegionWidth: resolvedRightRegionWidth
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
