import AppKit
import Combine
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let settings: AppSettings
    private let islandState: IslandStateStore
    private let geometryService: NotchGeometryService
    private let layoutStore = IslandLayoutStore()
    private let panel: NSPanel
    private var cancellables: Set<AnyCancellable> = []
    private var mouseContainmentTimer: Timer?
    private var targetExpandedFrame: NSRect?
    private weak var hostingView: IslandHostingView<IslandRootView>?

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
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.sharingType = .readOnly
        panel.isReleasedWhenClosed = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false

        let rootView = IslandRootView(
            settings: settings,
            islandState: islandState,
            layoutStore: layoutStore,
            modules: modules
        )
        let hostingView = IslandHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.onMouseDown = { [weak islandState] in
            guard islandState?.state == .collapsed else { return true }
            islandState?.toggleExpanded()
            return false
        }
        hostingView.visibleSurfaceFrame = { [weak self] in
            self?.visibleSurfaceFrame() ?? .zero
        }
        panel.contentView = hostingView
        self.hostingView = hostingView

        islandState.$state
            .sink { [weak self] state in
                self?.panel.orderFrontRegardless()
                self?.reposition(animated: true)
                if state == .collapsed {
                    self?.updateMouseContainmentTimer(for: state)
                }
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.setVisible(self.settings.overlayEnabled)
                    self.reposition(animated: false)
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                self?.reposition(animated: false)
            }
            .store(in: &cancellables)
    }

    func show() {
        islandState.collapse()
        reposition(animated: false)
        panel.orderFrontRegardless()
    }

    func setVisible(_ visible: Bool) {
        visible ? show() : panel.orderOut(nil)
        if !visible {
            updateMouseContainmentTimer(for: .collapsed)
        }
    }

    func reposition(animated: Bool = false) {
        let geometry = geometryService.geometry(
            collapsedSize: settings.collapsedSize,
            expandedSize: settings.expandedSize
        )
        layoutStore.update(canvas: geometry.canvas)
        targetExpandedFrame = geometry.expandedFrame
        applyFrame(geometry.canvas.frame)
        hostingView?.needsLayout = true

        switch islandState.state {
        case .expanded:
            updateMouseContainmentTimer(for: .expanded)
        case .collapsed:
            updateMouseContainmentTimer(for: .collapsed)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let correctedGeometry = self.geometryService.geometry(
                collapsedSize: self.settings.collapsedSize,
                expandedSize: self.settings.expandedSize
            )
            if !animated {
                self.layoutStore.update(canvas: correctedGeometry.canvas)
                self.targetExpandedFrame = correctedGeometry.expandedFrame
                self.applyFrame(correctedGeometry.canvas.frame)
                self.hostingView?.needsLayout = true
            }
        }
    }

    private func applyFrame(_ frame: NSRect) {
        panel.animations.removeAll()
        panel.disableScreenUpdatesUntilFlush()
        panel.setFrame(frame, display: true)
        panel.contentView?.frame = NSRect(origin: .zero, size: frame.size)
        panel.orderFrontRegardless()
    }

    private func updateMouseContainmentTimer(for state: IslandPresentationState) {
        mouseContainmentTimer?.invalidate()
        mouseContainmentTimer = nil

        guard state == .expanded else { return }
        let hitFrame = targetExpandedFrame ?? panel.frame
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.islandState.state == .expanded else { return }
                let expandedHitFrame = hitFrame.insetBy(dx: -8, dy: -8)
                if !expandedHitFrame.contains(NSEvent.mouseLocation) {
                    self.islandState.collapse()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseContainmentTimer = timer
    }

    private func visibleSurfaceFrame() -> CGRect {
        switch islandState.state {
        case .collapsed:
            layoutStore.collapsedSurfaceFrame
        case .expanded:
            layoutStore.expandedSurfaceFrame
        }
    }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Bool)?
    var visibleSurfaceFrame: (() -> CGRect)?
    private var trackingAreaReference: NSTrackingArea?

    override func updateTrackingAreas() {
        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        if onMouseDown?() ?? true {
            super.mouseDown(with: event)
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let surfaceFrame = visibleSurfaceFrame?() else {
            return nil
        }
        let localSurfaceFrame: CGRect
        if isFlipped {
            localSurfaceFrame = CGRect(
                x: surfaceFrame.minX,
                y: bounds.height - surfaceFrame.maxY,
                width: surfaceFrame.width,
                height: surfaceFrame.height
            )
        } else {
            localSurfaceFrame = surfaceFrame
        }
        guard localSurfaceFrame.insetBy(dx: -2, dy: -2).contains(point) else {
            return nil
        }
        return super.hitTest(point)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
