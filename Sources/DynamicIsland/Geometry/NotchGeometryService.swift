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
    public let collapsedPresentationProfile: CollapsedPresentationProfile
}

public enum CollapsedPresentationKind: String, Equatable, Sendable {
    case normal
    case systemHUD
    case screenRecording
    case agentRoutine
    case agentAttention
}

/// Transient visual geometry for the collapsed shell. These profiles never become
/// island states; they only let the canonical geometry service resolve one shell.
public struct CollapsedPresentationProfile: Equatable, Sendable {
    public let kind: CollapsedPresentationKind
    public let contentProfile: CollapsedActivityLayoutProfile?
    public let widthDelta: CGFloat
    public let heightDelta: CGFloat
    public let bottomCornerRadius: CGFloat
    public let horizontalContentInset: CGFloat
    public let glowStrength: CGFloat

    public static let normal = Self(
        kind: .normal,
        contentProfile: nil,
        widthDelta: 0,
        heightDelta: 0,
        bottomCornerRadius: 14,
        horizontalContentInset: 8,
        glowStrength: 0
    )

    /// Interactive volume/brightness HUD: the icon + percentage row occupies
    /// the physical top band (max of the collapsed height and the hardware
    /// notch, Droppy `HUDLayoutCalculator.notchHeight` parity) and the
    /// slider gets its own band hanging below it. The shell stays top-pinned
    /// and grows downward only by this band.
    public static let systemHUDSliderBandHeight: CGFloat = 24

    public static func systemHUDRowBandHeight(shellHeight: CGFloat) -> CGFloat {
        max(shellHeight - systemHUDSliderBandHeight, 0)
    }

    public static func systemHUD(value: Double) -> Self {
        _ = value
        return Self(
            kind: .systemHUD,
            contentProfile: .systemHUD,
            widthDelta: 12,
            heightDelta: systemHUDSliderBandHeight,
            bottomCornerRadius: 18,
            horizontalContentInset: 10,
            glowStrength: 0
        )
    }

    public static let screenRecording = Self(
        kind: .screenRecording,
        contentProfile: .screenRecording,
        widthDelta: 20,
        heightDelta: 28,
        bottomCornerRadius: 20,
        horizontalContentInset: 10,
        glowStrength: 0
    )

    public static func agentRoutine(leftContentWidth: CGFloat, rightContentWidth: CGFloat) -> Self {
        Self(
            kind: .agentRoutine,
            contentProfile: CollapsedActivityLayoutProfile(
                leftContentWidth: leftContentWidth,
                rightContentWidth: rightContentWidth
            ),
            widthDelta: 16,
            heightDelta: 2,
            bottomCornerRadius: 16,
            horizontalContentInset: 10,
            glowStrength: 1.0
        )
    }

    public static func agentAttention(leftContentWidth: CGFloat, rightContentWidth: CGFloat) -> Self {
        // AgentNotch parity: a transient notification peek grows the closed
        // notch by +200pt horizontally and +60pt vertically.
        Self(
            kind: .agentAttention,
            contentProfile: CollapsedActivityLayoutProfile(
                leftContentWidth: leftContentWidth,
                rightContentWidth: rightContentWidth
            ),
            widthDelta: 200,
            heightDelta: 60,
            bottomCornerRadius: 24,
            horizontalContentInset: 16,
            glowStrength: 1.0
        )
    }

    var minimumFloatingWidth: CGFloat {
        guard let contentProfile else { return 0 }
        return contentProfile.leftContentWidth
            + contentProfile.rightContentWidth
            + (horizontalContentInset * 2)
            + 18
    }
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
    public static let systemHUDLeftContentWidth: CGFloat = 16
    public static let systemHUDRightContentWidth: CGFloat = 48
    public static let genericActivityLeftContentWidth: CGFloat = 16
    public static let genericActivityRightContentWidth: CGFloat = 52
    public static let screenRecordingLeftContentWidth: CGFloat = 62
    public static let screenRecordingRightContentWidth: CGFloat = 96

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
    static let systemHUD = Self(
        leftContentWidth: systemHUDLeftContentWidth,
        rightContentWidth: systemHUDRightContentWidth
    )
    static let genericActivity = Self(
        leftContentWidth: genericActivityLeftContentWidth,
        rightContentWidth: genericActivityRightContentWidth
    )
    static let screenRecording = Self(
        leftContentWidth: screenRecordingLeftContentWidth,
        rightContentWidth: screenRecordingRightContentWidth
    )
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
        profile: CollapsedActivityLayoutProfile,
        outerHorizontalPadding: CGFloat = CollapsedActivityResolvedGeometry.outerHorizontalPadding
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

enum ExpandedPresentationKind: String, Equatable, Sendable {
    case standard
    case agentsWorkspace
    case trayQuickActions
}

struct ExpandedPresentationProfile: Equatable, Sendable {
    let kind: ExpandedPresentationKind
    let widthScale: CGFloat
    let additionalHeight: CGFloat
    /// Transparent panel space below the shell for attached accessories
    /// (File Tray quick actions). The shell itself is unchanged.
    var accessoryHeight: CGFloat = 0

    static let standard = ExpandedPresentationProfile(
        kind: .standard,
        widthScale: 1,
        additionalHeight: 0
    )

    static let trayQuickActions = ExpandedPresentationProfile(
        kind: .trayQuickActions,
        widthScale: 1,
        additionalHeight: 0,
        accessoryHeight: FileTrayQuickActionMetrics.accessoryHeight
    )
    // The managed console needs a fixed control/composer budget. Width keeps the
    // established breathing room while added height flows to the transcript.
    static let agentsWorkspace = ExpandedPresentationProfile(
        kind: .agentsWorkspace,
        widthScale: 1.10,
        additionalHeight: 160
    )

    static func resolve(for page: ExpandedIslandPage) -> Self {
        switch page {
        case .agents: .agentsWorkspace
        case .tray: .trayQuickActions
        default: .standard
        }
    }

    /// Panel frame: the expanded shell frame extended downward by the
    /// accessory height (screen coordinates, origin bottom-left).
    func panelFrame(forExpandedFrame expanded: CGRect) -> CGRect {
        guard accessoryHeight > 0 else { return expanded }
        return CGRect(
            x: expanded.minX,
            y: expanded.minY - accessoryHeight,
            width: expanded.width,
            height: expanded.height + accessoryHeight
        )
    }

    func resolvedSize(from base: CGSize) -> CGSize {
        CGSize(
            width: max(Self.stableScaled(base.width, by: widthScale), 1),
            height: max(Self.stableValue(base.height + additionalHeight), 1)
        )
    }

    private static func stableScaled(_ value: CGFloat, by scale: CGFloat) -> CGFloat {
        stableValue(value * scale)
    }

    private static func stableValue(_ value: CGFloat) -> CGFloat {
        (value * 1_000).rounded() / 1_000
    }
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
        collapsedPresentationProfile: CollapsedPresentationProfile = .normal,
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
            collapsedPresentationProfile: collapsedPresentationProfile,
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
        collapsedPresentationProfile: CollapsedPresentationProfile = .normal,
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

        let effectiveActivityProfile = collapsedPresentationProfile.contentProfile ?? collapsedActivityProfile
        let resolvedOuterHorizontalPadding = collapsedPresentationProfile.kind == .normal
            ? CollapsedActivityResolvedGeometry.outerHorizontalPadding
            : collapsedPresentationProfile.horizontalContentInset
        let presentedCollapsedSize = CGSize(
            width: max(
                collapsedSize.width + collapsedPresentationProfile.widthDelta,
                collapsedPresentationProfile.minimumFloatingWidth
            ),
            height: collapsedPresentationProfile.kind == .systemHUD
                // Only a notch-integrated island shares its top band with
                // the hardware notch; a floating island is never occluded.
                ? max(collapsedSize.height, useAdaptiveNotchSizing ? (notchRect?.height ?? 0) : 0)
                    + collapsedPresentationProfile.heightDelta
                : collapsedSize.height + collapsedPresentationProfile.heightDelta
        )
        let collapsedGeometry: CollapsedActivityResolvedGeometry
        if let notchRect, useAdaptiveNotchSizing {
            let notchMinimumActiveWidth = min(max((notchRect.width + 50) * 1.05, 226), 254)
            let notchMinimumInactiveWidth = min(notchMinimumActiveWidth - 28, max(172, notchRect.width * 0.94))
            let hasActiveContent = effectiveActivityProfile != nil
            let preferredCollapsedWidth = hasActiveContent
                ? presentedCollapsedSize.width
                : max(126, presentedCollapsedSize.width * 0.70)
            let resolvedCollapsedWidth = max(
                preferredCollapsedWidth,
                hasActiveContent ? notchMinimumActiveWidth : notchMinimumInactiveWidth
            )
            let resolvedCollapsedHeight = max(presentedCollapsedSize.height, 1)

            if let effectiveActivityProfile {
                collapsedGeometry = CollapsedActivityResolvedGeometry.resolve(
                    notchRect: notchRect,
                    existingWidth: resolvedCollapsedWidth,
                    collapsedHeight: resolvedCollapsedHeight,
                    topY: topY,
                    profile: effectiveActivityProfile,
                    outerHorizontalPadding: resolvedOuterHorizontalPadding
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
            let resolvedCollapsedWidth = effectiveActivityProfile != nil
                ? presentedCollapsedSize.width
                : max(126, presentedCollapsedSize.width * 0.70)
            collapsedGeometry = .inactive(
                frame: CGRect(
                    x: snapshot.frame.midX - resolvedCollapsedWidth / 2,
                    y: topY - presentedCollapsedSize.height - 8,
                    width: resolvedCollapsedWidth,
                    height: presentedCollapsedSize.height
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
                notchRect.minX - integralCollapsedFrame.minX - resolvedOuterHorizontalPadding,
                0
            )
            resolvedRightRegionWidth = max(
                integralCollapsedFrame.maxX - notchRect.maxX - resolvedOuterHorizontalPadding,
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
            collapsedRightRegionWidth: resolvedRightRegionWidth,
            collapsedPresentationProfile: collapsedPresentationProfile
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
    static func preferredScreen() -> NSScreen? {
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
