import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let settings: AppSettings
    private let islandState: IslandStateStore
    private let geometryService: NotchGeometryService
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []

    init(
        settings: AppSettings,
        islandState: IslandStateStore,
        modules: IslandModules,
        geometryService: NotchGeometryService
    ) {
        self.settings = settings
        self.islandState = islandState
        self.geometryService = geometryService

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let rootView = IslandRootView(
            settings: settings,
            islandState: islandState,
            modules: modules
        )
        panel.contentView = NSHostingView(rootView: rootView)

        islandState.$state
            .sink { [weak self] _ in
                self?.reposition(animated: true)
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setVisible(self.settings.overlayEnabled)
                    self.reposition(animated: true)
                }
            }
            .store(in: &cancellables)
    }

    func show() {
        reposition(animated: false)
        panel.orderFrontRegardless()
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : panel.orderOut(nil)
    }

    func collapseFromOutsideClick() {
        guard !panel.frame.contains(NSEvent.mouseLocation) else { return }
        islandState.collapseFromOutsideClick()
    }

    func reposition(animated: Bool = true) {
        let expandedSize = islandState.isExpandedSurfaceVisible ? settings.expandedSize : settings.peekSize
        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: expandedSize
        )
        let targetFrame = islandState.state == .collapsed ? geometry.collapsedFrame : geometry.expandedFrame

        if animated {
            let currentFrame = panel.frame
            let isExpanding = targetFrame.width > currentFrame.width || targetFrame.height > currentFrame.height

            if isExpanding {
                let overshootFrame = targetFrame.insetBy(dx: -14, dy: -7)
                let panel = panel
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.92, 0.24, 1.18)
                    panel.animator().setFrame(overshootFrame, display: true)
                } completionHandler: {
                    Task { @MainActor [weak panel] in
                        NSAnimationContext.runAnimationGroup { context in
                            context.duration = 0.16
                            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.20, 0.80, 0.22, 1.00)
                            panel?.animator().setFrame(targetFrame, display: true)
                        }
                    }
                }
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.20
                    context.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.00, 0.20, 1.00)
                    panel.animator().setFrame(targetFrame, display: true)
                }
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }
}
