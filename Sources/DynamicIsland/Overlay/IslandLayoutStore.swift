import Foundation

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
    @Published var isShellMorphing = false
    @Published var isCollapseShellOnly = false
    @Published var isExpandedContentExiting = false
    @Published var collapsedPreviewActive = false
    @Published var collapsedPreviewSurfaceFrame: CGRect = .zero
    @Published var panelFrame: CGRect = .zero
    @Published private(set) var isExpandedScrollGestureSuppressed = false
    @Published private(set) var agentAttentionWidthExpansion: CGFloat = 0

    private var baseCollapsedSurfaceFrame: CGRect = CGRect(x: 272, y: 226, width: 216, height: 34)

    func setAgentAttentionWidthExpansion(_ expansion: CGFloat) {
        let normalized = min(max(expansion, 0), 240)
        guard agentAttentionWidthExpansion != normalized else { return }
        agentAttentionWidthExpansion = normalized
        applyAgentAttentionWidth()
    }

    private func applyAgentAttentionWidth() {
        let maximumExtra = max(0, expandedSurfaceFrame.width - baseCollapsedSurfaceFrame.width)
        let extra = min(agentAttentionWidthExpansion, maximumExtra)
        let width = baseCollapsedSurfaceFrame.width + extra
        let proposedX = baseCollapsedSurfaceFrame.midX - (width / 2)
        let maximumX = max(0, canvasSize.width - width)
        let clampedX = min(max(0, proposedX), maximumX)
        collapsedSurfaceFrame = CGRect(
            x: clampedX,
            y: baseCollapsedSurfaceFrame.minY,
            width: width,
            height: baseCollapsedSurfaceFrame.height
        ).integral
        collapsedSize = collapsedSurfaceFrame.size
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

    func update(
        canvas: IslandCanvasGeometry,
        hasHardwareNotch: Bool,
        hardwareNotchWidth: CGFloat,
        collapsedLeftRegionWidth: CGFloat,
        collapsedNotchCoreWidth: CGFloat,
        collapsedRightRegionWidth: CGFloat
    ) {
        panelFrame = canvas.frame
        canvasSize = canvas.frame.size
        baseCollapsedSurfaceFrame = canvas.collapsedSurfaceFrame
        expandedSurfaceFrame = canvas.expandedSurfaceFrame
        applyAgentAttentionWidth()
        collapsedPreviewActive = false
        collapsedPreviewSurfaceFrame = .zero
        collapsedSize = collapsedSurfaceFrame.size
        expandedSize = canvas.expandedSurfaceFrame.size
        self.hasHardwareNotch = hasHardwareNotch
        self.hardwareNotchWidth = hasHardwareNotch ? max(hardwareNotchWidth, 0) : 0
        self.collapsedLeftRegionWidth = max(collapsedLeftRegionWidth, 0)
        self.collapsedNotchCoreWidth = max(collapsedNotchCoreWidth, 0)
        self.collapsedRightRegionWidth = max(collapsedRightRegionWidth, 0)
    }

    func updateLocal(
        panelFrame: CGRect,
        collapsedScreenFrame: CGRect,
        expandedScreenFrame: CGRect,
        hasHardwareNotch: Bool,
        hardwareNotchWidth: CGFloat,
        collapsedLeftRegionWidth: CGFloat,
        collapsedNotchCoreWidth: CGFloat,
        collapsedRightRegionWidth: CGFloat
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
        baseCollapsedSurfaceFrame = localCollapsedFrame
        expandedSurfaceFrame = localExpandedFrame
        applyAgentAttentionWidth()
        if !collapsedPreviewActive {
            collapsedPreviewSurfaceFrame = .zero
        }
        collapsedSize = collapsedSurfaceFrame.size
        expandedSize = localExpandedFrame.size
        self.hasHardwareNotch = hasHardwareNotch
        self.hardwareNotchWidth = hasHardwareNotch ? max(hardwareNotchWidth, 0) : 0
        self.collapsedLeftRegionWidth = max(collapsedLeftRegionWidth, 0)
        self.collapsedNotchCoreWidth = max(collapsedNotchCoreWidth, 0)
        self.collapsedRightRegionWidth = max(collapsedRightRegionWidth, 0)
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
