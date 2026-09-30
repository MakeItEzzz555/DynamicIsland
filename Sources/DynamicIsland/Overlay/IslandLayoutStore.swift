import Foundation

enum IslandCanvasCoordinateSpace {
    static let name = "DynamicIslandCanvas"

    static func appKitLocalRect(fromSwiftUI frame: CGRect, canvasHeight: CGFloat) -> CGRect {
        guard canvasHeight.isFinite, canvasHeight > 0 else { return .zero }
        return CGRect(
            x: frame.minX,
            y: canvasHeight - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }
}

@MainActor
final class IslandLayoutStore: ObservableObject {
    @Published var overlayPresentationGeneration = 0
    @Published var canvasSize: CGSize = CGSize(width: 760, height: 260)
    @Published var collapsedSurfaceFrame: CGRect = CGRect(x: 272, y: 226, width: 216, height: 34)
    @Published var expandedSurfaceFrame: CGRect = CGRect(x: 0, y: 0, width: 760, height: 260)
    @Published var collapsedSize: CGSize = CGSize(width: 216, height: 34)
    @Published var expandedSize: CGSize = CGSize(width: 760, height: 260)
    @Published var hasHardwareNotch = true
    @Published private(set) var hardwareNotchWidth: CGFloat = 0
    @Published private(set) var collapsedLeftRegionWidth: CGFloat = 0
    @Published private(set) var collapsedNotchCoreWidth: CGFloat = 0
    @Published private(set) var collapsedRightRegionWidth: CGFloat = 0
    @Published private(set) var collapsedPresentationProfile: CollapsedPresentationProfile = .normal
    @Published var isShellMorphing = false
    @Published var isCollapseShellOnly = false
    @Published var isExpandedContentExiting = false
    @Published var collapsedPreviewActive = false
    @Published var collapsedPreviewSurfaceFrame: CGRect = .zero
    @Published private(set) var collapsedLeadingSidecarFrame: CGRect = .zero
    @Published private(set) var collapsedTrailingSidecarFrame: CGRect = .zero
    @Published private(set) var collapsedCompositeInteractionFrame: CGRect = .zero
    @Published var panelFrame: CGRect = .zero
    @Published private(set) var isExpandedScrollGestureSuppressed = false
    @Published private(set) var expandedContentScrollRegion: CGRect = .zero
    @Published var isTransientInteractionActive = false
    /// Visible accessories attached below the expanded shell (panel-local,
    /// AppKit coordinates). They own hover, hit-testing and passthrough
    /// exactly like the shell, and only their own area.
    @Published private(set) var expandedAccessoryFrames: [CGRect] = []

    func setExpandedAccessoryFrames(_ frames: [CGRect]) {
        let valid = frames.filter { !$0.isNull && !$0.isInfinite && $0.width > 0 && $0.height > 0 }.map(\.integral)
        guard expandedAccessoryFrames != valid else { return }
        expandedAccessoryFrames = valid
    }

    /// An in-island text editor (Agents composer) is first responder.
    @Published private(set) var isTextInputFocused = false

    func setTextInputFocused(_ focused: Bool) {
        guard isTextInputFocused != focused else { return }
        isTextInputFocused = focused
    }

    func setExpandedScrollGestureSuppressed(_ suppressed: Bool) {
        guard isExpandedScrollGestureSuppressed != suppressed else { return }
        isExpandedScrollGestureSuppressed = suppressed
        #if DEBUG
        print(
            suppressed
                ? "[GestureDebug] expanded scroll suppression enabled"
                : "[GestureDebug] expanded scroll suppression disabled"
        )
        #endif
    }

    func setExpandedContentScrollRegion(_ region: CGRect) {
        let next = region.isNull || region.isInfinite || region.width <= 0 || region.height <= 0
            ? CGRect.zero
            : region.integral
        guard expandedContentScrollRegion != next else { return }
        expandedContentScrollRegion = next
        #if DEBUG
        if ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" {
            debugPrint("[GestureDebug] expanded content scroll region", next)
        }
        #endif
    }

    func update(
        canvas: IslandCanvasGeometry,
        hasHardwareNotch: Bool,
        hardwareNotchWidth: CGFloat,
        collapsedLeftRegionWidth: CGFloat,
        collapsedNotchCoreWidth: CGFloat,
        collapsedRightRegionWidth: CGFloat,
        collapsedPresentationProfile: CollapsedPresentationProfile = .normal
    ) {
        panelFrame = canvas.frame
        canvasSize = canvas.frame.size
        collapsedSurfaceFrame = canvas.collapsedSurfaceFrame
        expandedSurfaceFrame = canvas.expandedSurfaceFrame
        collapsedPreviewActive = false
        collapsedPreviewSurfaceFrame = .zero
        collapsedLeadingSidecarFrame = .zero
        collapsedTrailingSidecarFrame = .zero
        collapsedCompositeInteractionFrame = collapsedSurfaceFrame
        collapsedSize = collapsedSurfaceFrame.size
        expandedSize = canvas.expandedSurfaceFrame.size
        self.hasHardwareNotch = hasHardwareNotch
        self.hardwareNotchWidth = hasHardwareNotch ? max(hardwareNotchWidth, 0) : 0
        self.collapsedLeftRegionWidth = max(collapsedLeftRegionWidth, 0)
        self.collapsedNotchCoreWidth = max(collapsedNotchCoreWidth, 0)
        self.collapsedRightRegionWidth = max(collapsedRightRegionWidth, 0)
        self.collapsedPresentationProfile = collapsedPresentationProfile
    }

    func updateLocal(
        panelFrame: CGRect,
        collapsedScreenFrame: CGRect,
        expandedScreenFrame: CGRect,
        hasHardwareNotch: Bool,
        hardwareNotchWidth: CGFloat,
        collapsedLeftRegionWidth: CGFloat,
        collapsedNotchCoreWidth: CGFloat,
        collapsedRightRegionWidth: CGFloat,
        collapsedPresentationProfile: CollapsedPresentationProfile = .normal
    ) {
        let integralPanelFrame = panelFrame.integral
        let localCollapsedFrame = CGRect(
            x: collapsedScreenFrame.minX - integralPanelFrame.minX,
            y: collapsedScreenFrame.minY - integralPanelFrame.minY,
            width: collapsedScreenFrame.width,
            height: collapsedScreenFrame.height
        ).integral
        let localExpandedFrame = CGRect(
            x: expandedScreenFrame.minX - integralPanelFrame.minX,
            y: expandedScreenFrame.minY - integralPanelFrame.minY,
            width: expandedScreenFrame.width,
            height: expandedScreenFrame.height
        ).integral

        self.panelFrame = integralPanelFrame
        canvasSize = integralPanelFrame.size
        collapsedSurfaceFrame = localCollapsedFrame
        expandedSurfaceFrame = localExpandedFrame
        if !collapsedPreviewActive {
            collapsedPreviewSurfaceFrame = .zero
        }
        collapsedLeadingSidecarFrame = .zero
        collapsedTrailingSidecarFrame = .zero
        collapsedCompositeInteractionFrame = collapsedSurfaceFrame
        collapsedSize = collapsedSurfaceFrame.size
        expandedSize = localExpandedFrame.size
        self.hasHardwareNotch = hasHardwareNotch
        self.hardwareNotchWidth = hasHardwareNotch ? max(hardwareNotchWidth, 0) : 0
        self.collapsedLeftRegionWidth = max(collapsedLeftRegionWidth, 0)
        self.collapsedNotchCoreWidth = max(collapsedNotchCoreWidth, 0)
        self.collapsedRightRegionWidth = max(collapsedRightRegionWidth, 0)
        self.collapsedPresentationProfile = collapsedPresentationProfile
        debugLocalLayout(
            panelFrame: integralPanelFrame,
            collapsedScreenFrame: collapsedScreenFrame,
            expandedScreenFrame: expandedScreenFrame,
            collapsedSurfaceFrame: localCollapsedFrame,
            expandedSurfaceFrame: localExpandedFrame
        )
    }

    private func debugLocalLayout(
        panelFrame: CGRect,
        collapsedScreenFrame: CGRect,
        expandedScreenFrame: CGRect,
        collapsedSurfaceFrame: CGRect,
        expandedSurfaceFrame: CGRect
    ) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["DYNAMIC_ISLAND_VERBOSE_UI_LOGS"] == "1" else { return }
        debugPrint(
            "DynamicIsland local layout",
            "panelFrame=\(panelFrame)",
            "collapsedScreenFrame=\(collapsedScreenFrame)",
            "expandedScreenFrame=\(expandedScreenFrame)",
            "collapsedSurfaceFrame=\(collapsedSurfaceFrame)",
            "expandedSurfaceFrame=\(expandedSurfaceFrame)",
            "collapsedMidX=\(collapsedSurfaceFrame.midX)",
            "expandedMidX=\(expandedSurfaceFrame.midX)"
        )
        if abs(collapsedSurfaceFrame.midX - expandedSurfaceFrame.midX) > 1 {
            debugPrint(
                "DynamicIsland local layout warning",
                "collapsed and expanded local midX differ by more than 1pt"
            )
        }
        #endif
    }

    func updateCollapsedSidecars(_ geometry: LiveActivityCompositeGeometry) {
        let leading = geometry.leadingSidecarFrame?.integral ?? .zero
        let trailing = geometry.trailingSidecarFrame?.integral ?? .zero
        let interaction = geometry.interactionFrame.integral

        if collapsedLeadingSidecarFrame != leading {
            collapsedLeadingSidecarFrame = leading
        }
        if collapsedTrailingSidecarFrame != trailing {
            collapsedTrailingSidecarFrame = trailing
        }
        if collapsedCompositeInteractionFrame != interaction {
            collapsedCompositeInteractionFrame = interaction
        }
    }

    func updateCollapsedPreview(active: Bool, frame: CGRect) {
        let nextFrame = active ? frame.integral : .zero
        if collapsedPreviewActive != active {
            collapsedPreviewActive = active
        }
        if collapsedPreviewSurfaceFrame != nextFrame {
            collapsedPreviewSurfaceFrame = nextFrame
        }
    }
}
