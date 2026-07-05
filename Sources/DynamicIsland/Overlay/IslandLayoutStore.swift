import Foundation

@MainActor
final class IslandLayoutStore: ObservableObject {
    @Published var canvasSize: CGSize = CGSize(width: 760, height: 260)
    @Published var collapsedSurfaceFrame: CGRect = CGRect(x: 272, y: 226, width: 216, height: 34)
    @Published var expandedSurfaceFrame: CGRect = CGRect(x: 0, y: 0, width: 760, height: 260)
    @Published var collapsedSize: CGSize = CGSize(width: 216, height: 34)
    @Published var expandedSize: CGSize = CGSize(width: 760, height: 260)
    @Published var hasHardwareNotch = true
    @Published var isShellMorphing = false
    @Published var isCollapseShellOnly = false
    @Published var isExpandedContentExiting = false
    @Published var collapsedPreviewActive = false
    @Published var collapsedPreviewSurfaceFrame: CGRect = .zero
    @Published var panelFrame: CGRect = .zero

    func update(canvas: IslandCanvasGeometry, hasHardwareNotch: Bool) {
        panelFrame = canvas.frame
        canvasSize = canvas.frame.size
        collapsedSurfaceFrame = canvas.collapsedSurfaceFrame
        expandedSurfaceFrame = canvas.expandedSurfaceFrame
        collapsedPreviewActive = false
        collapsedPreviewSurfaceFrame = .zero
        collapsedSize = canvas.collapsedSurfaceFrame.size
        expandedSize = canvas.expandedSurfaceFrame.size
        self.hasHardwareNotch = hasHardwareNotch
    }

    func updateLocal(
        panelFrame: CGRect,
        collapsedScreenFrame: CGRect,
        expandedScreenFrame: CGRect,
        hasHardwareNotch: Bool
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
        collapsedSize = localCollapsedFrame.size
        expandedSize = localExpandedFrame.size
        self.hasHardwareNotch = hasHardwareNotch
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
