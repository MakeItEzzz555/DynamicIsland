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
    private var mouseContainmentTimer: Timer?

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
        panel.contentView = hostingView

        islandState.$state
            .sink { [weak self] state in
                self?.panel.orderFrontRegardless()
                self?.reposition(animated: false)
                self?.updateMouseContainmentTimer(for: state)
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
        let targetFrame = islandState.state == .collapsed ? geometry.collapsedFrame : geometry.expandedFrame

        applyFrame(targetFrame)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let correctedGeometry = self.geometryService.geometry(
                collapsedSize: self.settings.collapsedSize,
                expandedSize: self.settings.expandedSize
            )
            let correctedFrame = self.islandState.state == .collapsed ? correctedGeometry.collapsedFrame : correctedGeometry.expandedFrame
            self.applyFrame(correctedFrame)
        }
    }

    private func applyFrame(_ frame: NSRect) {
        panel.contentView?.layer?.removeAllAnimations()
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
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.islandState.state == .expanded else { return }
                let expandedHitFrame = self.panel.frame.insetBy(dx: -8, dy: -8)
                if !expandedHitFrame.contains(NSEvent.mouseLocation) {
                    self.islandState.collapse()
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        mouseContainmentTimer = timer
    }
}

private final class IslandHostingView<Content: View>: NSHostingView<Content> {
    var onMouseDown: (() -> Bool)?
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
